import RupaProject

public protocol ProjectViewSnapshotBuilding: Sendable {
    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot
    /// Builds the view of `state`, reusing what `previous` already built for the same document
    /// state (the published document, presentation scene and navigation) when it has one.
    func build(from state: ProjectStateSnapshot, reusing previous: ProjectViewSnapshot?) throws -> ProjectViewSnapshot
}

extension ProjectViewSnapshotBuilding {
    /// A builder that keeps nothing between views builds each one whole.
    public func build(from state: ProjectStateSnapshot, reusing previous: ProjectViewSnapshot?) throws -> ProjectViewSnapshot {
        try build(from: state)
    }
}
