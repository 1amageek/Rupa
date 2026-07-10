import RupaCore
import RupaDomainFoundation

struct ManufacturingPrintabilityLowering: DomainCommandLowering {
    var processCatalog: any ManufacturingProcessCatalog

    var capabilityID: DomainCapabilityID {
        ManufacturingDomain.validatePrintabilityCapabilityID
    }

    func lower(_ request: DomainCommandRequest) throws -> DomainCommandPlan {
        let options = try validate(request)
        guard let processProfile = processCatalog.profile(for: options.processID) else {
            throw ManufacturingProcessCatalogError(
                code: .unsupportedProcess,
                message: "Manufacturing process \(options.processID.rawValue) is not registered."
            )
        }
        return .query(
            ManufacturingPrintabilityQuery(
                options: options,
                processProfile: processProfile
            )
        )
    }

    private func validate(_ request: DomainCommandRequest) throws -> ManufacturingPrintabilityOptions {
        guard request.namespace == ManufacturingDomain.namespace else {
            throw EditorError(
                code: .commandInvalid,
                message: "Manufacturing printability validation received the wrong namespace."
            )
        }
        return try ManufacturingPrintabilityOptions(
            payload: request.payload,
            defaultProcessID: processCatalog.defaultProcessID
        )
    }
}
