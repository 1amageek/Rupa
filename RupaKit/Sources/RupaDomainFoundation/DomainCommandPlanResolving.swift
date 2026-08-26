public protocol DomainCommandPlanResolving: Sendable {
    func resolve(_ request: DomainCommandRequest) throws -> DomainCommandPlanResolution
}
