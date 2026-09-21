import Foundation
import RupaCore
import SwiftUI
import RupaViewportScene
import SwiftCAD

struct ViewportModelPoint3D: Equatable {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    func offset(axis: ViewportCoordinateAxis, amount: CGFloat) -> ViewportModelPoint3D {
        switch axis {
        case .x:
            ViewportModelPoint3D(x: x + amount, y: y, z: z)
        case .y:
            ViewportModelPoint3D(x: x, y: y + amount, z: z)
        case .z:
            ViewportModelPoint3D(x: x, y: y, z: z + amount)
        }
    }
}

struct ViewportModelVector3D: Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat

    static func + (lhs: ViewportModelVector3D, rhs: ViewportModelVector3D) -> ViewportModelVector3D {
        ViewportModelVector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func * (vector: ViewportModelVector3D, scalar: CGFloat) -> ViewportModelVector3D {
        ViewportModelVector3D(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }

    static func * (scalar: CGFloat, vector: ViewportModelVector3D) -> ViewportModelVector3D {
        vector * scalar
    }
}

struct ViewportObjectOrientation: Equatable, Sendable {
    var xAxis: ViewportModelVector3D
    var yAxis: ViewportModelVector3D
    var zAxis: ViewportModelVector3D

    static var identity: ViewportObjectOrientation {
        ViewportObjectOrientation(
            xAxis: ViewportModelVector3D(x: 1.0, y: 0.0, z: 0.0),
            yAxis: ViewportModelVector3D(x: 0.0, y: 1.0, z: 0.0),
            zAxis: ViewportModelVector3D(x: 0.0, y: 0.0, z: 1.0)
        )
    }

    var inverse: ViewportObjectOrientation {
        ViewportObjectOrientation(
            xAxis: ViewportModelVector3D(x: xAxis.x, y: yAxis.x, z: zAxis.x),
            yAxis: ViewportModelVector3D(x: xAxis.y, y: yAxis.y, z: zAxis.y),
            zAxis: ViewportModelVector3D(x: xAxis.z, y: yAxis.z, z: zAxis.z)
        )
    }

    func applied(to vector: ViewportModelVector3D) -> ViewportModelVector3D {
        xAxis * vector.x + yAxis * vector.y + zAxis * vector.z
    }

    func concatenating(_ rhs: ViewportObjectOrientation) -> ViewportObjectOrientation {
        ViewportObjectOrientation(
            xAxis: applied(to: rhs.xAxis),
            yAxis: applied(to: rhs.yAxis),
            zAxis: applied(to: rhs.zAxis)
        )
    }

    mutating func rotate(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        let cosine = cos(amount)
        let sine = sin(amount)
        switch axis {
        case .x:
            let baseY = yAxis
            let baseZ = zAxis
            yAxis = baseY * cosine + baseZ * sine
            zAxis = baseY * -sine + baseZ * cosine
        case .y:
            let baseX = xAxis
            let baseZ = zAxis
            xAxis = baseX * cosine + baseZ * -sine
            zAxis = baseX * sine + baseZ * cosine
        case .z:
            let baseX = xAxis
            let baseY = yAxis
            xAxis = baseX * cosine + baseY * sine
            yAxis = baseX * -sine + baseY * cosine
        }
    }
}

struct ViewportObjectEditState: Equatable, Sendable {
    var xMin: CGFloat
    var xMax: CGFloat
    var yMin: CGFloat
    var yMax: CGFloat
    var zMin: CGFloat
    var zMax: CGFloat
    var orientation: ViewportObjectOrientation

    private static let minimumSize: CGFloat = 1.0e-6

    init(item: ViewportSceneItem) {
        let yExtents: (min: CGFloat, max: CGFloat)
        if case .body(let component) = item.kind {
            yExtents = (
                min: CGFloat(component.yMinMeters),
                max: CGFloat(component.yMaxMeters)
            )
        } else {
            yExtents = (0.0, Self.minimumSize)
        }
        self.xMin = item.modelBounds.minX
        self.xMax = item.modelBounds.maxX
        self.yMin = yExtents.min
        self.yMax = max(yExtents.max, yExtents.min + Self.minimumSize)
        self.zMin = item.modelBounds.minY
        self.zMax = item.modelBounds.maxY
        self.orientation = .identity
    }

    init(
        xMin: CGFloat,
        xMax: CGFloat,
        yMin: CGFloat,
        yMax: CGFloat,
        zMin: CGFloat,
        zMax: CGFloat,
        preservesZeroExtents: Bool = false
    ) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
        self.zMin = zMin
        self.zMax = zMax
        self.orientation = .identity
        if !preservesZeroExtents { normalize() }
    }

    func projectedBodyProjection(layout: ViewportLayout) -> ViewportBodyProjection? {
        guard let frontFootprint = projectedFootprint(y: yMin, layout: layout),
              let backFootprint = projectedFootprint(y: yMax, layout: layout) else { return nil }
        return ViewportBodyProjection(
            frontFootprint: frontFootprint,
            backFootprint: backFootprint,
            offset: CGSize(
                width: backFootprint.center.x - frontFootprint.center.x,
                height: backFootprint.center.y - frontFootprint.center.y
            )
        )
    }

    /// Solves one affordance action against the mounted frame that drew its
    /// handle.
    ///
    /// `nil` means the pointer carried no direction the action could read, so
    /// the caller keeps the value it already had. A refusal is thrown, because
    /// a drag that cannot measure must not leave a handle following the pointer
    /// against a baseline nothing answered.
    @MainActor
    func applying(
        action: ViewportAffordanceAction,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> ViewportObjectEditState? {
        var next = self
        switch action {
        case .translate(let axis):
            next.translate(axis, by: try dragAmount(
                axis: axis, origin: centerPoint, start: start, current: current, measure: measure))
        case .oneSidedScale(let axis):
            next.resizePositive(axis, by: try dragAmount(
                axis: axis, origin: centerPoint, start: start, current: current, measure: measure))
        case .centerScale(let axis):
            next.resizeFromCenter(axis, by: try dragAmount(
                axis: axis, origin: centerPoint, start: start, current: current, measure: measure))
        case .rotate(let axis):
            guard let amount = try rotationAmount(
                axis: axis, start: start, current: current, measure: measure) else { return nil }
            next.rotate(axis, by: amount)
        case .vertexMove(let vertex):
            try next.moveVertex(vertex, start: start, current: current, measure: measure)
        case .profileCornerMove(_, let vertex):
            try next.moveProfileCorner(vertex, start: start, current: current, measure: measure)
        case .profileFaceMove(_, let face):
            try next.moveFace(face, start: start, current: current, measure: measure)
        case .profileEdgeChamfer, .profileEdgeFillet:
            break
        case .faceMove(let face):
            try next.moveFace(face, start: start, current: current, measure: measure)
        }
        next.normalize()
        return next
    }

    func transformedFromGroup(
        baseGroup: ViewportObjectEditState,
        targetGroup: ViewportObjectEditState
    ) -> ViewportObjectEditState {
        var next = self
        next.xMin = Self.map(
            xMin,
            fromMin: baseGroup.xMin,
            fromMax: baseGroup.xMax,
            toMin: targetGroup.xMin,
            toMax: targetGroup.xMax
        )
        next.xMax = Self.map(
            xMax,
            fromMin: baseGroup.xMin,
            fromMax: baseGroup.xMax,
            toMin: targetGroup.xMin,
            toMax: targetGroup.xMax
        )
        next.yMin = Self.map(
            yMin,
            fromMin: baseGroup.yMin,
            fromMax: baseGroup.yMax,
            toMin: targetGroup.yMin,
            toMax: targetGroup.yMax
        )
        next.yMax = Self.map(
            yMax,
            fromMin: baseGroup.yMin,
            fromMax: baseGroup.yMax,
            toMin: targetGroup.yMin,
            toMax: targetGroup.yMax
        )
        next.zMin = Self.map(
            zMin,
            fromMin: baseGroup.zMin,
            fromMax: baseGroup.zMax,
            toMin: targetGroup.zMin,
            toMax: targetGroup.zMax
        )
        next.zMax = Self.map(
            zMax,
            fromMin: baseGroup.zMin,
            fromMax: baseGroup.zMax,
            toMin: targetGroup.zMin,
            toMax: targetGroup.zMax
        )
        let groupRotationDelta = targetGroup.orientation.concatenating(baseGroup.orientation.inverse)
        next.orientation = groupRotationDelta.concatenating(orientation)
        next.normalize()
        return next
    }

    private static func map(
        _ value: CGFloat,
        fromMin: CGFloat,
        fromMax: CGFloat,
        toMin: CGFloat,
        toMax: CGFloat
    ) -> CGFloat {
        let sourceSpan = fromMax - fromMin
        guard abs(sourceSpan) > minimumSize else {
            return (toMin + toMax) / 2.0
        }
        let ratio = (value - fromMin) / sourceSpan
        return toMin + ratio * (toMax - toMin)
    }

    private var centerX: CGFloat { (xMin + xMax) / 2.0 }
    private var centerY: CGFloat { (yMin + yMax) / 2.0 }
    private var centerZ: CGFloat { (zMin + zMax) / 2.0 }

    var centerPoint: ViewportModelPoint3D {
        ViewportModelPoint3D(x: centerX, y: centerY, z: centerZ)
    }

    func position(for vertex: ViewportBodyVertex) -> ViewportModelPoint3D {
        ViewportModelPoint3D(
            x: vertex.usesMinX ? xMin : xMax,
            y: vertex.usesMinY ? yMin : yMax,
            z: vertex.usesMinZ ? zMin : zMax
        )
    }

    func position(for face: ViewportBodyFace) -> ViewportModelPoint3D {
        switch face {
        case .front:
            ViewportModelPoint3D(x: centerX, y: yMin, z: centerZ)
        case .back:
            ViewportModelPoint3D(x: centerX, y: yMax, z: centerZ)
        case .top:
            ViewportModelPoint3D(x: centerX, y: centerY, z: zMax)
        case .bottom:
            ViewportModelPoint3D(x: centerX, y: centerY, z: zMin)
        case .left:
            ViewportModelPoint3D(x: xMin, y: centerY, z: centerZ)
        case .right, .side:
            ViewportModelPoint3D(x: xMax, y: centerY, z: centerZ)
        }
    }

    /// The model point of one profile edge's midpoint.
    ///
    /// The profile edges run along `y`, so the midpoint is the box corner in
    /// `x` and `z` taken at the centre of the extrusion, which is the point the
    /// overlay producer draws the edge treatment handles from.
    func position(for edge: ViewportBodyEdge) -> ViewportModelPoint3D {
        switch edge {
        case .leftBottom:
            ViewportModelPoint3D(x: xMin, y: centerY, z: zMin)
        case .rightBottom:
            ViewportModelPoint3D(x: xMax, y: centerY, z: zMin)
        case .rightTop:
            ViewportModelPoint3D(x: xMax, y: centerY, z: zMax)
        case .leftTop:
            ViewportModelPoint3D(x: xMin, y: centerY, z: zMax)
        }
    }

    func projectedPoint(
        _ point: ViewportModelPoint3D,
        layout: ViewportLayout
    ) -> CGPoint? {
        projectedPoint(x: point.x, y: point.y, z: point.z, layout: layout)
    }

    private func projectedFootprint(y: CGFloat, layout: ViewportLayout) -> ViewportProjectedRect? {
        guard let bottomLeft = projectedPoint(x: xMin, y: y, z: zMin, layout: layout),
              let bottomRight = projectedPoint(x: xMax, y: y, z: zMin, layout: layout),
              let topRight = projectedPoint(x: xMax, y: y, z: zMax, layout: layout),
              let topLeft = projectedPoint(x: xMin, y: y, z: zMax, layout: layout) else { return nil }
        return ViewportProjectedRect(
            bottomLeft: bottomLeft, bottomRight: bottomRight, topRight: topRight, topLeft: topLeft
        )
    }

    func worldPoint(_ point: ViewportModelPoint3D) -> Point3D {
        let rotated = rotatedPoint(x: point.x, y: point.y, z: point.z)
        return Point3D(x: Double(rotated.x), y: Double(rotated.y), z: Double(rotated.z))
    }

    var worldBoxCorners: [Point3D] {
        (0..<8).map { index in
            worldPoint(ViewportModelPoint3D(
                x: index & 1 == 0 ? xMin : xMax,
                y: index & 2 == 0 ? yMin : yMax,
                z: index & 4 == 0 ? zMin : zMax
            ))
        }
    }

    /// The world direction of one model axis.
    ///
    /// `worldPoint` maps a model point as `centre + orientation.applied(p -
    /// centre)`, and `ViewportObjectOrientation.rotate` turns the basis rather
    /// than scaling it, so that map is an isometry: one model unit is one world
    /// metre and the three model axes stay orthonormal in world space. A drag
    /// therefore states its world axis here instead of probing the frame with a
    /// projected offset point.
    func worldAxis(_ axis: ViewportCoordinateAxis) -> Vector3D {
        let unit: ViewportModelVector3D
        switch axis {
        case .x:
            unit = ViewportModelVector3D(x: 1.0, y: 0.0, z: 0.0)
        case .y:
            unit = ViewportModelVector3D(x: 0.0, y: 1.0, z: 0.0)
        case .z:
            unit = ViewportModelVector3D(x: 0.0, y: 0.0, z: 1.0)
        }
        let rotated = orientation.applied(to: unit)
        return Vector3D(x: Double(rotated.x), y: Double(rotated.y), z: Double(rotated.z))
    }

    private func projectedPoint(
        x: CGFloat, y: CGFloat, z: CGFloat, layout: ViewportLayout
    ) -> CGPoint? {
        layout.projectedPoint(worldPoint(ViewportModelPoint3D(x: x, y: y, z: z)))?.point
    }

    private func rotatedPoint(x: CGFloat, y: CGFloat, z: CGFloat) -> (x: CGFloat, y: CGFloat, z: CGFloat) {
        let local = ViewportModelVector3D(
            x: x - centerX,
            y: y - centerY,
            z: z - centerZ
        )
        let rotated = orientation.applied(to: local)
        return (centerX + rotated.x, centerY + rotated.y, centerZ + rotated.z)
    }

    private mutating func translate(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        switch axis {
        case .x:
            xMin += amount
            xMax += amount
        case .y:
            yMin += amount
            yMax += amount
        case .z:
            zMin += amount
            zMax += amount
        }
    }

    private mutating func resizePositive(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        switch axis {
        case .x:
            xMax += amount
        case .y:
            yMax += amount
        case .z:
            zMax += amount
        }
    }

    private mutating func resizeFromCenter(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        switch axis {
        case .x:
            xMin -= amount
            xMax += amount
        case .y:
            yMin -= amount
            yMax += amount
        case .z:
            zMin -= amount
            zMax += amount
        }
    }

    private mutating func rotate(_ axis: ViewportCoordinateAxis, by amount: CGFloat) {
        orientation.rotate(axis, by: amount)
    }

    @MainActor
    private mutating func moveFace(
        _ face: ViewportBodyFace,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws {
        let amount = try dragAmount(
            axis: ViewportProfileFaceDragMapping.axis(for: face),
            origin: position(for: face),
            start: start,
            current: current,
            measure: measure
        )
        switch face {
        case .front:
            yMin += amount
        case .back:
            yMax += amount
        case .top:
            zMax += amount
        case .bottom:
            zMin += amount
        case .left:
            xMin += amount
        case .right, .side:
            xMax += amount
        }
    }

    @MainActor
    private mutating func moveVertex(
        _ vertex: ViewportBodyVertex,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws {
        // One view-plane displacement resolved on the orthonormal world axes.
        // Projecting the screen displacement onto each axis independently
        // cross-bleeds wherever the projected axes are not orthogonal on
        // screen, which is the defect the profile corner route was already
        // repaired for, and it left the dragged vertex behind the pointer in
        // isometric views.
        let anchor = worldPoint(position(for: vertex))
        let from = try measure.viewPlanePoint(at: start, through: anchor)
        let to = try measure.viewPlanePoint(at: current, through: anchor)
        let delta = try Self.displacement(from: from, to: to)
        let xAmount = CGFloat(delta.dot(worldAxis(.x)))
        let yAmount = CGFloat(delta.dot(worldAxis(.y)))
        let zAmount = CGFloat(delta.dot(worldAxis(.z)))
        if vertex.usesMinX {
            xMin += xAmount
        } else {
            xMax += xAmount
        }
        if vertex.usesMinY {
            yMin += yAmount
        } else {
            yMax += yAmount
        }
        if vertex.usesMinZ {
            zMin += zAmount
        } else {
            zMax += zAmount
        }
    }

    @MainActor
    private mutating func moveProfileCorner(
        _ vertex: ViewportBodyVertex,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws {
        let delta = try profileCornerDragDelta(
            vertex, start: start, current: current, measure: measure)
        if vertex.usesMinX {
            xMin += delta.x
        } else {
            xMax += delta.x
        }
        if vertex.usesMinZ {
            zMin += delta.y
        } else {
            zMax += delta.y
        }
    }

    /// The corner displacement in the profile sketch plane, as sketch `x` and
    /// sketch `y`, which are world `x` and world `z`.
    @MainActor
    func profileCornerDragDelta(
        _ vertex: ViewportBodyVertex,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> (x: CGFloat, y: CGFloat) {
        let delta = try profilePlaneDisplacement(
            origin: position(for: vertex), start: start, current: current, measure: measure)
        return (x: delta.x, y: delta.z)
    }

    @MainActor
    func profileFaceDragDistance(
        _ face: ViewportBodyFace,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> CGFloat? {
        // The mapping reads exactly one of the three deltas per face, so the
        // axis is chosen from the face first and only that axis is measured.
        // Asking for all three and refusing unless all three resolved made a
        // face solvable along its own axis unsolvable whenever a different axis
        // was degenerate on screen, and every axis-front camera has one.
        let axis = ViewportProfileFaceDragMapping.axis(for: face)
        let amount = Double(try dragAmount(
            axis: axis,
            origin: position(for: face),
            start: start,
            current: current,
            measure: measure
        ))
        guard let distance = ViewportProfileFaceDragMapping.distance(
            for: face,
            xDelta: axis == .x ? amount : 0.0,
            yDelta: axis == .y ? amount : 0.0,
            zDelta: axis == .z ? amount : 0.0
        ) else {
            return nil
        }
        return CGFloat(distance)
    }

    @MainActor
    func profileEdgeChamferDistance(
        _ edge: ViewportBodyEdge,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> CGFloat? {
        let delta = try profilePlaneDisplacement(
            origin: position(for: edge), start: start, current: current, measure: measure)
        guard let distance = ViewportProfileEdgeChamferMapping.distance(
            for: edge,
            xDelta: Double(delta.x),
            zDelta: Double(delta.z)
        ) else {
            return nil
        }
        return CGFloat(distance)
    }

    @MainActor
    func profileEdgeFilletRadius(
        _ edge: ViewportBodyEdge,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> CGFloat? {
        let delta = try profilePlaneDisplacement(
            origin: position(for: edge), start: start, current: current, measure: measure)
        guard let radius = ViewportProfileEdgeFilletMapping.radius(
            for: edge,
            xDelta: Double(delta.x),
            zDelta: Double(delta.z)
        ) else {
            return nil
        }
        return CGFloat(radius)
    }

    /// The signed metres travelled along one model axis, measured on the axis
    /// through `origin`.
    @MainActor
    private func dragAmount(
        axis: ViewportCoordinateAxis,
        origin: ViewportModelPoint3D,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> CGFloat {
        let delta = try measure.worldAxisDelta(
            from: start,
            to: current,
            axisOrigin: worldPoint(origin),
            axisDirection: worldAxis(axis)
        )
        guard delta.isFinite else {
            throw Self.measurementFailure("The affordance world-axis delta is not finite.")
        }
        return CGFloat(delta)
    }

    /// The displacement between two samples of the profile sketch plane,
    /// resolved on world `x` and world `z`.
    @MainActor
    private func profilePlaneDisplacement(
        origin: ViewportModelPoint3D,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> (x: CGFloat, z: CGFloat) {
        let planeOrigin = worldPoint(origin)
        let planeNormal = worldAxis(.y)
        let from = try measure.worldPlanePoint(
            at: start, planeOrigin: planeOrigin, planeNormal: planeNormal)
        let to = try measure.worldPlanePoint(
            at: current, planeOrigin: planeOrigin, planeNormal: planeNormal)
        let delta = try Self.displacement(from: from, to: to)
        return (x: CGFloat(delta.dot(worldAxis(.x))), z: CGFloat(delta.dot(worldAxis(.z))))
    }

    private static func displacement(from start: Point3D, to end: Point3D) throws -> Vector3D {
        let delta = end - start
        guard delta.isFinite else {
            throw measurementFailure("The affordance world displacement is not finite.")
        }
        return delta
    }

    /// The signed rotation between two samples of the rotation plane.
    ///
    /// The two answers are kept rather than their difference, because an angle
    /// is the difference of two absolute directions from the pivot and one
    /// displacement cannot state it.
    @MainActor
    private func rotationAmount(
        axis: ViewportCoordinateAxis,
        start: CGPoint,
        current: CGPoint,
        measure: some ViewportAffordanceMeasuring
    ) throws -> CGFloat? {
        let pivot = worldPoint(centerPoint)
        let normal = worldAxis(axis)
        let from = try measure.worldPlanePoint(
            at: start, planeOrigin: pivot, planeNormal: normal)
        let to = try measure.worldPlanePoint(
            at: current, planeOrigin: pivot, planeNormal: normal)
        let plane = rotationPlaneAxes(for: axis)
        guard let startAngle = try Self.rotationAngle(of: from, about: pivot, plane: plane),
              let currentAngle = try Self.rotationAngle(of: to, about: pivot, plane: plane) else {
            return nil
        }
        return normalizedRotationDelta(from: startAngle, to: currentAngle)
    }

    /// The ordered world basis of one rotation plane, matching the sign
    /// convention `ViewportObjectOrientation.rotate` turns the basis with.
    private func rotationPlaneAxes(
        for axis: ViewportCoordinateAxis
    ) -> (first: Vector3D, second: Vector3D) {
        switch axis {
        case .x:
            (worldAxis(.y), worldAxis(.z))
        case .y:
            (worldAxis(.z), worldAxis(.x))
        case .z:
            (worldAxis(.x), worldAxis(.y))
        }
    }

    /// `nil` means the sample carries no direction because it sits on the
    /// pivot, which leaves the caller's retained value unchanged. The basis is
    /// orthonormal because the orientation is a rigid rotation, so the collinear
    /// case the screen-space form fell back on cannot arise here; a camera that
    /// sees the rotation plane edge-on is refused by the frame instead.
    private static func rotationAngle(
        of point: Point3D,
        about pivot: Point3D,
        plane: (first: Vector3D, second: Vector3D)
    ) throws -> CGFloat? {
        let radial = point - pivot
        guard radial.isFinite else {
            throw measurementFailure("The affordance rotation sample is not finite.")
        }
        let first = radial.dot(plane.first)
        let second = radial.dot(plane.second)
        guard first.isFinite, second.isFinite else {
            throw measurementFailure("The affordance rotation basis parameters are not finite.")
        }
        guard hypot(first, second) > Self.retainedRadiusFloor else { return nil }
        return CGFloat(atan2(second, first))
    }

    /// A sample this close to the pivot carries no direction. One nanometre is
    /// far below any CAD tolerance this module works at.
    private static let retainedRadiusFloor: Double = 1.0e-9

    private static func measurementFailure(
        _ message: String
    ) -> MeshSourcePresentationRenderError {
        MeshSourcePresentationRenderError(code: .failed, message: message)
    }

    private func normalizedRotationDelta(from startAngle: CGFloat, to currentAngle: CGFloat) -> CGFloat {
        // The rotation must follow the cursor: the delta from start to current
        // is current - start. The previous start - current applied the
        // opposite rotation, so dragging the rotation affordance spun the
        // object against the cursor direction.
        var delta = currentAngle - startAngle
        while delta > .pi {
            delta -= .pi * 2.0
        }
        while delta < -.pi {
            delta += .pi * 2.0
        }
        return delta
    }

    private mutating func normalize() {
        if xMax - xMin < Self.minimumSize {
            xMax = xMin + Self.minimumSize
        }
        if yMax - yMin < Self.minimumSize {
            yMax = yMin + Self.minimumSize
        }
        if zMax - zMin < Self.minimumSize {
            zMax = zMin + Self.minimumSize
        }
    }
}
