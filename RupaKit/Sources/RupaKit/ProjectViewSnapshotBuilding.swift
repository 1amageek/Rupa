import RupaProject

public protocol ProjectViewSnapshotBuilding: Sendable {
    func build(from state: ProjectStateSnapshot) throws -> ProjectViewSnapshot
}
