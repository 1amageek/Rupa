import SwiftCAD

public enum SourceBodyOutputRole: String, Codable, Equatable, Hashable, Sendable {
    case body
    case sheet

    init(sourcePort: FeaturePort) throws {
        switch sourcePort {
        case .body:
            self = .body
        case .sheet:
            self = .sheet
        case .profile, .curve, .path, .guide, .target:
            throw CommandGeneratedIdentityError.wrongBodyOutputRole(sourcePort)
        }
    }
}
