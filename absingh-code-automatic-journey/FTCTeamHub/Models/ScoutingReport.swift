import Foundation
import SwiftData

@Model
final class ScoutingReport {
    @Attribute(.unique) var id: UUID
    var teamNumber: Int
    var teamName: String
    var eventName: String
    var matchNumber: String
    var autonomousScore: Int
    var teleOpScore: Int
    var endgameScore: Int
    var capabilities: [String]
    var notes: String
    var recordedByID: UUID
    var recordedByName: String
    var observedAt: Date

    init(id: UUID = UUID(), teamNumber: Int, teamName: String, eventName: String,
         matchNumber: String, autonomousScore: Int = 0, teleOpScore: Int = 0,
         endgameScore: Int = 0, capabilities: [String] = [], notes: String = "",
         recordedByID: UUID, recordedByName: String, observedAt: Date = .now) {
        self.id = id
        self.teamNumber = teamNumber
        self.teamName = teamName
        self.eventName = eventName
        self.matchNumber = matchNumber
        self.autonomousScore = autonomousScore
        self.teleOpScore = teleOpScore
        self.endgameScore = endgameScore
        self.capabilities = capabilities
        self.notes = notes
        self.recordedByID = recordedByID
        self.recordedByName = recordedByName
        self.observedAt = observedAt
    }

    var totalScore: Int { autonomousScore + teleOpScore + endgameScore }
}
