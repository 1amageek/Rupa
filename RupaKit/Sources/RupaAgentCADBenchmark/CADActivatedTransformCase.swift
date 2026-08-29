import Foundation

/// The transform cases whose production route has been independently activated.
///
/// Transform catalog entries remain prepared until their own vertical gate is
/// complete.  Only TRN-001 is part of the measured authority in this sprint.
enum CADActivatedTransformCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case trn001 = "TRN-001"

    var caseID: CADBenchmarkCaseID {
        CADBenchmarkCaseID(rawValue: rawValue)
    }

    init(caseID: CADBenchmarkCaseID) throws {
        guard let activated = Self(rawValue: caseID.rawValue) else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        self = activated
    }

    var preparedCase: CADTransformPreparedCase {
        switch self {
        case .trn001:
            .transform001
        }
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            try preparedCase.catalogEntry
        }
    }
}
