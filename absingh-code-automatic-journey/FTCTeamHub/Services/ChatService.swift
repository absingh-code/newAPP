//
//  ChatService.swift
//  FTCTeamHub
//
//  FIX: `db` is now marked `@ObservationIgnored`. The `@Observable` macro
//  rewrites every stored property into a tracked, computed-backed property
//  so SwiftUI can watch it for changes — but `lazy` cannot be combined
//  with that rewrite (that's the exact "init accessor cannot refer to
//  property '_db'" / "'lazy' cannot be used on a computed property" error
//  from the build log). `@ObservationIgnored` opts `db` out of the
//  Observable transformation entirely, which is correct anyway: we only
//  need SwiftUI to react to changes in `messages`, never to `db` itself.
//

import Foundation
import FirebaseFirestore
import Observation

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let authorID: String
    let authorName: String
    let text: String
    let timestamp: Date
    let isPending: Bool
}

enum ChatConnectionState: Equatable {
    case connecting
    case connected
    case cached
    case unavailable(String)
}

@MainActor
@Observable
final class ChatService {

    @ObservationIgnored
    private lazy var db = Firestore.firestore()

    @ObservationIgnored
    private var listener: ListenerRegistration?

    private(set) var messages: [ChatMessage] = []
    private(set) var connectionState: ChatConnectionState = .connecting

    func start() {
        if case .unavailable = connectionState {
            listener?.remove()
            listener = nil
        }
        guard listener == nil else { return }
        connectionState = .connecting
        listener = db.collection("chat")
            .order(by: "timestamp", descending: false)
            .limit(toLast: 300)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let error {
                        self.connectionState = .unavailable(error.localizedDescription)
                        return
                    }
                    guard let snapshot else {
                        self.connectionState = .unavailable("The chat service returned no response.")
                        return
                    }
                    self.connectionState = snapshot.metadata.isFromCache ? .cached : .connected
                    self.messages = snapshot.documents.compactMap { doc in
                        let data = doc.data()
                        guard let authorID = data["authorID"] as? String,
                              let authorName = data["authorName"] as? String,
                              let text = data["text"] as? String,
                              let timestamp = (data["timestamp"] as? Timestamp)?.dateValue() else { return nil }
                        return ChatMessage(id: doc.documentID, authorID: authorID, authorName: authorName,
                                           text: text, timestamp: timestamp, isPending: doc.metadata.hasPendingWrites)
                    }
                }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func send(text: String, authorID: UUID, authorName: String, completion: @escaping (Error?) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let data: [String: Any] = [
            "authorID": authorID.uuidString,
            "authorName": authorName,
            "text": trimmed,
            "timestamp": Date()
        ]
        db.collection("chat").addDocument(data: data) { [weak self] error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.connectionState = .unavailable(error.localizedDescription)
                }
                completion(error)
            }
        }
    }
}
