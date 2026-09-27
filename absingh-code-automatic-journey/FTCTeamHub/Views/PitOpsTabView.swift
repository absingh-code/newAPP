//
//  PitOpsTabView.swift
//  FTCTeamHub
//
//  FIX: `ForEach(ChecklistType.allCases, id: \.self)` caused an overload
//  ambiguity error because ChecklistType already conforms to Identifiable
//  (see the extension below) — explicitly passing `id: \.self` alongside
//  that conformance confused the compiler into trying to match the
//  Binding<C>-based ForEach initializer instead of the plain collection
//  one. Fix: drop `id: \.self` entirely and let it use Identifiable.
//

import SwiftUI
import SwiftData
import CoreImage.CIFilterBuiltins
import UIKit

struct PitOpsTabView: View {
    @Environment(TabRouter.self) private var router
    @State private var section: Section = .batteries

    enum Section: String, CaseIterable, Identifiable {
        case batteries = "Batteries", checklists = "Checklists", inventory = "Inventory"
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
                case .batteries: BatteryListView()
                case .checklists: ChecklistsView()
                case .inventory: InventoryListView()
                }
            }
            .navigationTitle("Pit Ops")
            .onChange(of: router.selection) {
                if router.selection == .inventory {
                    section = .inventory
                } else if router.selection == .pitOps {
                    section = .batteries
                }
            }
        }
    }
}

// MARK: - Batteries

private struct BatteryListView: View {
    @Query(sort: \Battery.label) private var batteries: [Battery]
    @Query private var allTestRuns: [TestRunRecord]
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var isPresentingNewBattery = false

    var body: some View {
        List {
            if batteries.isEmpty {
                EmptyStateView(icon: "battery.100", title: "No batteries tracked",
                               subtitle: "Add your team's batteries to start tracking cycles and performance.",
                               tint: .green, actionTitle: "Add Battery") { isPresentingNewBattery = true }
                    .listRowSeparator(.hidden)
            }
            ForEach(batteries) { battery in
                NavigationLink {
                    BatteryDetailView(battery: battery, runsUsingThisBattery: allTestRuns.filter { $0.batteryLabel == battery.label })
                } label: {
                    BatteryRow(battery: battery)
                }
            }
            Section {
                Button { isPresentingNewBattery = true } label: {
                    Label("Add Battery", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $isPresentingNewBattery) { NewBatterySheet() }
    }
}

private struct BatteryRow: View {
    @Bindable var battery: Battery
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager

    private var statusColor: Color {
        switch battery.status {
        case .charged: return .green
        case .inUse: return .blue
        case .charging: return .orange
        case .dead: return .red
        }
    }

    var body: some View {
        HStack {
            Image(systemName: battery.status.systemImage)
                .foregroundStyle(statusColor)
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(battery.label).font(.body.weight(.semibold))
                Text("\(battery.cycleCount) cycles").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(BatteryStatus.allCases) { status in
                    Button(status.rawValue) { setStatus(status) }
                }
            } label: {
                Text(battery.status.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }
        }
        .padding(.vertical, 2)
    }

    private func setStatus(_ status: BatteryStatus) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        battery.status = status
        if status == .charged { battery.lastChargedAt = .now }
        if status == .inUse { battery.cycleCount += 1 }
        syncService?.pushBattery(battery)

        if let user = authManager.currentUser {
            let event = ActivityEvent(authorID: user.id, authorName: user.name, kind: .batteryStatusChanged,
                                       message: "marked battery \(battery.label) as \(status.rawValue)")
            context.insert(event)
            syncService?.pushActivity(event)
        }
    }
}

private struct BatteryDetailView: View {
    let battery: Battery
    let runsUsingThisBattery: [TestRunRecord]

    private var averageTotalScore: Double {
        guard !runsUsingThisBattery.isEmpty else { return 0 }
        let total = runsUsingThisBattery.reduce(0) { $0 + $1.totalScore }
        return Double(total) / Double(runsUsingThisBattery.count)
    }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Status", value: battery.status.rawValue)
                LabeledContent("Cycle count", value: "\(battery.cycleCount)")
                if let lastCharged = battery.lastChargedAt {
                    LabeledContent("Last charged", value: lastCharged.formatted(date: .abbreviated, time: .shortened))
                }
            }
            Section("Performance (\(runsUsingThisBattery.count) run\(runsUsingThisBattery.count == 1 ? "" : "s"))") {
                if runsUsingThisBattery.isEmpty {
                    Text("No test runs logged with this battery yet.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Avg total score", value: String(format: "%.1f", averageTotalScore))
                    if battery.cycleCount > 30 && averageTotalScore < 40 {
                        Label("High cycle count with low scores — consider retiring this cell.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }
            if !battery.notes.isEmpty {
                Section("Notes") { Text(battery.notes) }
            }
        }
        .navigationTitle(battery.label)
    }
}

private struct NewBatterySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @State private var label = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label (e.g. B1)", text: $label)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("New Battery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(label.isEmpty)
                }
            }
        }
    }

    private func save() {
        let battery = Battery(label: label, notes: notes)
        context.insert(battery)
        syncService?.pushBattery(battery)
        dismiss()
    }
}

// MARK: - Checklists

private struct ChecklistsView: View {
    @Query(sort: \ChecklistRun.timestamp, order: .reverse) private var runs: [ChecklistRun]
    @State private var activeChecklistType: ChecklistType?

    var body: some View {
        List {
            Section {
                ForEach(ChecklistType.allCases) { type in
                    Button {
                        activeChecklistType = type
                    } label: {
                        Label("Start \(type.rawValue) Checklist", systemImage: type.systemImage)
                    }
                }
            }

            Section("Recent Checklists") {
                if runs.isEmpty {
                    Text("No checklists completed yet.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(runs) { run in
                    HStack {
                        Image(systemName: run.allChecked ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(run.allChecked ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.type.rawValue).font(.subheadline.weight(.medium))
                            Text("\(run.completedByName) · \(run.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $activeChecklistType) { type in
            ChecklistRunSheet(type: type)
        }
    }
}

extension ChecklistType: Identifiable {
    public var id: String { rawValue }
}

private struct ChecklistRunSheet: View {
    let type: ChecklistType
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var checkedStates: [Bool]

    init(type: ChecklistType) {
        self.type = type
        _checkedStates = State(initialValue: Array(repeating: false, count: type.defaultItems.count))
    }

    private var allChecked: Bool { checkedStates.allSatisfy { $0 } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(type.defaultItems.enumerated()), id: \.offset) { index, item in
                    Button {
                        checkedStates[index].toggle()
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        HStack {
                            Image(systemName: checkedStates[index] ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checkedStates[index] ? .green : .secondary)
                            Text(item).foregroundStyle(.primary)
                        }
                    }
                }
            }
            .navigationTitle(type.rawValue)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { submit() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !allChecked {
                    Text("All items should be checked before the robot leaves the pit.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
        }
    }

    private func submit() {
        guard let user = authManager.currentUser else { return }
        let results = zip(type.defaultItems, checkedStates).map { ChecklistItemResult(text: $0, checked: $1) }
        let run = ChecklistRun(type: type, itemResults: results, completedByID: user.id, completedByName: user.name)
        context.insert(run)
        syncService?.pushChecklistRun(run)

        let event = ActivityEvent(authorID: user.id, authorName: user.name, kind: .checklistCompleted,
                                   message: "completed \(type.rawValue) checklist" + (allChecked ? "" : " (incomplete)"))
        context.insert(event)
        syncService?.pushActivity(event)

        UINotificationFeedbackGenerator().notificationOccurred(allChecked ? .success : .warning)
        dismiss()
    }
}

// MARK: - Inventory

private struct InventoryListView: View {
    @Query(sort: \InventoryItem.name) private var items: [InventoryItem]
    @State private var isPresentingNewItem = false
    @State private var isPresentingScanner = false
    @State private var searchText = ""
    @State private var filter: Filter = .all

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All items"
        case lowStock = "Low stock"
        case maintenance = "Maintenance"
        case checkedOut = "Checked out"
        var id: String { rawValue }
    }

    private var visibleItems: [InventoryItem] {
        items.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                item.category.localizedCaseInsensitiveContains(searchText) ||
                item.binLocation.localizedCaseInsensitiveContains(searchText) ||
                item.notes.localizedCaseInsensitiveContains(searchText) ||
                item.checkedOutByName.localizedCaseInsensitiveContains(searchText)
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .lowStock: matchesFilter = item.isLowStock
            case .maintenance: matchesFilter = item.needsMaintenance
            case .checkedOut: matchesFilter = item.isCheckedOut
            }
            return matchesSearch && matchesFilter
        }
    }

    private var lowStockCount: Int { items.filter { $0.isLowStock }.count }
    private var maintenanceCount: Int { items.filter { $0.needsMaintenance }.count }

    var body: some View {
        List {
            if items.isEmpty {
                EmptyStateView(icon: "shippingbox", title: "No items tracked",
                               subtitle: "Track quantities, storage locations, low stock, and maintenance.",
                               tint: .orange, actionTitle: "Add Item") { isPresentingNewItem = true }
                    .listRowSeparator(.hidden)
            } else {
                Section {
                    HStack(spacing: 14) {
                        Label("\(lowStockCount) low", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(lowStockCount == 0 ? .secondary : .orange)
                        Label("\(maintenanceCount) repair", systemImage: "wrench.and.screwdriver.fill")
                            .foregroundStyle(maintenanceCount == 0 ? .secondary : .red)
                    }
                    .font(.caption.weight(.medium))
                }
            }
            if !items.isEmpty && visibleItems.isEmpty {
                ContentUnavailableView("No matching items", systemImage: "magnifyingglass",
                                       description: Text("Change the search or inventory filter."))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(visibleItems) { item in
                    NavigationLink {
                        InventoryDetailView(item: item)
                    } label: {
                        InventoryRow(item: item)
                    }
                }
            }
            Section {
                Button { isPresentingNewItem = true } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search parts, categories, bins")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    ForEach(Filter.allCases) { option in
                        Button {
                            filter = option
                        } label: {
                            if filter == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Label(filter.rawValue, systemImage: "line.3.horizontal.decrease")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { isPresentingScanner = true } label: {
                    Label("Scan", systemImage: "qrcode.viewfinder")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewItem) { NewInventoryItemSheet() }
        .fullScreenCover(isPresented: $isPresentingScanner) { QRCheckInOutView() }
    }
}

private struct InventoryRow: View {
    let item: InventoryItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium))
                Text("\(item.category) · \(item.binLocation.isEmpty ? "No bin" : "Bin \(item.binLocation)")")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("Qty \(item.quantity)")
                        .foregroundStyle(item.isLowStock ? .orange : .secondary)
                    if item.isLowStock {
                        Text("Low stock").foregroundStyle(.orange)
                    }
                    if item.needsMaintenance {
                        Text("Maintenance").foregroundStyle(.red)
                    }
                }
                .font(.caption2.weight(.medium))
            }
            Spacer()
            if item.isCheckedOut {
                Text("Checked out")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct InventoryDetailView: View {
    @Bindable var item: InventoryItem
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var isPresentingEdit = false

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Category", value: item.category)
                LabeledContent("Bin location", value: item.binLocation.isEmpty ? "Not set" : item.binLocation)
                LabeledContent("Quantity", value: "\(item.quantity)")
                LabeledContent("Low stock alert at", value: "\(item.lowStockThreshold) or fewer")
                LabeledContent("Status", value: statusDescription)
                if !item.notes.isEmpty { LabeledContent("Notes", value: item.notes) }
            }

            Section {
                Button {
                    isPresentingEdit = true
                } label: {
                    Label("Edit item details", systemImage: "pencil")
                }
                Button {
                    item.needsMaintenance.toggle()
                    syncService?.pushInventoryItem(item)
                } label: {
                    Label(item.needsMaintenance ? "Mark maintenance complete" : "Flag for maintenance",
                          systemImage: item.needsMaintenance ? "checkmark.circle" : "wrench.and.screwdriver")
                }
            }

            Section("QR Label") {
                if let qrImage = QRCodeGenerator.generate(from: item.qrPayload) {
                    HStack {
                        Spacer()
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 160, height: 160)
                        Spacer()
                    }
                    ShareLink(item: Image(uiImage: qrImage), preview: SharePreview("\(item.name) QR Label", image: Image(uiImage: qrImage))) {
                        Label("Print / Share Label", systemImage: "square.and.arrow.up")
                    }
                }
            }

            Section {
                Button {
                    toggleCheckout()
                } label: {
                    Label(item.isCheckedOut ? "Check In" : "Check Out", systemImage: item.isCheckedOut ? "arrow.uturn.down" : "arrow.up.right")
                }
                .disabled(!item.isCheckedOut && (item.quantity == 0 || item.needsMaintenance))
            }
        }
        .navigationTitle(item.name)
        .sheet(isPresented: $isPresentingEdit) {
            NewInventoryItemSheet(item: item)
        }
    }

    private var statusDescription: String {
        if item.needsMaintenance { return "Needs maintenance" }
        if item.isCheckedOut { return "Checked out by \(item.checkedOutByName)" }
        return item.isLowStock ? "Low stock" : "Available"
    }

    private func toggleCheckout() {
        guard let user = authManager.currentUser else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        item.isCheckedOut.toggle()
        item.checkedOutByName = item.isCheckedOut ? user.name : ""
        syncService?.pushInventoryItem(item)

        let event = ActivityEvent(authorID: user.id, authorName: user.name, kind: .inventoryUpdated,
                                   message: item.isCheckedOut ? "checked out: \(item.name)" : "returned: \(item.name)")
        context.insert(event)
        syncService?.pushActivity(event)
    }
}

private struct NewInventoryItemSheet: View {
    let item: InventoryItem?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @State private var name: String
    @State private var category: String
    @State private var binLocation: String
    @State private var quantity: Int
    @State private var lowStockThreshold: Int
    @State private var needsMaintenance: Bool
    @State private var notes: String

    init(item: InventoryItem? = nil) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _category = State(initialValue: item?.category ?? "")
        _binLocation = State(initialValue: item?.binLocation ?? "")
        _quantity = State(initialValue: item?.quantity ?? 1)
        _lowStockThreshold = State(initialValue: item?.lowStockThreshold ?? 1)
        _needsMaintenance = State(initialValue: item?.needsMaintenance ?? false)
        _notes = State(initialValue: item?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Category (e.g. Electronics)", text: $category)
                TextField("Bin location (e.g. Shelf 2, Bin B)", text: $binLocation)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 0...1000)
                Stepper("Low stock alert at: \(lowStockThreshold)", value: $lowStockThreshold, in: 0...1000)
                Toggle("Needs maintenance", isOn: $needsMaintenance)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBin = binLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let inventoryItem: InventoryItem
        if let item {
            inventoryItem = item
            item.name = cleanName
            item.category = cleanCategory.isEmpty ? "Uncategorized" : cleanCategory
            item.binLocation = cleanBin
            item.quantity = quantity
            item.lowStockThreshold = lowStockThreshold
            item.needsMaintenance = needsMaintenance
            item.notes = notes
        } else {
            inventoryItem = InventoryItem(
                name: cleanName, category: cleanCategory.isEmpty ? "Uncategorized" : cleanCategory,
                binLocation: cleanBin, quantity: quantity, notes: notes,
                lowStockThreshold: lowStockThreshold, needsMaintenance: needsMaintenance
            )
            context.insert(inventoryItem)
        }
        syncService?.pushInventoryItem(inventoryItem)
        dismiss()
    }
}

// MARK: - QR generation helper

enum QRCodeGenerator {
    static func generate(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    let router = TabRouter()
    return PitOpsTabView()
        .modelContainer(container)
        .environment(authManager)
        .environment(router)
}
