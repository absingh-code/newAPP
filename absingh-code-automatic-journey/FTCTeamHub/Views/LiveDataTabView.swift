//
//  LiveDataTabView.swift
//  FTCTeamHub
//
//  NEW: added a "Scoring Sim" segment (ScoringSimulatorView) — fits here
//  thematically since it's directly used during alliance selection,
//  alongside the team-search and bookmarking tools already in this tab.
//

import SwiftUI
import SwiftData
import UIKit

struct LiveDataTabView: View {
    @Environment(\.ftcScoutAPI) private var api
    @State private var section: Section = .search

    enum Section: String, CaseIterable, Identifiable {
        case search = "Team Search", bookmarked = "Tracked Teams", events = "Events", scouting = "Scout Reports", scoring = "Scoring Sim"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch section {
                case .search: TeamSearchView(api: api)
                case .bookmarked: BookmarkedTeamsView(api: api)
                case .events: EventsBrowserView(api: api)
                case .scouting: ScoutingTabView()
                case .scoring: ScoringSimulatorView()
                }
            }
            .navigationTitle(section.rawValue)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Scout tools", selection: $section) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Scout tools")
                }
            }
        }
    }
}

// MARK: - Team search

private struct TeamSearchView: View {
    let api: FTCScoutAPIServicing
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.modelContext) private var context
    @Query private var bookmarks: [TrackedTeam]

    @State private var teamNumberInput = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var result: FTCTeamOPR?
    @State private var season = Calendar.current.component(.year, from: .now)

    private var isBookmarked: Bool {
        guard let result else { return false }
        return bookmarks.contains { $0.teamNumber == result.number }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("Team number, e.g. 24211", text: $teamNumberInput)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        Task { await search() }
                    } label: {
                        if isLoading { ProgressView() } else { Text("Search") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(teamNumberInput.isEmpty || isLoading)
                }
                Picker("Season", selection: $season) {
                    ForEach((Calendar.current.component(.year, from: .now) - 4)...Calendar.current.component(.year, from: .now), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .onChange(of: season) {
                    result = nil
                    errorMessage = nil
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }

            if let result {
                Section("\(result.name) · #\(result.number)") {
                    OPRBreakdownView(team: result)

                    NavigationLink {
                        TeamDashboardView(teamNumber: result.number, teamName: result.name, season: season, api: api)
                    } label: {
                        Label("View Full Team Dashboard", systemImage: "chart.xyaxis.line")
                    }

                    Button {
                        bookmark(result)
                    } label: {
                        Label(isBookmarked ? "Bookmarked" : "Track This Team", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
                    }
                    .disabled(isBookmarked)
                }
            }

            Section {
                Label("Live FTCScout data · \(season)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Live event data requires an internet connection. Local scouting reports remain available offline.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func search() async {
        guard let number = Int(teamNumberInput), number > 0 else {
            errorMessage = "Enter a team number greater than zero."
            return
        }
        isLoading = true
        errorMessage = nil
        result = nil
        do {
            result = try await api.fetchTeamOPR(teamNumber: number, season: season)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func bookmark(_ team: FTCTeamOPR) {
        guard let currentUser = authManager.currentUser else { return }
        let tracked = TrackedTeam(teamNumber: team.number, teamName: team.name,
                                   addedByID: currentUser.id, addedByName: currentUser.name)
        context.insert(tracked)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - OPR breakdown (shared visual component)

struct OPRBreakdownView: View {
    let team: FTCTeamOPR

    private var maxOPR: Double {
        max(team.autoOPR, team.teleOpOPR, team.endgameOPR, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OPRBar(label: "Auto", value: team.autoOPR, maxValue: maxOPR, color: .blue)
            OPRBar(label: "TeleOp", value: team.teleOpOPR, maxValue: maxOPR, color: .orange)
            OPRBar(label: "Endgame", value: team.endgameOPR, maxValue: maxOPR, color: .purple)
            Divider()
            HStack {
                Text("Total OPR").font(.subheadline.weight(.semibold))
                Spacer()
                Text(team.totalOPR, format: .number.precision(.fractionLength(1)))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct OPRBar: View {
    let label: String
    let value: Double
    let maxValue: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(value, format: .number.precision(.fractionLength(1)))
                    .font(.caption.monospacedDigit())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 6)
                    Capsule().fill(color).frame(width: geo.size.width * min(value / maxValue, 1), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Bookmarked teams

private struct BookmarkedTeamsView: View {
    let api: FTCScoutAPIServicing
    @Query(sort: \TrackedTeam.addedAt, order: .reverse) private var bookmarks: [TrackedTeam]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            if bookmarks.isEmpty {
                EmptyStateView(icon: "bookmark", title: "No tracked teams",
                               subtitle: "Search a team and tap \"Track This Team\" to save it here.",
                               tint: .blue)
            }
            ForEach(bookmarks) { team in
                NavigationLink {
                    TeamDashboardView(
                        teamNumber: team.teamNumber,
                        teamName: team.teamName,
                        season: Calendar.current.component(.year, from: .now),
                        api: api
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.teamName).font(.body.weight(.medium))
                        Text("Team \(team.teamNumber) · added by \(team.addedByName)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .toolbar { EditButton() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(bookmarks[index]) }
    }
}

// MARK: - Events browser

private struct EventsBrowserView: View {
    let api: FTCScoutAPIServicing
    @State private var events: [FTCEventSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var season = Calendar.current.component(.year, from: .now)

    private var filteredEvents: [FTCEventSummary] {
        guard !searchText.isEmpty else { return events }
        return events.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Season", selection: $season) {
                    ForEach((Calendar.current.component(.year, from: .now) - 4)...(Calendar.current.component(.year, from: .now) + 1), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
            }
            if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Events unavailable", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await loadEvents() } }
                }
            } else if filteredEvents.isEmpty {
                EmptyStateView(icon: "calendar", title: "No events found",
                               subtitle: searchText.isEmpty
                                ? "The \(season) FTCScout schedule may not be published yet."
                                : "No events matched “\(searchText)”.",
                               tint: .orange)
            } else {
                ForEach(filteredEvents) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.name).font(.body.weight(.medium))
                        Text("\(event.start) – \(event.end) · \(event.code)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search events or event code")
        .refreshable { await loadEvents() }
        .task(id: season) {
            await loadEvents()
        }
    }

    private func loadEvents() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetchedEvents = try await api.fetchEvents(season: season).sorted { $0.start < $1.start }
            guard !Task.isCancelled else { return }
            events = fetchedEvents
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    LiveDataTabView()
        .modelContainer(container)
        .environment(authManager)
        .environment(\.ftcScoutAPI, LiveFTCScoutAPIClient())
}
