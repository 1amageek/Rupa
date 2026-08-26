/// A caller-owned lifecycle check executed before project work and immediately
/// before its result becomes externally observable.
public typealias ProjectOperationGuard = @Sendable () throws -> Void
