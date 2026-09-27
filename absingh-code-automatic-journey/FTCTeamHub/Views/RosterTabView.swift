//
//  RosterTabView.swift
//  FTCTeamHub
//
//  TAB 1 — Team Base & Roster. The command-center view of every team
//  member: role badge, avatar, whether they're the currently signed-in
//  user, and their most recent contribution pulled from the shared
//  activity feed.
//

import SwiftUI
import SwiftData

struct RosterTabView: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Query(sort: \AppUser.name) private var users: [AppUser]
    @Query(sort: \ActivityEvent.timestamp, order: .reverse) private var activity: [ActivityEvent]
    @State private var isPresentingProfile = false

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(users) { user in
                        RosterCard(
                            user: user,
                            isCurrentUser: user.id == authManager.currentUser?.id,
                            recentActivity: activity.first { $0.authorID == user.id }
                        )
                    }
                }
                .padding()

                if !activity.isEmpty {
                    RecentActivitySection(events: Array(activity.prefix(10)))
                        .padding(.horizontal)
                        .padding(.bottom)
                }
            }
            .navigationTitle("Team Roster")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingProfile = true } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $isPresentingProfile) { ProfileSheet() }
        }
    }
}

private struct RosterCard: View {
    let user: AppUser
    let isCurrentUser: Bool
    let recentActivity: ActivityEvent?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(user.avatarColor.color)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text(user.initials)
                            .font(.headline)
                            .foregroundStyle(.white)
                    )
                Spacer()
                if isCurrentUser {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text("You").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Text(user.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Label(user.role.rawValue, systemImage: user.role.systemImage)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.thinMaterial, in: Capsule())

            if let recentActivity {
                Text(recentActivity.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct RecentActivitySection: View {
    let events: [ActivityEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Activity")
                .font(.headline)
                .padding(.top, 8)

            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(spacing: 10) {
                        Image(systemName: event.systemImage)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 22)
                        (Text(event.authorName).fontWeight(.semibold) + Text(" \(event.message)"))
                            .font(.footnote)
                        Spacer()
                        Text(event.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)

                    if index < events.count - 1 {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct ProfileSheet: View {
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let user = authManager.currentUser {
                    Section("Signed in as") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: user.role.rawValue)
                    }
                }
                Section {
                    Button("Sign Out", role: .destructive) {
                        authManager.signOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return RosterTabView()
        .modelContainer(container)
        .environment(authManager)
}
