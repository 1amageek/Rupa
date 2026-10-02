import RupaCore
import SwiftCAD

/// The dialog of a local face operation while it runs, on the faces selected when it started:
/// Push Face (the faces pushed a Distance along their outward side, with an Angle Adjacent tilting
/// the planar faces beside them), Draft Face (the faces turned by Degrees about their crossing
/// with the last-selected face's plane, moved by an Offset), and Match Face (the faces put onto the
/// last-selected face's surface, facing its Front when chosen), and Remove Fillets From Shell (the
/// selected solid's fillets within a Max Radius and a Convexity), and Align Surface (the first
/// edge, of a sheet, following the last with a Continuity, a Tension and Blend rows). Tab steps
/// the Grow mode, Remove Fillets' Convexity, Extend Sheet's Shape, Align Surface's Continuity or
/// Rebuild Face's method (the faces refitted to a Degree and Spans layout or within a Tolerance,
/// extended past them and shrunk to them); OK, Return or right-click applies; Escape ends it without a change.
struct WorkspaceFaceEditSession: Equatable {
    /// This dialog, apart from the one the command starts next (`WorkspaceDialogSubmissions`).
    let instance = WorkspaceDialogInstance()

    enum Kind: Equatable {
        case push(faces: [SelectionTarget])
        case draft(faces: [SelectionTarget], neutral: SelectionTarget)
        case match(faces: [SelectionTarget], reference: SelectionTarget)
        case removeFillets(object: SceneNodeID)
        case hollow(targets: [SelectionTarget])
        case thicken(targets: [SelectionTarget])
        case extendSheet(edges: [SelectionTarget], limit: SelectionTarget? = nil)
        case alignSurface(edge: SelectionTarget, reference: SelectionTarget)
        case rebuildFace(faces: [SelectionTarget])
    }

    let kind: Kind
    /// Push Face's distance, in meters.
    var distanceMeters = 0.001
    /// Push Face's adjacent angle in degrees; zero leaves the faces beside unturned.
    var adjacentAngleDegrees = 0.0
    var draftAngleDegrees = 3.0
    /// Draft Face's neutral plane offset along the neutral face's outward side, in meters.
    var neutralOffsetMeters = 0.0
    var front = false
    var grow: FaceEditGrow = .moving
    /// Remove Fillets' largest radius, in meters; zero takes fillets of any radius.
    var maximumRadiusMeters = 0.0
    var convexity: FilletConvexity = .any
    /// Hollow's wall thickness, in meters.
    var wallThicknessMeters = 0.001
    /// Thicken's thicknesses along the sheet's normal and against it, in meters; locked, the back
    /// follows the front.
    var frontMeters = 0.001
    var backMeters = 0.0
    var locksThicknesses = false
    /// Extend Sheet's shape, which Tab steps, and whether the extensions join the sheet.
    var extensionShape: SheetExtensionShape = .natural
    /// How an extension runs on to the limit's object, when one is selected.
    var limitMode: SheetExtensionLimit.Mode = .minimal
    var modifies = true
    /// Align Surface's continuity, which Tab steps, the tension across the edge and the further
    /// control rows the change fades over.
    var continuity: SurfaceContinuityLevel = .tangentPlane
    var tension = 1.0
    var blendRows = 0
    /// Align Surface's input shape influence on the blended rows, its partial start and end along
    /// the edge, and, when `refitsLayout`, the degrees and spans the sheet is refitted to first.
    var inputShapeInfluence = 1.0
    var partialStart = 0.0
    var partialEnd = 0.0
    /// Align Surface's Boundary: the cross-edge flow along a G1 or G2 edge.
    var boundaryFlow = SquareFitOptions.BoundaryFlow.next
    var refitsLayout = false
    var layout = SurfaceControlLayout(uDegree: 3, vDegree: 3, uSpans: 4, vSpans: 4)
    /// Rebuild Face's method, which Tab steps: the explicit `layout`, a tolerance in meters, or
    /// Remove Nominal Surface (the face's spline cut exactly to its extent); its extensions past
    /// the face each way as fractions of its extent, and Shrink.
    enum RebuildMethodChoice: String, CaseIterable {
        case explicit = "Explicit"
        case tolerance = "Tolerance"
        case nominal = "Remove Nominal Surface"
    }
    var rebuildMethod = RebuildMethodChoice.explicit
    var rebuildToleranceMeters = 0.00001
    var extendU = 0.0
    var extendV = 0.0
    var shrinks = false

    init(kind: Kind) {
        self.kind = kind
    }

    var title: String {
        switch kind {
        case .push: "Push Face"
        case .draft: "Draft Face"
        case .match: "Match Face"
        case .removeFillets: "Remove Fillets"
        case .hollow: "Hollow"
        case .thicken: "Thicken"
        case .extendSheet: "Extend Sheet"
        case .alignSurface: "Align Surface"
        case .rebuildFace: "Rebuild Face"
        }
    }

    /// Whether the operation has a Grow mode: Push Face, Draft Face and Match Face do.
    var hasGrow: Bool {
        switch kind {
        case .push, .draft, .match: true
        case .removeFillets, .hollow, .thicken, .extendSheet, .alignSurface, .rebuildFace: false
        }
    }

    /// Tab's step through the Grow modes, Remove Fillets' convexities, Extend Sheet's shapes or
    /// Align Surface's continuities.
    mutating func stepGrow() {
        if case .rebuildFace = kind {
            let all = RebuildMethodChoice.allCases
            rebuildMethod = all[((all.firstIndex(of: rebuildMethod) ?? 0) + 1) % all.count]
            return
        }
        if case .alignSurface = kind {
            let all = SurfaceContinuityLevel.allCases
            continuity = all[((all.firstIndex(of: continuity) ?? 0) + 1) % all.count]
            return
        }
        if case .extendSheet = kind {
            let all = SheetExtensionShape.allCases
            extensionShape = all[((all.firstIndex(of: extensionShape) ?? 0) + 1) % all.count]
            return
        }
        if case .removeFillets = kind {
            let all = FilletConvexity.allCases
            convexity = all[((all.firstIndex(of: convexity) ?? 0) + 1) % all.count]
            return
        }
        guard hasGrow else { return }
        let all = FaceEditGrow.allCases
        grow = all[((all.firstIndex(of: grow) ?? 0) + 1) % all.count]
    }

    /// The command OK submits.
    func command() -> EditorCommand {
        switch kind {
        case let .push(faces):
            return .pushFaces(
                targets: faces, distance: .length(distanceMeters, .meter),
                adjacentAngle: adjacentAngleDegrees == 0 ? nil : .angle(adjacentAngleDegrees, .degree), grow: grow
            )
        case let .draft(faces, neutral):
            return .draftBodyFaces(
                targets: faces, neutralTarget: neutral, angle: .angle(draftAngleDegrees, .degree),
                neutralOffset: neutralOffsetMeters == 0 ? nil : .length(neutralOffsetMeters, .meter), grow: grow
            )
        case let .match(faces, reference):
            return .matchFaces(targets: faces, reference: reference, front: front, grow: grow)
        case let .extendSheet(edges, limit):
            return .extendSheet(targets: edges, distance: .length(distanceMeters, .meter), shape: extensionShape, modifies: modifies,
                                limit: limit, limitMode: limitMode)
        case let .rebuildFace(faces):
            return .rebuildFaces(
                targets: faces,
                method: rebuildMethod == .nominal ? .nominal
                    : (rebuildMethod == .tolerance ? .tolerance(.length(rebuildToleranceMeters, .meter)) : .explicit(layout)),
                extendU: rebuildMethod == .nominal ? 0 : extendU, extendV: rebuildMethod == .nominal ? 0 : extendV,
                shrinks: rebuildMethod == .nominal || shrinks
            )
        case let .alignSurface(edge, reference):
            return .alignSurface(
                targets: [edge, reference], continuity: continuity, tension: tension, blendRows: blendRows,
                inputShapeInfluence: inputShapeInfluence, partialStart: partialStart, partialEnd: partialEnd,
                layout: refitsLayout ? layout : nil, boundaryFlow: boundaryFlow
            )
        case let .hollow(targets):
            return .hollow(targets: targets, thickness: .length(wallThicknessMeters, .meter))
        case let .thicken(targets):
            return .thicken(
                targets: targets, front: .length(frontMeters, .meter),
                back: .length(locksThicknesses ? frontMeters : backMeters, .meter)
            )
        case let .removeFillets(object):
            return .removeFillets(
                target: object, maximumRadius: maximumRadiusMeters > 0 ? .length(maximumRadiusMeters, .meter) : nil, convexity: convexity
            )
        }
    }
}
