import SwiftUI

struct WorkHubTabView: View {
    @Environment(TabRouter.self) private var router

    var body: some View {
        Group {
            switch router.selection {
            case .roster: RosterTabView()
            case .testing: TestingTabView()
            case .tasks: TasksTabView()
            case .notebook: NotebookTabView()
            case .ideas: IdeasTabView()
            default: moduleList
            }
        }
    }

    private var moduleList: some View {
        NavigationStack {
            List {
                Section("Robot & strategy") {
                    module("Testing", detail: "Practice runs and performance trends", icon: "gauge.with.dots.needle.67percent", tab: .testing)
                    module("Engineering notebook", detail: "Design notes, tests, and configuration logs", icon: "book.closed.fill", tab: .notebook)
                    module("Ideas", detail: "Team proposals and brainstorming", icon: "lightbulb.fill", tab: .ideas)
                }
                Section("Team operations") {
                    module("Tasks", detail: "Assignments, priorities, and deadlines", icon: "checklist", tab: .tasks)
                    module("Roster", detail: "Team members and roles", icon: "person.3.fill", tab: .roster)
                }
            }
            .navigationTitle("Build")
        }
    }

    private func module(_ title: String, detail: String, icon: String, tab: AppTab) -> some View {
        Button {
            router.selection = tab
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}

struct TeamHubTabView: View {
    @Environment(TabRouter.self) private var router

    var body: some View {
        Group {
            switch router.selection {
            case .chat: ChatTabView()
            case .team: TeamTabView()
            default: moduleList
            }
        }
    }

    private var moduleList: some View {
        NavigationStack {
            List {
                Section("Communication") {
                    module("Team chat", detail: "Real-time conversation with teammates", icon: "bubble.left.and.bubble.right.fill", tab: .chat)
                }
                Section("Team management") {
                    module("Team profile & settings", detail: "Members, budget, rules, and app settings", icon: "gearshape.fill", tab: .team)
                }
            }
            .navigationTitle("Team")
        }
    }

    private func module(_ title: String, detail: String, icon: String, tab: AppTab) -> some View {
        Button {
            router.selection = tab
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: icon).foregroundStyle(Color.accentColor)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}
