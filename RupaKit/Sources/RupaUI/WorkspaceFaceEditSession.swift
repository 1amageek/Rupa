import RupaCore
import RupaRendering
import SwiftCAD

/// The dialog of a local face operation while it runs, on the faces selected when it started:
/// Push Face (the faces pushed a Distance along their outward side, with an Angle Adjacent tilting
/// the planar faces beside them), Draft Face (the faces turned by Degrees about their crossing
/// with the reference face's plane, moved by an Offset: the first face selected or clicked is the
/// reference, the faces clicked after it are drafted, Control-click taking one back off), and
/// Match Face (the selected faces put onto the reference face clicked in the dialog, facing its
/// Front when chosen), and Remove Fillets From Shell (the
/// selected solid's fillets within a Max Radius and a Convexity), and Align Surface (the first
/// edge, of a sheet, following the last with a Continuity, a Tension and Blend rows). Tab steps
/// the Grow mode, Remove Fillets' Convexity, Extend Sheet's Shape, Align Surface's Continuity or
/// Rebuild Face's method (the faces refitted to a Degree and Spans layout or within a Tolerance,
/// extended past them and shrunk to them); OK, Return or right-click applies; Escape ends it without a change.
struct WorkspaceFaceEditSession: Equatable {
    /// An edge of a sheet and the reference edge it is aligned to.
    struct AlignPair: Equatable {
        var edge: SelectionTarget
        var reference: SelectionTarget
    }

    /// This dialog, apart from the one the command starts next (`WorkspaceDialogSubmissions`).
    let instance = WorkspaceDialogInstance()

    enum Kind: Equatable {
        /// Push Face: the faces pushed by the Distance, or, once a face is clicked in the dialog
        /// (Plasticity's dependant offset), put onto that face.
        case push(faces: [SelectionTarget], onto: SelectionTarget? = nil)
        /// Draft Face: the faces to draft and the reference face whose plane they turn about,
        /// each picked while the dialog runs.
        case draft(faces: [SelectionTarget], neutral: SelectionTarget?)
        /// Match Face: the faces to put onto the reference, which is clicked in the dialog.
        case match(faces: [SelectionTarget], reference: SelectionTarget?)
        case removeFillets(object: SceneNodeID)
        case hollow(targets: [SelectionTarget])
        case thicken(targets: [SelectionTarget])
        case extendSheet(edges: [SelectionTarget], limit: SelectionTarget? = nil)
        /// Align Surface: each pair's sheet edge made to follow its reference edge.
        case alignSurface(pairs: [AlignPair])
        case rebuildFace(faces: [SelectionTarget])
        /// PolySplines on a mesh object: its mesh (in world space) becomes spline patches, the
        /// mesh object replaced by them.
        case polySplines(object: SceneNodeID, mesh: Mesh)
    }

    private(set) var kind: Kind
    /// Push Face's and Extend Sheet's distance, in meters; Push Face opens at 0 as Plasticity's
    /// does, set by the face's arrow or the field.
    var distanceMeters = 0.0
    /// Push Face's adjacent angle in degrees; zero leaves the faces beside unturned.
    var adjacentAngleDegrees = 0.0
    /// Draft Face's angle in degrees, opening at 0 as Plasticity's does; OK needs one set.
    var draftAngleDegrees = 0.0
    /// Draft Face's neutral plane offset along the neutral face's outward side, in meters.
    var neutralOffsetMeters = 0.0
    var front = false
    var grow: FaceEditGrow = .moving
    /// Remove Fillets' largest radius, in meters, which applies only while `limitsRadius` is on
    /// (Plasticity's Max radius checkbox, off by default: fillets of any radius).
    var maximumRadiusMeters = 0.0
    var limitsRadius = false
    var convexity: FilletConvexity = .any
    /// Hollow's wall thickness, in meters.
    var wallThicknessMeters = 0.001
    /// Thicken's thicknesses along the sheet's normal and against it, in meters; locked, the back
    /// follows the front.
    var frontMeters = 0.001
    var backMeters = 0.0
    var locksThicknesses = false
    /// Extend Sheet's shape, which Tab steps through `extensionShapes`, and whether the
    /// extensions join the sheet (not offered while Natural extends the surface itself).
    var extensionShape: SheetExtensionShape = .natural
    /// Whether Extend Sheet extends a planar sheet, which Plasticity offers Linear, Soft and
    /// Reflective, opening on Linear; a curved sheet adds Natural and opens on it.
    private(set) var extendsPlanarSheet = false
    /// How an extension runs on to the limit's object, when one is selected.
    var limitMode: SheetExtensionLimit.Mode = .minimal
    var modifies = true
    /// Align Surface's continuity, which Tab steps, the tension across the edge and the further
    /// control rows the change fades over.
    /// Plasticity's defaults: G0, Tension 0.5 as the dialog shows it (`DialogTensionScale`),
    /// influence 0, Boundary Adjacent.
    var continuity: SurfaceContinuityLevel = .positional
    var tension = DialogTensionScale.neutral
    var blendRows = 0
    /// Align Surface's input shape influence on the blended rows, its partial start and end along
    /// the edge, and, when `refitsLayout`, the degrees and spans the sheet is refitted to first.
    var inputShapeInfluence = 0.0
    var partialStart = 0.0
    var partialEnd = 1.0
    /// Align Surface's Boundary: the cross-edge flow along a G1 or G2 edge.
    var boundaryFlow = SquareFitOptions.BoundaryFlow.adjacent
    /// Each aligned pair's own continuity and tension, by its index, overriding `continuity` and
    /// `tension` (Plasticity shows one Tension per G1 or G2 edge).
    var pairContinuity: [Int: SurfaceContinuityLevel] = [:]
    var pairTension: [Int: Double] = [:]
    /// Align Surface's Analysis while the dialog is open: the continuity checked along the aligned
    /// edges and each one's scale (Plasticity's G0, G1 and G2 Scale, opening at 10, 10 and 0.1).
    /// They change what is drawn, never the commands.
    var analysisMeasure = ViewportEdgeAlignmentAnalysis.Measure.position
    var analysisScales: [ViewportEdgeAlignmentAnalysis.Measure: Double] = [.position: 10, .tangent: 10, .curvature: 0.1]
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
    /// PolySplines' options, opening as Plasticity's dialog does: Rounded corners off, Merge
    /// patches on, Interpolate boundary exactly off.
    var polySplineRoundedCorners = false
    var polySplineMergesPatches = true
    var polySplineInterpolatesBoundary = false
    var extendU = 0.0
    var extendV = 0.0
    var shrinks = false

    /// Bumped by D: the dialog focuses the command's main value field; by A, Push Face's Angle.
    private(set) var primaryFocusRequests = 0
    private(set) var angleFocusRequests = 0

    init(kind: Kind) {
        self.kind = kind
    }

    /// D: focus the main value (Plasticity's D for distance, thickness or angle).
    mutating func focusPrimaryValue() {
        primaryFocusRequests += 1
    }

    /// A: Push Face's Angle Adjacent; false when the command has no angle.
    mutating func focusAngle() -> Bool {
        guard case .push(_, nil) = kind else { return false }
        angleFocusRequests += 1
        return true
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
        case .polySplines: "PolySplines"
        }
    }

    /// Extend Sheet on a planar sheet: its shapes without Natural, opening on Linear.
    init(extendingPlanarSheetEdges edges: [SelectionTarget], limit: SelectionTarget?) {
        self.init(kind: .extendSheet(edges: edges, limit: limit))
        extendsPlanarSheet = true
        extensionShape = .linear
    }

    /// The shapes Extend Sheet offers for its sheet.
    var extensionShapes: [SheetExtensionShape] {
        extendsPlanarSheet ? SheetExtensionShape.allCases.filter { $0 != .natural } : SheetExtensionShape.allCases
    }

    /// Whether the dialog offers Modify: not while Natural extends the surface itself.
    var offersModify: Bool { extensionShape != .natural }

    /// Whether clicks on faces go to the dialog: Push Face's face to push onto, Draft Face's
    /// reference and faces, Match Face's reference, Extend Sheet's object to extend up to.
    var takesFacePicks: Bool {
        switch kind {
        case .push, .draft, .match, .extendSheet: true
        case .removeFillets, .hollow, .thicken, .alignSurface, .rebuildFace, .polySplines: false
        }
    }

    /// A clicked face: Push Face pushes its faces onto it instead of by the Distance (a pushed
    /// face itself is ignored); Draft Face takes it as the reference while it has none, then adds it to
    /// the drafted faces, Control-click (`toggles`) taking a drafted face back off; Match Face
    /// takes it as the reference, Control-click adding or taking off a face to match instead.
    mutating func pick(face: SelectionTarget, toggles: Bool) {
        switch kind {
        case let .draft(faces, neutral):
            guard let neutral else {
                kind = .draft(faces: faces.filter { $0 != face }, neutral: face)
                return
            }
            guard face != neutral else { return }
            if let index = faces.firstIndex(of: face) {
                if toggles { kind = .draft(faces: faces.filter { $0 != faces[index] }, neutral: neutral) }
            } else {
                kind = .draft(faces: faces + [face], neutral: neutral)
            }
        case let .match(faces, reference):
            if toggles {
                guard face != reference else { return }
                kind = .match(faces: faces.contains(face) ? faces.filter { $0 != face } : faces + [face], reference: reference)
            } else {
                kind = .match(faces: faces.filter { $0 != face }, reference: face)
            }
        case let .push(faces, _):
            guard faces.contains(face) == false else { return }
            kind = .push(faces: faces, onto: face)
            distanceMeters = 0
        case let .extendSheet(edges, _):
            // A face of another object makes that object the limit; Control-click drops it.
            guard edges.contains(where: { $0.sceneNodeID == face.sceneNodeID }) == false else { return }
            kind = .extendSheet(edges: edges, limit: toggles ? nil : SelectionTarget(sceneNodeID: face.sceneNodeID))
        case .removeFillets, .hollow, .thicken, .alignSurface, .rebuildFace, .polySplines:
            return
        }
    }

    /// Push Face's distance from the face's arrow, which pushes by the distance again rather than
    /// onto a clicked face.
    mutating func setPushDistance(_ meters: Double) {
        guard case let .push(faces, _) = kind else { return }
        kind = .push(faces: faces)
        distanceMeters = meters
    }

    /// A selected face's arrow dragged while the dialog runs, as Plasticity's yellow dot on the
    /// face's normal: Push Face's Distance, Hollow's Thickness (outward positive, so a drag into
    /// the body walls it inward) and Thicken's Front. False for a command whose dialog has no
    /// value the arrow sets.
    mutating func setArrowDistance(_ meters: Double) -> Bool {
        switch kind {
        case .push:
            setPushDistance(meters)
        case .hollow:
            wallThicknessMeters = meters
        case .thicken:
            frontMeters = meters
        case .draft, .match, .removeFillets, .extendSheet, .alignSurface, .rebuildFace, .polySplines:
            return false
        }
        return true
    }

    /// What OK still needs, as the status bar says it; nil once the command can run.
    var missingInput: String? {
        switch kind {
        case let .draft(faces, neutral):
            if neutral == nil { return "Draft Face: click the reference face." }
            if faces.isEmpty { return "Draft Face: click the faces to draft; Control-click takes one off." }
            if draftAngleDegrees == 0 { return "Draft Face: set Degrees." }
            return nil
        case let .match(faces, reference):
            if reference == nil { return "Match Face: click the face to match onto." }
            if faces.isEmpty { return "Match Face: Control-click the faces to match." }
            return nil
        case let .push(_, onto):
            return onto == nil && distanceMeters == 0
                ? "Push Face: drag the face's arrow or set the Distance; click a face to push onto it." : nil
        case let .extendSheet(_, limit):
            return limit == nil && distanceMeters == 0 ? "Extend Sheet: set the Distance." : nil
        case .removeFillets, .hollow, .thicken, .alignSurface, .rebuildFace, .polySplines:
            return nil
        }
    }

    /// Whether the operation has a Grow mode: Push Face, Draft Face and Match Face do.
    var hasGrow: Bool {
        switch kind {
        case .push, .draft, .match: true
        case .removeFillets, .hollow, .thicken, .extendSheet, .alignSurface, .rebuildFace, .polySplines: false
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
            pairContinuity = [:]
            return
        }
        if case .extendSheet = kind {
            let all = extensionShapes
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
    /// The commands the dialog applies together: one per aligned pair, otherwise its one command.
    /// None while `missingInput` says something is still to pick or set.
    func commands() -> [EditorCommand] {
        if case let .alignSurface(pairs) = kind {
            return pairs.indices.map { alignCommand(pairs[$0], index: $0) }
        }
        if case let .polySplines(object, mesh) = kind {
            return [
                .createPolySplineSurface(name: "PolySpline", sourceMesh: mesh, options: PolySplineOptions(
                    roundedCorners: polySplineRoundedCorners, mergePatches: polySplineMergesPatches,
                    interpolateBoundaryExactly: polySplineInterpolatesBoundary)),
                .deleteSceneNodes(ids: [object]),
            ]
        }
        guard missingInput == nil, let command = command() else { return [] }
        return [command]
    }

    private func alignCommand(_ pair: AlignPair, index: Int) -> EditorCommand {
        .alignSurface(
            targets: [pair.edge, pair.reference], continuity: pairContinuity[index] ?? continuity, tension: DialogTensionScale.kernelScale(pairTension[index] ?? tension), blendRows: blendRows,
            inputShapeInfluence: inputShapeInfluence, partialStart: partialStart, partialEnd: partialEnd,
            layout: refitsLayout ? layout : nil, boundaryFlow: boundaryFlow
        )
    }

    private func command() -> EditorCommand? {
        switch kind {
        case let .push(faces, onto):
            if let onto {
                return .matchFaces(targets: faces, reference: onto, front: false, grow: grow)
            }
            return .pushFaces(
                targets: faces, distance: .length(distanceMeters, .meter),
                adjacentAngle: adjacentAngleDegrees == 0 ? nil : .angle(adjacentAngleDegrees, .degree), grow: grow
            )
        case let .draft(faces, neutral):
            guard let neutral else { return nil }
            return .draftBodyFaces(
                targets: faces, neutralTarget: neutral, angle: .angle(draftAngleDegrees, .degree),
                neutralOffset: neutralOffsetMeters == 0 ? nil : .length(neutralOffsetMeters, .meter), grow: grow
            )
        case let .match(faces, reference):
            guard let reference else { return nil }
            return .matchFaces(targets: faces, reference: reference, front: front, grow: grow)
        case let .extendSheet(edges, limit):
            return .extendSheet(targets: edges, distance: .length(distanceMeters, .meter), shape: extensionShape, modifies: !offersModify || modifies,
                                limit: limit, limitMode: limitMode)
        case let .rebuildFace(faces):
            return .rebuildFaces(
                targets: faces,
                method: rebuildMethod == .nominal ? .nominal
                    : (rebuildMethod == .tolerance ? .tolerance(.length(rebuildToleranceMeters, .meter)) : .explicit(layout)),
                extendU: rebuildMethod == .nominal ? 0 : extendU, extendV: rebuildMethod == .nominal ? 0 : extendV,
                shrinks: rebuildMethod == .nominal || shrinks
            )
        case let .alignSurface(pairs):
            // The first pair's; `commands()` gives every pair's.
            return alignCommand(pairs[0], index: 0)
        case .polySplines:
            // `commands()` gives the conversion and the mesh's removal together.
            return nil
        case let .hollow(targets):
            return .hollow(targets: targets, thickness: .length(wallThicknessMeters, .meter))
        case let .thicken(targets):
            return .thicken(
                targets: targets, front: .length(frontMeters, .meter),
                back: .length(locksThicknesses ? frontMeters : backMeters, .meter)
            )
        case let .removeFillets(object):
            return .removeFillets(
                target: object, maximumRadius: limitsRadius ? .length(maximumRadiusMeters, .meter) : nil, convexity: convexity
            )
        }
    }
}
