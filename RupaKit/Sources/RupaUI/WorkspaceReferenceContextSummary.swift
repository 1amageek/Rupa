import RupaCore
import SwiftCAD

struct WorkspaceReferenceContextSummary: Equatable, Sendable {
    var referenceCount: Int
    var familyTitle: String
    var kindTitle: String
    var directionTitle: String?
    var indexTitle: String?
    var systemImage: String

    init(references: [SelectionReference]) {
        self.referenceCount = references.count
        let items = references.map(Self.item)

        guard !items.isEmpty else {
            self.familyTitle = "Reference"
            self.kindTitle = "None"
            self.directionTitle = nil
            self.indexTitle = nil
            self.systemImage = "scope"
            return
        }

        self.familyTitle = Self.commonTitle(items.map(\.familyTitle)) ?? "Mixed"
        self.kindTitle = Self.commonTitle(items.map(\.kindTitle)) ?? "Mixed"
        self.directionTitle = Self.commonOptionalTitle(items.map(\.directionTitle))
        self.indexTitle = Self.commonOptionalTitle(items.map(\.indexTitle))
        self.systemImage = Self.commonTitle(items.map(\.systemImage)) ?? "scope"
    }

    var showsReferenceCount: Bool {
        referenceCount > 1
    }

    private static func item(for reference: SelectionReference) -> Item {
        switch reference {
        case .topology:
            return Item(
                familyTitle: "Topology",
                kindTitle: "Shape",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "cube"
            )
        case let .edge(edge):
            return edgeItem(edge)
        case let .curve(curve):
            return curveItem(curve)
        case .sketchPoint:
            return Item(
                familyTitle: "Sketch",
                kindTitle: "Point",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "smallcircle.filled.circle"
            )
        case let .surface(surface):
            return surfaceItem(surface)
        }
    }

    private static func edgeItem(_ reference: EdgeSubobjectReference) -> Item {
        switch reference {
        case .whole:
            return Item(
                familyTitle: "Edge",
                kindTitle: "Whole",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "line.diagonal"
            )
        case .parameter:
            return Item(
                familyTitle: "Edge",
                kindTitle: "Param",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "line.diagonal"
            )
        }
    }

    private static func curveItem(_ reference: CurveSubobjectReference) -> Item {
        switch reference {
        case .whole:
            return Item(
                familyTitle: "Curve",
                kindTitle: "Whole",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        case .parameter:
            return Item(
                familyTitle: "Curve",
                kindTitle: "Param",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        case .center:
            return Item(
                familyTitle: "Curve",
                kindTitle: "Center",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        case .span:
            return Item(
                familyTitle: "Curve",
                kindTitle: "Span",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        case .controlPoint:
            return Item(
                familyTitle: "Curve",
                kindTitle: "CV",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        case .knot:
            return Item(
                familyTitle: "Curve",
                kindTitle: "Knot",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        }
    }

    private static func surfaceItem(_ reference: SurfaceSubobjectReference) -> Item {
        switch reference {
        case .whole:
            return Item(
                familyTitle: "Surface",
                kindTitle: "Whole",
                directionTitle: nil,
                indexTitle: nil,
                systemImage: "square.grid.3x3"
            )
        case let .parameter(parameter):
            return Item(
                familyTitle: "Surface",
                kindTitle: "Address",
                directionTitle: "UV",
                indexTitle: "u\(compactNumberTitle(parameter.u)) v\(compactNumberTitle(parameter.v))",
                systemImage: "square.grid.3x3"
            )
        case let .span(span):
            return Item(
                familyTitle: "Surface",
                kindTitle: "Span",
                directionTitle: directionTitle(span.direction),
                indexTitle: "s\(span.spanIndex)",
                systemImage: "square.grid.3x3"
            )
        case let .controlPoint(controlPoint):
            return Item(
                familyTitle: "Surface",
                kindTitle: "CV",
                directionTitle: "UV",
                indexTitle: "u\(controlPoint.uIndex) v\(controlPoint.vIndex)",
                systemImage: "square.grid.3x3"
            )
        case let .knot(knot):
            return Item(
                familyTitle: "Surface",
                kindTitle: "Knot",
                directionTitle: directionTitle(knot.direction),
                indexTitle: "k\(knot.knotIndex)",
                systemImage: "square.grid.3x3"
            )
        case let .trim(trim):
            return Item(
                familyTitle: "Trim",
                kindTitle: "Edge",
                directionTitle: nil,
                indexTitle: trimIndexTitle(trim),
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        case let .trimSpan(span):
            return Item(
                familyTitle: "Trim",
                kindTitle: "Span",
                directionTitle: nil,
                indexTitle: "\(trimIndexTitle(span.trim)) s\(span.spanIndex)",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        case let .trimKnot(knot):
            return Item(
                familyTitle: "Trim",
                kindTitle: "Knot",
                directionTitle: nil,
                indexTitle: "\(trimIndexTitle(knot.trim)) k\(knot.knotIndex)",
                systemImage: "point.topleft.down.curvedto.point.bottomright.up"
            )
        }
    }

    private static func directionTitle(_ direction: SurfaceParameterDirection) -> String {
        direction.rawValue.uppercased()
    }

    private static func trimIndexTitle(_ reference: SurfaceTrimReference) -> String {
        "l\(reference.loopIndex) e\(reference.edgeIndex)"
    }

    private static func compactNumberTitle(_ value: Double) -> String {
        let rounded = (value * 1000.0).rounded() / 1000.0
        guard rounded.isFinite else {
            return String(value)
        }
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        var title = String(rounded)
        while title.last == "0" {
            title.removeLast()
        }
        if title.last == "." {
            title.removeLast()
        }
        return title
    }

    private static func commonTitle(_ titles: [String]) -> String? {
        guard let first = titles.first else {
            return nil
        }
        return titles.allSatisfy { $0 == first } ? first : nil
    }

    private static func commonOptionalTitle(_ titles: [String?]) -> String? {
        let values = titles.compactMap { $0 }
        guard values.count == titles.count else {
            return nil
        }
        return commonTitle(values)
    }

    private struct Item: Equatable, Sendable {
        var familyTitle: String
        var kindTitle: String
        var directionTitle: String?
        var indexTitle: String?
        var systemImage: String
    }
}
