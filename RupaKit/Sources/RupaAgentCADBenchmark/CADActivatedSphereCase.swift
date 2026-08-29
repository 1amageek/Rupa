import Foundation

/// The sphere cases whose production capability boundary has been reviewed.
///
/// The kernel may support analytic sphere construction, but the Agent surface
/// currently exposes no sphere ingress. SPH-001 is therefore activated as an
/// honest capability-observation case; the remaining prepared cases stay out
/// of the production authority until their own gates are complete.
enum CADActivatedSphereCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case sphere001 = "SPH-001"

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
        }
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            try preparedCase.catalogEntry
        }
    }
}
