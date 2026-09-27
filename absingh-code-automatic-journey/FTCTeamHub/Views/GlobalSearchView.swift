//
//  GlobalSearchView.swift
//  FTCTeamHub
//
//  Spotlight-style search across Tasks, Notebook, Ideas, and Inventory at
//  once. Presented as a sheet (from the Dashboard's toolbar) rather than
//  a dedicated tab, to avoid growing the tab bar further. Tapping a
//  result jumps straight to the relevant tab via TabRouter and dismisses.
//

import SwiftUI
import SwiftData

struct GlobalSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TabRouter.self) private var router

    @Query private var tasks: [TaskItem]
    @Query private var notebookEntries: [NotebookEntry]
    @Query private var ideas: [Idea]
    @Query private var inventoryItems: [InventoryItem]

    @State private var searchText = ""

    private var filteredTasks: [TaskItem] {
        guard !searchText.isEmpty else { return [] }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.taskDescription.localizedCaseInsensitiveContains(searchText) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private var filteredNotebook: [NotebookEntry] {
        guard !searchText.isEmpty else { return [] }
        return notebookEntries.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredIdeas: [Idea] {
        guard !searchText.isEmpty else { return [] }
        return ideas.filter {
            $0.summary.localizedCaseInsensitiveContains(searchText) ||
            $0.detail.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredInventory: [InventoryItem] {
        guard !searchText.isEmpty else { return [] }
        return inventoryItems.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.category.localizedCaseInsensitiveContains(searchText) ||
            $0.binLocation.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var hasAnyResults: Bool {
        !filteredTasks.isEmpty || !filteredNotebook.isEmpty || !filteredIdeas.isEmpty || !filteredInventory.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "Search everything",
                                   subtitle: "Find tasks, notebook entries, ideas, and inventory items all at once.",
                                   tint: .blue)
                        .listRowSeparator(.hidden)
                } else if !hasAnyResults {
                    EmptyStateView(icon: "questionmark.circle", title: "No results",
                                   subtitle: "Nothing matched \"\(searchText)\".", tint: .secondary)
                        .listRowSeparator(.hidden)
                } else {
                    if !filteredTasks.isEmpty {
                        Section("Tasks") {
                            ForEach(filteredTasks) { task in
                                resultRow(icon: "checklist", title: task.title, subtitle: task.assignedToName, tint: .blue) {
                                    router.selection = .tasks
                                    dismiss()
                                }
                            }
                        }
                    }
                    if !filteredNotebook.isEmpty {
                        Section("Notebook") {
                            ForEach(filteredNotebook) { entry in
                                resultRow(icon: "book.closed", title: entry.title, subtitle: entry.authorName, tint: .purple) {
                                    router.selection = .notebook
                                    dismiss()
                                }
                            }
                        }
                    }
                    if !filteredIdeas.isEmpty {
                        Section("Ideas") {
                            ForEach(filteredIdeas) { idea in
                                resultRow(icon: "lightbulb", title: idea.summary, subtitle: idea.authorName, tint: .orange) {
                                    router.selection = .ideas
                                    dismiss()
                                }
                            }
                        }
                    }
                    if !filteredInventory.isEmpty {
                        Section("Inventory") {
                            ForEach(filteredInventory) { item in
                                resultRow(icon: "shippingbox", title: item.name, subtitle: "Bin \(item.binLocation)", tint: .green) {
                                    router.selection = .inventory
                                    dismiss()
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Search tasks, notebook, ideas, inventory")
            .navigationTitle("Search")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func resultRow(icon: String, title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body).foregroundStyle(.primary).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let container = makePreviewContainer()
    let router = TabRouter()
    return GlobalSearchView()
        .modelContainer(container)
        .environment(router)
}
