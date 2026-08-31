import RupaCLIKit
import RupaProjectAccessComposition
import RupaProjectAccessPlatform

/// Provides the executable composition for the signed Xcode `rupa` product.
@MainActor
public enum RupaCLIComposition {
    /// Resolves product coordination, installs one access composition, and
    /// invokes the existing asynchronous CLI command tree.
    public static func run() async {
        let configuration = RupaProductAccessConfiguration.current
        let access = makeAccess(configuration: configuration)
        let dependencies = CLIProjectAccessDependencies(
            opener: access,
            observer: access,
            requestTimeout: configuration.requestTimeout
        )
        await CLIProjectAccessContext.$current.withValue(dependencies) {
            await CLICommand.main()
        }
    }

    private static func makeAccess(
        configuration: RupaProductAccessConfiguration
    ) -> LiveProjectAccessOpening {
        return LiveProjectAccessOpening(
            discoveryReader: configuration.makeDiscoveryStore(),
            launcher: LaunchServicesProjectApplicationLauncher(
                applicationBundleIdentifier:
                    configuration.applicationBundleIdentifier
            ),
            requestTimeout: configuration.requestTimeout
        )
    }
}
