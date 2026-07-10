public enum DomainCommandParameterKind: String, Codable, Equatable, Sendable {
    case text
    case boolean
    case integer
    case number
    case length
    case angle
    case choice
}
