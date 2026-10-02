import Foundation
import RupaCore
import SwiftCAD

/// Editable text and explicit operands, never a mutable source document.
struct ModelingOperationDraft: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
        case box = "Box"
        case cylinder = "Cylinder"
        case sphere = "Sphere"
        case extrude = "Extrude"
        case revolve = "Revolve"
        case sweep = "Sweep"
        case pipe = "Pipe"
        case loft = "Loft"
        case fillet = "Fillet"
        case chamfer = "Chamfer"
        case g2Blend = "G2 Blend"
        case constrainedSurface = "Constrained Surface"
        case surfacePatch = "Plane Surface"
        case patch = "Patch"
        case bridge = "Boundary Bridge (G0)"
        case square = "Square"
        case xnurbs = "XNURBS"
        case bridgeSurface = "Bridge Surface"
        case surfaceOffset = "Sheet Offset"
        case surfaceExtend = "Extend Trim"
        case shell = "Shell"
        case thicken = "Thicken"

        var id: String { rawValue }

        /// Operations not already represented by a canvas placement tool: the primitives and Sweep
        /// have their own tools, and the surface-only creations open from the Surface tool.
        static var paletteOperations: [Self] {
            allCases.filter { ![.box, .sphere, .cylinder, .sweep, .surfacePatch, .patch, .bridge, .constrainedSurface, .square, .xnurbs, .bridgeSurface].contains($0) }
        }

        /// The dialogs that preview as they are edited and that a right-click confirms, as
        /// Plasticity's Square and Constrained Surface do.
        var previewsLive: Bool { self == .square || self == .constrainedSurface }

        static let surfaceCreationOperations: [Self] = [.surfacePatch, .constrainedSurface, .extrude, .revolve, .sweep, .loft, .patch, .bridge, .square, .xnurbs, .bridgeSurface]

        var systemImage: String {
            switch self {
            case .box: "cube"
            case .sphere: "globe"
            case .cylinder: "cylinder"
            case .extrude: "arrow.up.to.line"
            case .revolve: "arrow.trianglehead.2.clockwise.rotate.90"
            case .sweep: "arrow.triangle.2.circlepath"
            case .pipe: "circle.circle"
            case .loft: "square.stack.3d.up"
            case .fillet: "square.on.circle"
            case .chamfer: "cube.transparent"
            case .g2Blend: "point.topleft.down.to.point.bottomright.curvepath"
            case .constrainedSurface: "point.3.connected.trianglepath.dotted"
            case .surfacePatch: "square.dashed"
            case .patch: "square.dashed.inset.filled"
            case .bridge: "rectangle.split.2x1"
            case .square: "square.split.bottomrightquarter"
            case .xnurbs: "pentagon"
            case .bridgeSurface: "point.topleft.down.to.point.bottomright.filled.curvepath"
            case .surfaceOffset: "square.3.layers.3d"
            case .surfaceExtend: "arrow.up.left.and.arrow.down.right"
            case .shell: "shippingbox"
            case .thicken: "square.stack.3d.up.fill"
            }
        }
    }

    var constrainedPoints: [ConstrainedSurfaceFeature.PointConstraint] = []
    var constrainedFeatureID: FeatureID?
    var constrainedSceneNodeID: SceneNodeID?
    /// Constrained Surface's tolerances and optimization, Plasticity's defaults (0.00100 cm, 5°,
    /// Performance).
    var pointTolerance = "0.01 mm"
    var angularTolerance = "5"
    var pointOptimization = ConstrainedSurfaceFeature.Optimization.performance

    mutating func appendCoordinatePoint() throws {
        constrainedPoints.append(.init(position: Point3D(
            x: try length(origin[0], label: "Point X"),
            y: try length(origin[1], label: "Point Y"),
            z: try length(origin[2], label: "Point Z"))))
    }

    mutating func appendWorldPoint(_ point: Point3D, in document: DesignDocument) throws {
        var local = point
        if constrainedFeatureID != nil {
            guard let id = constrainedSceneNodeID else {
                throw invalid("Select the surface occurrence before adding viewport points to its source.")
            }
            local = try SceneNodeHierarchy(metadata: document.productMetadata)
                .worldTransform(of: id).inverse().applied(to: point)
        }
        try local.validate()
        constrainedPoints.append(.init(position: local))
    }

    mutating func undoConstrainedPoint() {
        if !constrainedPoints.isEmpty { constrainedPoints.removeLast() }
    }

    var kind: Kind
    var name: String
    var targets: [SelectionTarget]
    var unit: LengthDisplayUnit
    var startDistance: String = "0"
    var distance: String
    var width: String
    var height: String
    var origin = ["0", "0", "0"]
    var axis = ["0", "1", "0"]
    /// A revolve's axis: through its origin along a direction, or from its origin to an end point.
    enum RevolveAxisChoice: String, CaseIterable, Identifiable {
        case direction = "Direction"
        case twoPoints = "Two Points"
        /// The section's own axes (`RevolveSectionAxis`).
        case normal = "Normal"
        case binormal = "Binormal"
        case tangent = "Tangent"
        var id: Self { self }
    }
    var revolveAxisChoice = RevolveAxisChoice.direction
    /// The second point of a two-point revolve axis.
    var axisEnd = ["0", "0.01", "0"]
    var angle = "360"
    enum ExtrusionDirectionChoice: String, CaseIterable, Identifiable {
        case normal = "Source normal"
        case symmetric = "Symmetric normal"
        case vector = "Vector"
        var id: Self { self }
    }
    var extrusionDirection = ExtrusionDirectionChoice.normal
    /// How an extrusion combines with the bodies selected after its section: a new body, or a
    /// Boolean with them, keeping the extruded tool when `keepsTools`. Automatic joins an
    /// extruded face to its own body (Union outward, Difference inward) and leaves any other
    /// extrusion a new body.
    enum SolidBooleanChoice: String, CaseIterable, Identifiable {
        case automatic = "Automatic"
        case newBody = "New Body"
        case union = "Union"
        case difference = "Difference"
        case intersect = "Intersect"
        case slice = "Slice"
        var id: Self { self }
        /// Whether the result is combined with bodies by an explicit Boolean.
        var combines: Bool { operation != .newBody }
        var operation: SolidOperation {
            switch self {
            case .automatic, .newBody: .newBody
            case .union: .union
            case .difference: .difference
            case .intersect: .intersect
            case .slice: .slice
            }
        }
    }
    /// How an extrusion or a revolve combines with the bodies selected after its section.
    var solidBoolean = SolidBooleanChoice.automatic
    /// The extrusion's draft in degrees: positive narrows the section along the extrusion.
    var draftDegrees = "0"
    /// A thin extrusion's wall thickness, empty for a whole section.
    var wallThickness = ""
    /// Faces extrude each along its own normal (Individual) or all along the first's (Direct).
    var extrudesIndividually = false

    /// Whether the operands are faces of a body, which Extrude takes instead of a section.
    var extrudesFaces: Bool {
        kind == .extrude && targets.isEmpty == false && targets.allSatisfy { target in
            if case .face = target.component { return true }
            return false
        }
    }
    var keepsTools = false
    var sheet = false
    var isSurfaceCreation = false
    /// Loft's smooth connectors: on, as Plasticity lofts several sections into one smooth surface.
    var smooth = true
    /// Simplify: flat faces of a sweep or loft are trimmed planes. Plasticity leaves it off for
    /// Sweep and on for Loft.
    var sweepSimplify = false
    var loftSimplify = true
    var loftDefaultTension = "1"
    /// How a Loft meets the face beside an edge selected as its first or last section.
    enum LoftContinuityChoice: String, CaseIterable, Identifiable {
        case g0 = "G0"
        case g1 = "G1"
        case g2 = "G2"
        var id: Self { self }
        var order: SurfaceEdgeContinuity.Order? {
            switch self {
            case .g0: nil
            case .g1: .tangent
            case .g2: .curvature
            }
        }
    }
    /// How each end of a Loft meets the face beside the edge selected there: G1 by default, as
    /// Plasticity labels both edges; ends that are not edges of a body take none.
    var loftStartContinuity = LoftContinuityChoice.g1
    var loftEndContinuity = LoftContinuityChoice.g1
    /// The cross-boundary scale of each G1 or G2 end, times the distance between the end sections.
    var loftStartTension = "1"
    var loftEndTension = "1"
    /// How a Square meets the faces beside the edges among its sides, and their tension.
    /// How a Square side meets what is beside it: Free (followed loosely), G0, or G1/G2 with the
    /// face beside an edge (a curve's side takes G0 for those).
    enum SquareContinuityChoice: String, CaseIterable, Identifiable {
        case free = "Free"
        case g0 = "G0"
        case g1 = "G1"
        case g2 = "G2"
        var id: Self { self }
        var order: SurfaceEdgeContinuity.Order? {
            switch self {
            case .free, .g0: nil
            case .g1: .tangent
            case .g2: .curvature
            }
        }
    }
    /// Every side's continuity unless the side has its own in `squareSideContinuity`.
    var squareContinuity = SquareContinuityChoice.g0
    var squareSideContinuity: [SelectionTarget: SquareContinuityChoice] = [:]
    /// Square's Tension as the dialog shows it (0.5 neutral, `DialogTensionScale`).
    var squareTension = "0.5"
    var squareUDegree = "3"
    var squareVDegree = "3"
    var squareUSpans = "3"
    var squareVSpans = "3"
    var squareFlatness = "1"
    var squareWeight = "1"
    var squareBoundaryFlow = SquareFitOptions.BoundaryFlow.adjacent

    /// Whether `target` is a face (a Square over faces refits them).
    func isFace(_ target: SelectionTarget) -> Bool {
        if case .face = target.component { return true }
        return false
    }

    /// The continuity a Square side takes: its own, else the Square's.
    func squareContinuity(of target: SelectionTarget) -> SquareContinuityChoice {
        squareSideContinuity[target] ?? squareContinuity
    }

    /// The Square's fit options from the form.
    func squareFitOptions() throws -> SquareFitOptions {
        func count(_ text: String, _ label: String) throws -> Int {
            guard let value = Int(text.trimmingCharacters(in: .whitespaces)) else {
                throw EditorError(code: .commandInvalid, message: "\(label) must be a whole number.")
            }
            return value
        }
        let options = SquareFitOptions(
            uDegree: try count(squareUDegree, "Degree U"), vDegree: try count(squareVDegree, "Degree V"),
            uSpans: try count(squareUSpans, "Spans U"), vSpans: try count(squareVSpans, "Spans V"),
            flatness: try number(squareFlatness, label: "Flatness"), weight: try number(squareWeight, label: "Weight"),
            boundaryFlow: squareBoundaryFlow
        )
        do { try options.validate() } catch {
            throw EditorError(code: .commandInvalid, message: "The Square's options are invalid: \(error).")
        }
        return options
    }
    /// The angle (degrees) a G1 surface may stray from a curved face's normals beside an edge; a
    /// planar face is met exactly.
    var continuityAllowance = "0.1"
    /// Bridge Surface's Shape, Tension, Trim walls and Sense; its width is the distance field.
    enum BridgeShapeChoice: String, CaseIterable, Identifiable {
        case g2 = "G2"
        case chamfer = "Chamfer"
        var id: Self { self }
    }
    var bridgeShape = BridgeShapeChoice.g2
    var bridgeTension = "1"
    var bridgeReversesSense = false
    /// Bridge Surface's Trim walls: none, both, or the sheet reaching less (Short) or more (Long)
    /// far from where the sheets meet.
    enum BridgeTrimChoice: String, CaseIterable, Identifiable {
        case none = "None"
        case both = "Both"
        case short = "Short"
        case long = "Long"
        var id: Self { self }
    }
    var bridgeTrim = BridgeTrimChoice.none

    /// `continuityAllowance` in radians.
    private func continuityAllowanceRadians() throws -> Double {
        let degrees = try number(continuityAllowance, label: "Angle allowance")
        guard degrees.isFinite, degrees > 0, degrees < 90 else { throw invalid("Angle allowance is between 0 and 90 degrees.") }
        return degrees * Double.pi / 180
    }
    /// The radius-of-curvature mismatch (as curvature, 1/length) a G2 surface may keep beside a
    /// curved face; entered as a length whose reciprocal is the allowance.
    var curvatureAllowanceRadius = "1 m"

    /// The curvature allowance for `order`: none for tangent continuity.
    private func curvatureAllowance(for order: SurfaceEdgeContinuity.Order) throws -> Double? {
        guard order == .curvature else { return nil }
        let radius = try length(curvatureAllowanceRadius, label: "Curvature allowance radius")
        guard radius > 0 else { throw invalid("Curvature allowance radius must be positive.") }
        return 1 / radius
    }
    var closesSectionLoop = false
    var uBounds = ["0", "1"]
    var vBounds = ["0", "1"]
    var twistAngle = "0"
    var doubleHelical = false
    /// How a sweep's section follows its path: turning with it (Normal) or keeping its
    /// orientation (Parallel).
    enum SweepAlignmentChoice: String, CaseIterable, Identifiable {
        case normal = "Normal"
        case parallel = "Parallel"
        var id: Self { self }
        var alignment: SweepAlignment {
            switch self {
            case .normal: .normal
            case .parallel: .parallel
            }
        }
    }
    var sweepAlignment = SweepAlignmentChoice.normal
    /// How a Normal sweep turns a corner of its path: a pointed mitre or a round outside.
    enum SweepCornerChoice: String, CaseIterable, Identifiable {
        case mitre = "Mitre"
        case round = "Round"
        var id: Self { self }
        var style: SweepCornerStyle {
            switch self {
            case .mitre: .mitre
            case .round: .round
            }
        }
    }
    var sweepCorners = SweepCornerChoice.mitre
    /// How a sweep's guide steers the section: Point turns and scales it so its contact stays on
    /// the guide, Chord only turns it toward the guide, Curve turns it, unscaled, so it keeps
    /// touching the guide wherever on the section that is.
    enum SweepGuideChoice: String, CaseIterable, Identifiable {
        case point = "Point"
        case chord = "Chord"
        case curve = "Curve"
        var id: Self { self }
        var method: SweepGuideMethod {
            switch self {
            case .point: .point
            case .chord: .chord
            case .curve: .curve
            }
        }
    }
    var sweepGuide = SweepGuideChoice.point
    /// Fillet Shell's Shape: Round, a conic, chordal or curvature (G2) cross-section with Tension,
    /// or Full across the face between two edges.
    enum FilletShapeChoice: String, CaseIterable, Identifiable {
        case round = "Round"
        case conic = "Conic"
        case chordal = "Chordal"
        case curvature = "G2"
        case full = "Full"
        var id: Self { self }
        var shape: FilletShape {
            switch self {
            case .round: .round
            case .conic: .conic
            case .chordal: .chordal
            case .curvature: .curvature
            case .full: .full
            }
        }
        var takesTension: Bool { self == .conic || self == .chordal || self == .curvature }
        /// The shapes Plasticity's dialog offers: no Round, Conic at 0.5 being one.
        static let offered: [FilletShapeChoice] = [.conic, .chordal, .curvature, .full]
    }
    /// Fillet's click on an edge while the dialog runs: added to its edges, or taken back off when
    /// it is one, as Plasticity's Shift-click edits the selection inside the command.
    mutating func toggleFilletEdge(_ edge: SelectionTarget) {
        if let index = targets.firstIndex(of: edge) {
            targets.remove(at: index)
        } else {
            targets.append(edge)
        }
    }

    /// Fillet's click on a round: its radius becomes the Distance, as Plasticity copies a fillet's
    /// radius from a clicked round.
    mutating func copyFilletRadius(meters: Double) {
        let presented = workspaceLengthFieldPresentation(fromMeters: meters, preferredUnit: unit)
        distance = presented.text + " " + presented.unit.symbol
    }

    /// Plasticity's default: Conic at tension 0.5, which is the round of the distance's radius.
    var filletShape = FilletShapeChoice.conic
    /// The shapes the dialog offers for its edges: Full only once two edges, the pair on either
    /// side of a face, are its targets, as Plasticity's Shape row shows it.
    var offeredFilletShapes: [FilletShapeChoice] {
        let edges = WorkspaceSelectionTargetClassification(targets: targets).edgeTargets
        let pairs = edges.count == 2 && targets.count == 2
        return FilletShapeChoice.offered.filter { $0 != .full || pairs || filletShape == .full }
    }
    var filletTension = "0.5"
    /// The shape the kernel builds: a Conic at tension 0.5 (or blank) is the round itself, which
    /// takes the round's full route (curved edges, chains, corners).
    var effectiveFilletShape: FilletShapeChoice {
        guard filletShape == .conic else { return filletShape }
        let text = filletTension.trimmingCharacters(in: .whitespaces)
        return text.isEmpty || Double(text) == 0.5 ? .round : .conic
    }
    /// A chamfer's mode, its angle from the reference face (blank for a symmetric chamfer) and
    /// whether the reference is each edge's second face.
    enum ChamferModeChoice: String, CaseIterable, Identifiable {
        case offset = "Offset"
        case apex = "Apex"
        var id: Self { self }
        var mode: ChamferMode { self == .offset ? .offset : .apex }
    }
    var chamferMode = ChamferModeChoice.offset
    var chamferAngle = ""
    var chamferFlipped = false
    /// A variable fillet's radius at the edge's end; blank for a constant one.
    var filletEndRadius = ""
    /// A fillet's variable points, "fraction@radius" separated by commas; blank for none.
    var filletVariablePoints = ""
    /// A fillet's limit points as fractions of the edge from its start; both blank for the whole edge.
    var limitStart = ""
    var limitEnd = ""
    /// Whether the blend runs over the rest of the edge instead of between its limits.
    var limitsReversed = false
    /// Fillet Shell's Tangent Edges: whether a selected edge takes the edges continuing it tangentially.
    var tangentEdges = true
    /// A pipe's section: its diameter, a vertex count (0 for a circle) and the angle it is turned by.
    var pipeDiameter = "10 mm"
    var pipeVertices = "0"
    /// Whether the first selected region or face is the pipe's section in place of the circle.
    var pipeCustomProfile = false
    var pipeAngle = "0"
    var pipeEndScale = "1"
    /// The fractions of each path's length a pipe runs between.
    var pipeStart = "0"
    var pipeEnd = "1"
    /// A pipe's twist about its path from start to end, in degrees.
    var pipeTwist = "0"
    /// The positional allowance a pipe along a curved path is built within.
    var pipeAllowance = "0.001 mm"
    var approximationTolerance = ""
    /// A sweep's end-section scale and the fraction of its path it runs along.
    var sweepEndScale = "1"
    var sweepDistance = "1"
    /// Thicken's back thickness; the distance field is its front.
    var thickenBack = "0"
    var reverseSecondBoundary = false
    var loftSectionControls: [SceneNodeID: LoftSectionDraft] = [:]
    var loftGuideNodeIDs: Set<SceneNodeID> = []
    /// Edges of bodies marked as Loft guides, each a guide along its curve (Plasticity guides any
    /// combination of curves and edges).
    var loftGuideEdges: Set<SelectionTarget> = []
    /// Whether the operand `target` is a Loft guide: a guide curve source or a guide edge.
    func isLoftGuide(_ target: SelectionTarget) -> Bool {
        if case .edge = target.component { return loftGuideEdges.contains(target) }
        return loftGuideNodeIDs.contains(target.sceneNodeID)
    }
    /// Loft's click while its dialog runs, Plasticity's "Select guides" slot: the clicked curve or
    /// body edge becomes a guide, added to the operands when new; clicked again it is dropped.
    mutating func toggleLoftGuide(_ target: SelectionTarget) {
        if isLoftGuide(target) {
            targets.removeAll { $0 == target }
            if case .edge = target.component { loftGuideEdges.remove(target) } else { loftGuideNodeIDs.remove(target.sceneNodeID) }
            return
        }
        if targets.contains(target) == false { targets.append(target) }
        if case .edge = target.component { loftGuideEdges.insert(target) } else { loftGuideNodeIDs.insert(target.sceneNodeID) }
    }
    /// XNURBS: the operands that are guides (the rest frame it), the continuity edges take, and its
    /// options.
    var xnurbsGuideNodeIDs: Set<SceneNodeID> = []
    /// Every boundary edge's continuity unless the edge has its own in `xnurbsEdgeContinuity`
    /// (Plasticity's badge per edge).
    var xnurbsContinuity = LoftContinuityChoice.g0
    var xnurbsEdgeContinuity: [SelectionTarget: LoftContinuityChoice] = [:]
    func xnurbsContinuity(of target: SelectionTarget) -> LoftContinuityChoice {
        xnurbsEdgeContinuity[target] ?? xnurbsContinuity
    }
    var xnurbsQuadSided = false
    var xnurbsFlatness = "0.95"
    /// XNURBS's Tension as the dialog shows it (0.5 neutral, `DialogTensionScale`).
    var xnurbsTension = "0.5"
    var xnurbsBoundaryFlow = SquareFitOptions.BoundaryFlow.adjacent
    var xnurbsQuality = XNurbsFeature.Quality.auto
    var xnurbsSatisfiesTolerances = true
    var xnurbsPositionTolerance = "0.01 mm"
    var xnurbsAngleTolerance = "0.1"

    var createsSheet: Bool { sheet || isSurfaceCreation }

    mutating func selectSurfaceOperation(_ operation: Kind) {
        precondition(Kind.surfaceCreationOperations.contains(operation))
        if name == kind.rawValue { name = operation.rawValue }
        kind = operation
        isSurfaceCreation = true
        reverseSecondBoundary = false
    }

    /// Opens a draft at the default the workspace scale publishes for what
    /// the kind is about to author.
    ///
    /// A size and an increment are different quantities and Core publishes
    /// each separately. `WorkspaceScaleDefaults` owns the default feature size,
    /// which is the size the canvas solid tool places, so a kind that creates
    /// geometry opens at it and the panel and the canvas agree on what one
    /// default solid is at the current scale.
    /// `WorkspaceInteractionScaleDefaults` owns the smallest increment the
    /// workspace moves by; a fillet radius and a chamfer distance are
    /// increments applied to an existing edge and open at it. Seeding a size
    /// from the increment is what makes a default solid degenerate at a fine
    /// scale, where the increment equals the document's distance tolerance.
    /// See `Modeling/DESIGN.md`, "Contracts and Invariants".
    init(kind: Kind, selection: SelectionModel, ruler: RulerConfiguration) {
        self.kind = kind
        self.name = kind.rawValue
        self.targets = selection.selectedTargets
        let unit = ruler.displayUnit
        self.unit = unit
        let initial = workspaceLengthFieldPresentation(
            fromMeters: Self.seedMeters(for: kind, ruler: ruler),
            preferredUnit: unit
        )
        let text = initial.text + " " + initial.unit.symbol
        self.distance = text
        self.width = text
        self.height = text
    }

    private static func seedMeters(for kind: Kind, ruler: RulerConfiguration) -> Double {
        switch kind {
        case .fillet, .chamfer, .g2Blend, .surfaceOffset, .shell, .thicken:
            WorkspaceInteractionScaleDefaults(ruler: ruler).operationStepMeters
        case .box, .cylinder, .sphere, .extrude, .revolve, .sweep, .pipe, .loft, .constrainedSurface, .surfacePatch, .patch, .bridge, .square, .xnurbs, .bridgeSurface, .surfaceExtend:
            WorkspaceScaleDefaults(ruler: ruler).placedSolidSideMeters
        }
    }

    func command(in document: DesignDocument) throws -> EditorCommand {
        guard !isSurfaceCreation || Kind.surfaceCreationOperations.contains(kind) else {
            throw invalid("This operation does not provide Surface Creation output.")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw invalid("Enter an operation name.")
        }
        if kind == .constrainedSurface {
            guard constrainedPoints.count >= 3 else {
                throw invalid("Add at least three non-collinear points to create a surface.")
            }
            let source = ConstrainedSurfaceFeature(points: constrainedPoints,
                positionTolerance: try length(pointTolerance, label: "Tolerance"),
                angularTolerance: try number(angularTolerance, label: "Angular tolerance") * .pi / 180,
                optimization: pointOptimization)
            try source.validate(tolerance: document.modelingSettings.tolerance)
            if let id = constrainedFeatureID { return .setConstrainedSurface(featureID: id, source: source) }
            return .createConstrainedSurface(name: name, source: source)
        }
        if [.box, .cylinder, .sphere, .surfacePatch].contains(kind) {
            let x = try length(origin[0], label: "Origin X")
            let y = try length(origin[1], label: "Origin Y")
            let z = try length(origin[2], label: "Origin Z")
            if kind == .surfacePatch {
                let w = try modelableLength(width, label: "Width", in: document)
                let h = try modelableLength(height, label: "Height", in: document)
                return .createBSplineSurface(name: name, surface: .bilinearPatch(
                    bottomLeft: Point3D(x: x, y: y, z: z),
                    bottomRight: Point3D(x: x + w, y: y, z: z),
                    topRight: Point3D(x: x + w, y: y + h, z: z),
                    topLeft: Point3D(x: x, y: y + h, z: z)
                ))
            }
            if kind == .sphere {
                return .createAnalyticSphere(name: name, center: Point3D(x: x, y: y, z: z), radius: try modelableLength(width, label: "Radius", in: document))
            }
            if kind == .cylinder {
                return .createExtrudedCircle(
                    name: name, plane: .plane(Plane3D(origin: Point3D(x: x, y: y, z: z), normal: .unitZ)),
                    center: SketchPoint(x: .length(0, .meter), y: .length(0, .meter)),
                    radius: .length(try modelableLength(width, label: "Radius", in: document), .meter),
                    depth: .length(try modelableLength(distance, label: "Depth", in: document), .meter), direction: .normal
                )
            }
            let w = try modelableLength(width, label: "Width", in: document)
            let h = try modelableLength(height, label: "Height", in: document)
            return .createExtrudedRectangle(
                name: name,
                plane: .plane(Plane3D(origin: Point3D(x: x + w / 2, y: y + h / 2, z: z), normal: .unitZ)),
                width: .length(w, .meter), height: .length(h, .meter),
                depth: .length(try modelableLength(distance, label: "Depth", in: document), .meter),
                direction: .normal
            )
        }

        if extrudesFaces {
            // Faces of one body: each its own extrusion of the face, combining with that body when
            // a Boolean is chosen.
            guard createsSheet == false else {
                throw invalid("Extruding faces makes a solid; turn Sheet output off.")
            }
            let draft = try number(draftDegrees, label: "Degrees")
            guard draft.isFinite, abs(draft) < 90 else { throw invalid("Degrees must be under 90.") }
            let thickness = wallThickness.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : try length(wallThickness, label: "Thickness")
            let end = try length(distance, label: "End position")
            // Automatic joins the extrusion to the faces' body: Union outward, Difference inward.
            let operation: SolidOperation = solidBoolean == .automatic ? (end >= 0 ? .union : .difference) : solidBoolean.operation
            return .extrudeFaces(
                targets: targets,
                distance: .length(end, .meter),
                startDistance: .length(try length(startDistance, label: "Start position"), .meter),
                individual: extrudesIndividually,
                operation: operation,
                keepTools: keepsTools,
                draftAngle: draft == 0 ? nil : .angle(draft, .degree),
                thickness: thickness.map { .length($0, .meter) }
            )
        }
        let nodes = try operandNodes(in: document)
        let features = try nodes.map { node -> FeatureID in
            guard let featureID = node.object?.sourceFeatureID,
                  node.reference?.featureID == featureID,
                  document.cadDocument.designGraph.nodes[featureID] != nil else {
                throw invalid("Select CAD source geometry. Authored Mesh uses Mesh editing.")
            }
            return featureID
        }
        switch kind {
        case .box, .cylinder, .sphere, .surfacePatch, .constrainedSurface:
            throw invalid("Primitive planning reached an invalid operand route.")
        case .extrude, .revolve:
            // Edges of bodies alone extrude into sheets, each along its curve.
            if kind == .extrude, targets.isEmpty == false,
               targets.allSatisfy({ if case .edge = $0.component { return true }; return false }) {
                let edgeCurves = try targets.map { edge in
                    EdgeCurveSource(id: FeatureID(), feature: try document.edgeCurveFeature(
                        for: edge, operationName: "Extrude", currentEvaluation: nil
                    ))
                }
                let direction: ExtrudeDirection
                switch extrusionDirection {
                case .normal: direction = .normal
                case .symmetric: direction = .symmetric
                case .vector:
                    let vector = Vector3D(x: try number(axis[0], label: "Direction X"),
                        y: try number(axis[1], label: "Direction Y"), z: try number(axis[2], label: "Direction Z"))
                    direction = .vector(try vector.normalized(tolerance: document.modelingSettings.tolerance.distance))
                }
                return .extrudeEdges(
                    name: name, edgeCurves: edgeCurves,
                    distance: .length(try length(distance, label: "End position"), .meter),
                    startDistance: extrusionDirection == .symmetric ? nil
                        : .length(try length(startDistance, label: "Start position"), .meter),
                    direction: direction
                )
            }
            // A face beside whole objects, a vertex, or an edge beside other operands is refused
            // rather than read as its whole object (Revolve takes regions and curves only, as
            // Plasticity's does).
            guard targets.allSatisfy({ target in
                switch target.component {
                case .face, .edge, .vertex: false
                default: true
                }
            }) else {
                throw invalid(kind == .extrude
                    ? "Extrude takes faces alone, edges alone, or whole sections; vertices are not sections."
                    : "Revolve takes whole sections, not faces, edges or vertices.")
            }
            // A Boolean extrusion or revolve takes the section first and the bodies it combines
            // with after it.
            let combines = solidBoolean.combines
            guard let node = nodes.first, combines ? features.count >= 2 : features.count == 1 else {
                throw invalid(combines
                    ? "Select the section first, then the bodies to combine it with."
                    : "Select exactly one section source.")
            }
            let section = try sectionReference(for: node.id, in: document)
            // A curve extruded with a thickness makes a solid wall whatever the Sheet output says.
            var thinCurve = false
            if kind == .extrude, case .curve = section, wallThickness.trimmingCharacters(in: .whitespaces).isEmpty == false {
                thinCurve = true
            }
            // A revolved curve may close into a solid along its axis; the kernel checks its ends.
            guard createsSheet || section.isProfile || kind == .revolve || thinCurve else {
                throw invalid("A selected curve requires Sheet output.")
            }
            if kind == .extrude {
                let direction: ExtrudeDirection
                switch extrusionDirection {
                case .normal: direction = .normal
                case .symmetric: direction = .symmetric
                case .vector:
                    let vector = Vector3D(x: try number(axis[0], label: "Direction X"),
                        y: try number(axis[1], label: "Direction Y"), z: try number(axis[2], label: "Direction Z"))
                    direction = .vector(try vector.normalized(tolerance: document.modelingSettings.tolerance.distance))
                }
                let extrusion = ExtrudeFeature(section: section,
                    distance: .length(try length(distance, label: "End position"), .meter),
                    startDistance: extrusionDirection == .symmetric ? nil
                        : .length(try length(startDistance, label: "Start position"), .meter),
                    direction: direction, resultKind: createsSheet && !thinCurve ? .sheet : .solid,
                    thickness: thinCurve ? .length(try length(wallThickness, label: "Thickness"), .meter) : nil)
                _ = try extrusion.resolvedAxialRange(tolerance: document.modelingSettings.tolerance) {
                    try document.cadDocument.parameters.resolvedValue(for: $0)
                }
                let draft = try number(draftDegrees, label: "Degrees")
                guard draft.isFinite, abs(draft) < 90 else {
                    throw invalid("Degrees must be under 90.")
                }
                let thickness = wallThickness.trimmingCharacters(in: .whitespaces).isEmpty
                    ? nil : try length(wallThickness, label: "Thickness")
                if thickness != nil, createsSheet, thinCurve == false {
                    throw invalid("A thin extrusion makes a solid wall; turn Sheet output off.")
                }
                guard combines || draft != 0 || thickness != nil else {
                    return .extrudeSection(name: name, section: section, distance: extrusion.distance,
                        startDistance: extrusion.startDistance, direction: direction, resultKind: extrusion.resultKind)
                }
                var drafted = extrusion
                drafted.draftAngle = draft == 0 ? nil : .angle(draft, .degree)
                drafted.thickness = thickness.map { .length($0, .meter) }
                guard combines else { return .createExtrusion(name: name, source: drafted) }
                guard createsSheet == false else {
                    throw invalid("A Boolean extrusion makes a solid; turn Sheet output off.")
                }
                var combined = drafted
                combined.operation = solidBoolean.operation
                combined.targets = features.dropFirst().map { BooleanTargetReference(featureID: $0) }
                combined.keepTools = keepsTools
                return .createExtrusion(name: name, source: combined)
            }
            let degrees = try number(angle, label: "Angle")
            guard degrees != 0, abs(degrees) <= 360 else {
                throw invalid("Revolve angle must be non-zero and within -360…360 degrees.")
            }
            let revolveAxis: RevolveAxis
            switch revolveAxisChoice {
            case .normal, .binormal, .tangent:
                let choice: RevolveSectionAxis.Direction = revolveAxisChoice == .normal ? .normal
                    : (revolveAxisChoice == .binormal ? .binormal : .tangent)
                let evaluated = try DocumentEvaluationContextResolver().exactEvaluatedDocument(
                    document: document, failurePrefix: "Revolve's section axes need the section evaluated")
                do {
                    revolveAxis = try RevolveSectionAxis().axis(choice, section: section, in: evaluated)
                } catch let error as KernelError {
                    throw invalid("Revolve axis: \(error.message)")
                }
            case .direction, .twoPoints:
                revolveAxis = try explicitRevolveAxis(in: document)
            }
            let thickness = wallThickness.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : try length(wallThickness, label: "Thickness")
            guard !createsSheet || (thickness == nil && !combines) else {
                throw invalid("A thin or Boolean revolve makes a solid; turn Sheet output off.")
            }
            return .revolveSection(
                name: name, section: section, axis: revolveAxis,
                angle: .angle(degrees, .degree), resultKind: createsSheet ? .sheet : .solid,
                operation: solidBoolean.operation, targets: Array(features.dropFirst()), keepTools: combines && keepsTools,
                thickness: thickness.map { .length($0, .meter) }
            )
        case .pipe:
            // A pipe follows each selected curve and each selected edge of a body; an edge's curve
            // is added with the pipes. With a custom profile the first selected region or face is
            // the section.
            var pathTargets = targets
            var profile: SectionReference?
            if pipeCustomProfile {
                guard let first = pathTargets.first else { throw invalid("Select the custom profile first, then the curves.") }
                switch first.component {
                case .face:
                    profile = .face(try document.faceSectionReference(for: first, operationName: "Pipe", currentEvaluation: nil))
                case .object:
                    profile = try sectionReference(for: first.sceneNodeID, in: document)
                default:
                    throw invalid("A pipe's custom profile is a region or a face.")
                }
                guard profile?.isClosedRegion == true else { throw invalid("A pipe's custom profile is a closed region or a face.") }
                pathTargets.removeFirst()
            }
            let profileNode = profile == nil || pathTargets.contains(where: { $0.sceneNodeID == targets.first?.sceneNodeID && $0.component == .object })
                ? nil : targets.first?.sceneNodeID
            guard pathTargets.allSatisfy({ target in
                switch target.component {
                case .object, .edge: true
                default: false
                }
            }) else {
                throw invalid("Pipe follows curves and edges; select whole curve sources or edges.")
            }
            var edgeCurves: [EdgeCurveSource] = []
            for edge in pathTargets where edge.component != .object {
                edgeCurves.append(EdgeCurveSource(id: FeatureID(), feature: try document.edgeCurveFeature(
                    for: edge, operationName: "Pipe", currentEvaluation: nil
                )))
            }
            let edgeOwners = Set(pathTargets.filter { $0.component != .object }.map(\.sceneNodeID))
            var paths = zip(nodes, features).filter { !edgeOwners.contains($0.0.id) && $0.0.id != profileNode }.map(\.1)
            var bodies: [SweepTargetReference] = []
            if solidBoolean.combines {
                // The bodies to combine with come after the curves, or a pipe along an edge
                // combines with the edge's own body.
                while paths.count > (edgeCurves.isEmpty ? 1 : 0), let node = nodes.last(where: { $0.object?.sourceFeatureID == paths.last }),
                      node.object?.geometryRole == .solid, let featureID = paths.last {
                    bodies.insert(SweepTargetReference(featureID: featureID), at: 0)
                    paths.removeLast()
                }
                if bodies.isEmpty, let owner = edgeCurves.first?.feature.source {
                    bodies = [SweepTargetReference(featureID: owner)]
                }
                guard !bodies.isEmpty else { throw invalid("Select the curves first, then the bodies to combine with.") }
            }
            paths += edgeCurves.map(\.id)
            guard !paths.isEmpty else { throw invalid("Select at least one curve or edge for the pipe to follow.") }
            let vertices = profile == nil ? try number(pipeVertices, label: "Vertices") : 0
            guard vertices == vertices.rounded(), vertices == 0 || (3...256).contains(vertices) else {
                throw invalid("Vertices is 0 for a circle or 3 to 256 for a polygon.")
            }
            let thickness = wallThickness.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : CADExpression.length(try length(wallThickness, label: "Thickness"), .meter)
            guard let operation = SweepBooleanOperation(rawValue: solidBoolean.operation.rawValue) else {
                throw invalid("The pipe's Boolean is not a sweep Boolean.")
            }
            let sources = paths.map { path in
                PipeFeature(
                    path: SweepPathReference(featureID: path),
                    diameter: profile == nil ? .length(0, .meter) : nil, profile: profile, thickness: thickness, vertexCount: Int(vertices),
                    booleanOperation: operation, targets: bodies, keepTools: solidBoolean.combines && keepsTools,
                    approximationTolerance: .length(0, .meter)
                )
            }
            let diameter = profile == nil ? CADExpression.length(try length(pipeDiameter, label: "Diameter"), .meter) : nil
            let angle = CADExpression.angle(try number(pipeAngle, label: "Angle"), .degree)
            let twist = CADExpression.angle(try number(pipeTwist, label: "Twist"), .degree)
            let endScale = CADExpression.scalar(try number(pipeEndScale, label: "Scale"))
            let start = CADExpression.scalar(try number(pipeStart, label: "Start"))
            let end = CADExpression.scalar(try number(pipeEnd, label: "End"))
            let allowance = CADExpression.length(try length(pipeAllowance, label: "Positional approximation allowance"), .meter)
            let pipes = try sources.map { source -> PipeFeature in
                var pipe = source
                pipe.diameter = diameter
                pipe.angle = angle
                pipe.twist = twist
                pipe.endScale = endScale
                pipe.start = start
                pipe.end = end
                pipe.approximationTolerance = allowance
                do { try pipe.validate() } catch { throw invalid("The pipe is invalid: \(error).") }
                return pipe
            }
            return .createPipes(name: name, sources: pipes, edgeCurves: edgeCurves)
        case .sweep:
            let degrees = try number(twistAngle, label: "Twist angle")
            var options = SweepOptions()
            options.resultKind = createsSheet ? .sheet : .solid
            options.alignment = sweepAlignment.alignment
            options.cornerStyle = sweepCorners.style
            options.simplify = sweepSimplify
            options.guideMethod = sweepGuide.method
            // The allowance bounds whichever approximation the sweep needs (a twist, a Normal sweep
            // along a curved path, a Chord or Curve guide); left blank, the planner's default.
            let twists = degrees != 0 || doubleHelical
            if !approximationTolerance.trimmingCharacters(in: .whitespaces).isEmpty {
                let allowance = try length(approximationTolerance, label: "Positional approximation allowance")
                guard allowance > 0 else { throw invalid("Positional approximation allowance must be positive.") }
                options.approximationTolerance = .length(allowance, .meter)
            }
            // Scale: the end section's size against the start's; Distance: the fraction of the
            // path the sweep runs along.
            let endScale = try number(sweepEndScale, label: "Scale")
            guard endScale.isFinite, endScale > 0 else { throw invalid("Scale must be positive.") }
            options.endScale = .constant(.scalar(endScale))
            let distance = try number(sweepDistance, label: "Distance")
            guard distance.isFinite, distance > 0, distance <= 1 else { throw invalid("Distance must be in 0 < d ≤ 1.") }
            options.distanceFraction = .constant(.scalar(distance))
            if twists {
                if doubleHelical {
                    options.twistLaw = [
                        .init(position: 0, angle: .angle(0, .degree)),
                        .init(position: 0.5, angle: .angle(degrees, .degree)),
                        .init(position: 1, angle: .angle(0, .degree))
                    ]
                } else {
                    options.twistAngle = .angle(degrees, .degree)
                }
            }
            // A Boolean sweep combines with the bodies selected after its section and path, or
            // with the body its face section lies on.
            var sources = targets
            // An edge selected for the path is the path along its curve.
            var pathEdgeCurve: EdgeCurveSource?
            if let edgeIndex = sources.lastIndex(where: { if case .edge = $0.component { return true }; return false }) {
                pathEdgeCurve = EdgeCurveSource(id: FeatureID(), feature: try document.edgeCurveFeature(
                    for: sources[edgeIndex], operationName: "Sweep", currentEvaluation: nil
                ))
                sources.remove(at: edgeIndex)
            }
            var bodies: [SweepTargetReference] = []
            if solidBoolean.combines {
                guard let operation = SweepBooleanOperation(rawValue: solidBoolean.operation.rawValue), !createsSheet else {
                    throw invalid("A Boolean sweep makes a solid; turn Sheet output off.")
                }
                while sources.count > 1, let last = sources.last, last.component == .object,
                      let node = document.productMetadata.sceneNodes[last.sceneNodeID],
                      node.object?.geometryRole == .solid, let featureID = node.object?.sourceFeatureID {
                    bodies.insert(SweepTargetReference(featureID: featureID), at: 0)
                    sources.removeLast()
                }
                if bodies.isEmpty, let face = sources.first(where: { if case .face = $0.component { return true }; return false }),
                   let featureID = document.productMetadata.sceneNodes[face.sceneNodeID]?.object?.sourceFeatureID {
                    bodies = [SweepTargetReference(featureID: featureID)]
                }
                guard !bodies.isEmpty else {
                    throw invalid("Select the section and path first, then the bodies to combine with.")
                }
                options.booleanOperation = operation
                options.keepTools = keepsTools
            }
            return try SweepSelectionPlanningService(
                document: document, selection: SelectionModel(selectedTargets: sources)
            ).command(name: name, options: options, targets: bodies, pathEdgeCurve: pathEdgeCurve)
        case .loft:
            // Sections in selection order: each edge or face of a body its own section, each other
            // source once.
            var seenTargets = Set<SelectionTarget>(), seenNodes = Set<SceneNodeID>()
            // A selected vertex of a body is the loft's apex, after its one section.
            let vertices = targets.filter { if case .vertex = $0.component { return true }; return false }
            let sectionTargets = targets.filter { target in
                guard !isLoftGuide(target), seenTargets.insert(target).inserted else { return false }
                switch target.component {
                case .edge, .face: return true
                case .vertex: return false
                default: return seenNodes.insert(target.sceneNodeID).inserted
                }
            }
            guard vertices.count <= 1 else { throw invalid("A loft ends at one vertex.") }
            guard sectionTargets.count >= (vertices.isEmpty ? 2 : 1) else {
                throw invalid(vertices.isEmpty ? "Select at least two ordered sections, separate from guides." : "Select a section to loft to the vertex.")
            }
            // A selected edge of a body is a curve section or guide along it, its curve added with
            // the loft.
            var edgeCurves: [EdgeCurveSource] = []
            var guides = zip(nodes, features).compactMap { node, feature in
                loftGuideNodeIDs.contains(node.id) ? LoftGuideReference(featureID: feature) : nil
            }
            for target in targets where loftGuideEdges.contains(target) {
                guard case .edge = target.component else { continue }
                let curve = EdgeCurveSource(id: FeatureID(), feature: try document.edgeCurveFeature(
                    for: target, operationName: "Loft", currentEvaluation: nil
                ))
                edgeCurves.append(curve)
                guides.append(LoftGuideReference(featureID: curve.id))
            }
            // A G1 or G2 end is continuous with the face beside the edge selected there, with its
            // own tension.
            func endTension(_ text: String, _ choice: LoftContinuityChoice, label: String) throws -> Double {
                guard choice != .g0 else { return 1 }
                let value = try number(text, label: label)
                guard value.isFinite, value > 0 else { throw invalid("\(label) must be positive.") }
                return value
            }
            let startTension = try endTension(loftStartTension, loftStartContinuity, label: "Start tension")
            let endTension = try endTension(loftEndTension, loftEndContinuity, label: "End tension")
            let sections = try sectionTargets.enumerated().map { index, target in
                let reference: SectionReference
                let choice = index == 0 ? loftStartContinuity : index == sectionTargets.count - 1 ? loftEndContinuity : .g0
                let edgeTension = index == 0 ? startTension : endTension
                var continuity: SurfaceEdgeContinuity?
                switch target.component {
                case .edge:
                    let curve = EdgeCurveSource(id: FeatureID(), feature: try document.edgeCurveFeature(
                        for: target, operationName: "Loft", currentEvaluation: nil
                    ))
                    edgeCurves.append(curve)
                    reference = .curve(CurveSectionReference(featureID: curve.id))
                    if let order = choice.order, let edge = curve.feature.edges.first {
                        continuity = SurfaceEdgeContinuity(source: curve.feature.source, bodyRole: curve.feature.bodyRole,
                                                        edge: edge, order: order, tension: edgeTension,
                                                        angularAllowance: try continuityAllowanceRadians(),
                                                        curvatureAllowance: try curvatureAllowance(for: order))
                    }
                case .face:
                    // A selected face of a body is a section of its own.
                    reference = .face(try document.faceSectionReference(for: target, operationName: "Loft", currentEvaluation: nil))
                default:
                    reference = try sectionReference(for: target.sceneNodeID, in: document)
                }
                let controls = loftSectionControls[target.sceneNodeID] ?? LoftSectionDraft(section: LoftSectionReference(section: reference))
                var section = try controls.applying(to: LoftSectionReference(section: reference))
                section.continuity = continuity
                return section
            }
            // Curves loft into a sheet; regions and faces into a solid unless Sheet output is on.
            let lofted = createsSheet || sections.contains { $0.section.isClosedRegion == false }
            let options = LoftOptions(resultKind: lofted ? .sheet : .solid,
                closesSectionLoop: closesSectionLoop, surfaceMode: smooth ? .smooth : .ruled,
                smoothTangentScale: try number(loftDefaultTension, label: "Default section tension"),
                simplify: loftSimplify)
            if let vertex = vertices.first {
                let apex = try document.loftApex(for: vertex, currentEvaluation: nil)
                guard sections.count == 1, guides.isEmpty else { throw invalid("A loft to a vertex takes one section and no guides.") }
                try LoftFeature(sections: sections, options: options, apex: apex).validate()
                return .createApexLoft(name: name, section: sections[0], apex: apex, options: options, edgeCurves: edgeCurves)
            }
            try LoftFeature(sections: sections, guides: guides, options: options).validate()
            return .createLoft(name: name, sections: sections, guides: guides, options: options, edgeCurves: edgeCurves)
        case .bridgeSurface:
            // Two sheets, the bridge set back by the width from where they meet.
            let sheets = zip(nodes, features).filter { _, feature in
                document.cadDocument.designGraph.nodes[feature]?.outputs.contains(where: { $0.role == .sheet }) == true
            }.map(\.1)
            guard targets.count == 2, sheets.count == 2, sheets[0] != sheets[1] else {
                throw invalid("Bridge Surface joins two sheets; select both.")
            }
            let tension = try number(bridgeTension, label: "Tension")
            let bridge = SheetBridgeFeature(first: sheets[0], second: sheets[1],
                width: try topologyLength(distance, label: "Width", in: document), tension: tension,
                shape: bridgeShape == .g2 ? .curvature : .chamfer, trimWalls: bridgeTrim == .both ? .both : .none,
                reversesSense: bridgeReversesSense,
                angularAllowance: try continuityAllowanceRadians(),
                curvatureAllowance: bridgeShape == .g2 ? try curvatureAllowance(for: .curvature) : nil)
            do { try bridge.validate() } catch { throw invalid("The Bridge Surface is invalid: \(error).") }
            let wallByReach: SheetBridgeWallReach.Wall? = switch bridgeTrim {
            case .short: .short
            case .long: .long
            case .none, .both: nil
            }
            return .createBridgeSurface(name: name, bridge: bridge, wallByReach: wallByReach)
        case .xnurbs:
            // Boundaries: edges of bodies (their curves added with it, taking the continuity) or
            // curves; guides: curves marked as such.
            let boundaryTargets = targets.filter { !xnurbsGuideNodeIDs.contains($0.sceneNodeID) }
            // One closed curve frames it on its own (Plasticity fills a single outline).
            guard boundaryTargets.isEmpty == false else { throw invalid("XNURBS takes a closed curve, or two or more boundary edges or curves.") }
            let tension = DialogTensionScale.kernelScale(try number(xnurbsTension, label: "Tension"))
            var edgeCurves: [EdgeCurveSource] = []
            let boundaries = try boundaryTargets.map { target -> SquareSide in
                switch target.component {
                case .edge:
                    let curve = EdgeCurveSource(id: FeatureID(), feature: try document.edgeCurveFeature(
                        for: target, operationName: "XNURBS", currentEvaluation: nil
                    ))
                    edgeCurves.append(curve)
                    var continuity: SurfaceEdgeContinuity?
                    if let order = xnurbsContinuity(of: target).order, let edge = curve.feature.edges.first {
                        continuity = SurfaceEdgeContinuity(source: curve.feature.source, bodyRole: curve.feature.bodyRole,
                                                           edge: edge, order: order, tension: tension,
                                                           angularAllowance: try continuityAllowanceRadians(),
                                                           curvatureAllowance: try curvatureAllowance(for: order))
                    }
                    return SquareSide(curve: CurveSectionReference(featureID: curve.id), continuity: continuity)
                case .object:
                    guard case .curve(let curve) = try sectionReference(for: target.sceneNodeID, in: document) else {
                        throw invalid("An XNURBS boundary is a curve or an edge of a body.")
                    }
                    return SquareSide(curve: curve)
                default:
                    throw invalid("An XNURBS boundary is a curve or an edge of a body.")
                }
            }
            let guides = try targets.filter { xnurbsGuideNodeIDs.contains($0.sceneNodeID) }.map { target -> CurveSectionReference in
                guard case .object = target.component, case .curve(let curve) = try sectionReference(for: target.sceneNodeID, in: document) else {
                    throw invalid("An XNURBS guide is a curve.")
                }
                return curve
            }
            let angle = try number(xnurbsAngleTolerance, label: "Angle tolerance")
            let xnurbs = XNurbsFeature(
                boundaries: boundaries, guides: guides, quadSided: xnurbsQuadSided,
                flatness: try number(xnurbsFlatness, label: "Flatness"), boundaryFlow: xnurbsBoundaryFlow, quality: xnurbsQuality,
                satisfiesTolerances: xnurbsSatisfiesTolerances,
                positionTolerance: try length(xnurbsPositionTolerance, label: "Position tolerance"),
                angleTolerance: angle * Double.pi / 180
            )
            do { try xnurbs.validate() } catch { throw invalid("The XNURBS is invalid: \(error).") }
            return .createXNurbs(name: name, xnurbs: xnurbs, edgeCurves: edgeCurves)
        case .square:
            // Faces: Refit, each replaced by a Square sheet on its own edges at the Square's
            // continuity (Free has no meaning there, the edges staying shared).
            if targets.isEmpty == false, targets.allSatisfy(isFace) {
                guard squareContinuity != .free else {
                    throw invalid("Refit keeps a face's edges: choose G0, G1 or G2.")
                }
                let order = squareContinuity.order
                let refit = SquareRefit(options: try squareFitOptions(), order: order,
                                        angularAllowance: order == nil ? nil : try continuityAllowanceRadians(),
                                        curvatureAllowance: try order.flatMap { try curvatureAllowance(for: $0) })
                do { try refit.validate() } catch { throw invalid("The Refit is invalid: \(error).") }
                return .rebuildFaces(targets: targets, method: .square(refit))
            }
            // Two to four sides in any order: edges of bodies (their curves added with the
            // Square), which take G1 or G2, or whole curve sources; each side Free, G0 or its edge's
            // continuity.
            guard (2...4).contains(targets.count) else {
                throw invalid("Square takes two to four sides: edges of bodies or curves.")
            }
            let continuous = targets.contains { squareContinuity(of: $0).order != nil }
            let tension = continuous ? DialogTensionScale.kernelScale(try number(squareTension, label: "Tension")) : 1
            let options = try squareFitOptions()
            var edgeCurves: [EdgeCurveSource] = []
            let sides = try targets.map { target -> SquareSide in
                let choice = squareContinuity(of: target)
                switch target.component {
                case .edge:
                    let curve = EdgeCurveSource(id: FeatureID(), feature: try document.edgeCurveFeature(
                        for: target, operationName: "Square", currentEvaluation: nil
                    ))
                    edgeCurves.append(curve)
                    var continuity: SurfaceEdgeContinuity?
                    if let order = choice.order, let edge = curve.feature.edges.first {
                        continuity = SurfaceEdgeContinuity(source: curve.feature.source, bodyRole: curve.feature.bodyRole,
                                                           edge: edge, order: order, tension: tension,
                                                           angularAllowance: try continuityAllowanceRadians(),
                                                           curvatureAllowance: try curvatureAllowance(for: order))
                    }
                    return SquareSide(curve: CurveSectionReference(featureID: curve.id), continuity: continuity, isFree: choice == .free)
                case .object:
                    guard case .curve(let curve) = try sectionReference(for: target.sceneNodeID, in: document) else {
                        throw invalid("A Square's side is an open curve or an edge of a body.")
                    }
                    return SquareSide(curve: curve, isFree: choice == .free)
                default:
                    throw invalid("A Square's side is an open curve or an edge of a body.")
                }
            }
            do { try SquareSurfaceFeature(sides: sides, options: options).validate() } catch { throw invalid("The Square is invalid: \(error).") }
            return .createSquare(name: name, sides: sides, options: options, edgeCurves: edgeCurves)
        case .shell:
            guard targets.count == 1, case .face(let component) = targets[0].component,
                  component.generatedTopologySubshapeID != nil,
                  nodes[0].reference?.kind == .body else {
                throw invalid("Select one generated solid face to remove for the Shell opening.")
            }
            return .createBodyShell(name: name, target: targets[0],
                thickness: try topologyLength(distance, label: "Wall thickness", in: document))
        case .patch where targets.contains(where: { $0.component == .object }):
            // Closed curves (the operands' kind, not their count, selects this): whole curve
            // sources, with any edges of bodies among them (their curves added with the patch),
            // joined end to end.
            var edgeCurves: [EdgeCurveSource] = []
            let curves = try targets.map { target -> CurveSectionReference in
                switch target.component {
                case .edge:
                    let curve = EdgeCurveSource(id: FeatureID(), feature: try document.edgeCurveFeature(
                        for: target, operationName: "Patch", currentEvaluation: nil
                    ))
                    edgeCurves.append(curve)
                    return CurveSectionReference(featureID: curve.id)
                case .object:
                    let source = try sectionReference(for: target.sceneNodeID, in: document)
                    switch source {
                    case .curve(let curve): return curve
                    case .profile:
                        // A closed sketch's region is its curve loop.
                        guard let feature = document.productMetadata.sceneNodes[target.sceneNodeID]?.object?.sourceFeatureID else {
                            throw invalid("Patch source is missing.")
                        }
                        return CurveSectionReference(featureID: feature)
                    case .face:
                        throw invalid("Patch spans curves or edges, not faces.")
                    }
                default:
                    throw invalid("Patch spans curves or edges.")
                }
            }
            do { try CurvePatchFeature(curves: curves).validate() } catch { throw invalid("The patch is invalid: \(error).") }
            return .createCurvePatch(name: name, curves: curves, edgeCurves: edgeCurves)
        case .patch, .bridge:
            guard kind != .patch || targets.count == 1 else {
                throw invalid("Patch requires exactly one edge of the opening to fill.")
            }
            guard kind != .bridge || targets.count == 2 else {
                throw invalid("Boundary Bridge requires exactly two open edges, in boundary order.")
            }
            guard (targets.count == 1 || targets.count == 2),
                  targets.allSatisfy({ target in
                      guard case .edge(let component) = target.component else { return false }
                      return component.generatedTopologySubshapeID != nil
                  }),
                  !nodes.isEmpty,
                  nodes.allSatisfy({ $0.reference?.kind == .body }) else {
                throw invalid("Select one open-boundary edge to close an opening, or two distinct boundary edges to bridge them.")
            }
            guard targets.count == 1 || targets[0] != targets[1] else {
                throw invalid("Select two different boundary edges.")
            }
            guard targets.count == 2 || !reverseSecondBoundary else {
                throw invalid("Reverse boundary is available only when two edges are selected.")
            }
            if kind == .patch { return .createSurfaceFill(name: name, target: targets[0]) }
            return .createBoundaryBridge(name: name, first: targets[0], second: targets[1],
                                         reverseSecondBoundary: reverseSecondBoundary)
        case .surfaceOffset, .surfaceExtend, .thicken:
            guard targets.count == 1, case .face(let component) = targets[0].component,
                  component.generatedTopologySubshapeID != nil,
                  let feature = features.first,
                  document.cadDocument.designGraph.nodes[feature]?.outputs.contains(where: { $0.role == .sheet }) == true else {
                throw invalid("Select one generated face of a sheet surface.")
            }
            let edit: SheetSurfaceEdit
            if kind == .surfaceOffset {
                edit = .offset(distance: try topologyLength(distance, label: "Offset", signed: true, in: document))
            } else if kind == .thicken {
                edit = .thicken(
                    front: try topologyLength(distance, label: "Front", allowsZero: true, in: document),
                    back: try topologyLength(thickenBack, label: "Back", allowsZero: true, in: document)
                )
            } else {
                let u0 = try number(uBounds[0], label: "U minimum")
                let u1 = try number(uBounds[1], label: "U maximum")
                let v0 = try number(vBounds[0], label: "V minimum")
                let v1 = try number(vBounds[1], label: "V maximum")
                guard u0 < u1, v0 < v1 else { throw invalid("Each minimum must be less than its maximum.") }
                edit = .extend(uDomain: .closed(u0, u1), vDomain: .closed(v0, v1))
            }
            return .createSheetSurfaceEdit(name: name, target: targets[0], edit: edit)
        case .fillet where filletShape == .full:
            let edges = WorkspaceSelectionTargetClassification(targets: targets).edgeTargets
            guard edges.count == 2, targets.count == 2 else {
                throw invalid("Full rounds across the face between two edges; select both.")
            }
            return .createBodyEdgeTreatment(name: name, target: edges[0], treatment: .fullFillet(across: edges[1]))
        case .fillet, .chamfer, .g2Blend:
            let edges = WorkspaceSelectionTargetClassification(targets: targets).edgeTargets
            guard edges.isEmpty == false, edges.count == targets.count, Set(edges).count == edges.count,
                  edges.allSatisfy({ edge in
                      guard case .edge(let component) = edge.component else { return false }
                      return component.generatedTopologySubshapeID != nil
                  }) else {
                throw invalid("Select distinct generated CAD edges of one body.")
            }
            // Fillet Shell: a negative distance chamfers the edges by its size.
            let signedAmount = try topologyLength(distance,
                label: kind == .fillet && effectiveFilletShape == .round ? "Radius" : "Distance", signed: kind == .fillet, in: document)
            let signedValue = try document.cadDocument.parameters.resolvedValue(for: signedAmount).value
            let chamfers = kind == .fillet && signedValue < 0
            let amount: CADExpression
            if chamfers {
                let text = distance.trimmingCharacters(in: .whitespaces)
                amount = text.hasPrefix("-")
                    ? try topologyLength(String(text.dropFirst()), label: "Distance", in: document)
                    : .length(-signedValue, .meter)
            } else {
                amount = signedAmount
            }
            // Limit points bound one fillet's or chamfer's edge to a stretch of it.
            let limits: EdgeBlendLimits?
            if kind != .g2Blend, limitStart.trimmingCharacters(in: .whitespaces).isEmpty == false
                || limitEnd.trimmingCharacters(in: .whitespaces).isEmpty == false {
                func fraction(_ value: String, blank: Double, label: String) throws -> Double {
                    let trimmed = value.trimmingCharacters(in: .whitespaces)
                    return trimmed.isEmpty ? blank : try number(trimmed, label: label)
                }
                let stretch = EdgeBlendLimits(start: try fraction(limitStart, blank: 0, label: "Limit start"),
                                              end: try fraction(limitEnd, blank: 1, label: "Limit end"), reversed: limitsReversed)
                do { try stretch.validate() } catch {
                    throw invalid("Limits lie within the edge, 0 ≤ start < end ≤ 1, and limit it somewhere.")
                }
                guard edges.count == 1 else { throw invalid("Limits bound one edge.") }
                limits = stretch
            } else {
                limits = nil
            }
            var treatment: BodyEdgeTreatment
            switch kind {
            case .fillet where chamfers:
                treatment = .chamfer(distance: amount, limits: limits)
            case .fillet where limits != nil:
                let text = filletTension.trimmingCharacters(in: .whitespaces)
                let tension = effectiveFilletShape.takesTension && !text.isEmpty ? try number(text, label: "Tension") : nil
                guard let limits else { throw invalid("A limited fillet has its limits.") }
                treatment = .limitedFillet(distance: amount, shape: effectiveFilletShape.shape, tension: tension, limits: limits)
            case .fillet where filletEndRadius.trimmingCharacters(in: .whitespaces).isEmpty == false
                || filletVariablePoints.trimmingCharacters(in: .whitespaces).isEmpty == false:
                guard edges.count == 1 else { throw invalid("A variable fillet rounds one edge.") }
                let text = filletTension.trimmingCharacters(in: .whitespaces)
                let tension = effectiveFilletShape.takesTension && !text.isEmpty ? try number(text, label: "Tension") : nil
                let endText = filletEndRadius.trimmingCharacters(in: .whitespaces)
                let points = try filletVariablePoints.split(separator: ",").map { entry -> FilletVariablePoint in
                    let parts = entry.split(separator: "@", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.count == 2 else { throw invalid("A variable point is written as fraction@radius.") }
                    return FilletVariablePoint(position: try number(parts[0], label: "Variable point position"),
                                               radius: try topologyLength(parts[1], label: "Variable point radius", in: document))
                }
                treatment = .variableFillet(radius: amount,
                                            endRadius: endText.isEmpty ? amount : try topologyLength(endText, label: "End radius", in: document),
                                            shape: effectiveFilletShape.shape, tension: tension, points: points)
            case .fillet where effectiveFilletShape != .round:
                let text = filletTension.trimmingCharacters(in: .whitespaces)
                let tension = effectiveFilletShape.takesTension && !text.isEmpty ? try number(text, label: "Tension") : nil
                treatment = .shapedFillet(distance: amount, shape: effectiveFilletShape.shape, tension: tension)
            case .fillet: treatment = .fillet(radius: amount)
            case .chamfer:
                let angleText = chamferAngle.trimmingCharacters(in: .whitespaces)
                let angle = angleText.isEmpty ? nil : CADExpression.angle(try number(angleText, label: "Chamfer angle"), .degree)
                treatment = .chamfer(distance: amount, mode: chamferMode.mode, angle: angle, flipped: angle != nil && chamferFlipped,
                                     limits: limits)
            default: treatment = .g2Blend(distance: amount)
            }
            // Tangent Edges off: only the selected edges.
            if tangentEdges == false, kind != .g2Blend {
                treatment = .tangentEdgesOff(treatment)
            }
            // Further edges take the same treatment, blended in turn.
            return .createBodyEdgeTreatment(name: name, target: edges[0],
                                            treatment: edges.count == 1 ? treatment : .several(treatment, more: Array(edges.dropFirst())))
        }
    }

    /// A revolve's axis typed in: through its origin along a direction, or from its origin to its end.
    private func explicitRevolveAxis(in document: DesignDocument) throws -> RevolveAxis {
        let axisOrigin = Point3D(
            x: try length(origin[0], label: "Axis origin X"),
            y: try length(origin[1], label: "Axis origin Y"),
            z: try length(origin[2], label: "Axis origin Z")
        )
        let direction: Vector3D
        switch revolveAxisChoice {
        case .twoPoints:
            let end = Point3D(
                x: try length(axisEnd[0], label: "Axis end X"),
                y: try length(axisEnd[1], label: "Axis end Y"),
                z: try length(axisEnd[2], label: "Axis end Z")
            )
            direction = end - axisOrigin
        default:
            direction = Vector3D(
                x: try number(axis[0], label: "Axis X"),
                y: try number(axis[1], label: "Axis Y"),
                z: try number(axis[2], label: "Axis Z")
            )
        }
        let revolveAxis = RevolveAxis(origin: axisOrigin, direction: direction)
        do {
            try revolveAxis.validate(tolerance: document.modelingSettings.tolerance)
        } catch {
            throw invalid(revolveAxisChoice == .twoPoints
                ? "The axis's two points must be apart." : "The axis direction must not be zero.")
        }
        return revolveAxis
    }

    func operandTitle(at index: Int, in document: DesignDocument) -> String {
        let name = document.productMetadata.sceneNodes[targets[index].sceneNodeID]?.name ?? "Missing source"
        let role: String
        switch kind {
        case .loft:
            let isGuide = isLoftGuide(targets[index])
            let ordinal = targets.prefix(index + 1).filter { isLoftGuide($0) == isGuide }.count
            role = "\(isGuide ? "Guide" : "Section") \(ordinal)"
        case .sweep: role = index == targets.count - 1 ? "Path" : "Section / guide"
        case .pipe:
            let isBody = document.productMetadata.sceneNodes[targets[index].sceneNodeID]?.object?.geometryRole == .solid
            role = isBody ? "Body" : "Path"
        case .fillet, .chamfer, .g2Blend: role = "Edge \(index + 1)"
        case .surfaceOffset, .surfaceExtend, .thicken: role = "Sheet face"
        case .shell: role = "Opening face"
        case .patch, .bridge: role = targets.count == 2 ? "Boundary \(index == 0 ? "A" : "B")" : "Opening boundary"
        default: role = "Profile"
        }
        return "\(role): \(name)"
    }

    func sectionReference(for id: SceneNodeID, in document: DesignDocument) throws -> SectionReference {
        guard let node = document.productMetadata.sceneNodes[id],
              let feature = node.object?.sourceFeatureID,
              node.reference?.featureID == feature,
              document.cadDocument.designGraph.nodes[feature] != nil else {
            throw invalid("Section source is missing.")
        }
        if let reference = try document.explicitModelingSectionReference(
            for: feature, sceneNodeID: id, selectedTargets: targets) { return reference }
        return try document.modelingSectionReference(for: feature)
    }

    private func operandNodes(in document: DesignDocument) throws -> [SceneNode] {
        let preservesOccurrence = [.fillet, .chamfer, .g2Blend, .surfaceOffset, .surfaceExtend, .patch, .bridge, .shell, .thicken].contains(kind)
        var seen = Set<SceneNodeID>()
        var nodes: [SceneNode] = []
        for target in targets where seen.insert(target.sceneNodeID).inserted {
            guard let node = document.productMetadata.sceneNodes[target.sceneNodeID], !node.isLocked else {
                throw invalid("An operand is missing or locked. Select an editable source.")
            }
            var ancestors: Set<SceneNodeID> = [node.id]
            var current = node
            while true {
                guard preservesOccurrence || current.localTransform == .identity else {
                    throw invalid("\(node.name) has an occurrence transform. This operation requires source-frame CAD geometry; its placement cannot be ignored.")
                }
                guard let parent = document.productMetadata.sceneNodes.values.first(where: { $0.childIDs.contains(current.id) }) else { break }
                guard ancestors.insert(parent.id).inserted else { throw invalid("The scene hierarchy contains a cycle.") }
                current = parent
            }
            nodes.append(node)
        }
        return nodes
    }

    private func topologyLength(
        _ text: String, label: String, signed: Bool = false, allowsZero: Bool = false, in document: DesignDocument
    ) throws -> CADExpression {
        let parameters = document.cadDocument.parameters
        let expression = try ParameterExpressionParser().parse(text, parameters: parameters,
            targetKind: .length, defaults: ParameterExpressionDefaults(lengthUnit: unit))
        let quantity = try parameters.resolvedValue(for: expression)
        if allowsZero {
            // One side of a thickening may be nothing; neither may be negative.
            guard quantity.value.isFinite, quantity.value >= 0 else {
                throw invalid("\(label) must resolve to a finite length that is not negative.")
            }
            return expression
        }
        guard quantity.value.isFinite,
              (signed ? abs(quantity.value) : quantity.value) > document.modelingSettings.tolerance.distance else {
            throw invalid("\(label) must resolve to a finite \(signed ? "non-zero" : "positive") length above modeling tolerance.")
        }
        return expression
    }

    private func length(_ text: String, label: String) throws -> Double {
        guard let value = workspaceLengthMeters(fromFieldText: text, defaultUnit: unit), value.isFinite else {
            throw invalid("\(label) must be a finite length with valid units.")
        }
        return value
    }

    /// Native feature extents and edge blends both exceed modeling tolerance.
    private func modelableLength(
        _ text: String,
        label: String,
        in document: DesignDocument
    ) throws -> Double {
        let value = try length(text, label: label)
        let toleranceMeters = document.modelingSettings.tolerance.distance
        guard value > toleranceMeters else {
            let threshold = workspaceLengthFieldPresentation(
                fromMeters: toleranceMeters,
                preferredUnit: unit
            )
            throw invalid(
                "\(label) must be greater than the document tolerance of "
                    + threshold.text + " " + threshold.unit.symbol + "."
            )
        }
        return value
    }

    private func number(_ text: String, label: String) throws -> Double {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)), value.isFinite else {
            throw invalid("\(label) must be a finite number.")
        }
        return value
    }

    private func invalid(_ message: String) -> EditorError {
        EditorError(code: .commandInvalid, message: message)
    }
}
