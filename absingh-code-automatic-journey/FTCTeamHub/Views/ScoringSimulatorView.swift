//
//  ScoringSimulatorView.swift
//  FTCTeamHub
//
//  Configurable scoring calculator for alliance-selection strategy:
//  set your season's actual point values once (Manage Elements), then
//  tally expected points for "Your Alliance" vs "Opponent Alliance" by
//  stepping through counts per scoring action, grouped by match phase.
//

import SwiftUI
import SwiftData
import UIKit

struct ScoringSimulatorView: View {
    @Query(sort: \ScoringElement.sortOrder) private var elements: [ScoringElement]
    @Environment(\.modelContext) private var context

    @State private var yourCounts: [UUID: Int] = [:]
    @State private var opponentCounts: [UUID: Int] = [:]
    @State private var isPresentingManageElements = false

    private var yourTotal: Int {
        elements.reduce(0) { $0 + $1.pointValue * (yourCounts[$1.id] ?? 0) }
    }
    private var opponentTotal: Int {
        elements.reduce(0) { $0 + $1.pointValue * (opponentCounts[$1.id] ?? 0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            comparisonHeader

            if elements.isEmpty {
                EmptyStateView(icon: "sum", title: "No scoring elements yet",
                               subtitle: "Add your season's scoring actions and point values to start calculating.",
                               tint: .indigo, actionTitle: "Add Elements") { isPresentingManageElements = true }
            } else {
                List {
                    ForEach(ScoringPhase.allCases) { phase in
                        let phaseElements = elements.filter { $0.phase == phase }
                        if !phaseElements.isEmpty {
                            Section(phase.rawValue) {
                                ForEach(phaseElements) { element in
                                    ScoringElementRow(
                                        element: element,
                                        yourCount: Binding(get: { yourCounts[element.id] ?? 0 },
                                                            set: { yourCounts[element.id] = $0 }),
                                        opponentCount: Binding(get: { opponentCounts[element.id] ?? 0 },
                                                                set: { opponentCounts[element.id] = $0 })
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingManageElements = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Reset Counts") {
                    yourCounts = [:]
                    opponentCounts = [:]
                }
            }
        }
        .sheet(isPresented: $isPresentingManageElements) {
            ManageScoringElementsSheet()
        }
    }

    private var comparisonHeader: some View {
        HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Your Alliance").font(.caption).foregroundStyle(.secondary)
                Text("\(yourTotal)").font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Image(systemName: yourTotal >= opponentTotal ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(yourTotal >= opponentTotal ? .green : .red)
                Text("\(abs(yourTotal - opponentTotal))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60)

            VStack(spacing: 2) {
                Text("Opponent").font(.caption).foregroundStyle(.secondary)
                Text("\(opponentTotal)").font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.red)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }
}

private struct ScoringElementRow: View {
    let element: ScoringElement
    @Binding var yourCount: Int
    @Binding var opponentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(element.name).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(element.pointValue) pt\(element.pointValue == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 20) {
                CounterControl(label: "Yours", value: $yourCount, tint: .blue)
                CounterControl(label: "Opp.", value: $opponentCount, tint: .red)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CounterControl: View {
    let label: String
    @Binding var value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption2).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                value = max(0, value - 1)
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(tint.opacity(0.7))
            }
            .buttonStyle(.plain)
            Text("\(value)").font(.subheadline.monospacedDigit().weight(.semibold)).frame(minWidth: 20)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                value += 1
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(tint)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Manage elements

private struct ManageScoringElementsSheet: View {
    @Query(sort: \ScoringElement.sortOrder) private var elements: [ScoringElement]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingNew = false

    var body: some View {
        NavigationStack {
            List {
                if elements.isEmpty {
                    Text("No elements yet. Add one per scoring action from your game manual.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(elements) { element in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(element.name)
                            Text(element.phase.rawValue).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("\(element.pointValue) pts", value: Binding(
                            get: { element.pointValue },
                            set: { element.pointValue = $0 }
                        ), in: 0...100)
                        .fixedSize()
                        .labelsHidden()
                        Text("\(element.pointValue)").font(.subheadline.monospacedDigit())
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Scoring Elements")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isPresentingNew) { NewScoringElementSheet(nextSortOrder: elements.count) }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(elements[index]) }
    }
}

private struct NewScoringElementSheet: View {
    let nextSortOrder: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var phase: ScoringPhase = .autonomous
    @State private var pointValue = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Scoring action name", text: $name)
                Picker("Phase", selection: $phase) {
                    ForEach(ScoringPhase.allCases) { Text($0.rawValue).tag($0) }
                }
                Stepper("Points: \(pointValue)", value: $pointValue, in: 0...100)
            }
            .navigationTitle("New Element")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() {
        context.insert(ScoringElement(name: name, phase: phase, pointValue: pointValue, sortOrder: nextSortOrder))
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ScoringSimulatorView()
    }
    .modelContainer(makePreviewContainer())
}
