//
//  MatchTimerView.swift
//  FTCTeamHub
//
//  Drive Team Timer — the FTC match cycle (30s Auto / 90s TeleOp / 30s
//  Endgame) with haptic phase cues, PLUS phase-specific legal reminders
//  (drive team conduct rules) so drivers get a quick nudge about what's
//  and isn't allowed during each phase, without needing to memorize the
//  whole manual mid-match.
//

import SwiftUI
import UIKit

struct MatchTimerView: View {
    private let totalDuration = 150
    private let autoEnd = 30
    private let endgameStart = 120

    @State private var elapsedSeconds = 0
    @State private var isRunning = false
    @State private var lastAnnouncedPhase: Phase = .notStarted

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum Phase: Equatable {
        case notStarted, autonomous, teleop, endgame, complete

        var label: String {
            switch self {
            case .notStarted: return "Ready"
            case .autonomous: return "Autonomous"
            case .teleop: return "TeleOp"
            case .endgame: return "Endgame"
            case .complete: return "Match Complete"
            }
        }

        var color: Color {
            switch self {
            case .notStarted: return .secondary
            case .autonomous: return .orange
            case .teleop: return .blue
            case .endgame: return .red
            case .complete: return .green
            }
        }

        /// General drive-team-conduct reminders. Deliberately generic
        /// (not season-specific game rules) since those change every year —
        /// see the Team tab's Rules Reference for season-specific details.
        var reminder: String? {
            switch self {
            case .notStarted:
                return "Confirm alliance color, Driver Hub connection, and E-Stop access before starting."
            case .autonomous:
                return "Hands off the controls — autonomous code only, no driver input."
            case .teleop:
                return "Only drivers touch controls. Human player follows placement rules, no touching the robot."
            case .endgame:
                return "Check parking/hang legality carefully — illegal contact or early scoring claims can draw a penalty."
            case .complete:
                return "Match over — no further scoring actions count after 0:00."
            }
        }
    }

    private var currentPhase: Phase {
        phase(at: elapsedSeconds)
    }

    private func phase(at elapsed: Int) -> Phase {
        if elapsed <= 0 { return .notStarted }
        if elapsed < autoEnd { return .autonomous }
        if elapsed < endgameStart { return .teleop }
        if elapsed < totalDuration { return .endgame }
        return .complete
    }

    private var remaining: Int { max(0, totalDuration - elapsedSeconds) }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text(currentPhase.label)
                .font(.title2.weight(.semibold))
                .foregroundStyle(currentPhase.color)

            Text(timeString(remaining))
                .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            PhaseProgressBar(elapsedSeconds: elapsedSeconds, autoEnd: autoEnd, endgameStart: endgameStart, total: totalDuration)
                .frame(height: 10)
                .padding(.horizontal, 40)

            if let reminder = currentPhase.reminder {
                Label(reminder, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)

                Button {
                    toggleRunning()
                } label: {
                    Label(isRunning ? "Pause" : (elapsedSeconds == 0 ? "Start Match" : "Resume"), systemImage: isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentPhase == .complete)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .onReceive(timer) { _ in
            guard isRunning, elapsedSeconds < totalDuration else { return }
            elapsedSeconds += 1
            let newPhase = phase(at: elapsedSeconds)
            if newPhase != lastAnnouncedPhase {
                lastAnnouncedPhase = newPhase
                announce(newPhase)
            }
        }
    }

    private func toggleRunning() {
        if !isRunning && elapsedSeconds == 0 {
            lastAnnouncedPhase = .autonomous
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        isRunning.toggle()
    }

    private func reset() {
        isRunning = false
        elapsedSeconds = 0
        lastAnnouncedPhase = .notStarted
    }

    private func announce(_ phase: Phase) {
        switch phase {
        case .teleop, .endgame:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .complete:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        default:
            break
        }
    }

    private func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct PhaseProgressBar: View {
    let elapsedSeconds: Int
    let autoEnd: Int
    let endgameStart: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    Capsule().fill(Color.orange.opacity(0.25)).frame(width: geo.size.width * CGFloat(autoEnd) / CGFloat(total))
                    Capsule().fill(Color.blue.opacity(0.25)).frame(width: geo.size.width * CGFloat(endgameStart - autoEnd) / CGFloat(total))
                    Capsule().fill(Color.red.opacity(0.25)).frame(width: geo.size.width * CGFloat(total - endgameStart) / CGFloat(total))
                }
                Capsule()
                    .fill(Color.primary.opacity(0.8))
                    .frame(width: geo.size.width * CGFloat(min(elapsedSeconds, total)) / CGFloat(total))
            }
        }
    }
}

#Preview {
    MatchTimerView()
}
