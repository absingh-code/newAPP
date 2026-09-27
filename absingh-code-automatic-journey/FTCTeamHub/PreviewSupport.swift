//
//  PreviewSupport.swift
//  FTCTeamHub
//
//  NEW: schema includes ScoringElement, with sample point values filled
//  in (unlike the real app's zeroed defaults) so the Scoring Simulator
//  preview looks realistic.
//

import Foundation
import SwiftData

@MainActor
func makePreviewContainer() -> ModelContainer {
    let schema = Schema([
        AppUser.self, TaskItem.self, NotebookEntry.self,
        TestRunRecord.self, Idea.self, ActivityEvent.self, TrackedTeam.self,
        Battery.self, ChecklistRun.self, InventoryItem.self,
        TeamSettings.self, Sponsor.self, BudgetExpense.self,
        ScoringElement.self, ScoutingReport.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let context = container.mainContext

    let alex = AppUser(email: "alex@team24211.com", name: "Alex Rivera", role: .softwareLead,
                        avatarColor: .blue, passwordHash: "", isLogged: true)
    let sam = AppUser(email: "sam@team24211.com", name: "Sam Okafor", role: .hardware,
                       avatarColor: .orange, passwordHash: "")
    let priya = AppUser(email: "priya@team24211.com", name: "Priya Nandan", role: .strategy,
                         avatarColor: .purple, passwordHash: "")
    let jordan = AppUser(email: "jordan@team24211.com", name: "Jordan Lee", role: .builder,
                          avatarColor: .green, passwordHash: "")

    [alex, sam, priya, jordan].forEach { context.insert($0) }

    context.insert(TaskItem(title: "Mount odometry pods",
                             taskDescription: "Finalize bracket for dead-wheel pods on drivetrain.",
                             assignedToID: sam.id, assignedToName: sam.name,
                             status: .inProgress, priority: .high,
                             deadline: Calendar.current.date(byAdding: .day, value: 2, to: .now),
                             tags: ["Hardware", "Chassis"], authorID: priya.id, authorName: priya.name))

    context.insert(TaskItem(title: "Tune PID for arm subsystem",
                             taskDescription: "Reduce overshoot below 3 degrees.",
                             assignedToID: alex.id, assignedToName: alex.name,
                             status: .toDo, priority: .critical,
                             deadline: Calendar.current.date(byAdding: .day, value: 1, to: .now),
                             tags: ["Software"], authorID: alex.id, authorName: alex.name))

    context.insert(TaskItem(title: "Finalize sponsor outreach packet",
                             assignedToID: priya.id, assignedToName: priya.name,
                             status: .blocked, priority: .low,
                             tags: ["Outreach"], authorID: priya.id, authorName: priya.name))

    context.insert(TestRunRecord(driverID: jordan.id, driverName: jordan.name, date: .now,
                                  autoScore: 28, teleopScore: 64, endgameScore: 15,
                                  cycleTimeSeconds: 4.2, autoConsistencyPercent: 85,
                                  mechanicalIssues: ["Intake Jam"], notes: "Consistent auto, strong cycle time.",
                                  recordedByID: alex.id, recordedByName: alex.name, batteryLabel: "B1"))

    context.insert(TestRunRecord(driverID: jordan.id, driverName: jordan.name,
                                  date: Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now,
                                  autoScore: 18, teleopScore: 50, endgameScore: 10,
                                  cycleTimeSeconds: 5.1, autoConsistencyPercent: 65,
                                  mechanicalIssues: ["Belt Slipped", "Code Crash"], notes: "Rough first week.",
                                  recordedByID: alex.id, recordedByName: alex.name, batteryLabel: "B2"))

    context.insert(NotebookEntry(authorID: alex.id, authorName: alex.name, title: "IMU drift investigation",
                                  content: "## Summary\nObserved yaw drift after 8 minutes of continuous operation.",
                                  tags: ["Software", "IMU"],
                                  imuLog: IMUTuningLog(chip: "BHI260AP", logoFacingDirection: "UP",
                                                        usbFacingDirection: "FORWARD", yawOffsetDegrees: 1.2,
                                                        driftOverTenMinDegrees: 2.8,
                                                        calibrationNotes: "Re-ran calibration after remounting hub level.")))

    context.insert(Idea(authorID: sam.id, authorName: sam.name, summary: "Dual-intake system",
                         detail: "Add a second intake on the rear to cut travel distance in half.",
                         upvoterIDs: [alex.id, priya.id]))

    context.insert(ActivityEvent(authorID: sam.id, authorName: sam.name, kind: .taskCompleted,
                                  message: "completed task: Wire drivetrain motors"))
    context.insert(ActivityEvent(authorID: jordan.id, authorName: jordan.name, kind: .testLogged,
                                  message: "logged a test run"))
    context.insert(ActivityEvent(authorID: sam.id, authorName: sam.name, kind: .ideaPosted,
                                  message: "posted idea: Dual-intake system"))

    context.insert(TrackedTeam(teamNumber: 18234, teamName: "Circuit Breakers",
                                note: "Strong auto, watch their endgame climb.",
                                addedByID: priya.id, addedByName: priya.name))

    context.insert(Battery(label: "B1", status: .charged, cycleCount: 12))
    context.insert(Battery(label: "B2", status: .inUse, cycleCount: 34, notes: "Slight voltage sag under load."))
    context.insert(Battery(label: "B3", status: .dead, cycleCount: 58, notes: "Retire — won't hold charge."))

    context.insert(InventoryItem(name: "REV Expansion Hub (spare)", category: "Electronics",
                                  binLocation: "Shelf 2, Bin B", quantity: 2))
    context.insert(InventoryItem(name: "Custom 3D-printed intake roller", category: "Printed Parts",
                                  binLocation: "Drawer 4", quantity: 4, notes: "PETG, 0.3mm layer height"))

    let preFlight = ChecklistType.preFlight
    context.insert(ChecklistRun(
        type: preFlight,
        itemResults: preFlight.defaultItems.map { ChecklistItemResult(text: $0, checked: true) },
        completedByID: sam.id, completedByName: sam.name
    ))

    context.insert(TeamSettings(teamNumber: 24211, teamName: "Wild Circuits", rookieYear: 2026, seasonName: "2026-2027"))

    context.insert(Sponsor(name: "Acme Robotics Supply", contactName: "Jamie Fields",
                            contactEmail: "jamie@acmerobotics.com", pledgedAmount: 500, receivedAmount: 500,
                            status: .received, notes: "Annual sponsor, provided REV hardware discount too."))
    context.insert(Sponsor(name: "Local Credit Union", contactName: "Pat Nguyen",
                            pledgedAmount: 750, receivedAmount: 0, status: .pledged))

    context.insert(BudgetExpense(item: "FTC Registration Fee", amount: 275, category: "Registration", addedByName: priya.name))
    context.insert(BudgetExpense(item: "REV Control Hub", amount: 250, category: "Hardware", addedByName: sam.name))

    context.insert(ScoringElement(name: "Leave / Depart Start", phase: .autonomous, pointValue: 3, sortOrder: 0))
    context.insert(ScoringElement(name: "Score Game Element (Auto)", phase: .autonomous, pointValue: 6, sortOrder: 1))
    context.insert(ScoringElement(name: "Score Game Element (TeleOp)", phase: .teleop, pointValue: 3, sortOrder: 2))
    context.insert(ScoringElement(name: "Park", phase: .endgame, pointValue: 5, sortOrder: 3))
    context.insert(ScoringElement(name: "Climb / Hang", phase: .endgame, pointValue: 15, sortOrder: 4))

    try? context.save()
    return container
}
