//
//  NotebookTabView.swift
//  FTCTeamHub
//
//  NEW: added a full-notebook PDF export (toolbar button on the main
//  list) that combines every entry into one multi-page PDF — the actual
//  artifact you'd hand to Inspire Award judges, rather than exporting
//  one entry at a time.
//

import SwiftUI
import SwiftData
import UIKit

struct NotebookTabView: View {
    @Query(sort: \NotebookEntry.timestamp, order: .reverse) private var entries: [NotebookEntry]
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @State private var isPresentingTemplatePicker = false
    @State private var selectedTemplate: NotebookTemplate?
    @State private var fullExportURL: URL?
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var oldestFirst = false

    private var availableTags: [String] {
        Array(Set(entries.flatMap(\.tags))).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var visibleEntries: [NotebookEntry] {
        entries.filter { entry in
            let matchesTag = selectedTag.map { entry.tags.contains($0) } ?? true
            let matchesSearch = searchText.isEmpty ||
                entry.title.localizedCaseInsensitiveContains(searchText) ||
                entry.content.localizedCaseInsensitiveContains(searchText) ||
                entry.authorName.localizedCaseInsensitiveContains(searchText) ||
                entry.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesTag && matchesSearch
        }
        .sorted { oldestFirst ? $0.timestamp < $1.timestamp : $0.timestamp > $1.timestamp }
    }

    var body: some View {
        NavigationStack {
            List {
                if visibleEntries.isEmpty && !entries.isEmpty {
                    ContentUnavailableView("No matching entries", systemImage: "magnifyingglass",
                                           description: Text("Change the search or tag filter to see notebook entries."))
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(visibleEntries) { entry in
                        NavigationLink(value: entry) {
                            NotebookRow(entry: entry)
                        }
                    }
                    .onDelete(perform: deleteEntries)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Notebook")
            .searchable(text: $searchText, prompt: "Search notes, tags, or authors")
            .navigationDestination(for: NotebookEntry.self) { entry in
                NotebookEntryDetailView(entry: entry)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingTemplatePicker = true } label: { Image(systemName: "square.and.pencil") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        fullExportURL = NotebookPDFExporter.exportAll(entries: entries)
                    } label: {
                        Label("Export Full Notebook", systemImage: "square.and.arrow.up.on.square")
                    }
                    .disabled(entries.isEmpty)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("All tags") { selectedTag = nil }
                        if !availableTags.isEmpty {
                            Divider()
                            ForEach(availableTags, id: \.self) { tag in
                                Button {
                                    selectedTag = tag
                                } label: {
                                    if selectedTag == tag {
                                        Label(tag, systemImage: "checkmark")
                                    } else {
                                        Text(tag)
                                    }
                                }
                            }
                        }
                        Divider()
                        Button(oldestFirst ? "Newest first" : "Oldest first") {
                            oldestFirst.toggle()
                        }
                    } label: {
                        Label("Organize", systemImage: "line.3.horizontal.decrease")
                    }
                }
            }
            .confirmationDialog("New Entry", isPresented: $isPresentingTemplatePicker, titleVisibility: .visible) {
                ForEach(NotebookTemplate.allCases) { template in
                    Button(template.rawValue) { selectedTemplate = template }
                }
            }
            .sheet(item: $selectedTemplate) { template in
                NewNotebookEntrySheet(template: template)
            }
            .sheet(item: Binding(get: { fullExportURL.map(IdentifiableURL.init) }, set: { fullExportURL = $0?.url })) { wrapped in
                ShareSheet(activityItems: [wrapped.url])
            }
            .overlay {
                if entries.isEmpty {
                    EmptyStateView(icon: "book.closed", title: "No notebook entries yet",
                                   subtitle: "Tap the pencil icon to add your first entry.",
                                   tint: .purple, actionTitle: "New Entry") {
                        isPresentingTemplatePicker = true
                    }
                }
            }
        }
    }

    private func deleteEntries(at offsets: IndexSet) {
        for index in offsets {
            let entry = visibleEntries[index]
            syncService?.deleteNotebookEntry(id: entry.id)
            context.delete(entry)
        }
    }
}

private struct NotebookRow: View {
    let entry: NotebookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.title).font(.body.weight(.medium))
            Text(entry.content)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Text(entry.authorName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if !entry.tags.isEmpty {
                    Text("· " + entry.tags.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                Spacer()
                Text(entry.timestamp, style: .date).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail (rendered Markdown + structured payloads + PDF export + edit)

private struct NotebookEntryDetailView: View {
    @Bindable var entry: NotebookEntry
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(\.dismiss) private var dismiss
    @State private var pdfURL: URL?
    @State private var isPresentingEdit = false
    @State private var isPresentingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.title).font(.title2.bold())
                Text("By \(entry.authorName) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)

                Divider()

                Text(.init(entry.content))

                if let auto = entry.autonomousLog { AutonomousLogCard(log: auto) }
                if let hub = entry.hubConfigLog { HubConfigCard(log: hub) }
                if let imu = entry.imuLog { IMULogCard(log: imu) }

                if !entry.tags.isEmpty {
                    HStack {
                        ForEach(entry.tags, id: \.self) { tag in
                            Text(tag).font(.caption2)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isPresentingEdit = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        pdfURL = NotebookPDFExporter.export(entry: entry)
                    } label: {
                        Label("Export This Entry", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        isPresentingDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isPresentingEdit) {
            EditNotebookEntrySheet(entry: entry)
        }
        .sheet(item: Binding(get: { pdfURL.map(IdentifiableURL.init) }, set: { pdfURL = $0?.url })) { wrapped in
            ShareSheet(activityItems: [wrapped.url])
        }
        .confirmationDialog("Delete this entry?", isPresented: $isPresentingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                syncService?.deleteNotebookEntry(id: entry.id)
                context.delete(entry)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct AutonomousLogCard: View {
    let log: AutonomousTestLog
    var body: some View {
        GroupBox("Autonomous Test — \(log.routineName)") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Starting position", value: log.startingPosition)
                LabeledContent("Scored", value: "\(log.samplesOrSpecimensScored)")
                LabeledContent("Cycle time", value: String(format: "%.2fs", log.cycleTimeSeconds))
                LabeledContent("Success rate", value: String(format: "%.0f%%", log.successRatePercent))
                if !log.failureNotes.isEmpty {
                    Text(log.failureNotes).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct HubConfigCard: View {
    let log: ControlHubConfigLog
    var body: some View {
        GroupBox("Control Hub Configuration") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Control Hub OS", value: log.controlHubOSVersion)
                LabeledContent("SDK version", value: log.sdkVersion)
                LabeledContent("Expansion Hubs", value: "\(log.expansionHubCount)")
            }
        }
    }
}

private struct IMULogCard: View {
    let log: IMUTuningLog
    var body: some View {
        GroupBox("IMU Tuning — \(log.chip)") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Logo facing", value: log.logoFacingDirection)
                LabeledContent("USB facing", value: log.usbFacingDirection)
                LabeledContent("Yaw offset", value: String(format: "%.2f°", log.yawOffsetDegrees))
                LabeledContent("10-min drift", value: String(format: "%.2f°", log.driftOverTenMinDegrees))
                if !log.calibrationNotes.isEmpty {
                    Text(log.calibrationNotes).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - PDF export

enum NotebookPDFExporter {

    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 48
    private static var contentWidth: CGFloat { pageWidth - margin * 2 }

    /// Exports a single entry as a one-page-ish PDF (existing behavior).
    static func export(entry: NotebookEntry) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notebook_\(entry.id.uuidString).pdf")
        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                drawEntry(entry, in: context, startingAt: margin)
            }
            return url
        } catch {
            return nil
        }
    }

    /// Exports EVERY entry into one combined, multi-page PDF with a cover
    /// page — this is the artifact meant for judges, showing the whole
    /// engineering notebook in one document rather than scattered files.
    static func exportAll(entries: [NotebookEntry]) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("engineering_notebook_full_export.pdf")
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }

        do {
            try renderer.writePDF(to: url) { context in
                // Cover page
                context.beginPage()
                let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 28)]
                ("Engineering Notebook" as NSString).draw(at: CGPoint(x: margin, y: 140), withAttributes: titleAttrs)

                let subtitleAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.darkGray
                ]
                let dateRange = sorted.isEmpty ? "" :
                    "\(sorted.first!.timestamp.formatted(date: .abbreviated, time: .omitted)) – \(sorted.last!.timestamp.formatted(date: .abbreviated, time: .omitted))"
                ("\(sorted.count) entries · \(dateRange)" as NSString)
                    .draw(at: CGPoint(x: margin, y: 180), withAttributes: subtitleAttrs)

                ("Exported \(Date().formatted(date: .abbreviated, time: .shortened))" as NSString)
                    .draw(at: CGPoint(x: margin, y: 200), withAttributes: subtitleAttrs)

                // One page per entry
                for entry in sorted {
                    context.beginPage()
                    drawEntry(entry, in: context, startingAt: margin)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    private static func drawEntry(_ entry: NotebookEntry, in context: UIGraphicsPDFRendererContext, startingAt startY: CGFloat) {
        var cursorY = startY

        let titleAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20)]
        (entry.title as NSString).draw(at: CGPoint(x: margin, y: cursorY), withAttributes: titleAttrs)
        cursorY += 28

        let metaAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.darkGray
        ]
        let meta = "By \(entry.authorName) · \(entry.timestamp.formatted(date: .abbreviated, time: .shortened))" as NSString
        meta.draw(at: CGPoint(x: margin, y: cursorY), withAttributes: metaAttrs)
        cursorY += 24

        if !entry.tags.isEmpty {
            let tagsLine = entry.tags.joined(separator: " · ") as NSString
            tagsLine.draw(at: CGPoint(x: margin, y: cursorY), withAttributes: metaAttrs)
            cursorY += 20
        }

        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
        let bodyRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: pageHeight - cursorY - margin - 120)
        (entry.content as NSString).draw(in: bodyRect, withAttributes: bodyAttrs)
        cursorY = bodyRect.maxY + 12

        if let auto = entry.autonomousLog {
            let text = "Autonomous Test — \(auto.routineName)\nStarting position: \(auto.startingPosition)\nScored: \(auto.samplesOrSpecimensScored)\nCycle time: \(String(format: "%.2f", auto.cycleTimeSeconds))s\nSuccess rate: \(String(format: "%.0f", auto.successRatePercent))%"
            (text as NSString).draw(in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 90), withAttributes: bodyAttrs)
            cursorY += 90
        }
        if let hub = entry.hubConfigLog {
            let text = "Control Hub Config\nOS: \(hub.controlHubOSVersion)  SDK: \(hub.sdkVersion)  Expansion Hubs: \(hub.expansionHubCount)"
            (text as NSString).draw(in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 40), withAttributes: bodyAttrs)
            cursorY += 40
        }
        if let imu = entry.imuLog {
            let text = "IMU Tuning — \(imu.chip)\nLogo facing: \(imu.logoFacingDirection)  USB facing: \(imu.usbFacingDirection)\nYaw offset: \(String(format: "%.2f", imu.yawOffsetDegrees))°  10-min drift: \(String(format: "%.2f", imu.driftOverTenMinDegrees))°"
            (text as NSString).draw(in: CGRect(x: margin, y: cursorY, width: contentWidth, height: 60), withAttributes: bodyAttrs)
        }
    }
}

// MARK: - New entry sheet, template-aware

private struct NewNotebookEntrySheet: View {
    let template: NotebookTemplate
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager

    @State private var title = ""
    @State private var content = ""
    @State private var tagsInput = ""

    @State private var routineName = ""
    @State private var startingPosition = ""
    @State private var samplesScored = 0
    @State private var cycleTime = 0.0
    @State private var successRate = 0.0
    @State private var failureNotes = ""

    @State private var hubOS = "1.1.3"
    @State private var sdkVersion = "10.1"
    @State private var expansionHubs = 0

    @State private var imuChip = "BHI260AP"
    @State private var logoFacing = "UP"
    @State private var usbFacing = "FORWARD"
    @State private var yawOffset = 0.0
    @State private var drift = 0.0
    @State private var calibrationNotes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    TextField("Title", text: $title)
                    TextEditor(text: $content).frame(minHeight: 120)
                    TextField("Tags (comma-separated)", text: $tagsInput)
                }
                templateSpecificSection
            }
            .navigationTitle(template.rawValue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var templateSpecificSection: some View {
        switch template {
        case .autonomousTest:
            Section("Autonomous Routine") {
                TextField("Routine name", text: $routineName)
                TextField("Starting position", text: $startingPosition)
                Stepper("Scored: \(samplesScored)", value: $samplesScored, in: 0...20)
                HStack { Text("Cycle time (s)"); Spacer(); TextField("0.0", value: $cycleTime, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Success rate (%)"); Spacer(); TextField("0", value: $successRate, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                TextField("Failure notes", text: $failureNotes, axis: .vertical)
            }
        case .controlHubConfig:
            Section("Control Hub Config") {
                TextField("Control Hub OS version", text: $hubOS)
                TextField("SDK version", text: $sdkVersion)
                Stepper("Expansion Hubs: \(expansionHubs)", value: $expansionHubs, in: 0...4)
            }
        case .imuTuning:
            Section("IMU Tuning") {
                Picker("Chip", selection: $imuChip) {
                    Text("BHI260AP").tag("BHI260AP")
                    Text("BNO055").tag("BNO055")
                }
                TextField("Logo facing direction", text: $logoFacing)
                TextField("USB facing direction", text: $usbFacing)
                HStack { Text("Yaw offset (°)"); Spacer(); TextField("0.0", value: $yawOffset, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("10-min drift (°)"); Spacer(); TextField("0.0", value: $drift, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                TextField("Calibration notes", text: $calibrationNotes, axis: .vertical)
            }
        case .softwareLog, .hardwareLog, .blank:
            EmptyView()
        }
    }

    private func save() {
        guard let currentUser = authManager.currentUser else { return }
        let tags = Array(Set(tagsInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))

        let entry = NotebookEntry(authorID: currentUser.id, authorName: currentUser.name,
                                   title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                   content: content, tags: tags.sorted())

        switch template {
        case .autonomousTest:
            entry.autonomousLog = AutonomousTestLog(routineName: routineName, startingPosition: startingPosition,
                                                     samplesOrSpecimensScored: samplesScored, cycleTimeSeconds: cycleTime,
                                                     successRatePercent: successRate, failureNotes: failureNotes)
        case .controlHubConfig:
            entry.hubConfigLog = ControlHubConfigLog(controlHubOSVersion: hubOS, sdkVersion: sdkVersion,
                                                      expansionHubCount: expansionHubs, motorPortMap: [:], servoPortMap: [:])
        case .imuTuning:
            entry.imuLog = IMUTuningLog(chip: imuChip, logoFacingDirection: logoFacing, usbFacingDirection: usbFacing,
                                         yawOffsetDegrees: yawOffset, driftOverTenMinDegrees: drift,
                                         calibrationNotes: calibrationNotes)
        case .softwareLog, .hardwareLog, .blank:
            break
        }

        context.insert(entry)
        syncService?.pushNotebookEntry(entry)

        let event = ActivityEvent(authorID: currentUser.id, authorName: currentUser.name, kind: .notebookEntry,
                                   message: "added notebook entry: \(title)")
        context.insert(event)
        syncService?.pushActivity(event)

        dismiss()
    }
}

// MARK: - Edit existing entry sheet

private struct EditNotebookEntrySheet: View {
    @Bindable var entry: NotebookEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.syncService) private var syncService

    @State private var title: String
    @State private var content: String
    @State private var tagsInput: String

    @State private var autoRoutineName: String
    @State private var autoStartingPosition: String
    @State private var autoSamplesScored: Int
    @State private var autoCycleTime: Double
    @State private var autoSuccessRate: Double
    @State private var autoFailureNotes: String

    @State private var imuChip: String
    @State private var imuLogoFacing: String
    @State private var imuUsbFacing: String
    @State private var imuYawOffset: Double
    @State private var imuDrift: Double
    @State private var imuCalibrationNotes: String

    init(entry: NotebookEntry) {
        self.entry = entry
        _title = State(initialValue: entry.title)
        _content = State(initialValue: entry.content)
        _tagsInput = State(initialValue: entry.tags.joined(separator: ", "))

        let auto = entry.autonomousLog
        _autoRoutineName = State(initialValue: auto?.routineName ?? "")
        _autoStartingPosition = State(initialValue: auto?.startingPosition ?? "")
        _autoSamplesScored = State(initialValue: auto?.samplesOrSpecimensScored ?? 0)
        _autoCycleTime = State(initialValue: auto?.cycleTimeSeconds ?? 0)
        _autoSuccessRate = State(initialValue: auto?.successRatePercent ?? 0)
        _autoFailureNotes = State(initialValue: auto?.failureNotes ?? "")

        let imu = entry.imuLog
        _imuChip = State(initialValue: imu?.chip ?? "BHI260AP")
        _imuLogoFacing = State(initialValue: imu?.logoFacingDirection ?? "UP")
        _imuUsbFacing = State(initialValue: imu?.usbFacingDirection ?? "FORWARD")
        _imuYawOffset = State(initialValue: imu?.yawOffsetDegrees ?? 0)
        _imuDrift = State(initialValue: imu?.driftOverTenMinDegrees ?? 0)
        _imuCalibrationNotes = State(initialValue: imu?.calibrationNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Entry") {
                    TextField("Title", text: $title)
                    TextEditor(text: $content).frame(minHeight: 120)
                    TextField("Tags (comma-separated)", text: $tagsInput)
                }

                if entry.autonomousLog != nil {
                    Section("Autonomous Routine") {
                        TextField("Routine name", text: $autoRoutineName)
                        TextField("Starting position", text: $autoStartingPosition)
                        Stepper("Scored: \(autoSamplesScored)", value: $autoSamplesScored, in: 0...20)
                        HStack { Text("Cycle time (s)"); Spacer(); TextField("0.0", value: $autoCycleTime, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Success rate (%)"); Spacer(); TextField("0", value: $autoSuccessRate, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        TextField("Failure notes", text: $autoFailureNotes, axis: .vertical)
                    }
                }

                if entry.imuLog != nil {
                    Section("IMU Tuning") {
                        TextField("Chip", text: $imuChip)
                        TextField("Logo facing direction", text: $imuLogoFacing)
                        TextField("USB facing direction", text: $imuUsbFacing)
                        HStack { Text("Yaw offset (°)"); Spacer(); TextField("0.0", value: $imuYawOffset, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        HStack { Text("10-min drift (°)"); Spacer(); TextField("0.0", value: $imuDrift, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        TextField("Calibration notes", text: $imuCalibrationNotes, axis: .vertical)
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.content = content
        entry.tags = Array(Set(tagsInput.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })).sorted()

        if entry.autonomousLog != nil {
            entry.autonomousLog = AutonomousTestLog(routineName: autoRoutineName, startingPosition: autoStartingPosition,
                                                     samplesOrSpecimensScored: autoSamplesScored, cycleTimeSeconds: autoCycleTime,
                                                     successRatePercent: autoSuccessRate, failureNotes: autoFailureNotes)
        }
        if entry.imuLog != nil {
            entry.imuLog = IMUTuningLog(chip: imuChip, logoFacingDirection: imuLogoFacing, usbFacingDirection: imuUsbFacing,
                                         yawOffsetDegrees: imuYawOffset, driftOverTenMinDegrees: imuDrift,
                                         calibrationNotes: imuCalibrationNotes)
        }

        syncService?.pushNotebookEntry(entry)
        dismiss()
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return NotebookTabView()
        .modelContainer(container)
        .environment(authManager)
}
