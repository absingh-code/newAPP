import SwiftUI
import SwiftData

struct ScoutingTabView: View {
    @Environment(\.ftcScoutAPI) private var api
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @Query(sort: \ScoutingReport.observedAt, order: .reverse) private var reports: [ScoutingReport]

    @State private var events: [FTCEventSummary] = []
    @State private var isLoadingEvents = false
    @State private var eventError: String?
    @State private var searchText = ""
    @State private var isPresentingNewReport = false

    private var season: Int { Calendar.current.component(.year, from: .now) }

    private var visibleReports: [ScoutingReport] {
        guard !searchText.isEmpty else { return reports }
        return reports.filter {
            String($0.teamNumber).localizedCaseInsensitiveContains(searchText) ||
            $0.teamName.localizedCaseInsensitiveContains(searchText) ||
            $0.eventName.localizedCaseInsensitiveContains(searchText) ||
            $0.matchNumber.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText) ||
            $0.capabilities.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        List {
                Section {
                    HStack(spacing: 12) {
                        Label("\(reports.count)", systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                        Text("match observations saved")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            isPresentingNewReport = true
                        } label: {
                            Label("Scout", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }

                if let eventError {
                    Section("Live event schedule") {
                        Label(eventError, systemImage: "wifi.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Retry event list") { Task { await loadEvents() } }
                    }
                } else if isLoadingEvents {
                    Section("Live event schedule") {
                        ProgressView("Loading FTCScout events…")
                    }
                }

                if visibleReports.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No scouting reports yet" : "No matching reports",
                        systemImage: searchText.isEmpty ? "binoculars" : "magnifyingglass",
                        description: Text(searchText.isEmpty
                            ? "Record observed match performance and robot capabilities. Reports stay on this device and sync through your configured Firebase project."
                            : "Try another team, event, match, or capability.")
                    )
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(visibleReports) { report in
                        ScoutingReportRow(report: report)
                    }
                    .onDelete(perform: deleteReports)
                }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Team, event, match, capability")
        .navigationTitle("Match Scouting")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingNewReport = true } label: {
                    Label("Record observation", systemImage: "plus")
                }
            }
        }
        .refreshable { await loadEvents() }
        .sheet(isPresented: $isPresentingNewReport) {
            NewScoutingReportSheet(events: events)
        }
        .task { await loadEvents() }
    }

    private func loadEvents() async {
        isLoadingEvents = true
        eventError = nil
        do {
            events = try await api.fetchEvents(season: season)
                .sorted { $0.start < $1.start }
        } catch {
            eventError = error.localizedDescription
        }
        isLoadingEvents = false
    }

    private func deleteReports(at offsets: IndexSet) {
        for index in offsets {
            let report = visibleReports[index]
            syncService?.deleteScoutingReport(id: report.id)
            context.delete(report)
        }
    }
}

private struct ScoutingReportRow: View {
    let report: ScoutingReport

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(report.teamName.isEmpty ? "Team #\(report.teamNumber)" : "#\(report.teamNumber) \(report.teamName)")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(report.totalScore) pts")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            Text("\(report.eventName) · \(report.matchNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !report.capabilities.isEmpty {
                Text(report.capabilities.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .lineLimit(2)
            }
            HStack {
                Text("Auto \(report.autonomousScore)  ·  TeleOp \(report.teleOpScore)  ·  Endgame \(report.endgameScore)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(report.observedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if !report.notes.isEmpty {
                Text(report.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct NewScoutingReportSheet: View {
    let events: [FTCEventSummary]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager

    @State private var teamNumber = ""
    @State private var teamName = ""
    @State private var eventName = ""
    @State private var matchNumber = ""
    @State private var autoScore = ""
    @State private var teleOpScore = ""
    @State private var endgameScore = ""
    @State private var capabilitiesInput = ""
    @State private var notes = ""

    private var parsedTeamNumber: Int? { Int(teamNumber) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Match") {
                    TextField("Team number", text: $teamNumber)
                        .keyboardType(.numberPad)
                    TextField("Team name (optional)", text: $teamName)
                    if events.isEmpty {
                        TextField("Event name", text: $eventName)
                    } else {
                        Picker("Event", selection: $eventName) {
                            Text("Select event").tag("")
                            ForEach(events) { event in
                                Text(event.name).tag(event.name)
                            }
                        }
                        if eventName.isEmpty {
                            TextField("Or enter event name", text: $eventName)
                        }
                    }
                    TextField("Match number (e.g. Q12)", text: $matchNumber)
                        .textInputAutocapitalization(.characters)
                }

                Section("Observed score") {
                    scoreField("Autonomous", value: $autoScore)
                    scoreField("TeleOp", value: $teleOpScore)
                    scoreField("Endgame", value: $endgameScore)
                    Text("Enter each observed phase score explicitly; use 0 only when you observed no points. Scores are not fetched from FTCScout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Robot observations") {
                    TextField("Capabilities (comma-separated)", text: $capabilitiesInput, axis: .vertical)
                    TextField("Notes, reliability, or strategy", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Scout Report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!(parsedTeamNumber.map { $0 > 0 } ?? false) ||
                                  eventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  matchNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  !scoresAreValid)
                }
            }
        }
    }

    private var scoresAreValid: Bool {
        [autoScore, teleOpScore, endgameScore].allSatisfy(isNonNegativeInteger)
    }

    private func isNonNegativeInteger(_ value: String) -> Bool {
        guard let score = Int(value) else { return false }
        return score >= 0
    }

    private func scoreField(_ title: String, value: Binding<String>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func save() {
        guard let user = authManager.currentUser, let number = parsedTeamNumber, scoresAreValid else { return }
        let capabilities = capabilitiesInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let report = ScoutingReport(
            teamNumber: number,
            teamName: teamName.trimmingCharacters(in: .whitespacesAndNewlines),
            eventName: eventName.trimmingCharacters(in: .whitespacesAndNewlines),
            matchNumber: matchNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            autonomousScore: Int(autoScore) ?? 0,
            teleOpScore: Int(teleOpScore) ?? 0,
            endgameScore: Int(endgameScore) ?? 0,
            capabilities: capabilities,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            recordedByID: user.id,
            recordedByName: user.name
        )
        context.insert(report)
        syncService?.pushScoutingReport(report)
        dismiss()
    }
}
