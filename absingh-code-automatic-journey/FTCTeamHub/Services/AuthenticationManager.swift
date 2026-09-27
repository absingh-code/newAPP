//
//  AuthenticationManager.swift
//  FTCTeamHub
//
//  NEW: now takes an optional `syncService` so sign-up pushes the new
//  user's profile to Firestore immediately — this is what makes a
//  teammate's account visible in the Roster tab on OTHER devices, and
//  lets them sign in from any device once their profile has synced down.
//

import Foundation
import SwiftData
import CryptoKit
import Observation

@MainActor
@Observable
final class AuthenticationManager {

    private(set) var currentUser: AppUser?
    var errorMessage: String?

    private let modelContext: ModelContext
    private let syncService: FirebaseSyncService?
    private let sessionKey = "com.ftcteamhub.session.userID"

    init(modelContext: ModelContext, syncService: FirebaseSyncService? = nil) {
        self.modelContext = modelContext
        self.syncService = syncService
        restoreSession()
    }

    func restoreSession() {
        guard let idString = KeychainService.read(sessionKey),
              let uuid = UUID(uuidString: idString) else { return }

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.id == uuid })
        if let user = try? modelContext.fetch(descriptor).first {
            currentUser = user
        }
    }

    func signUp(name: String, email: String, password: String, role: TeamRole, avatarColor: AvatarColor) {
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        guard !trimmedName.isEmpty, !normalizedEmail.isEmpty, password.count >= 4 else {
            errorMessage = "Enter your name, email, and a password of at least 4 characters."
            return
        }

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.email == normalizedEmail })
        if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty {
            errorMessage = "An account with that email already exists. Try signing in instead."
            return
        }

        let user = AppUser(email: normalizedEmail, name: trimmedName, role: role, avatarColor: avatarColor,
                            passwordHash: Self.hash(password), isLogged: true)
        modelContext.insert(user)
        try? modelContext.save()

        // Push to Firestore so other devices see this team member and can
        // sign in as them once it syncs down.
        syncService?.pushUser(user)

        KeychainService.save(sessionKey, value: user.id.uuidString)
        currentUser = user
    }

    func signIn(email: String, password: String) {
        errorMessage = nil
        let normalizedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()

        let descriptor = FetchDescriptor<AppUser>(predicate: #Predicate { $0.email == normalizedEmail })
        guard let user = try? modelContext.fetch(descriptor).first else {
            errorMessage = "No account found with that email on this device yet. If you signed up on another device, make sure both phones have been online recently so it can sync — then try again in a few seconds."
            return
        }

        guard user.passwordHash == Self.hash(password) else {
            errorMessage = "Incorrect password."
            return
        }

        user.isLogged = true
        try? modelContext.save()
        KeychainService.save(sessionKey, value: user.id.uuidString)
        currentUser = user
    }

    func signOut() {
        currentUser?.isLogged = false
        try? modelContext.save()
        KeychainService.delete(sessionKey)
        currentUser = nil
    }

    private static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
