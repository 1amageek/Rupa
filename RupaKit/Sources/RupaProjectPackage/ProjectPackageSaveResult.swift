import RupaCoreTypes

public struct ProjectPackageSaveResult: Sendable {
    public let document: ProjectPackageDocument
    public let documentContentIdentity: DocumentContentIdentity
    public let report: ProjectPackageIOReport
    public let warnings: [ProjectPackageSaveWarning]

    public init(
        document: ProjectPackageDocument,
        documentContentIdentity: DocumentContentIdentity,
        report: ProjectPackageIOReport,
        warnings: [ProjectPackageSaveWarning] = []
    ) {
        self.document = document
        self.documentContentIdentity = documentContentIdentity
        self.report = report
        self.warnings = warnings
    }
}
