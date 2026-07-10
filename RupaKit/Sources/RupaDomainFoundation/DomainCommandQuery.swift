public protocol DomainCommandQuery: Sendable {
    func execute(
        _ request: DomainCommandRequest,
        in context: DomainQueryContext
    ) throws -> DomainQueryResult
}
