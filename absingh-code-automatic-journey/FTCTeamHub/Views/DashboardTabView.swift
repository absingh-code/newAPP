//
//  DashboardTabView.swift
//  FTCTeamHub
//
//  NEW: added a search toolbar button presenting GlobalSearchView.
//

import SwiftUI
import SwiftData

struct DashboardTabView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(TabRouter.self) private var router
    @Environment(\.ftcScoutAPI) private var api

    @Query private var allTasks: [TaskItem]
    @Query private var batteries: [Battery]
    @Query private var inventoryItems: [InventoryItem]
    @Query private var testRuns: [TestRunRecord]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var activity: [ActivityEvent]
    @Query(sort: \ChecklistRun.timestamp, order: .reverse) private var checklistRuns: [ChecklistRun]

    @State private var nextEvent: FTCEventSummary?
    @State private var daysUntilEvent: Int?
    @State private var isLoadingEvent = true
    @State private var eventLoadError: String?
    @State private var isPresentingSearch = false

    private var myOpenTasks: [TaskItem] {
        guard let uid = authManager.currentUser?.id else { return [] }
        return allTasks.filter { $0.assignedToID == uid && $0.status != .done }
    }

    private var inventoryAlertCard: some View {
        GroupBox {
            Button {
                router.selection = .inventory
            } label: {
                HStack {
                    Image(systemName: "shippingbox.fill").foregroundStyle(.orange)
                    Text("\(inventoryNeedingAttention.count) inventory item\(inventoryNeedingAttention.count == 1 ? "" : "s") low or needing maintenance")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var overdueTasks: [TaskItem] {
        myOpenTasks.filter { ($0.deadline ?? .distantFuture) < .now }
    }

    private var batteriesNeedingAttention: [Battery] {
        batteries.filter { $0.status == .dead || $0.cycleCount > 40 }
    }

    private var inventoryNeedingAttention: [InventoryItem] {
        inventoryItems.filter { $0.isLowStock || $0.needsMaintenance }
    }

    private var todaysChecklist: ChecklistRun? {
        checklistRuns.first { Calendar.current.isDateInToday($0.timestamp) }
    }

    private var insights: [Insight] {
        InsightsEngine.generate(testRuns: testRuns, batteries: batteries, tasks: allTasks)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    nextEventCard
                    statGrid
                    insightsSection
                    if !batteriesNeedingAttention.isEmpty { batteryAlertCard }
                    if !inventoryNeedingAttention.isEmpty { inventoryAlertCard }
                    if todaysChecklist == nil { checklistNudgeCard }
                    recentActivitySection
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingSearch = true } label: { Image(systemName: "magnifyingglass") }
                }
            }
            .sheet(isPresented: $isPresentingSearch) { GlobalSearchView() }
            .task { await loadNextEvent() }
            .refreshable { await loadNextEvent() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.title2.bold())
            if let user = authManager.currentUser {
                Label(user.role.rawValue, systemImage: user.role.systemImage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = authManager.currentUser?.name.split(separator: " ").first.map(String.init) ?? "there"
        switch hour {
        case 0..<12: return "Good morning, \(name)"
        case 12..<17: return "Good afternoon, \(name)"
        default: return "Good evening, \(name)"
        }
    }

    // MARK: - Next event

    @ViewBuilder
    private var nextEventCard: some View {
        GroupBox {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    if isLoadingEvent {
                        Text("Checking upcoming events…").font(.subheadline).foregroundStyle(.secondary)
                    } else if let event = nextEvent, let days = daysUntilEvent {
                        Text(event.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let eventLoadError {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upcoming events unavailable").font(.subheadline.weight(.medium))
                            Text(eventLoadError).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    } else {
                        Text("No upcoming events published").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    router.selection = .liveData
                } label: {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func loadNextEvent() async {
        isLoadingEvent = true
        eventLoadError = nil
        nextEvent = nil
        daysUntilEvent = nil
        do {
            let season = Calendar.current.component(.year, from: .now)
            let events = try await api.fetchEvents(season: season)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")

            let upcoming = events.compactMap { event -> (FTCEventSummary, Date)? in
                guard let date = formatter.date(from: String(event.start.prefix(10))) else { return nil }
                return (event, date)
            }
            .filter { $0.1 >= Calendar.current.startOfDay(for: .now) }
            .sorted { $0.1 < $1.1 }

            if !events.isEmpty && upcoming.isEmpty &&
                events.allSatisfy({ formatter.date(from: String($0.start.prefix(10))) == nil }) {
                eventLoadError = "FTCScout returned event dates in an unexpected format."
            }
            if let soonest = upcoming.first {
                nextEvent = soonest.0
                daysUntilEvent = Calendar.current.dateComponents(
                    [.day], from: Calendar.current.startOfDay(for: .now),
                    to: Calendar.current.startOfDay(for: soonest.1)
                ).day
            }
        } catch {
            eventLoadError = error.localizedDescription
        }
        isLoadingEvent = false
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            DashboardStatCard(
                title: "My Open Tasks", value: "\(myOpenTasks.count)",
                subtitle: overdueTasks.isEmpty ? nil : "\(overdueTasks.count) overdue",
                subtitleColor: .red, icon: "checklist", tint: .blue
            ) { router.selection = .tasks }

            DashboardStatCard(
                title: "Batteries Tracked", value: "\(batteries.count)",
                subtitle: batteriesNeedingAttention.isEmpty ? nil : "\(batteriesNeedingAttention.count) need attention",
                subtitleColor: .orange, icon: "battery.75", tint: .green
            ) { router.selection = .pitOps }

            DashboardStatCard(
                title: "Notebook & Ideas", value: "\(activity.filter { $0.kind == .notebookEntry || $0.kind == .ideaPosted }.count)",
                subtitle: "this season", subtitleColor: .secondary, icon: "book.closed", tint: .purple
            ) { router.selection = .notebook }

            DashboardStatCard(
                title: "Scout & Events", value: "Open", subtitle: "FTCScout + reports", subtitleColor: .secondary,
                icon: "antenna.radiowaves.left.and.right", tint: .indigo
            ) { router.selection = .liveData }
        }
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                Text("Insights").font(.headline)
            }
            Text("On-device trend analysis of your own data — not cloud AI.")
                .font(.caption2).foregroundStyle(.tertiary)

            VStack(spacing: 8) {
                ForEach(insights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.icon)
                            .foregroundStyle(color(for: insight.tint))
                            .frame(width: 20)
                        Text(insight.text)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func color(for tint: InsightTint) -> Color {
        switch tint {
        case .positive: return .green
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }

    // MARK: - Alerts

    private var batteryAlertCard: some View {
        GroupBox {
            Button {
                router.selection = .pitOps
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(batteriesNeedingAttention.count) battery\(batteriesNeedingAttention.count == 1 ? "" : "ies") need attention")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var checklistNudgeCard: some View {
        GroupBox {
            Button {
                router.selection = .pitOps
            } label: {
                HStack {
                    Image(systemName: "checklist").foregroundStyle(.blue)
                    Text("No pre-flight checklist completed today")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Recent activity

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity").font(.headline)

            if activity.isEmpty {
                Text("No activity yet.").font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activity.prefix(6).enumerated()), id: \.element.id) { index, event in
                        HStack(spacing: 10) {
                            Image(systemName: event.systemImage)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 20)
                            (Text(event.authorName).fontWeight(.semibold) + Text(" \(event.message)"))
                                .font(.footnote)
                                .lineLimit(2)
                            Spacer()
                            Text(event.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        if index < min(activity.count, 6) - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

private struct DashboardStatCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let subtitleColor: Color
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(tint)
                    Spacer()
                }
                Text(value)
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(subtitleColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    let router = TabRouter()
    return DashboardTabView()
        .modelContainer(container)
        .environment(authManager)
        .environment(router)
        .environment(\.ftcScoutAPI, LiveFTCScoutAPIClient())
}
