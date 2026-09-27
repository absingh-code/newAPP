//
//  FirebaseSyncService.swift
//  FTCTeamHub
//
//  Full, current version — includes sync for: roster, tasks, activity,
//  notebook (with delete propagation), ideas, test runs, batteries,
//  checklists, inventory, team settings, sponsors, and budget expenses.
//

import Foundation
import SwiftData
import FirebaseFirestore

@MainActor
final class FirebaseSyncService {

    private lazy var db = Firestore.firestore()
    private var taskListener: ListenerRegistration?
    private var activityListener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    private var notebookListener: ListenerRegistration?
    private var ideaListener: ListenerRegistration?
    private var testRunListener: ListenerRegistration?
    private var batteryListener: ListenerRegistration?
    private var checklistListener: ListenerRegistration?
    private var inventoryListener: ListenerRegistration?
    private var scoutingReportListener: ListenerRegistration?
    private var teamSettingsListener: ListenerRegistration?
    private var sponsorListener: ListenerRegistration?
    private var expenseListener: ListenerRegistration?
    private weak var modelContext: ModelContext?

    func start(modelContext: ModelContext) {
        self.modelContext = modelContext
        listenForUserChanges()
        listenForTaskChanges()
        listenForActivityChanges()
        listenForNotebookChanges()
        listenForIdeaChanges()
        listenForTestRunChanges()
        listenForBatteryChanges()
        listenForChecklistChanges()
        listenForInventoryChanges()
        listenForScoutingReportChanges()
        listenForTeamSettingsChanges()
        listenForSponsorChanges()
        listenForExpenseChanges()
    }

    func stop() {
        taskListener?.remove()
        activityListener?.remove()
        userListener?.remove()
        notebookListener?.remove()
        ideaListener?.remove()
        testRunListener?.remove()
        batteryListener?.remove()
        checklistListener?.remove()
        inventoryListener?.remove()
        scoutingReportListener?.remove()
        teamSettingsListener?.remove()
        sponsorListener?.remove()
        expenseListener?.remove()
    }

    // MARK: - Roster (AppUser)

    func pushUser(_ user: AppUser) {
        let data: [String: Any] = [
            "email": user.email, "name": user.name, "roleRaw": user.roleRaw,
            "avatarColorRaw": user.avatarColorRaw, "passwordHash": user.passwordHash, "joinedAt": user.joinedAt
        ]
        db.collection("users").document(user.id.uuidString).setData(data, merge: true)
    }

    private func listenForUserChanges() {
        userListener = db.collection("users").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges { self.upsertUser(from: change.document) }
        }
    }

    private func upsertUser(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()
        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        let user = existing ?? AppUser(id: id, email: data["email"] as? String ?? "", name: "", role: .builder, avatarColor: .blue, passwordHash: "")
        user.email = data["email"] as? String ?? user.email
        user.name = data["name"] as? String ?? user.name
        user.roleRaw = data["roleRaw"] as? String ?? user.roleRaw
        user.avatarColorRaw = data["avatarColorRaw"] as? String ?? user.avatarColorRaw
        user.passwordHash = data["passwordHash"] as? String ?? user.passwordHash
        if existing == nil { context.insert(user) }
        try? context.save()
    }

    // MARK: - Tasks

    func pushTask(_ task: TaskItem) {
        let data: [String: Any] = [
            "title": task.title, "taskDescription": task.taskDescription,
            "assignedToID": task.assignedToID?.uuidString ?? "", "assignedToName": task.assignedToName,
            "status": task.status.rawValue, "priority": task.priority.rawValue,
            "deadline": task.deadline as Any, "tags": task.tags, "dateCreated": task.dateCreated,
            "authorID": task.authorID.uuidString, "authorName": task.authorName, "lastModified": task.lastModified
        ]
        db.collection("tasks").document(task.id.uuidString).setData(data, merge: true)
    }

    private func listenForTaskChanges() {
        taskListener = db.collection("tasks").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges { self.upsertTask(from: change.document) }
        }
    }

    private func upsertTask(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        let remoteModified = (data["lastModified"] as? Timestamp)?.dateValue() ?? .distantPast
        if let existing, existing.lastModified >= remoteModified { return }
        let task = existing ?? TaskItem(id: id, title: "", authorID: UUID(), authorName: "")
        task.title = data["title"] as? String ?? task.title
        task.taskDescription = data["taskDescription"] as? String ?? task.taskDescription
        task.assignedToID = UUID(uuidString: data["assignedToID"] as? String ?? "")
        task.assignedToName = data["assignedToName"] as? String ?? task.assignedToName
        task.status = TaskStatus(rawValue: data["status"] as? String ?? "") ?? task.status
        task.priority = TaskPriority(rawValue: data["priority"] as? String ?? "") ?? task.priority
        task.tags = data["tags"] as? [String] ?? task.tags
        task.lastModified = remoteModified
        if existing == nil { context.insert(task) }
        try? context.save()
    }

    // MARK: - Activity feed

    func pushActivity(_ event: ActivityEvent) {
        let data: [String: Any] = [
            "authorID": event.authorID.uuidString, "authorName": event.authorName,
            "kind": event.kind.rawValue, "message": event.message, "timestamp": event.timestamp
        ]
        db.collection("activity").document(event.id.uuidString).setData(data, merge: true)
    }

    private func listenForActivityChanges() {
        activityListener = db.collection("activity")
            .order(by: "timestamp", descending: true)
            .limit(to: 200)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, let snapshot, error == nil else { return }
                for change in snapshot.documentChanges where change.type == .added {
                    self.insertActivityIfNeeded(from: change.document)
                }
            }
    }

    private func insertActivityIfNeeded(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<ActivityEvent>(predicate: #Predicate { $0.id == id })
        guard (try? context.fetch(descriptor).first) == nil else { return }
        let data = document.data()
        guard let authorID = UUID(uuidString: data["authorID"] as? String ?? ""),
              let kindRaw = data["kind"] as? String,
              let kind = ActivityKind(rawValue: kindRaw) else { return }
        let event = ActivityEvent(id: id, authorID: authorID, authorName: data["authorName"] as? String ?? "",
                                   kind: kind, message: data["message"] as? String ?? "",
                                   timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? .now)
        context.insert(event)
        try? context.save()
    }

    // MARK: - Notebook entries

    func pushNotebookEntry(_ entry: NotebookEntry) {
        var data: [String: Any] = [
            "authorID": entry.authorID.uuidString, "authorName": entry.authorName,
            "title": entry.title, "content": entry.content, "tags": entry.tags, "timestamp": entry.timestamp
        ]
        if let auto = entry.autonomousLog, let encoded = try? JSONEncoder().encode(auto) {
            data["autonomousLog"] = String(data: encoded, encoding: .utf8)
        }
        if let hub = entry.hubConfigLog, let encoded = try? JSONEncoder().encode(hub) {
            data["hubConfigLog"] = String(data: encoded, encoding: .utf8)
        }
        if let imu = entry.imuLog, let encoded = try? JSONEncoder().encode(imu) {
            data["imuLog"] = String(data: encoded, encoding: .utf8)
        }
        db.collection("notebook").document(entry.id.uuidString).setData(data, merge: true)
    }

    func deleteNotebookEntry(id: UUID) {
        db.collection("notebook").document(id.uuidString).delete()
    }

    private func listenForNotebookChanges() {
        notebookListener = db.collection("notebook").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges {
                switch change.type {
                case .added:
                    self.insertNotebookEntryIfNeeded(from: change.document)
                case .removed:
                    self.deleteNotebookEntryLocally(id: change.document.documentID)
                case .modified:
                    self.insertNotebookEntryIfNeeded(from: change.document, allowUpdate: true)
                }
            }
        }
    }

    private func insertNotebookEntryIfNeeded(from document: QueryDocumentSnapshot, allowUpdate: Bool = false) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<NotebookEntry>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        if existing != nil && !allowUpdate { return }

        let data = document.data()
        guard let authorID = UUID(uuidString: data["authorID"] as? String ?? "") else { return }

        let entry = existing ?? NotebookEntry(id: id, authorID: authorID, authorName: "", title: "")
        entry.authorName = data["authorName"] as? String ?? entry.authorName
        entry.title = data["title"] as? String ?? entry.title
        entry.content = data["content"] as? String ?? entry.content
        entry.tags = data["tags"] as? [String] ?? entry.tags
        entry.timestamp = (data["timestamp"] as? Timestamp)?.dateValue() ?? entry.timestamp

        if let raw = data["autonomousLog"] as? String, let json = raw.data(using: .utf8) {
            entry.autonomousLog = try? JSONDecoder().decode(AutonomousTestLog.self, from: json)
        }
        if let raw = data["hubConfigLog"] as? String, let json = raw.data(using: .utf8) {
            entry.hubConfigLog = try? JSONDecoder().decode(ControlHubConfigLog.self, from: json)
        }
        if let raw = data["imuLog"] as? String, let json = raw.data(using: .utf8) {
            entry.imuLog = try? JSONDecoder().decode(IMUTuningLog.self, from: json)
        }
        if existing == nil { context.insert(entry) }
        try? context.save()
    }

    private func deleteNotebookEntryLocally(id documentID: String) {
        guard let context = modelContext, let id = UUID(uuidString: documentID) else { return }
        let descriptor = FetchDescriptor<NotebookEntry>(predicate: #Predicate { $0.id == id })
        if let entry = try? context.fetch(descriptor).first {
            context.delete(entry)
            try? context.save()
        }
    }

    // MARK: - Ideas

    func pushIdea(_ idea: Idea) {
        let data: [String: Any] = [
            "authorID": idea.authorID.uuidString, "authorName": idea.authorName,
            "summary": idea.summary, "detail": idea.detail,
            "upvoterIDs": idea.upvoterIDs.map { $0.uuidString },
            "timestamp": idea.timestamp, "promotedToTask": idea.promotedToTask
        ]
        db.collection("ideas").document(idea.id.uuidString).setData(data, merge: true)
    }

    private func listenForIdeaChanges() {
        ideaListener = db.collection("ideas").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges { self.upsertIdea(from: change.document) }
        }
    }

    private func upsertIdea(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()
        let descriptor = FetchDescriptor<Idea>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        guard let authorID = UUID(uuidString: data["authorID"] as? String ?? "") else { return }
        let idea = existing ?? Idea(id: id, authorID: authorID, authorName: "", summary: "")
        idea.authorName = data["authorName"] as? String ?? idea.authorName
        idea.summary = data["summary"] as? String ?? idea.summary
        idea.detail = data["detail"] as? String ?? idea.detail
        idea.upvoterIDs = (data["upvoterIDs"] as? [String] ?? []).compactMap { UUID(uuidString: $0) }
        idea.promotedToTask = data["promotedToTask"] as? Bool ?? idea.promotedToTask
        if existing == nil { context.insert(idea) }
        try? context.save()
    }

    // MARK: - Test runs

    func pushTestRun(_ record: TestRunRecord) {
        var data: [String: Any] = [
            "driverID": record.driverID.uuidString, "driverName": record.driverName, "date": record.date,
            "autoScore": record.autoScore, "teleopScore": record.teleopScore, "endgameScore": record.endgameScore,
            "cycleTimeSeconds": record.cycleTimeSeconds, "autoConsistencyPercent": record.autoConsistencyPercent,
            "mechanicalIssues": record.mechanicalIssues, "notes": record.notes,
            "recordedByID": record.recordedByID.uuidString, "recordedByName": record.recordedByName
        ]
        data["batteryLabel"] = record.batteryLabel ?? ""
        db.collection("testRuns").document(record.id.uuidString).setData(data, merge: true)
    }

    private func listenForTestRunChanges() {
        testRunListener = db.collection("testRuns").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges where change.type == .added {
                self.insertTestRunIfNeeded(from: change.document)
            }
        }
    }

    private func insertTestRunIfNeeded(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<TestRunRecord>(predicate: #Predicate { $0.id == id })
        guard (try? context.fetch(descriptor).first) == nil else { return }
        let data = document.data()
        guard let driverID = UUID(uuidString: data["driverID"] as? String ?? ""),
              let recordedByID = UUID(uuidString: data["recordedByID"] as? String ?? "") else { return }
        let batteryLabelRaw = data["batteryLabel"] as? String ?? ""
        let record = TestRunRecord(
            id: id, driverID: driverID, driverName: data["driverName"] as? String ?? "",
            date: (data["date"] as? Timestamp)?.dateValue() ?? .now,
            autoScore: data["autoScore"] as? Int ?? 0, teleopScore: data["teleopScore"] as? Int ?? 0,
            endgameScore: data["endgameScore"] as? Int ?? 0,
            cycleTimeSeconds: data["cycleTimeSeconds"] as? Double ?? 0,
            autoConsistencyPercent: data["autoConsistencyPercent"] as? Double ?? 0,
            mechanicalIssues: data["mechanicalIssues"] as? [String] ?? [], notes: data["notes"] as? String ?? "",
            recordedByID: recordedByID, recordedByName: data["recordedByName"] as? String ?? "",
            batteryLabel: batteryLabelRaw.isEmpty ? nil : batteryLabelRaw
        )
        context.insert(record)
        try? context.save()
    }

    // MARK: - Batteries

    func pushBattery(_ battery: Battery) {
        let data: [String: Any] = [
            "label": battery.label, "statusRaw": battery.statusRaw, "cycleCount": battery.cycleCount,
            "lastChargedAt": battery.lastChargedAt as Any, "notes": battery.notes, "addedAt": battery.addedAt
        ]
        db.collection("batteries").document(battery.id.uuidString).setData(data, merge: true)
    }

    private func listenForBatteryChanges() {
        batteryListener = db.collection("batteries").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges { self.upsertBattery(from: change.document) }
        }
    }

    private func upsertBattery(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()
        let descriptor = FetchDescriptor<Battery>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        let battery = existing ?? Battery(id: id, label: data["label"] as? String ?? "")
        battery.label = data["label"] as? String ?? battery.label
        battery.statusRaw = data["statusRaw"] as? String ?? battery.statusRaw
        battery.cycleCount = data["cycleCount"] as? Int ?? battery.cycleCount
        battery.lastChargedAt = (data["lastChargedAt"] as? Timestamp)?.dateValue()
        battery.notes = data["notes"] as? String ?? battery.notes
        if existing == nil { context.insert(battery) }
        try? context.save()
    }

    // MARK: - Checklists

    func pushChecklistRun(_ run: ChecklistRun) {
        var data: [String: Any] = [
            "typeRaw": run.typeRaw, "completedByID": run.completedByID.uuidString,
            "completedByName": run.completedByName, "timestamp": run.timestamp
        ]
        if let encoded = try? JSONEncoder().encode(run.itemResults) {
            data["itemResults"] = String(data: encoded, encoding: .utf8)
        }
        db.collection("checklists").document(run.id.uuidString).setData(data, merge: true)
    }

    private func listenForChecklistChanges() {
        checklistListener = db.collection("checklists").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges where change.type == .added {
                self.insertChecklistRunIfNeeded(from: change.document)
            }
        }
    }

    private func insertChecklistRunIfNeeded(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<ChecklistRun>(predicate: #Predicate { $0.id == id })
        guard (try? context.fetch(descriptor).first) == nil else { return }
        let data = document.data()
        guard let completedByID = UUID(uuidString: data["completedByID"] as? String ?? ""),
              let typeRaw = data["typeRaw"] as? String,
              let type = ChecklistType(rawValue: typeRaw) else { return }
        var results: [ChecklistItemResult] = []
        if let raw = data["itemResults"] as? String, let json = raw.data(using: .utf8) {
            results = (try? JSONDecoder().decode([ChecklistItemResult].self, from: json)) ?? []
        }
        let run = ChecklistRun(id: id, type: type, itemResults: results, completedByID: completedByID,
                                completedByName: data["completedByName"] as? String ?? "",
                                timestamp: (data["timestamp"] as? Timestamp)?.dateValue() ?? .now)
        context.insert(run)
        try? context.save()
    }

    // MARK: - Inventory

    func pushInventoryItem(_ item: InventoryItem) {
        let data: [String: Any] = [
            "name": item.name, "category": item.category, "binLocation": item.binLocation,
            "quantity": item.quantity, "isCheckedOut": item.isCheckedOut,
            "checkedOutByName": item.checkedOutByName, "notes": item.notes,
            "lowStockThreshold": item.lowStockThreshold, "needsMaintenance": item.needsMaintenance,
            "addedAt": item.addedAt
        ]
        db.collection("inventory").document(item.id.uuidString).setData(data, merge: true)
    }

    private func listenForInventoryChanges() {
        inventoryListener = db.collection("inventory").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges { self.upsertInventoryItem(from: change.document) }
        }
    }

    private func upsertInventoryItem(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()
        let descriptor = FetchDescriptor<InventoryItem>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        let item = existing ?? InventoryItem(id: id, name: data["name"] as? String ?? "",
                                              category: data["category"] as? String ?? "", binLocation: "")
        item.name = data["name"] as? String ?? item.name
        item.category = data["category"] as? String ?? item.category
        item.binLocation = data["binLocation"] as? String ?? item.binLocation
        item.quantity = data["quantity"] as? Int ?? item.quantity
        item.isCheckedOut = data["isCheckedOut"] as? Bool ?? item.isCheckedOut
        item.checkedOutByName = data["checkedOutByName"] as? String ?? item.checkedOutByName
        item.notes = data["notes"] as? String ?? item.notes
        item.lowStockThreshold = data["lowStockThreshold"] as? Int ?? item.lowStockThreshold
        item.needsMaintenance = data["needsMaintenance"] as? Bool ?? item.needsMaintenance
        if existing == nil { context.insert(item) }
        try? context.save()
    }

    // MARK: - Match scouting

    func pushScoutingReport(_ report: ScoutingReport) {
        let data: [String: Any] = [
            "teamNumber": report.teamNumber, "teamName": report.teamName,
            "eventName": report.eventName, "matchNumber": report.matchNumber,
            "autonomousScore": report.autonomousScore, "teleOpScore": report.teleOpScore,
            "endgameScore": report.endgameScore, "capabilities": report.capabilities,
            "notes": report.notes, "recordedByID": report.recordedByID.uuidString,
            "recordedByName": report.recordedByName, "observedAt": report.observedAt
        ]
        db.collection("scoutingReports").document(report.id.uuidString).setData(data, merge: true)
    }

    func deleteScoutingReport(id: UUID) {
        db.collection("scoutingReports").document(id.uuidString).delete()
    }

    private func listenForScoutingReportChanges() {
        scoutingReportListener = db.collection("scoutingReports").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges {
                if change.type == .removed {
                    self.deleteScoutingReportLocally(id: change.document.documentID)
                } else {
                    self.upsertScoutingReport(from: change.document)
                }
            }
        }
    }

    private func upsertScoutingReport(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()
        guard let recordedByID = UUID(uuidString: data["recordedByID"] as? String ?? "") else { return }
        let descriptor = FetchDescriptor<ScoutingReport>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        let report = existing ?? ScoutingReport(
            id: id, teamNumber: 0, teamName: "", eventName: "", matchNumber: "",
            recordedByID: recordedByID, recordedByName: ""
        )
        report.teamNumber = data["teamNumber"] as? Int ?? report.teamNumber
        report.teamName = data["teamName"] as? String ?? report.teamName
        report.eventName = data["eventName"] as? String ?? report.eventName
        report.matchNumber = data["matchNumber"] as? String ?? report.matchNumber
        report.autonomousScore = data["autonomousScore"] as? Int ?? report.autonomousScore
        report.teleOpScore = data["teleOpScore"] as? Int ?? report.teleOpScore
        report.endgameScore = data["endgameScore"] as? Int ?? report.endgameScore
        report.capabilities = data["capabilities"] as? [String] ?? report.capabilities
        report.notes = data["notes"] as? String ?? report.notes
        report.recordedByName = data["recordedByName"] as? String ?? report.recordedByName
        report.observedAt = (data["observedAt"] as? Timestamp)?.dateValue() ?? report.observedAt
        if existing == nil { context.insert(report) }
        try? context.save()
    }

    private func deleteScoutingReportLocally(id documentID: String) {
        guard let context = modelContext, let id = UUID(uuidString: documentID) else { return }
        let descriptor = FetchDescriptor<ScoutingReport>(predicate: #Predicate { $0.id == id })
        if let report = try? context.fetch(descriptor).first {
            context.delete(report)
            try? context.save()
        }
    }

    // MARK: - Team Settings (single shared row, doc id fixed as "shared")

    func pushTeamSettings(_ settings: TeamSettings) {
        let data: [String: Any] = [
            "teamNumber": settings.teamNumber, "teamName": settings.teamName,
            "rookieYear": settings.rookieYear, "seasonName": settings.seasonName
        ]
        db.collection("teamSettings").document("shared").setData(data, merge: true)
    }

    private func listenForTeamSettingsChanges() {
        teamSettingsListener = db.collection("teamSettings").document("shared").addSnapshotListener { [weak self] document, error in
            guard let self, let document, let data = document.data(), error == nil else { return }
            guard let context = self.modelContext else { return }
            let descriptor = FetchDescriptor<TeamSettings>()
            let settings = (try? context.fetch(descriptor).first) ?? TeamSettings()
            settings.teamNumber = data["teamNumber"] as? Int ?? settings.teamNumber
            settings.teamName = data["teamName"] as? String ?? settings.teamName
            settings.rookieYear = data["rookieYear"] as? Int ?? settings.rookieYear
            settings.seasonName = data["seasonName"] as? String ?? settings.seasonName
            if (try? context.fetch(descriptor).first) == nil { context.insert(settings) }
            try? context.save()
        }
    }

    // MARK: - Sponsors

    func pushSponsor(_ sponsor: Sponsor) {
        let data: [String: Any] = [
            "name": sponsor.name, "contactName": sponsor.contactName, "contactEmail": sponsor.contactEmail,
            "pledgedAmount": sponsor.pledgedAmount, "receivedAmount": sponsor.receivedAmount,
            "statusRaw": sponsor.statusRaw, "notes": sponsor.notes, "addedAt": sponsor.addedAt
        ]
        db.collection("sponsors").document(sponsor.id.uuidString).setData(data, merge: true)
    }

    private func listenForSponsorChanges() {
        sponsorListener = db.collection("sponsors").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges { self.upsertSponsor(from: change.document) }
        }
    }

    private func upsertSponsor(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let data = document.data()
        let descriptor = FetchDescriptor<Sponsor>(predicate: #Predicate { $0.id == id })
        let existing = try? context.fetch(descriptor).first
        let sponsor = existing ?? Sponsor(id: id, name: data["name"] as? String ?? "")
        sponsor.name = data["name"] as? String ?? sponsor.name
        sponsor.contactName = data["contactName"] as? String ?? sponsor.contactName
        sponsor.contactEmail = data["contactEmail"] as? String ?? sponsor.contactEmail
        sponsor.pledgedAmount = data["pledgedAmount"] as? Double ?? sponsor.pledgedAmount
        sponsor.receivedAmount = data["receivedAmount"] as? Double ?? sponsor.receivedAmount
        sponsor.statusRaw = data["statusRaw"] as? String ?? sponsor.statusRaw
        sponsor.notes = data["notes"] as? String ?? sponsor.notes
        if existing == nil { context.insert(sponsor) }
        try? context.save()
    }

    // MARK: - Budget Expenses

    func pushExpense(_ expense: BudgetExpense) {
        let data: [String: Any] = [
            "item": expense.item, "amount": expense.amount, "category": expense.category,
            "date": expense.date, "notes": expense.notes, "addedByName": expense.addedByName
        ]
        db.collection("expenses").document(expense.id.uuidString).setData(data, merge: true)
    }

    private func listenForExpenseChanges() {
        expenseListener = db.collection("expenses").addSnapshotListener { [weak self] snapshot, error in
            guard let self, let snapshot, error == nil else { return }
            for change in snapshot.documentChanges where change.type == .added {
                self.insertExpenseIfNeeded(from: change.document)
            }
        }
    }

    private func insertExpenseIfNeeded(from document: QueryDocumentSnapshot) {
        guard let context = modelContext, let id = UUID(uuidString: document.documentID) else { return }
        let descriptor = FetchDescriptor<BudgetExpense>(predicate: #Predicate { $0.id == id })
        guard (try? context.fetch(descriptor).first) == nil else { return }
        let data = document.data()
        let expense = BudgetExpense(
            id: id, item: data["item"] as? String ?? "", amount: data["amount"] as? Double ?? 0,
            category: data["category"] as? String ?? "Uncategorized",
            date: (data["date"] as? Timestamp)?.dateValue() ?? .now,
            notes: data["notes"] as? String ?? "", addedByName: data["addedByName"] as? String ?? ""
        )
        context.insert(expense)
        try? context.save()
    }
}
