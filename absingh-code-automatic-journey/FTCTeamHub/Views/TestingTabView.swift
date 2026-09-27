//
//  TestingTabView.swift
//  FTCTeamHub
//
//  NEW: Analytics section now has a CSV export button producing a
//  spreadsheet-ready file of every logged test run, for deeper analysis
//  in Excel/Sheets than the in-app charts allow.
//

import SwiftUI
import SwiftData
import Charts
import UIKit

struct TestingTabView: View {
    @Query(sort: \AppUser.name) private var users: [AppUser]
    @Query(sort: \TestRunRecord.date, order: .reverse) private var records: [TestRunRecord]
    @Query(sort: \Battery.label) private var batteries: [Battery]
    @State private var section: Section = .log

    enum Section: String, CaseIterable, Identifiable {
        case log = "Log Test", timer = "Match Timer", analytics = "Analytics"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                switch section {
                case .log: TestLogForm(users: users, batteries: batteries)
                case .timer: MatchTimerView()
                case .analytics: TestingAnalyticsView(records: records)
                }
            }
            .navigationTitle("Robot Testing")
        }
    }
}

// MARK: - Log Test

private struct TestLogForm: View {
    let users: [AppUser]
    let batteries: [Battery]
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService

    @State private var selectedDriverID: UUID?
    @State private var selectedBatteryLabel: String?
    @State private var autoScore = 0
    @State private var teleopScore = 0
    @State private var endgameScore = 0
    @State private var cycleTime = 0.0
    @State private var autoConsistency = 80.0
    @State private var selectedIssues: Set<String> = []
    @State private var notes = ""

    private let commonIssues = ["Intake Jam", "Belt Slipped", "Code Crash", "Sensor Drift", "Battery Died", "Odometry Slip"]
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        Form {
            Section("Driver & Battery") {
                Picker("Driver", selection: $selectedDriverID) {
                    Text("Select driver").tag(UUID?.none)
                    ForEach(users) { user in
                        Text(user.name).tag(Optional(user.id))
                    }
                }
                Picker("Battery", selection: $selectedBatteryLabel) {
                    Text("Not tracked").tag(String?.none)
                    ForEach(batteries) { battery in
                        Text(battery.label).tag(Optional(battery.label))
                    }
                }
            }

            Section("Scores") {
                LargeStepperRow(label: "Auto Score", value: $autoScore, haptics: haptics)
                LargeStepperRow(label: "TeleOp Score", value: $teleopScore, haptics: haptics)
                LargeStepperRow(label: "Endgame Score", value: $endgameScore, haptics: haptics)
            }

            Section("Consistency") {
                HStack {
                    Text("Cycle time (s)")
                    Spacer()
                    TextField("0.0", value: $cycleTime, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto consistency: \(Int(autoConsistency))%")
                    Slider(value: $autoConsistency, in: 0...100, step: 5)
                }
            }

            Section("Failures Observed") {
                IssueChipGrid(options: commonIssues, selected: $selectedIssues)
            }

            Section("Notes") {
                TextEditor(text: $notes).frame(minHeight: 70)
            }

            Section {
                Button {
                    submit()
                } label: {
                    Text("Log Test Run")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDriverID == nil)
            }
        }
    }

    private func submit() {
        guard let driverID = selectedDriverID,
              let driver = users.first(where: { $0.id == driverID }),
              let currentUser = authManager.currentUser else { return }

        let record = TestRunRecord(
            driverID: driverID, driverName: driver.name, date: .now,
            autoScore: autoScore, teleopScore: teleopScore, endgameScore: endgameScore,
            cycleTimeSeconds: cycleTime, autoConsistencyPercent: autoConsistency,
            mechanicalIssues: Array(selectedIssues), notes: notes,
            recordedByID: currentUser.id, recordedByName: currentUser.name,
            batteryLabel: selectedBatteryLabel
        )
        context.insert(record)
        syncService?.pushTestRun(record)

        let event = ActivityEvent(
            authorID: currentUser.id, authorName: currentUser.name, kind: .testLogged,
            message: "logged a test run for \(driver.name)" + (selectedBatteryLabel.map { " (battery \($0))" } ?? "")
        )
        context.insert(event)
        syncService?.pushActivity(event)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        autoScore = 0; teleopScore = 0; endgameScore = 0
        cycleTime = 0; autoConsistency = 80; selectedIssues = []; notes = ""
    }
}

private struct LargeStepperRow: View {
    let label: String
    @Binding var value: Int
    let haptics: UIImpactFeedbackGenerator

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button {
                haptics.impactOccurred()
                value = max(0, value - 1)
            } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 28))
            }
            .buttonStyle(.plain)

            Text("\(value)")
                .font(.title3.monospacedDigit().bold())
                .frame(minWidth: 32)

            Button {
                haptics.impactOccurred()
                value += 1
            } label: {
                Image(systemName: "plus.circle.fill").font(.system(size: 28))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct IssueChipGrid: View {
    let options: [String]
    @Binding var selected: Set<String>

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    if selected.contains(option) {
                        selected.remove(option)
                    } else {
                        selected.insert(option)
                    }
                } label: {
                    Text(option)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(
                            selected.contains(option) ? Color.accentColor : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(selected.contains(option) ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Analytics

private struct TestingAnalyticsView: View {
    let records: [TestRunRecord]
    @State private var exportURL: URL?

    var body: some View {
        Group {
            if records.isEmpty {
                EmptyStateView(icon: "chart.line.uptrend.xyaxis", title: "No test runs yet",
                               subtitle: "Log a practice run to start tracking your robot's progress.",
                               tint: .blue)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        GroupBox("Score Progression") {
                            Chart {
                                ForEach(records.sorted(by: { $0.date < $1.date })) { record in
                                    LineMark(x: .value("Date", record.date), y: .value("Score", record.autoScore))
                                        .foregroundStyle(by: .value("Series", "Auto"))
                                    LineMark(x: .value("Date", record.date), y: .value("Score", record.teleopScore))
                                        .foregroundStyle(by: .value("Series", "TeleOp"))
                                }
                            }
                            .frame(height: 220)
                            .padding(.top, 8)
                        }

                        GroupBox("Common Failures") {
                            let counts = failureCounts
                            if counts.isEmpty {
                                Text("No failures logged yet — nice.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                Chart {
                                    ForEach(counts, id: \.issue) { item in
                                        BarMark(x: .value("Count", item.count), y: .value("Issue", item.issue))
                                    }
                                }
                                .frame(height: CGFloat(counts.count * 34 + 20))
                                .padding(.top, 8)
                            }
                        }

                        GroupBox("Averages") {
                            VStack(alignment: .leading, spacing: 6) {
                                LabeledContent("Avg Auto Score", value: String(format: "%.1f", average(\.autoScore)))
                                LabeledContent("Avg TeleOp Score", value: String(format: "%.1f", average(\.teleopScore)))
                                LabeledContent("Avg Cycle Time", value: String(format: "%.2fs", averageCycleTime))
                                LabeledContent("Total Runs Logged", value: "\(records.count)")
                            }
                            .padding(.top, 4)
                        }

                        Button {
                            exportURL = TestRunCSVExporter.writeTempFile(records: records)
                        } label: {
                            Label("Export All Runs as CSV", systemImage: "tablecells")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
        }
        .sheet(item: Binding(get: { exportURL.map(IdentifiableFileURL.init) }, set: { exportURL = $0?.url })) { wrapped in
            CSVShareSheet(activityItems: [wrapped.url])
        }
    }

    private func average(_ keyPath: KeyPath<TestRunRecord, Int>) -> Double {
        guard !records.isEmpty else { return 0 }
        let total = records.reduce(0) { $0 + $1[keyPath: keyPath] }
        return Double(total) / Double(records.count)
    }

    private var averageCycleTime: Double {
        guard !records.isEmpty else { return 0 }
        return records.map(\.cycleTimeSeconds).reduce(0, +) / Double(records.count)
    }

    private var failureCounts: [(issue: String, count: Int)] {
        var counts: [String: Int] = [:]
        for record in records {
            for issue in record.mechanicalIssues {
                counts[issue, default: 0] += 1
            }
        }
        return counts.map { (issue: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }
}

private struct IdentifiableFileURL: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct CSVShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - CSV export

enum TestRunCSVExporter {
    static func csv(from records: [TestRunRecord]) -> String {
        var lines = ["Date,Driver,AutoScore,TeleopScore,EndgameScore,TotalScore,CycleTimeSeconds,AutoConsistencyPercent,Battery,MechanicalIssues,Notes,RecordedBy"]
        let formatter = ISO8601DateFormatter()
        for record in records.sorted(by: { $0.date < $1.date }) {
            let safeNotes = "\"\(record.notes.replacingOccurrences(of: "\"", with: "\"\""))\""
            let issues = "\"\(record.mechanicalIssues.joined(separator: "; "))\""
            let row = [
                formatter.string(from: record.date),
                record.driverName,
                "\(record.autoScore)", "\(record.teleopScore)", "\(record.endgameScore)", "\(record.totalScore)",
                String(format: "%.2f", record.cycleTimeSeconds),
                String(format: "%.0f", record.autoConsistencyPercent),
                record.batteryLabel ?? "",
                issues, safeNotes, record.recordedByName
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    static func writeTempFile(records: [TestRunRecord]) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_runs_export.csv")
        do {
            try csv(from: records).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return TestingTabView()
        .modelContainer(container)
        .environment(authManager)
}
