//
//  NotificationScheduler.swift
//  FTCTeamHub
//
//  Local (on-device) notifications for task deadlines. Deliberately local
//  rather than push-based — no server infrastructure needed, and push
//  notifications require a paid Apple Developer Program capability
//  (same restriction hit with CloudKit) which this free-Apple-ID
//  sideloaded app doesn't have. Local notifications have no such restriction.
//

import Foundation
import UserNotifications

enum NotificationScheduler {

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedules a reminder for 9 AM on the task's deadline day. Silently
    /// does nothing if there's no deadline or the deadline has already passed.
    static func scheduleDeadlineReminder(for task: TaskItem) {
        guard let deadline = task.deadline else { return }

        var components = Calendar.current.dateComponents([.year, .month, .day], from: deadline)
        components.hour = 9
        components.minute = 0
        guard let fireDate = Calendar.current.date(from: components), fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Task due today: \(task.title)"
        content.body = "Assigned to \(task.assignedToName) · Priority: \(task.priority.rawValue)"
        content.sound = .default

        let triggerComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request)
    }

    /// Call when a task is completed or deleted so a stale reminder
    /// doesn't fire for a task that's already done.
    static func cancelReminder(for task: TaskItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [task.id.uuidString])
    }
}
