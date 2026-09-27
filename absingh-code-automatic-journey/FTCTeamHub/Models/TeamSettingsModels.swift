//
//  TeamSettingsModels.swift
//  FTCTeamHub
//
//  Team profile settings plus a Budget & Sponsorship tracker.
//

import Foundation
import SwiftData

// MARK: - Team Settings (one shared row, synced so the whole team sees the same info)

@Model
final class TeamSettings {
    @Attribute(.unique) var id: UUID
    var teamNumber: Int
    var teamName: String
    var rookieYear: Int
    var seasonName: String

    init(id: UUID = UUID(),
         teamNumber: Int = 0,
         teamName: String = "My FTC Team",
         rookieYear: Int = Calendar.current.component(.year, from: .now),
         seasonName: String = "2026-2027") {
        self.id = id
        self.teamNumber = teamNumber
        self.teamName = teamName
        self.rookieYear = rookieYear
        self.seasonName = seasonName
    }
}

// MARK: - Sponsors

enum SponsorStatus: String, Codable, CaseIterable, Identifiable {
    case contacted = "Contacted"
    case pledged = "Pledged"
    case received = "Received"
    var id: String { rawValue }

    var color: String {
        switch self {
        case .contacted: return "systemGray"
        case .pledged: return "systemOrange"
        case .received: return "systemGreen"
        }
    }
}

@Model
final class Sponsor {
    @Attribute(.unique) var id: UUID
    var name: String
    var contactName: String
    var contactEmail: String
    var pledgedAmount: Double
    var receivedAmount: Double
    var statusRaw: String
    var notes: String
    var addedAt: Date

    var status: SponsorStatus {
        get { SponsorStatus(rawValue: statusRaw) ?? .contacted }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, contactName: String = "", contactEmail: String = "",
         pledgedAmount: Double = 0, receivedAmount: Double = 0, status: SponsorStatus = .contacted,
         notes: String = "", addedAt: Date = .now) {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.contactEmail = contactEmail
        self.pledgedAmount = pledgedAmount
        self.receivedAmount = receivedAmount
        self.statusRaw = status.rawValue
        self.notes = notes
        self.addedAt = addedAt
    }
}

// MARK: - Budget Expenses

@Model
final class BudgetExpense {
    @Attribute(.unique) var id: UUID
    var item: String
    var amount: Double
    var category: String
    var date: Date
    var notes: String
    var addedByName: String

    init(id: UUID = UUID(), item: String, amount: Double, category: String,
         date: Date = .now, notes: String = "", addedByName: String) {
        self.id = id
        self.item = item
        self.amount = amount
        self.category = category
        self.date = date
        self.notes = notes
        self.addedByName = addedByName
    }
}
