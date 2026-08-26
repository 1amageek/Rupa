import RupaProjectPackage

/// The package result and exact project authority published by one save.
public struct ProjectSaveCommitResult: Sendable {
    public let package: ProjectPackageSaveResult
    public let state: ProjectStateSnapshot

    public init(
        package: ProjectPackageSaveResult,
        state: ProjectStateSnapshot
    ) {
        self.package = package
        self.state = state
    }
}
