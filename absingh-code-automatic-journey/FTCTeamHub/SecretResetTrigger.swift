//
//  SecretResetTrigger.swift
//  FTCTeamHub
//
//  A hidden reset unlock: tap the wrapped content 7 times within 3
//  seconds to reveal the reset flow. Wired into AboutView's
//  "Version 1.0" label in TeamTabView.swift.
//
//  Uses authManager.signOut() — the only sign-out method that actually
//  exists on AuthenticationManager.
//

import SwiftUI
import SwiftData
import UIKit

struct SecretResetTrigger<Content: View>: View {
    @Environment(\.modelContext) private var context
    @Environment(AuthenticationManager.self) private var authManager

    @ViewBuilder let content: () -> Content

    @State private var tapCount = 0
    @State private var lastTapTime: Date = .distantPast
    @State private var isPresentingResetSheet = false

    private let requiredTaps = 7
    private let tapWindowSeconds: TimeInterval = 3

    var body: some View {
        content()
            .contentShape(Rectangle())
            .onTapGesture {
                registerTap()
            }
            .sheet(isPresented: $isPresentingResetSheet) {
                ResetConfirmationSheet()
            }
    }

    private func registerTap() {
        let now = Date()
        if now.timeIntervalSince(lastTapTime) > tapWindowSeconds {
            tapCount = 0
        }
        lastTapTime = now
        tapCount += 1

        if tapCount >= requiredTaps {
            tapCount = 0
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            isPresentingResetSheet = true
        } else if tapCount >= requiredTaps - 2 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}

private struct ResetConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthenticationManager.self) private var authManager

    @State private var confirmationText = ""
    @State private var includeRoster = false
    @State private var isWiping = false
    @State private var resultMessage: String?
    private let expectedPhrase = "RESET"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.headline)
                    Text("This permanently deletes every task, notebook entry, idea, test run, battery, checklist run, inventory item, and activity log on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Also delete the team roster & log everyone out", isOn: $includeRoster)
                } footer: {
                    Text("Leave this off to wipe season data but keep everyone's accounts.")
                }

                Section("Type RESET to confirm") {
                    TextField("RESET", text: $confirmationText)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage).font(.footnote).foregroundStyle(.green)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        performWipe()
                    } label: {
                        if isWiping {
                            ProgressView()
                        } else {
                            Text("Wipe All Data").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(confirmationText != expectedPhrase || isWiping)
                }
            }
            .navigationTitle("Reset App Data")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .interactiveDismissDisabled(isWiping)
    }

    private func performWipe() {
        isWiping = true
        do {
            try DataResetManager.wipeAllLocalData(context: context, includeRoster: includeRoster)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            resultMessage = "Done. All local data has been wiped."
            if includeRoster {
                authManager.signOut()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                dismiss()
            }
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            resultMessage = "Reset failed: \(error.localizedDescription)"
            isWiping = false
        }
    }
}

#Preview {
    SecretResetTrigger {
        Text("FTC Team Hub v1.0")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}
