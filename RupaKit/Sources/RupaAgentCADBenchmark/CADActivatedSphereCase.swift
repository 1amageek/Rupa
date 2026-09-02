import Foundation

/// The sphere cases covered by the semantic CAD operation boundary.
enum CADActivatedSphereCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case sphere001 = "SPH-001"
    case sphere002 = "SPH-002"
    case sphere003 = "SPH-003"
    case sphere004 = "SPH-004"
    case sphere005 = "SPH-005"

    var caseID: CADBenchmarkCaseID {
        CADBenchmarkCaseID(rawValue: rawValue)
    }

    init(caseID: CADBenchmarkCaseID) throws {
        guard let activated = Self(rawValue: caseID.rawValue) else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        self = activated
    }

    init(caseID: String) throws {
        guard let activated = Self(rawValue: caseID) else {
            throw CADBenchmarkError.invalidCaseID(caseID)
        }
        self = activated
    }

    var preparedCase: CADSpherePreparationCase {
        switch self {
        case .sphere001:
            .sph001
        case .sphere002:
            .sph002
        case .sphere003:
            .sph003
        case .sphere004:
            .sph004
        case .sphere005:
            .sph005
        }
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            try preparedCase.catalogEntry
        }
    }
}
