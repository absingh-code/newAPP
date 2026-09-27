//
//  EmptyStateView.swift
//  FTCTeamHub
//
//  A more polished empty state than SwiftUI's default ContentUnavailableView
//  — icon in a soft tinted circle, clear title/subtitle, and an optional
//  action button. Deliberately NOT cartoon illustration artwork: Apple's
//  own apps (Notes, Reminders, Things 3) use exactly this pattern —
//  tinted SF Symbol + text — for empty states, so this stays consistent
//  with the native-HIG visual language the rest of the app already uses.
//

import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var tint: Color = .accentColor
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: icon)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView(icon: "checkmark.circle", title: "All caught up",
                   subtitle: "No open tasks assigned to you.", tint: .blue,
                   actionTitle: "Add a Task", action: {})
}
