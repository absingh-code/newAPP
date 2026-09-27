//
//  PitOpsModels.swift
//  FTCTeamHub
//
//  Data models for the Pit Ops tab: battery cycle tracking, pre/post
//  flight + robot inspection checklists, and parts/tools inventory with
//  QR labels. This file was missing from the repo, which is why
//  ChecklistType/Battery/ChecklistRun/InventoryItem/ChecklistItemResult
//  were all "cannot find in scope" across multiple other files.
//

import Foundation
import SwiftData

// MARK: - Battery Cycle Tracker

enum BatteryStatus: String, Codable, CaseIterable, Identifiable {
    case charged = "Charged"
    case inUse = "In Use"
    case charging = "Charging"
    case dead = "Dead"
    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .charged: return "battery.100"
        case .inUse: return "battery.75"
        case .charging: return "battery.100.bolt"
        case .dead: return "battery.0"
        }
    }
}

@Model
final class Battery {
    @Attribute(.unique) var id: UUID
    var label: String
    var statusRaw: String
    var cycleCount: Int
    var lastChargedAt: Date?
    var notes: String
    var addedAt: Date

    var status: BatteryStatus {
        get { BatteryStatus(rawValue: statusRaw) ?? .charged }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), label: String, status: BatteryStatus = .charged,
         cycleCount: Int = 0, lastChargedAt: Date? = nil, notes: String = "", addedAt: Date = .now) {
        self.id = id
        self.label = label
        self.statusRaw = status.rawValue
        self.cycleCount = cycleCount
        self.lastChargedAt = lastChargedAt
        self.notes = notes
        self.addedAt = addedAt
    }
}

// MARK: - Checklists

enum ChecklistType: String, Codable, CaseIterable {
    case preFlight = "Pre-Flight"
    case postFlight = "Post-Flight"
    case robotInspection = "Robot Inspection"

    var defaultItems: [String] {
        switch self {
        case .preFlight:
            return [
                "Set screws tightened",
                "Chains / belts tensioned",
                "Battery voltage checked (12.0V+)",
                "Phone / Control Hub mount secured",
                "Code configuration verified",
                "Bumpers on and legal",
                "Wiring inspected, no loose connectors"
            ]
        case .postFlight:
            return [
                "Battery removed and placed on charger",
                "Field-damage inspection",
                "Loose hardware check",
                "Notes logged for next match"
            ]
        case .robotInspection:
            return [
                "Robot fits within the 18x18x18 inch sizing cube at start",
                "Robot weight within the game manual's limit",
                "Team number clearly visible on robot",
                "Bumpers meet color/size/coverage requirements",
                "No banned materials or mechanisms present",
                "Battery securely mounted, no exposed terminals",
                "No exposed sharp edges or pinch points",
                "Transmitter/Control Hub properly labeled with team number"
            ]
        }
    }

    var systemImage: String {
        switch self {
        case .preFlight: return "checkmark.shield"
        case .postFlight: return "checkmark.shield.fill"
        case .robotInspection: return "ruler"
        }
    }
}

struct ChecklistItemResult: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var checked: Bool
}

@Model
final class ChecklistRun {
    @Attribute(.unique) var id: UUID
    var typeRaw: String
    var itemResults: [ChecklistItemResult]
    var completedByID: UUID
    var completedByName: String
    var timestamp: Date

    var type: ChecklistType {
        get { ChecklistType(rawValue: typeRaw) ?? .preFlight }
        set { typeRaw = newValue.rawValue }
    }

    var allChecked: Bool { itemResults.allSatisfy { $0.checked } }

    init(id: UUID = UUID(), type: ChecklistType, itemResults: [ChecklistItemResult],
         completedByID: UUID, completedByName: String, timestamp: Date = .now) {
        self.id = id
        self.typeRaw = type.rawValue
        self.itemResults = itemResults
        self.completedByID = completedByID
        self.completedByName = completedByName
        self.timestamp = timestamp
    }
}

// MARK: - Parts & Tools Inventory

@Model
final class InventoryItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var category: String
    var binLocation: String
    var quantity: Int
    var isCheckedOut: Bool
    var checkedOutByName: String
    var notes: String
    var lowStockThresholdValue: Int?
    var needsMaintenanceValue: Bool?
    var addedAt: Date

    var lowStockThreshold: Int {
        get { max(lowStockThresholdValue ?? 1, 0) }
        set { lowStockThresholdValue = max(newValue, 0) }
    }

    var needsMaintenance: Bool {
        get { needsMaintenanceValue ?? false }
        set { needsMaintenanceValue = newValue }
    }

    var isLowStock: Bool { quantity <= lowStockThreshold }

    init(id: UUID = UUID(), name: String, category: String, binLocation: String,
         quantity: Int = 1, isCheckedOut: Bool = false, checkedOutByName: String = "",
         notes: String = "", lowStockThreshold: Int = 1, needsMaintenance: Bool = false,
         addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.category = category
        self.binLocation = binLocation
        self.quantity = quantity
        self.isCheckedOut = isCheckedOut
        self.checkedOutByName = checkedOutByName
        self.notes = notes
        self.lowStockThresholdValue = lowStockThreshold
        self.needsMaintenanceValue = needsMaintenance
        self.addedAt = addedAt
    }

    var qrPayload: String { "ftcteamhub:item:\(id.uuidString)" }
}
