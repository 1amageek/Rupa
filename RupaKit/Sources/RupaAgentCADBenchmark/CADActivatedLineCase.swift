import Foundation

/// The line cases whose production route has been independently activated.
///
/// Catalog membership is not activation.  Keeping this allow-list separate
/// from the catalog prevents a later target specification from entering the
/// measured execution path before its own vertical gate.
enum CADActivatedLineCase: String, CaseIterable, Equatable, Hashable, Sendable {
    case lin001 = "LIN-001"
    case lin002 = "LIN-002"

    var caseID: CADBenchmarkCaseID {
        CADBenchmarkCaseID(rawValue: rawValue)
    }

    init(caseID: CADBenchmarkCaseID) throws {
        guard let activated = Self(rawValue: caseID.rawValue) else {
            throw CADBenchmarkError.invalidCaseID(caseID.rawValue)
        }
        self = activated
    }

    init(_ caseID: CADBenchmarkCaseID) throws {
        try self.init(caseID: caseID)
    }

    init(caseID: String) throws {
        guard let activated = Self(rawValue: caseID) else {
            throw CADBenchmarkError.invalidCaseID(caseID)
        }
        self = activated
    }

    var catalogEntry: CADCatalogEntry {
        get throws {
            guard let entry = try CADInternalCatalogStore.entries().first(where: {
                $0.challenge.id == caseID
            }) else {
                throw CADBenchmarkError.missingCaseID(caseID.rawValue)
            }
            return entry
        }
    }
}
