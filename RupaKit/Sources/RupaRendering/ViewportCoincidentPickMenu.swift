import CoreGraphics
import RupaCore
import RupaViewportScene

/// Control-Shift-click on coincident sub-shapes of different bodies — the edge two touching sheets
/// share — as Plasticity's pop-up: the click's canvas target and the sub-shapes to choose from, each
/// named by its kind and its object, listed where the click was. Hovering an entry highlights its
/// object; choosing one delivers the click with that sub-shape.
struct ViewportCoincidentPickMenu {
    struct Entry: Identifiable {
        let id: Int
        let hit: ViewportHit
        let title: String
    }

    let point: CGPoint
    let entries: [Entry]
    private let target: ViewportCanvasTarget

    /// The menu for a click at `point` resolved to `target`, listing `hits` (at least two) named
    /// by their object's name from `name`.
    init(point: CGPoint, target: ViewportCanvasTarget, hits: [ViewportHit], name: (SceneNodeID) -> String?) {
        self.point = point
        self.target = target
        entries = hits.enumerated().map { index, hit in
            let kind: String = switch hit.selectionComponent {
            case .vertex?: "Vertex"
            case .edge?: "Edge"
            case .face?: "Face"
            default: "Object"
            }
            let object = hit.sceneNodeID.flatMap(name) ?? "Object"
            return Entry(id: index, hit: hit, title: "\(kind) - \(object)")
        }
    }

    /// The click's target with `entry`'s sub-shape in place of the one the pointer resolved.
    /// Control only opened the menu, so the delivered click does not carry it; Shift's intent stays.
    func target(choosing entry: Entry) -> ViewportCanvasTarget {
        var chosen = target
        chosen.hit = entry.hit
        chosen.modifierFlags.containsControl = false
        return chosen
    }

    /// Where the list is drawn, beside the click, which the canvas leaves to it: wide enough for
    /// an object's name, a row per entry.
    var inputExclusionRect: CGRect {
        CGRect(x: point.x + 8, y: point.y + 8, width: 260, height: CGFloat(entries.count) * 24 + 8)
    }

    /// `entry`'s object hit whole: what hovering the entry highlights.
    func objectHit(of entry: Entry) -> ViewportHit {
        ViewportHit(featureID: entry.hit.featureID, sceneNodeID: entry.hit.sceneNodeID, kind: entry.hit.kind)
    }
}
