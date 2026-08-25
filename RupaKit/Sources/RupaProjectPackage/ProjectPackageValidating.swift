/// Validates the complete canonical save plan without writing a destination.
public protocol ProjectPackageValidating: Sendable {
    func validateForSave(_ document: ProjectPackageDocument) throws
}
