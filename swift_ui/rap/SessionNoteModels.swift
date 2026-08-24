import Foundation

/// A user-authored note, optionally tied to a specific recorded session.
///
/// This is personal journaling, not "session notes integration" in the
/// sense of connecting to a therapist's own practice-management software
/// (SimplePractice, TherapyNotes, an EHR) — no such integration exists
/// here, and implying one would mean claiming a clinical software
/// relationship this app doesn't have. It's a place to write something
/// down; what happens to it after that is the report-export feature.
struct SessionNote: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var date: Date
    var text: String
    /// Ties this note to one recorded session, when relevant — "felt
    /// anxious before this one." `nil` for a freestanding reflection not
    /// tied to any particular session.
    var linkedSessionID: UUID?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        text: String,
        linkedSessionID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.linkedSessionID = linkedSessionID
        self.createdAt = createdAt
    }
}
