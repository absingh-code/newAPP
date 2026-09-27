//
//  Models.swift
//  FTCTeamHub
//
//  Core SwiftData models. See PitOpsModels.swift for Battery, ChecklistRun,
//  and InventoryItem (added separately to keep this file from ballooning).
//
//  CHANGE: TestRunRecord gained `batteryLabel: String?` so practice runs
//  can be tagged with which battery was in the robot, letting the Pit Ops
//  tab flag a specific battery as underperforming over time.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Roles & Avatar Colors

enum TeamRole: String, Codable, CaseIterable, Identifiable {
    case softwareLead = "Software Lead"
    case hardware = "Hardware"
    case strategy = "Strategy"
    case builder = "Builder"
    case outreach = "Outreach"
    case mentor = "Mentor"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .softwareLead: return "chevron.left.forwardslash.chevron.right"
        case .hardware: return "wrench.and.screwdriver"
        case .strategy: return "chart.bar.xaxis"
        case .builder: return "hammer"
        case .outreach: return "megaphone"
        case .mentor: return "person.badge.shield.checkmark"
        }
    }
}

enum AvatarColor: String, Codable, CaseIterable, Identifiable {
    case blue, red, green, orange, purple, pink, teal, indigo

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .red: return .red
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .pink: return .pink
        case .teal: return .teal
        case .indigo: return .indigo
        }
    }
}

// MARK: - AppUser

@Model
final class AppUser {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var email: String
    var name: String
    var roleRaw: String
    var avatarColorRaw: String
    var passwordHash: String
    var isLogged: Bool
    var joinedAt: Date

    init(id: UUID = UUID(),
         email: String,
         name: String,
         role: TeamRole,
         avatarColor: AvatarColor,
         passwordHash: String,
         isLogged: Bool = false,
         joinedAt: Date = .now) {
        self.id = id
        self.email = email
        self.name = name
        self.roleRaw = role.rawValue
        self.avatarColorRaw = avatarColor.rawValue
        self.passwordHash = passwordHash
        self.isLogged = isLogged
        self.joinedAt = joinedAt
    }

    var role: TeamRole {
        get { TeamRole(rawValue: roleRaw) ?? .builder }
        set { roleRaw = newValue.rawValue }
    }

    var avatarColor: AvatarColor {
        get { AvatarColor(rawValue: avatarColorRaw) ?? .blue }
        set { avatarColorRaw = newValue.rawValue }
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

// MARK: - Tasks & Kanban

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case low = "Low", medium = "Medium", high = "High", critical = "Critical"
    var id: String { rawValue }
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case toDo = "To Do", inProgress = "In Progress", blocked = "Blocked", done = "Done"
    var id: String { rawValue }
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var taskDescription: String
    var assignedToID: UUID?
    var assignedToName: String
    var status: TaskStatus
    var priority: TaskPriority
    var deadline: Date?
    var tags: [String]
    var dateCreated: Date
    var authorID: UUID
    var authorName: String
    var lastModified: Date

    init(id: UUID = UUID(),
         title: String,
         taskDescription: String = "",
         assignedToID: UUID? = nil,
         assignedToName: String = "Unassigned",
         status: TaskStatus = .toDo,
         priority: TaskPriority = .medium,
         deadline: Date? = nil,
         tags: [String] = [],
         dateCreated: Date = .now,
         authorID: UUID,
         authorName: String,
         lastModified: Date = .now) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.assignedToID = assignedToID
        self.assignedToName = assignedToName
        self.status = status
        self.priority = priority
        self.deadline = deadline
        self.tags = tags
        self.dateCreated = dateCreated
        self.authorID = authorID
        self.authorName = authorName
        self.lastModified = lastModified
    }
}

// MARK: - Engineering Notebook

struct AutonomousTestLog: Codable, Hashable {
    var routineName: String
    var startingPosition: String
    var samplesOrSpecimensScored: Int
    var cycleTimeSeconds: Double
    var successRatePercent: Double
    var failureNotes: String
}

struct ControlHubConfigLog: Codable, Hashable {
    var controlHubOSVersion: String
    var sdkVersion: String
    var expansionHubCount: Int
    var motorPortMap: [String: String]
    var servoPortMap: [String: String]
}

struct IMUTuningLog: Codable, Hashable {
    var chip: String
    var logoFacingDirection: String
    var usbFacingDirection: String
    var yawOffsetDegrees: Double
    var driftOverTenMinDegrees: Double
    var calibrationNotes: String
}

enum NotebookTemplate: String, CaseIterable, Identifiable {
    case blank = "Blank Entry"
    case softwareLog = "Software Log"
    case hardwareLog = "Hardware Log"
    case autonomousTest = "Autonomous Routine Test"
    case controlHubConfig = "Control Hub Config"
    case imuTuning = "IMU Tuning (BHI260AP)"
    var id: String { rawValue }
}

@Model
final class NotebookEntry {
    @Attribute(.unique) var id: UUID
    var authorID: UUID
    var authorName: String
    var title: String
    var content: String
    var tags: [String]
    var timestamp: Date

    var autonomousLog: AutonomousTestLog?
    var hubConfigLog: ControlHubConfigLog?
    var imuLog: IMUTuningLog?

    var attachmentFileNames: [String]

    init(id: UUID = UUID(),
         authorID: UUID,
         authorName: String,
         title: String,
         content: String = "",
         tags: [String] = [],
         timestamp: Date = .now,
         autonomousLog: AutonomousTestLog? = nil,
         hubConfigLog: ControlHubConfigLog? = nil,
         imuLog: IMUTuningLog? = nil,
         attachmentFileNames: [String] = []) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.title = title
        self.content = content
        self.tags = tags
        self.timestamp = timestamp
        self.autonomousLog = autonomousLog
        self.hubConfigLog = hubConfigLog
        self.imuLog = imuLog
        self.attachmentFileNames = attachmentFileNames
    }
}

// MARK: - Internal Robot Testing & Telemetry

@Model
final class TestRunRecord {
    @Attribute(.unique) var id: UUID
    var driverID: UUID
    var driverName: String
    var date: Date
    var autoScore: Int
    var teleopScore: Int
    var endgameScore: Int
    var cycleTimeSeconds: Double
    var autoConsistencyPercent: Double
    var mechanicalIssues: [String]
    var notes: String
    var recordedByID: UUID
    var recordedByName: String
    /// Label of the battery installed for this run (e.g. "B1"), if tracked.
    var batteryLabel: String?

    init(id: UUID = UUID(),
         driverID: UUID,
         driverName: String,
         date: Date = .now,
         autoScore: Int = 0,
         teleopScore: Int = 0,
         endgameScore: Int = 0,
         cycleTimeSeconds: Double = 0,
         autoConsistencyPercent: Double = 0,
         mechanicalIssues: [String] = [],
         notes: String = "",
         recordedByID: UUID,
         recordedByName: String,
         batteryLabel: String? = nil) {
        self.id = id
        self.driverID = driverID
        self.driverName = driverName
        self.date = date
        self.autoScore = autoScore
        self.teleopScore = teleopScore
        self.endgameScore = endgameScore
        self.cycleTimeSeconds = cycleTimeSeconds
        self.autoConsistencyPercent = autoConsistencyPercent
        self.mechanicalIssues = mechanicalIssues
        self.notes = notes
        self.recordedByID = recordedByID
        self.recordedByName = recordedByName
        self.batteryLabel = batteryLabel
    }

    var totalScore: Int { autoScore + teleopScore + endgameScore }
}

// MARK: - Ideas & Whiteboard

struct IdeaComment: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var authorID: UUID
    var authorName: String
    var text: String
    var timestamp: Date = .now
}

@Model
final class Idea {
    @Attribute(.unique) var id: UUID
    var authorID: UUID
    var authorName: String
    var summary: String
    var detail: String
    var upvoterIDs: [UUID]
    var comments: [IdeaComment]
    var timestamp: Date
    var promotedToTask: Bool

    init(id: UUID = UUID(),
         authorID: UUID,
         authorName: String,
         summary: String,
         detail: String = "",
         upvoterIDs: [UUID] = [],
         comments: [IdeaComment] = [],
         timestamp: Date = .now,
         promotedToTask: Bool = false) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.summary = summary
        self.detail = detail
        self.upvoterIDs = upvoterIDs
        self.comments = comments
        self.timestamp = timestamp
        self.promotedToTask = promotedToTask
    }

    var upvoteCount: Int { upvoterIDs.count }
}

// MARK: - Internal Activity Feed

enum ActivityKind: String, Codable {
    case taskCompleted, taskCreated, testLogged, ideaPosted, ideaUpvoted, notebookEntry
    case checklistCompleted, batteryStatusChanged, inventoryUpdated
}

@Model
final class ActivityEvent {
    @Attribute(.unique) var id: UUID
    var authorID: UUID
    var authorName: String
    var kind: ActivityKind
    var message: String
    var timestamp: Date

    init(id: UUID = UUID(),
         authorID: UUID,
         authorName: String,
         kind: ActivityKind,
         message: String,
         timestamp: Date = .now) {
        self.id = id
        self.authorID = authorID
        self.authorName = authorName
        self.kind = kind
        self.message = message
        self.timestamp = timestamp
    }

    var systemImage: String {
        switch kind {
        case .taskCompleted: return "checkmark.circle.fill"
        case .taskCreated: return "plus.circle"
        case .testLogged: return "gauge.with.dots.needle.67percent"
        case .ideaPosted: return "lightbulb.fill"
        case .ideaUpvoted: return "hand.thumbsup.fill"
        case .notebookEntry: return "book.closed.fill"
        case .checklistCompleted: return "checklist"
        case .batteryStatusChanged: return "battery.75"
        case .inventoryUpdated: return "shippingbox.fill"
        }
    }
}
