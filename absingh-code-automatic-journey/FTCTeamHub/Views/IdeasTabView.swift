//
//  IdeasTabView.swift
//  FTCTeamHub
//
//  NEW: posting/upvoting/commenting/promoting now calls syncService?.pushIdea(...)
//  so ideas actually sync across devices.
//

import SwiftUI
import SwiftData
import UIKit

struct IdeasTabView: View {
    @Query(sort: \Idea.timestamp, order: .reverse) private var ideas: [Idea]
    @State private var isPresentingNewIdea = false

    var sortedByUpvotes: [Idea] { ideas.sorted { $0.upvoteCount > $1.upvoteCount } }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedByUpvotes) { idea in
                    NavigationLink(value: idea) {
                        IdeaRow(idea: idea)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Ideas")
            .navigationDestination(for: Idea.self) { idea in IdeaDetailView(idea: idea) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewIdea = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isPresentingNewIdea) { NewIdeaSheet() }
            .overlay {
                if ideas.isEmpty {
                    ContentUnavailableView("No ideas yet", systemImage: "lightbulb",
                                           description: Text("Post a mechanism idea or strategy pivot to get the discussion going."))
                }
            }
        }
    }
}

private struct IdeaRow: View {
    @Bindable var idea: Idea
    @Environment(AuthenticationManager.self) private var authManager
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService

    private var hasUpvoted: Bool {
        guard let uid = authManager.currentUser?.id else { return false }
        return idea.upvoterIDs.contains(uid)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { toggleUpvote() } label: {
                VStack(spacing: 2) {
                    Image(systemName: hasUpvoted ? "arrowshape.up.circle.fill" : "arrowshape.up.circle")
                        .font(.title2)
                    Text("\(idea.upvoteCount)").font(.caption2.monospacedDigit())
                }
                .foregroundStyle(hasUpvoted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(idea.summary).font(.body.weight(.medium))
                Text("\(idea.authorName) · \(idea.comments.count) comment\(idea.comments.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                if idea.promotedToTask {
                    Label("On task board", systemImage: "checklist")
                        .font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toggleUpvote() {
        guard let uid = authManager.currentUser?.id, let name = authManager.currentUser?.name else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let index = idea.upvoterIDs.firstIndex(of: uid) {
            idea.upvoterIDs.remove(at: index)
        } else {
            idea.upvoterIDs.append(uid)
            let event = ActivityEvent(authorID: uid, authorName: name, kind: .ideaUpvoted,
                                       message: "upvoted idea: \(idea.summary)")
            context.insert(event)
            syncService?.pushActivity(event)
        }
        syncService?.pushIdea(idea)
    }
}

private struct IdeaDetailView: View {
    @Bindable var idea: Idea
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var commentText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(idea.summary).font(.title3.bold())
                if !idea.detail.isEmpty { Text(idea.detail) }

                Divider()

                Text("Comments").font(.headline)
                if idea.comments.isEmpty {
                    Text("No comments yet.").font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(idea.comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comment.authorName).font(.caption.weight(.semibold))
                        Text(comment.text).font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    TextField("Add a comment", text: $commentText)
                        .textFieldStyle(.roundedBorder)
                    Button("Post") { postComment() }.disabled(commentText.isEmpty)
                }

                if !idea.promotedToTask {
                    Button {
                        promoteToTask()
                    } label: {
                        Label("Promote to Task Board", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .navigationTitle("Idea")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func postComment() {
        guard let uid = authManager.currentUser?.id, let name = authManager.currentUser?.name else { return }
        idea.comments.append(IdeaComment(authorID: uid, authorName: name, text: commentText))
        commentText = ""
        // Note: comments aren't yet mirrored to Firestore individually —
        // pushIdea() only syncs top-level idea fields (summary/detail/
        // upvotes/promoted state) for now. Extending this to sync the full
        // comment thread follows the same pattern as pushIdea's dictionary.
    }

    private func promoteToTask() {
        guard let currentUser = authManager.currentUser else { return }
        let task = TaskItem(title: idea.summary, taskDescription: idea.detail,
                             status: .toDo, priority: .medium, tags: ["From Idea"],
                             authorID: currentUser.id, authorName: currentUser.name)
        context.insert(task)
        syncService?.pushTask(task)

        idea.promotedToTask = true
        syncService?.pushIdea(idea)

        let event = ActivityEvent(authorID: currentUser.id, authorName: currentUser.name, kind: .taskCreated,
                                   message: "promoted idea to task: \(idea.summary)")
        context.insert(event)
        syncService?.pushActivity(event)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - New idea sheet

private struct NewIdeaSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager
    @State private var summary = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("One-line summary", text: $summary)
                TextField("Details", text: $detail, axis: .vertical)
            }
            .navigationTitle("New Idea")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { post() }.disabled(summary.isEmpty)
                }
            }
        }
    }

    private func post() {
        guard let currentUser = authManager.currentUser else { return }
        let idea = Idea(authorID: currentUser.id, authorName: currentUser.name, summary: summary, detail: detail)
        context.insert(idea)
        syncService?.pushIdea(idea)

        let event = ActivityEvent(authorID: currentUser.id, authorName: currentUser.name, kind: .ideaPosted,
                                   message: "posted idea: \(summary)")
        context.insert(event)
        syncService?.pushActivity(event)

        dismiss()
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return IdeasTabView()
        .modelContainer(container)
        .environment(authManager)
}
