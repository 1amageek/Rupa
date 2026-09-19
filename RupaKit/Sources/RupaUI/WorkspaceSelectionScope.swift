import RupaCore
import RupaRendering
import SwiftUI

enum WorkspaceSelectionScope: String, CaseIterable, Identifiable, Sendable {
    case object
    case face
    case edge
    case vertex
    case region
    case sketchEntity

    var id: String {
        rawValue
    }

    /// The digit that chooses this scope, and the scope a digit chooses.
    ///
    /// The rail already shows the scopes in `allCases` order, so the keys follow
    /// that order and stay discoverable from the control they duplicate. Both
    /// directions live here so the router and the rail's tooltip cannot disagree
    /// about which digit means which scope.
    var keyEquivalent: Character? {
        guard let position = Self.allCases.firstIndex(of: self),
              position < 9 else {
            return nil
        }
        return Character(String(position + 1))
    }

    static func scope(forKeyEquivalent key: Character) -> WorkspaceSelectionScope? {
        allCases.first { $0.keyEquivalent == key }
    }

    var title: String {
        switch self {
        case .object:
            return "Object"
        case .face:
            return "Face"
        case .edge:
            return "Edge"
        case .vertex:
            return "Vertex"
        case .region:
            return "Region"
        case .sketchEntity:
            return "Curve"
        }
    }

    var systemImage: String {
        switch self {
        case .object:
            return "cube"
        case .face:
            return "square.on.square"
        case .edge:
            return "line.diagonal"
        case .vertex:
            return "smallcircle.filled.circle"
        case .region:
            return "square.dashed"
        case .sketchEntity:
            return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    var help: String {
        switch self {
        case .object:
            return "Select whole objects"
        case .face:
            return "Select body faces"
        case .edge:
            return "Select body edges"
        case .vertex:
            return "Select body vertices"
        case .region:
            return "Select closed sketch regions"
        case .sketchEntity:
            return "Select source sketch entities"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .object, .face, .edge, .vertex, .region, .sketchEntity:
            return true
        }
    }

    var viewportSelectionHitPolicy: ViewportSelectionHitPolicy {
        switch self {
        case .object:
            return .object
        case .face:
            return .face
        case .edge:
            return .edge
        case .vertex:
            return .vertex
        case .region:
            return .region
        case .sketchEntity:
            return .sketchEntity
        }
    }

    var allowsSelectionRectangle: Bool {
        switch self {
        case .object, .face, .edge, .vertex, .region, .sketchEntity:
            return true
        }
    }

    func allowsPresentationOccurrencePick(for tool: ModelingTool) -> Bool {
        tool == .select && self == .object
    }
}
