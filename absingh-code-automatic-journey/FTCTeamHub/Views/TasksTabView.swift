//
//  TasksTabView.swift
//  FTCTeamHub
//
//  NEW: added a "Calendar" view mode — a week-strip agenda (not a full
//  month grid, to keep the date math simple and reliable) showing which
//  days have deadlines, with the day's tasks listed below. Covers
//  "organize meeting schedules, project deadlines, and portfolio
//  milestone logs" by tagging tasks with dates the same way as any other
//  deadline.
//

import SwiftUI
import SwiftData
import UIKit

struct TasksTabView: View {
    @Query(sort: \TaskItem.dateCreated, order: .reverse) private var allTasks: [TaskItem]
    @Query(sort: \AppUser.name) private var users: [AppUser]
    @Environment(AuthenticationManager.self) private var authManager
    @State private var viewMode: ViewMode = .myTasks
    @State private var isPresentingNewTask = false
    @State private var filterTag: String?

    enum ViewMode: String, CaseIterable, Identifiable {
        case myTasks = "My Tasks", board = "Team Board", calendar = "Calendar"
        var id: String { rawValue }
    }

    var myTasks: [TaskItem] {
        guard let uid = authManager.currentUser?.id else { return [] }
        return allTasks
            .filter { $0.assignedToID == uid && $0.status != .done }
            .sorted { ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
    }

    var allTags: [String] {
        Array(Set(allTasks.flatMap(\.tags))).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $viewMode) {
                    ForEach(ViewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top])

                if viewMode == .board && !allTags.isEmpty {
                    TagFilterBar(tags: allTags, selected: $filterTag)
                }

                Divider().padding(.top, 8)

                switch viewMode {
                case .myTasks: MyTasksList(tasks: myTasks)
                case .board: KanbanBoard(tasks: filteredBoardTasks)
                case .calendar: TaskCalendarView(tasks: allTasks)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPresentingNewTask = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isPresentingNewTask) { NewTaskSheet(users: users) }
        }
    }

    private var filteredBoardTasks: [TaskItem] {
        guard let tag = filterTag else { return allTasks }
        return allTasks.filter { $0.tags.contains(tag) }
    }
}

// MARK: - My Tasks

private struct MyTasksList: View {
    let tasks: [TaskItem]

    var body: some View {
        if tasks.isEmpty {
            EmptyStateView(icon: "checkmark.circle", title: "All caught up",
                           subtitle: "No open tasks assigned to you.", tint: .blue)
        } else {
            List {
                ForEach(tasks) { task in
                    TaskRow(task: task)
                }
            }
            .listStyle(.plain)
        }
    }
}

private struct TaskRow: View {
    @Bindable var task: TaskItem
    @Environment(\.syncService) private var syncService

    private var priorityColor: Color {
        switch task.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(priorityColor).frame(width: 10, height: 10).padding(.top, 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title).font(.body.weight(.medium))
                if !task.taskDescription.isEmpty {
                    Text(task.taskDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 6) {
                    ForEach(task.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.thinMaterial, in: Capsule())
                    }
                    Spacer()
                    if let deadline = task.deadline {
                        Text(deadline, style: .date)
                            .font(.caption2)
                            .foregroundStyle(deadline < .now ? .red : .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                task.status = .done
                task.lastModified = .now
                syncService?.pushTask(task)
                NotificationScheduler.cancelReminder(for: task)
            } label: { Label("Done", systemImage: "checkmark") }
            .tint(.green)
        }
    }
}

// MARK: - Kanban board

private struct KanbanBoard: View {
    let tasks: [TaskItem]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(TaskStatus.allCases) { status in
                    KanbanColumn(status: status, tasks: tasks.filter { $0.status == status })
                }
            }
            .padding()
        }
    }
}

private struct KanbanColumn: View {
    let status: TaskStatus
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(status.rawValue).font(.subheadline.weight(.semibold))
                Text("\(tasks.count)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            VStack(spacing: 8) {
                ForEach(tasks) { task in
                    KanbanCard(task: task)
                }
            }
        }
        .frame(width: 220)
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let uuid = UUID(uuidString: idString) else { return false }
            NotificationCenter.default.post(name: .taskDroppedOnColumn, object: nil,
                                             userInfo: ["id": uuid, "status": status])
            return true
        }
    }
}

private struct KanbanCard: View {
    @Bindable var task: TaskItem
    @Environment(\.syncService) private var syncService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.title).font(.footnote.weight(.medium)).lineLimit(2)
            HStack {
                Text(task.priority.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                Spacer()
                Text(task.assignedToName).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .draggable(task.id.uuidString)
        .onReceive(NotificationCenter.default.publisher(for: .taskDroppedOnColumn)) { note in
            guard let id = note.userInfo?["id"] as? UUID, id == task.id,
                  let newStatus = note.userInfo?["status"] as? TaskStatus else { return }
            task.status = newStatus
            task.lastModified = .now
            syncService?.pushTask(task)
            if newStatus == .done { NotificationScheduler.cancelReminder(for: task) }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
    }
}

extension Notification.Name {
    static let taskDroppedOnColumn = Notification.Name("taskDroppedOnColumn")
}

// MARK: - Calendar (week-strip agenda)

private struct TaskCalendarView: View {
    let tasks: [TaskItem]
    @State private var weekStart: Date = Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    private var weekDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private func tasksOn(_ date: Date) -> [TaskItem] {
        tasks.filter { task in
            guard let deadline = task.deadline else { return false }
            return Calendar.current.isDate(deadline, inSameDayAs: date)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { changeWeek(by: -1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(weekRangeLabel).font(.subheadline.weight(.medium))
                Spacer()
                Button { changeWeek(by: 1) } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal)

            HStack(spacing: 6) {
                ForEach(weekDays, id: \.self) { day in
                    DayButton(date: day, isSelected: Calendar.current.isDate(day, inSameDayAs: selectedDate),
                              hasTasks: !tasksOn(day).isEmpty) {
                        selectedDate = day
                    }
                }
            }
            .padding(.horizontal)

            Divider()

            let dayTasks = tasksOn(selectedDate)
            if dayTasks.isEmpty {
                EmptyStateView(icon: "calendar", title: "Nothing due",
                               subtitle: "No task deadlines on this day.", tint: .blue)
            } else {
                List {
                    ForEach(dayTasks) { task in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title).font(.body.weight(.medium))
                            Text("\(task.assignedToName) · \(task.priority.rawValue)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
            }
        }
        .padding(.top, 8)
    }

    private func changeWeek(by delta: Int) {
        if let newStart = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: weekStart) {
            weekStart = newStart
        }
    }

    private var weekRangeLabel: String {
        guard let last = weekDays.last else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: weekStart)) – \(formatter.string(from: last))"
    }
}

private struct DayButton: View {
    let date: Date
    let isSelected: Bool
    let hasTasks: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
                Text(date.formatted(.dateTime.day())).font(.subheadline.weight(.semibold))
                Circle().fill(hasTasks ? Color.accentColor : .clear).frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tag filter bar

private struct TagFilterBar: View {
    let tags: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        selected = (selected == tag) ? nil : tag
                    } label: {
                        Text(tag)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selected == tag ? Color.accentColor : Color(.tertiarySystemFill),
                                        in: Capsule())
                            .foregroundStyle(selected == tag ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - New Task sheet

private struct NewTaskSheet: View {
    let users: [AppUser]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.syncService) private var syncService
    @Environment(AuthenticationManager.self) private var authManager

    @State private var title = ""
    @State private var description = ""
    @State private var assigneeID: UUID?
    @State private var priority: TaskPriority = .medium
    @State private var deadline: Date = .now.addingTimeInterval(86400)
    @State private var hasDeadline = false
    @State private var tagsInput = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                }
                Section("Assignment") {
                    Picker("Assignee", selection: $assigneeID) {
                        Text("Unassigned").tag(UUID?.none)
                        ForEach(users) { user in Text(user.name).tag(Optional(user.id)) }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Set deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, displayedComponents: .date)
                        Text("You'll get a reminder notification at 9 AM on this day.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section("Tags (comma-separated)") {
                    TextField("Chassis, Odometry, Outreach, Meeting, Portfolio", text: $tagsInput)
                }
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let currentUser = authManager.currentUser else { return }
        let tags = tagsInput.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let assigneeName = users.first(where: { $0.id == assigneeID })?.name ?? "Unassigned"

        let task = TaskItem(title: title, taskDescription: description, assignedToID: assigneeID,
                             assignedToName: assigneeName, priority: priority,
                             deadline: hasDeadline ? deadline : nil, tags: tags,
                             authorID: currentUser.id, authorName: currentUser.name)
        context.insert(task)
        syncService?.pushTask(task)
        if hasDeadline {
            NotificationScheduler.scheduleDeadlineReminder(for: task)
        }

        let event = ActivityEvent(authorID: currentUser.id, authorName: currentUser.name, kind: .taskCreated,
                                   message: "created task: \(title)")
        context.insert(event)
        syncService?.pushActivity(event)

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

#Preview {
    let container = makePreviewContainer()
    let authManager = AuthenticationManager(modelContext: container.mainContext)
    return TasksTabView()
        .modelContainer(container)
        .environment(authManager)
}
