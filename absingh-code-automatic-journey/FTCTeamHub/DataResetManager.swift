//
//  DataResetManager.swift
//  FTCTeamHub
//
//  Wipes local SwiftData records. Reached only through a hidden gesture
//  (see SecretResetTrigger below) — never a plainly visible button —
//  specifically so it can't be tapped by accident in the pit.
//
//  NOTE: this clears the on-device database only. If Firestore sync is
//  still holding copies of this data, it can re-sync back down. Ask for
//  SyncService.swift if you also want a matching cloud-side wipe.
//

import Foundation
import SwiftData

enum DataResetManager {

    /// Deletes all season data: tasks, notebook entries, test runs, ideas,
    /// activity feed, batteries, checklist runs, inventory items, and
    /// scouting reports.
    /// Does NOT touch AppUser (team roster/login) unless `includeRoster`
    /// is true.
    @MainActor
    static func wipeAllLocalData(context: ModelContext, includeRoster: Bool) throws {
        try deleteAll(TaskItem.self, in: context)
        try deleteAll(NotebookEntry.self, in: context)
        try deleteAll(TestRunRecord.self, in: context)
        try deleteAll(Idea.self, in: context)
        try deleteAll(ActivityEvent.self, in: context)
        try deleteAll(Battery.self, in: context)
        try deleteAll(ChecklistRun.self, in: context)
        try deleteAll(InventoryItem.self, in: context)
        try deleteAll(ScoutingReport.self, in: context)

        if includeRoster {
            try deleteAll(AppUser.self, in: context)
        }

        try context.save()
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<T>()
        let items = try context.fetch(descriptor)
        for item in items {
            context.delete(item)
        }
    }
}
