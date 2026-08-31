import RupaCLIKit
import RupaProjectAccessComposition
import RupaProjectAccessPlatform

/// Provides the one executable composition shared by every `rupa` product.
@MainActor
public enum RupaCLIComposition {
    /// Resolves product coordination, installs one access composition, and
    /// invokes the existing asynchronous CLI command tree.
    public static func run() async {
        do {
            let access = try makeAccess()
            let dependencies = CLIProjectAccessDependencies(
                opener: access,
                observer: access
            )
            await CLIProjectAccessContext.$current.withValue(dependencies) {
                await CLICommand.main()
            }
        } catch {
            CLICommand.exit(withError: error)
        }
    }

    private static func makeAccess() throws -> DefaultProjectAccess {
        let endpoint = try RupaAgentEndpointComposition.productEndpoint()
        let authorityDirectory = try RupaProjectFileAuthorityComposition
            .projectFileDirectory()
        let live = LiveProjectAccessOpening(
            endpoint: endpoint,
            launcher: LaunchServicesProjectApplicationLauncher()
        )
        let closed = ClosedProjectAccessOpening(
            leaseStore: ProjectFileAuthorityLeaseStore(
                rootDirectory: authorityDirectory
            )
        )
        return DefaultProjectAccess(live: live, closed: closed)
    }
}
