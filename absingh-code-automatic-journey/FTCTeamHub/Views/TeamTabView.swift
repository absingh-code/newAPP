//
//  TeamTabView.swift
//  FTCTeamHub
//
//  NEW: added a "Rules" segment — a searchable plain-language glossary of
//  common FTC terminology plus direct links to the OFFICIAL Game Manual
//  and Q&A System. Deliberately does NOT reproduce manual text verbatim
//  (that's FIRST's copyrighted material, and it changes every season) —
//  instead it explains concepts in original wording and sends you to the
//  authoritative source for actual rule numbers and point values.
//
//  NEW: the "Version 1.0" label in AboutView is now wrapped in
//  SecretResetTrigger — tap it 7 times within 3 seconds to reveal the
//  hidden "Reset App Data" flow. No visible reset button exists anywhere
//  else in the app.
//

import SwiftUI
import SwiftData
import UIKit

struct TeamTabView: View {
    @State private var section: Section = .profile

    enum Section: String, CaseIterable, Identifiable {
        case profile = "Profile", budget = "Budget", rules = "Rules", about = "About"
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
                case .profile: ProfileSettingsView()
                case .budget: BudgetView()
                case .rules: RulesReferenceView()
                case .about: AboutView()
                }
            }
            .navigationTitle("Team")
        }
    }
}

// MARK: - Profile & Team Settings

private struct ProfileSettingsView: View {
    @Query private var teamSettingsList: [TeamSettings]
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @AppStorage("accentColorRaw") private var accentColorRaw: String = AvatarColor.blue.rawValue

    private var teamSettings: TeamSettings {
        if let existing = teamSettingsList.first { return existing }
        let created = TeamSettings()
        context.insert(created)
        return created
    }

    var body: some View {
        Form {
            if let user = authManager.currentUser {
                Section("Signed in as") {
                    LabeledContent("Name", value: user.name)
                    LabeledContent("Email", value: user.email)
                    LabeledContent("Role", value: user.role.rawValue)
                }
            }

            Section("Team Profile") {
                TeamSettingsFields(teamSettings: teamSettings, syncService: syncService)
            }

            Section("App Accent Color") {
                HStack(spacing: 12) {
                    ForEach(AvatarColor.allCases) { swatch in
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if accentColorRaw == swatch.rawValue {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                            .onTapGesture {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                accentColorRaw = swatch.rawValue
                            }
                    }
                }
                Text("Applies across the whole app, on this device only.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                }
            }
        }
    }
}

private struct TeamSettingsFields: View {
    @Bindable var teamSettings: TeamSettings
    let syncService: FirebaseSyncService?

    var body: some View {
        TextField("Team number", value: $teamSettings.teamNumber, format: .number)
            .keyboardType(.numberPad)
            .onChange(of: teamSettings.teamNumber) { push() }
        TextField("Team name", text: $teamSettings.teamName)
            .onChange(of: teamSettings.teamName) { push() }
        Stepper("Rookie year: \(teamSettings.rookieYear)", value: $teamSettings.rookieYear, in: 2000...2100)
            .onChange(of: teamSettings.rookieYear) { push() }
        TextField("Season", text: $teamSettings.seasonName)
            .onChange(of: teamSettings.seasonName) { push() }
    }

    private func push() {
        syncService?.pushTeamSettings(teamSettings)
    }
}

// MARK: - Budget & Sponsors

private struct BudgetView: View {
    @Query(sort: \Sponsor.addedAt, order: .reverse) private var sponsors: [Sponsor]
    @Query(sort: \BudgetExpense.date, order: .reverse) private var expenses: [BudgetExpense]
    @State private var isPresentingNewSponsor = false
    @State private var isPresentingNewExpense = false

    private var totalPledged: Double { sponsors.reduce(0) { $0 + $1.pledgedAmount } }
    private var totalReceived: Double { sponsors.reduce(0) { $0 + $1.receivedAmount } }
    private var totalSpent: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var remaining: Double { totalReceived - totalSpent }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Total Pledged", value: totalPledged, format: .currency(code: "USD"))
                LabeledContent("Total Received", value: totalReceived, format: .currency(code: "USD"))
                LabeledContent("Total Spent", value: totalSpent, format: .currency(code: "USD"))
                LabeledContent("Remaining", value: remaining, format: .currency(code: "USD"))
                    .foregroundStyle(remaining < 0 ? .red : .primary)
            }

            Section("Sponsors") {
                if sponsors.isEmpty {
                    Text("No sponsors logged yet.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(sponsors) { sponsor in
                    SponsorRow(sponsor: sponsor)
                }
                Button { isPresentingNewSponsor = true } label: {
                    Label("Add Sponsor", systemImage: "plus")
                }
            }

            Section("Expenses") {
                if expenses.isEmpty {
                    Text("No expenses logged yet.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(expenses) { expense in
                    ExpenseRow(expense: expense)
                }
                Button { isPresentingNewExpense = true } label: {
                    Label("Add Expense", systemImage: "plus")
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $isPresentingNewSponsor) { NewSponsorSheet() }
        .sheet(isPresented: $isPresentingNewExpense) { NewExpenseSheet() }
    }
}

private struct SponsorRow: View {
    @Bindable var sponsor: Sponsor
    @Environment(\.syncService) private var syncService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(sponsor.name).font(.body.weight(.medium))
                Spacer()
                Menu {
                    ForEach(SponsorStatus.allCases) { status in
                        Button(status.rawValue) {
                            sponsor.status = status
                            syncService?.pushSponsor(sponsor)
                        }
                    }
                } label: {
                    Text(sponsor.status.rawValue)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            if sponsor.pledgedAmount > 0 || sponsor.receivedAmount > 0 {
                Text("Pledged \(sponsor.pledgedAmount, format: .currency(code: "USD")) · Received \(sponsor.receivedAmount, format: .currency(code: "USD"))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ExpenseRow: View {
    let expense: BudgetExpense

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.item).font(.body.weight(.medium))
                Text("\(expense.category) · \(expense.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(expense.amount, format: .currency(code: "USD")).font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 2)
    }
}

private struct NewSponsorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @State private var name = ""
    @State private var contactName = ""
    @State private var contactEmail = ""
    @State private var pledgedAmount = 0.0
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Sponsor / company name", text: $name)
                TextField("Contact name", text: $contactName)
                TextField("Contact email", text: $contactEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                HStack {
                    Text("Pledged amount")
                    Spacer()
                    TextField("0", value: $pledgedAmount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("New Sponsor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func save() {
        let sponsor = Sponsor(name: name, contactName: contactName, contactEmail: contactEmail,
                               pledgedAmount: pledgedAmount, notes: notes)
        context.insert(sponsor)
        syncService?.pushSponsor(sponsor)
        dismiss()
    }
}

private struct NewExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var item = ""
    @State private var amount = 0.0
    @State private var category = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Item", text: $item)
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0", value: $amount, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                TextField("Category (e.g. Hardware, Registration, Travel)", text: $category)
                TextField("Notes", text: $notes, axis: .vertical)
            }
            .navigationTitle("New Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(item.isEmpty || amount <= 0)
                }
            }
        }
    }

    private func save() {
        guard let user = authManager.currentUser else { return }
        let expense = BudgetExpense(item: item, amount: amount,
                                     category: category.isEmpty ? "Uncategorized" : category,
                                     notes: notes, addedByName: user.name)
        context.insert(expense)
        syncService?.pushExpense(expense)
        dismiss()
    }
}

// MARK: - Rules Reference

private struct RulesReferenceView: View {
    @State private var searchText = ""

    private let terms: [(term: String, definition: String)] = [
        ("Autonomous (Auto)", "The opening period of a match — typically 30 seconds — where the robot operates entirely from pre-written code, with no driver input allowed."),
        ("TeleOp", "The driver-controlled period following Autonomous, where two drivers operate the robot using gamepads connected to the Driver Hub."),
        ("Endgame", "The final portion of TeleOp (commonly the last 30 seconds) where special, often higher-value scoring actions like parking or hanging become available."),
        ("Ranking Points (RP)", "Points awarded for match wins/ties plus specific in-game achievements, used to seed qualification rankings ahead of alliance selection."),
        ("Alliance", "Two teams' robots competing together as a unit in a given match."),
        ("Alliance Selection", "The process after qualification matches where top-seeded teams pick partners to form alliances for the elimination bracket."),
        ("Inspection", "The mandatory pre-competition check confirming a robot meets size, weight, and safety requirements before it's allowed to compete."),
        ("Bumpers", "Required protective structures around a robot's base, with specific rules on color, size, and coverage."),
        ("Control Hub / Driver Hub", "The Control Hub is the onboard computer that runs your robot's code; the Driver Hub is the handheld device drivers use to control it."),
        ("Penalty", "Points deducted from your alliance (or awarded to the opponent) for a rule violation during a match."),
        ("Qualification Match", "A match in the main round-robin schedule, used to determine each team's tournament ranking."),
        ("Elimination Match", "A playoff match between alliances selected after qualification play, determining the event's winner."),
        ("Scouting", "Collecting data on other teams' robots and performance to inform alliance-selection strategy."),
        ("Pit", "The team's assigned workspace at an event where the robot is repaired and prepared between matches.")
    ]

    private var filtered: [(term: String, definition: String)] {
        guard !searchText.isEmpty else { return terms }
        return terms.filter {
            $0.term.localizedCaseInsensitiveContains(searchText) ||
            $0.definition.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Link(destination: URL(string: "https://ftc-resources.firstinspires.org/ftc/game")!) {
                    Label("Official Game Manual & Resources", systemImage: "book.fill")
                }
                Link(destination: URL(string: "https://ftc-qa.firstinspires.org")!) {
                    Label("Official Q&A System", systemImage: "questionmark.bubble.fill")
                }
            }

            Section("Glossary") {
                if filtered.isEmpty {
                    Text("No matching terms.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(filtered, id: \.term) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.term).font(.subheadline.weight(.semibold))
                        Text(entry.definition).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                Text("This glossary covers general FTC terminology in plain language and is not a substitute for the official Game Manual. Game elements, point values, and specific rules change every season — always confirm against the current manual and Q&A linked above before relying on anything for competition.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $searchText, prompt: "Search rules & terms")
        .listStyle(.insetGrouped)
    }
}

// MARK: - About

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                    Text("FTC Team Hub").font(.headline)

                    // Hidden reset unlock lives here: tap this label 7
                    // times within 3 seconds to reveal "Reset App Data".
                    // No visible reset button exists anywhere else.
                    SecretResetTrigger {
                        Text("Version 1.0")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section("About") {
                Text("Built for team management: roster, testing telemetry, tasks, engineering notebook, ideas, pit ops, match scouting, scoring strategy, and FTCScout event data. Team records sync through your configured Firestore project.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return TeamTabView()
        .modelContainer(container)
        .environment(authManager)
}
