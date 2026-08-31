import Foundation

/// Product-owned identifiers shared by the signed Rupa App and CLI.
public struct RupaProductAccessConfiguration: Equatable, Sendable {
    public static let current = RupaProductAccessConfiguration(
        applicationBundleIdentifier: "team.stamp.Rupa",
        discoveryService: "team.stamp.Rupa.agent-api",
        discoveryAccount: "live-listener",
        keychainAccessGroup: "WWCKBW8CKN.team.stamp.rupa.agent",
        requestTimeout: .seconds(120)
    )

    public let applicationBundleIdentifier: String
    public let discoveryService: String
    public let discoveryAccount: String
    public let keychainAccessGroup: String
    public let requestTimeout: Duration

    public init(
        applicationBundleIdentifier: String,
        discoveryService: String,
        discoveryAccount: String,
        keychainAccessGroup: String,
        requestTimeout: Duration
    ) {
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.discoveryService = discoveryService
        self.discoveryAccount = discoveryAccount
        self.keychainAccessGroup = keychainAccessGroup
        self.requestTimeout = requestTimeout
    }

    public func makeDiscoveryStore() -> KeychainAgentDiscoveryStore {
        KeychainAgentDiscoveryStore(
            service: discoveryService,
            account: discoveryAccount,
            accessGroup: keychainAccessGroup
        )
    }
}
