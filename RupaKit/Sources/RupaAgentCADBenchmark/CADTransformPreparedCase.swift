/// Transform cases prepared for later serial authority activation.
enum CADTransformPreparedCase: String, CaseIterable, Sendable {
    case transform001 = "TRN-001"
    case transform002 = "TRN-002"
    case transform003 = "TRN-003"
    case transform004 = "TRN-004"
    case transform005 = "TRN-005"
    case transform006 = "TRN-006"
    case transform007 = "TRN-007"
    case transform008 = "TRN-008"

    var caseID: CADBenchmarkCaseID { CADBenchmarkCaseID(rawValue: rawValue) }

    var catalogEntry: CADCatalogEntry {
        get throws {
            guard let entry = try CADInternalCatalogStore.entries().first(where: {
                $0.challenge.id == caseID
            }) else {
                throw CADBenchmarkError.missingCaseID(rawValue)
            }
            return entry
        }
    }
}
