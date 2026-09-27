//
//  InsightsEngine.swift
//  FTCTeamHub
//
//  "AI-style" local feedback — but built honestly: this is rule-based
//  trend analysis over your own logged data, computed entirely on-device
//  with no network call and no actual language model. Framed as
//  "Insights" rather than "AI" in the UI for that reason. It still gives
//  genuinely useful, automatically-generated coaching-style observations
//  a rookie team wouldn't necessarily think to check for themselves.
//

import Foundation

struct Insight: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let tint: InsightTint
}

enum InsightTint {
    case positive, warning, neutral
}

enum InsightsEngine {

    static func generate(testRuns: [TestRunRecord], batteries: [Battery], tasks: [TaskItem]) -> [Insight] {
        var insights: [Insight] = []

        // Trend: compare most recent 3 runs vs the 3 before that.
        let sorted = testRuns.sorted { $0.date < $1.date }
        if sorted.count >= 6 {
            let recent = sorted.suffix(3)
            let previous = sorted.suffix(6).prefix(3)
            let recentAvg = Double(recent.reduce(0) { $0 + $1.totalScore }) / 3
            let previousAvg = Double(previous.reduce(0) { $0 + $1.totalScore }) / 3
            if previousAvg > 0 {
                let change = (recentAvg - previousAvg) / previousAvg * 100
                if change <= -15 {
                    insights.append(Insight(icon: "arrow.down.right.circle.fill",
                                             text: String(format: "Average score dropped %.0f%% over your last 3 runs — worth checking for a regression.", abs(change)),
                                             tint: .warning))
                } else if change >= 15 {
                    insights.append(Insight(icon: "arrow.up.right.circle.fill",
                                             text: String(format: "Average score is up %.0f%% over your last 3 runs — whatever changed, keep it.", change),
                                             tint: .positive))
                }
            }
        }

        // Most common failure this week.
        let calendar = Calendar.current
        let recentRuns = testRuns.filter { calendar.dateComponents([.day], from: $0.date, to: .now).day ?? 99 <= 7 }
        let failureCounts = recentRuns.flatMap(\.mechanicalIssues).reduce(into: [String: Int]()) { counts, issue in
            counts[issue, default: 0] += 1
        }
        if let topFailure = failureCounts.max(by: { $0.value < $1.value }), topFailure.value >= 2 {
            insights.append(Insight(icon: "wrench.and.screwdriver.fill",
                                     text: "\"\(topFailure.key)\" has come up \(topFailure.value) times this week — might be worth a dedicated fix session.",
                                     tint: .warning))
        }

        // Battery flags.
        let deadBatteries = batteries.filter { $0.status == .dead }
        if !deadBatteries.isEmpty {
            insights.append(Insight(icon: "battery.0",
                                     text: "\(deadBatteries.count) battery\(deadBatteries.count == 1 ? "" : "ies") marked dead — remove from rotation before your next event.",
                                     tint: .warning))
        }

        // Overdue critical tasks.
        let overdueCritical = tasks.filter { $0.status != .done && $0.priority == .critical && ($0.deadline ?? .distantFuture) < .now }
        if !overdueCritical.isEmpty {
            insights.append(Insight(icon: "exclamationmark.octagon.fill",
                                     text: "\(overdueCritical.count) critical-priority task\(overdueCritical.count == 1 ? "" : "s") overdue — these are blocking-severity by definition.",
                                     tint: .warning))
        }

        // Consistency check.
        if let last = testRuns.sorted(by: { $0.date > $1.date }).first, last.autoConsistencyPercent < 50 {
            insights.append(Insight(icon: "waveform.path.ecg",
                                     text: String(format: "Latest logged autonomous consistency was only %.0f%% — consider re-tuning before relying on it in a match.", last.autoConsistencyPercent),
                                     tint: .warning))
        }

        if insights.isEmpty {
            insights.append(Insight(icon: "checkmark.seal.fill",
                                     text: "No red flags in your recent data. Keep logging test runs to build a longer trend history.",
                                     tint: .positive))
        }

        return insights
    }
}
