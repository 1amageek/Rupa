import Foundation
import RupaCore
import SwiftUI
import RupaViewportScene

struct ViewportVertexHandle: Equatable {
    var vertex: ViewportBodyVertex
    var position: ViewportModelPoint3D
    var point: CGPoint
}

struct ViewportFaceHandle: Equatable {
    var face: ViewportBodyFace
    var position: ViewportModelPoint3D
    var point: CGPoint
}

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

struct ViewportModelVector3D: Equatable {
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

struct ViewportObjectOrientation: Equatable {
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

struct ViewportProjectedBox {
    var minXMinYMinZ: CGPoint
    var maxXMinYMinZ: CGPoint
    var minXMaxYMinZ: CGPoint
    var maxXMaxYMinZ: CGPoint
    var minXMinYMaxZ: CGPoint
    var maxXMinYMaxZ: CGPoint
    var minXMaxYMaxZ: CGPoint
    var maxXMaxYMaxZ: CGPoint

    var faces: [[CGPoint]] {
        [
            [minXMinYMinZ, minXMinYMaxZ, minXMaxYMaxZ, minXMaxYMinZ],
            [maxXMinYMinZ, maxXMaxYMinZ, maxXMaxYMaxZ, maxXMinYMaxZ],
            [minXMinYMinZ, maxXMinYMinZ, maxXMinYMaxZ, minXMinYMaxZ],
            [minXMaxYMinZ, minXMaxYMaxZ, maxXMaxYMaxZ, maxXMaxYMinZ],
            [minXMinYMinZ, minXMaxYMinZ, maxXMaxYMinZ, maxXMinYMinZ],
            [minXMinYMaxZ, maxXMinYMaxZ, maxXMaxYMaxZ, minXMaxYMaxZ],
        ]
    }

    var edges: [(start: CGPoint, end: CGPoint)] {
        [
            (minXMinYMinZ, maxXMinYMinZ),
            (minXMinYMinZ, minXMaxYMinZ),
            (maxXMinYMinZ, maxXMaxYMinZ),
            (minXMaxYMinZ, maxXMaxYMinZ),
            (minXMinYMaxZ, maxXMinYMaxZ),
            (minXMinYMaxZ, minXMaxYMaxZ),
            (maxXMinYMaxZ, maxXMaxYMaxZ),
            (minXMaxYMaxZ, maxXMaxYMaxZ),
            (minXMinYMinZ, minXMinYMaxZ),
            (maxXMinYMinZ, maxXMinYMaxZ),
            (minXMaxYMinZ, minXMaxYMaxZ),
            (maxXMaxYMinZ, maxXMaxYMaxZ),
        ]
    }
}

struct ViewportObjectEditState: Equatable {
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
        zMax: CGFloat
    ) {
        self.xMin = xMin
        self.xMax = xMax
        self.yMin = yMin
        self.yMax = yMax
        self.zMin = zMin
        self.zMax = zMax
        self.orientation = .identity
        normalize()
    }

    func projectedBodyProjection(layout: ViewportLayout) -> ViewportBodyProjection {
        let frontFootprint = projectedFootprint(y: yMin, layout: layout)
        let backFootprint = projectedFootprint(y: yMax, layout: layout)
        return ViewportBodyProjection(
            frontFootprint: frontFootprint,
            backFootprint: backFootprint,
            offset: CGSize(
                width: backFootprint.center.x - frontFootprint.center.x,
                height: backFootprint.center.y - frontFootprint.center.y
            )
        )
    }

    func applying(
        action: ViewportAffordanceAction,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> ViewportObjectEditState {
        var next = self
        switch action {
        case .translate(let axis):
            next.translate(axis, by: dragAmount(axis: axis, start: start, current: current, layout: layout))
        case .oneSidedScale(let axis):
            next.resizePositive(axis, by: dragAmount(axis: axis, start: start, current: current, layout: layout))
        case .centerScale(let axis):
            next.resizeFromCenter(axis, by: dragAmount(axis: axis, start: start, current: current, layout: layout))
        case .rotate(let axis):
            next.rotate(axis, by: rotationAmount(axis: axis, start: start, current: current, layout: layout))
        case .vertexMove(let vertex):
            next.moveVertex(vertex, start: start, current: current, layout: layout)
        case .profileCornerMove(_, let vertex):
            next.moveProfileCorner(vertex, start: start, current: current, layout: layout)
        case .profileFaceMove(_, let face):
            next.moveFace(face, start: start, current: current, layout: layout)
        case .profileEdgeChamfer, .profileEdgeFillet:
            break
        case .faceMove(let face):
            next.moveFace(face, start: start, current: current, layout: layout)
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

    func projectedPoint(
        _ point: ViewportModelPoint3D,
        layout: ViewportLayout
    ) -> CGPoint {
        projectedPoint(x: point.x, y: point.y, z: point.z, layout: layout)
    }

    func projectedAxisBasis(layout: ViewportLayout) -> ViewportProjectionBasis {
        ViewportProjectionBasis(
            mode: .orbit,
            xDirection: projectedAxisDirection(.x, layout: layout),
            yDirection: projectedAxisDirection(.y, layout: layout),
            zDirection: projectedAxisDirection(.z, layout: layout)
        )
    }

    func projectedAxisDirection(
        _ axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> CGVector {
        projectedAxisVector(axis, layout: layout).normalized
    }

    func modelLength(
        forViewportLength length: CGFloat,
        axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> CGFloat {
        length / max(projectedAxisVector(axis, layout: layout).length, 1.0e-9)
    }

    func projectedCube(
        center: ViewportModelPoint3D,
        sideLength: CGFloat,
        layout: ViewportLayout
    ) -> ViewportProjectedBox {
        let halfSide = sideLength / 2.0
        return ViewportProjectedBox(
            minXMinYMinZ: projectedPoint(
                ViewportModelPoint3D(x: center.x - halfSide, y: center.y - halfSide, z: center.z - halfSide),
                layout: layout
            ),
            maxXMinYMinZ: projectedPoint(
                ViewportModelPoint3D(x: center.x + halfSide, y: center.y - halfSide, z: center.z - halfSide),
                layout: layout
            ),
            minXMaxYMinZ: projectedPoint(
                ViewportModelPoint3D(x: center.x - halfSide, y: center.y + halfSide, z: center.z - halfSide),
                layout: layout
            ),
            maxXMaxYMinZ: projectedPoint(
                ViewportModelPoint3D(x: center.x + halfSide, y: center.y + halfSide, z: center.z - halfSide),
                layout: layout
            ),
            minXMinYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: center.x - halfSide, y: center.y - halfSide, z: center.z + halfSide),
                layout: layout
            ),
            maxXMinYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: center.x + halfSide, y: center.y - halfSide, z: center.z + halfSide),
                layout: layout
            ),
            minXMaxYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: center.x - halfSide, y: center.y + halfSide, z: center.z + halfSide),
                layout: layout
            ),
            maxXMaxYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: center.x + halfSide, y: center.y + halfSide, z: center.z + halfSide),
                layout: layout
            )
        )
    }

    func projectedBox(layout: ViewportLayout) -> ViewportProjectedBox {
        ViewportProjectedBox(
            minXMinYMinZ: projectedPoint(
                ViewportModelPoint3D(x: xMin, y: yMin, z: zMin),
                layout: layout
            ),
            maxXMinYMinZ: projectedPoint(
                ViewportModelPoint3D(x: xMax, y: yMin, z: zMin),
                layout: layout
            ),
            minXMaxYMinZ: projectedPoint(
                ViewportModelPoint3D(x: xMin, y: yMax, z: zMin),
                layout: layout
            ),
            maxXMaxYMinZ: projectedPoint(
                ViewportModelPoint3D(x: xMax, y: yMax, z: zMin),
                layout: layout
            ),
            minXMinYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: xMin, y: yMin, z: zMax),
                layout: layout
            ),
            maxXMinYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: xMax, y: yMin, z: zMax),
                layout: layout
            ),
            minXMaxYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: xMin, y: yMax, z: zMax),
                layout: layout
            ),
            maxXMaxYMaxZ: projectedPoint(
                ViewportModelPoint3D(x: xMax, y: yMax, z: zMax),
                layout: layout
            )
        )
    }

    private func projectedFootprint(y: CGFloat, layout: ViewportLayout) -> ViewportProjectedRect {
        ViewportProjectedRect(
            bottomLeft: projectedPoint(x: xMin, y: y, z: zMin, layout: layout),
            bottomRight: projectedPoint(x: xMax, y: y, z: zMin, layout: layout),
            topRight: projectedPoint(x: xMax, y: y, z: zMax, layout: layout),
            topLeft: projectedPoint(x: xMin, y: y, z: zMax, layout: layout)
        )
    }

    private func projectedPoint(
        x: CGFloat,
        y: CGFloat,
        z: CGFloat,
        layout: ViewportLayout
    ) -> CGPoint {
        let rotated = rotatedPoint(x: x, y: y, z: z)
        let base = layout.project(CGPoint(x: rotated.x, y: rotated.z))
        return CGPoint(
            x: base.x + layout.basis.yDirection.dx * rotated.y * layout.scale,
            y: base.y + layout.basis.yDirection.dy * rotated.y * layout.scale
        )
    }

    private func projectedAxisVector(
        _ axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> CGVector {
        let start = projectedPoint(centerPoint, layout: layout)
        let end = projectedPoint(centerPoint.offset(axis: axis, amount: 1.0), layout: layout)
        return CGVector(dx: end.x - start.x, dy: end.y - start.y)
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

    private mutating func moveFace(
        _ face: ViewportBodyFace,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) {
        switch face {
        case .front:
            yMin += dragAmount(axis: .y, start: start, current: current, layout: layout)
        case .back:
            yMax += dragAmount(axis: .y, start: start, current: current, layout: layout)
        case .top:
            zMax += dragAmount(axis: .z, start: start, current: current, layout: layout)
        case .bottom:
            zMin += dragAmount(axis: .z, start: start, current: current, layout: layout)
        case .left:
            xMin += dragAmount(axis: .x, start: start, current: current, layout: layout)
        case .right, .side:
            xMax += dragAmount(axis: .x, start: start, current: current, layout: layout)
        }
    }

    private mutating func moveVertex(
        _ vertex: ViewportBodyVertex,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) {
        let xAmount = dragAmount(axis: .x, start: start, current: current, layout: layout)
        let yAmount = dragAmount(axis: .y, start: start, current: current, layout: layout)
        let zAmount = dragAmount(axis: .z, start: start, current: current, layout: layout)
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

    private mutating func moveProfileCorner(
        _ vertex: ViewportBodyVertex,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) {
        let delta = profileCornerDragDelta(start: start, current: current, layout: layout)
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

    func profileCornerDragDelta(
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> (x: CGFloat, y: CGFloat) {
        // Solve the 2x2 system delta = a * vx + b * vz instead of projecting
        // the screen delta onto each axis independently: the projected x/z
        // axes are not orthogonal on screen in isometric views, so independent
        // projections cross-bleed (dragging along the x grid direction also
        // moved the corner in z) and the corner drifted off the cursor.
        let xVector = projectedAxisVector(.x, layout: layout)
        let zVector = projectedAxisVector(.z, layout: layout)
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let determinant = xVector.dx * zVector.dy - xVector.dy * zVector.dx
        let degenerateDeterminant = 1.0e-6 * xVector.length * zVector.length
        guard abs(determinant) > degenerateDeterminant else {
            // Edge-on view: the axes project to near-parallel screen
            // directions and the planar system has no unique solution; keep
            // the independent projections there.
            return (
                x: dragAmount(axis: .x, start: start, current: current, layout: layout),
                y: dragAmount(axis: .z, start: start, current: current, layout: layout)
            )
        }
        let xAmount = (delta.dx * zVector.dy - delta.dy * zVector.dx) / determinant
        let zAmount = (xVector.dx * delta.dy - xVector.dy * delta.dx) / determinant
        return (x: xAmount, y: zAmount)
    }

    func profileFaceDragDistance(
        _ face: ViewportBodyFace,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat? {
        let xDelta = dragAmount(axis: .x, start: start, current: current, layout: layout)
        let yDelta = dragAmount(axis: .y, start: start, current: current, layout: layout)
        let zDelta = dragAmount(axis: .z, start: start, current: current, layout: layout)
        guard let distance = ViewportProfileFaceDragMapping.distance(
            for: face,
            xDelta: Double(xDelta),
            yDelta: Double(yDelta),
            zDelta: Double(zDelta)
        ) else {
            return nil
        }
        return CGFloat(distance)
    }

    func profileEdgeChamferDistance(
        _ edge: ViewportBodyEdge,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat? {
        let xDelta = dragAmount(axis: .x, start: start, current: current, layout: layout)
        let zDelta = dragAmount(axis: .z, start: start, current: current, layout: layout)
        guard let distance = ViewportProfileEdgeChamferMapping.distance(
            for: edge,
            xDelta: Double(xDelta),
            zDelta: Double(zDelta)
        ) else {
            return nil
        }
        return CGFloat(distance)
    }

    func profileEdgeFilletRadius(
        _ edge: ViewportBodyEdge,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat? {
        let xDelta = dragAmount(axis: .x, start: start, current: current, layout: layout)
        let zDelta = dragAmount(axis: .z, start: start, current: current, layout: layout)
        guard let radius = ViewportProfileEdgeFilletMapping.radius(
            for: edge,
            xDelta: Double(xDelta),
            zDelta: Double(zDelta)
        ) else {
            return nil
        }
        return CGFloat(radius)
    }

    private func dragAmount(
        axis: ViewportCoordinateAxis,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat {
        let axisVector = projectedAxisVector(axis, layout: layout)
        let direction = axisVector.normalized
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        return (delta.dx * direction.dx + delta.dy * direction.dy) / max(axisVector.length, 1.0e-9)
    }

    private func rotationAmount(
        axis: ViewportCoordinateAxis,
        start: CGPoint,
        current: CGPoint,
        layout: ViewportLayout
    ) -> CGFloat {
        let center = projectedPoint(centerPoint, layout: layout)
        let plane = rotationPlaneDirections(for: axis, layout: layout)
        let startAngle = rotationPlaneAngle(for: start, center: center, plane: plane)
        let currentAngle = rotationPlaneAngle(for: current, center: center, plane: plane)
        return normalizedRotationDelta(from: startAngle, to: currentAngle)
    }

    private func rotationPlaneDirections(
        for axis: ViewportCoordinateAxis,
        layout: ViewportLayout
    ) -> (first: CGVector, second: CGVector) {
        switch axis {
        case .x:
            (projectedAxisDirection(.y, layout: layout), projectedAxisDirection(.z, layout: layout))
        case .y:
            (projectedAxisDirection(.z, layout: layout), projectedAxisDirection(.x, layout: layout))
        case .z:
            (projectedAxisDirection(.x, layout: layout), projectedAxisDirection(.y, layout: layout))
        }
    }

    private func rotationPlaneAngle(
        for point: CGPoint,
        center: CGPoint,
        plane: (first: CGVector, second: CGVector)
    ) -> CGFloat {
        let vector = CGVector(dx: point.x - center.x, dy: point.y - center.y)
        let determinant = plane.first.dx * plane.second.dy - plane.first.dy * plane.second.dx
        guard abs(determinant) > 1.0e-6 else {
            return atan2(vector.dy, vector.dx)
        }
        let firstAmount = (vector.dx * plane.second.dy - vector.dy * plane.second.dx) / determinant
        let secondAmount = (plane.first.dx * vector.dy - plane.first.dy * vector.dx) / determinant
        return atan2(secondAmount, firstAmount)
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
