import Foundation

/// Which narrator holds each story. A story has at most one narrator at a time: a second one
/// would send the same paid requests and overwrite the same chunk files.
public struct NarrationClaims<Owner: Hashable & Sendable>: Sendable {
    private var owners: [UUID: Owner] = [:]

    public init() {}

    /// Takes the story for `owner`. False when another owner already holds it; the same owner
    /// claiming again is fine.
    @discardableResult
    public mutating func claim(_ storyID: UUID, for owner: Owner) -> Bool {
        if let current = owners[storyID], current != owner { return false }
        owners[storyID] = owner
        return true
    }

    /// Gives the story back, but only if `owner` still holds it.
    public mutating func release(_ storyID: UUID, for owner: Owner) {
        if owners[storyID] == owner { owners[storyID] = nil }
    }

    /// Drops the claim whoever holds it, and returns that owner.
    @discardableResult
    public mutating func revoke(_ storyID: UUID) -> Owner? {
        owners.removeValue(forKey: storyID)
    }

    public func owner(of storyID: UUID) -> Owner? { owners[storyID] }

    public func isClaimed(_ storyID: UUID) -> Bool { owners[storyID] != nil }
}
