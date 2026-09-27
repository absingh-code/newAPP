//
//  ScoringModels.swift
//  FTCTeamHub
//
//  Backing model for the Scoring Simulator. Deliberately fully
//  user-configurable rather than hardcoded: as of this build, the
//  2026-2027 "BIOBUZZ" season kicks off TODAY and official point values
//  aren't published yet. Hardcoding guessed numbers would actively
//  mislead alliance-selection strategy, so instead the team edits these
//  once the real Game Manual is released, and the calculator works
//  correctly for every future season without needing an app update.
//

import Foundation
import SwiftData

enum ScoringPhase: String, Codable, CaseIterable, Identifiable {
    case autonomous = "Autonomous"
    case teleop = "TeleOp"
    case endgame = "Endgame"
    var id: String { rawValue }
}

@Model
final class ScoringElement {
    @Attribute(.unique) var id: UUID
    var name: String
    var phaseRaw: String
    var pointValue: Int
    var sortOrder: Int

    var phase: ScoringPhase {
        get { ScoringPhase(rawValue: phaseRaw) ?? .autonomous }
        set { phaseRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, phase: ScoringPhase, pointValue: Int = 0, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.phaseRaw = phase.rawValue
        self.pointValue = pointValue
        self.sortOrder = sortOrder
    }
}
