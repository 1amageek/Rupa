import RupaCoreTypes

public protocol DocumentExportPreflightValidator: Sendable {
    func validateExport(
        context: DocumentExportPreflightContext
    ) throws -> DocumentExportPreflightResult
}
