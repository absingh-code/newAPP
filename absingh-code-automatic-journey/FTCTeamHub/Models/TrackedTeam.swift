//
//  TrackedTeam.swift
//  FTCTeamHub
//
//  A locally-saved bookmark pointing at a real FTC team (usually an
//  upcoming opponent or alliance partner), so the team doesn't have to
//  re-search the same team number every time before an event. This is
//  separate from `AppUser` — it represents an EXTERNAL team, not a member
//  of your own roster.
//

import Foundation
import SwiftData

@Model
final class TrackedTeam {
    @Attribute(.unique) var id: UUID
    var teamNumber: Int
    var teamName: String
    var note: String
    var addedByID: UUID
    var addedByName: String
    var addedAt: Date

    init(id: UUID = UUID(),
         teamNumber: Int,
         teamName: String,
         note: String = "",
         addedByID: UUID,
         addedByName: String,
         addedAt: Date = .now) {
        self.id = id
        self.teamNumber = teamNumber
        self.teamName = teamName
        self.note = note
        self.addedByID = addedByID
        self.addedByName = addedByName
        self.addedAt = addedAt
    }
}
