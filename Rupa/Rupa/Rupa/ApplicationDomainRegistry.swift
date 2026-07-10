import Foundation
import RupaCore
import RupaDomainFoundation
import RupaManufacturing

struct ApplicationDomainRegistryConfiguration {
    var registry: DomainRegistry
    var exportService: DocumentExportService
    var startupDiagnostics: [String]
}

enum ApplicationDomainRegistry {
    static func makeConfiguration() -> ApplicationDomainRegistryConfiguration {
        var diagnostics: [String] = []
        var registries: [DomainRegistry] = []
        let manufacturingProcessCatalog = StandardManufacturingProcessCatalog()

        do {
            registries.append(
                try ManufacturingDomain.registry(
                    processCatalog: manufacturingProcessCatalog
                )
            )
        } catch {
            diagnostics.append("Manufacturing domain registration failed: \(error.localizedDescription)")
        }

        do {
            return ApplicationDomainRegistryConfiguration(
                registry: try DomainRegistry.merged(registries),
                exportService: DocumentExportService(
                    preflightValidators: [
                        ManufacturingExportPreflightValidator(
                            processCatalog: manufacturingProcessCatalog
                        ),
                    ]
                ),
                startupDiagnostics: diagnostics
            )
        } catch {
            diagnostics.append("Domain registry composition failed: \(error.localizedDescription)")
            return ApplicationDomainRegistryConfiguration(
                registry: DomainRegistry(),
                exportService: DocumentExportService(),
                startupDiagnostics: diagnostics
            )
        }
    }
}
