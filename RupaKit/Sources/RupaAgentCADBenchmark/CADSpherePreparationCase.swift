import Foundation

/// Preparation-only identity for the five catalog sphere cases.
///
/// This type is intentionally not an activation ledger. It lets the sphere
/// preparation tests exercise each fixed target without adding a production
/// candidate action or changing the shared activated executor.
enum CADSpherePreparationCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case sph001 = "SPH-001"
    case sph002 = "SPH-002"
    case sph003 = "SPH-003"
    case sph004 = "SPH-004"
    case sph005 = "SPH-005"

    var caseID: CADBenchmarkCaseID {
        CADBenchmarkCaseID(rawValue: rawValue)
    }

    init(caseID: CADBenchmarkCaseID) throws {
        guard let value = Self(rawValue: caseID.rawValue) else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        self = value
    }

    init(caseID: String) throws {
        guard let value = Self(rawValue: caseID) else {
            throw CADBenchmarkError.invalidCaseID(caseID)
        }
        self = value
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            guard let entry = try CADInternalCatalogStore.entries().first(where: {
                $0.challenge.id == caseID
            }) else {
                throw CADBenchmarkError.missingCaseID(caseID.rawValue)
            }
            guard entry.challenge.category == .sphere else {
                throw CADBenchmarkError.invalidInput(
                    caseID: caseID.rawValue,
                    reason: "The preparation identity resolved to a non-sphere challenge."
                )
            }
            return entry
        }
    }
}
