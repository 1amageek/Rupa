import ArgumentParser
import RupaCLIKit
import RupaProjectAccessComposition
import RupaProjectAccessPlatform

@main
struct CLI {
    @MainActor
    static func main() async {
        do {
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
            let access = DefaultProjectAccess(live: live, closed: closed)
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
}
