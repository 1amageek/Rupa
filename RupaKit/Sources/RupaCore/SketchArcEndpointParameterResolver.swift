import Foundation
import SwiftCAD
import RupaCoreTypes

struct SketchArcEndpointParameterResolver: Sendable {
    struct EndpointParameters: Equatable, Sendable {
        var start: Double
        var end: Double
    }

    func endpointParameters(
        for arc: SketchArc,
        plane: SketchPlane,
        in document: DesignDocument,
        owner: String
    ) throws -> EndpointParameters {
        let center = try resolvedPoint(
            arc.center,
            document: document,
            owner: "\(owner) arc center"
        )
        let radius = try resolvedLength(
            arc.radius,
            document: document,
            owner: "\(owner) arc radius"
        )
        let startAngle = try resolvedAngle(
            arc.startAngle,
            document: document,
            owner: "\(owner) arc start angle"
        )
        let endAngle = try resolvedAngle(
            arc.endAngle,
            document: document,
            owner: "\(owner) arc end angle"
        )
        let span = try normalizedPartialArcSpan(startAngle: startAngle, endAngle: endAngle)
        let startPoint = Point2D(
            x: center.x + cos(startAngle) * radius,
            y: center.y + sin(startAngle) * radius
        )
        let circle = Circle3D(
            center: try mapTo3D(center, on: plane),
            normal: try planeNormal(for: plane),
            radius: radius
        )
        let startParameter = try circleParameter(
            for: try mapTo3D(startPoint, on: plane),
            on: circle
        )
        return EndpointParameters(
            start: startParameter,
            end: startParameter + span
        )
    }

    private func resolvedPoint(
        _ point: SketchPoint,
        document: DesignDocument,
        owner: String
    ) throws -> Point2D {
        Point2D(
            x: try resolvedLength(point.x, document: document, owner: "\(owner).x"),
            y: try resolvedLength(point.y, document: document, owner: "\(owner).y")
        )
    }

    private func resolvedLength(
        _ expression: CADExpression,
        document: DesignDocument,
        owner: String
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a length."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite length."
            )
        }
        return quantity.value
    }

    private func resolvedAngle(
        _ expression: CADExpression,
        document: DesignDocument,
        owner: String
    ) throws -> Double {
        let quantity = try document.cadDocument.parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to an angle."
            )
        }
        guard quantity.value.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) must resolve to a finite angle."
            )
        }
        return quantity.value
    }

    private func normalizedPartialArcSpan(
        startAngle: Double,
        endAngle: Double
    ) throws -> Double {
        let fullCircle = Double.pi * 2.0
        var span = endAngle - startAngle
        while span <= ModelingTolerance.standard.angle {
            span += fullCircle
        }
        while span > fullCircle + ModelingTolerance.standard.angle {
            span -= fullCircle
        }
        guard span > ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch arc endpoint parameters require a positive arc span."
            )
        }
        guard span < fullCircle - ModelingTolerance.standard.angle else {
            throw EditorError(
                code: .commandInvalid,
                message: "Sketch arc endpoint parameters require a partial arc."
            )
        }
        return span
    }

    private func mapTo3D(_ point: Point2D, on plane: SketchPlane) throws -> Point3D {
        switch plane {
        case .xy:
            return Point3D(x: point.x, y: point.y, z: 0.0)
        case .yz:
            return Point3D(x: 0.0, y: point.x, z: point.y)
        case .zx:
            return Point3D(x: point.y, y: 0.0, z: point.x)
        case let .plane(plane):
            let normal = try plane.normal.normalized(tolerance: ModelingTolerance.standard.distance)
            let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            let u = try helper.cross(normal).normalized(tolerance: ModelingTolerance.standard.distance)
            let v = normal.cross(u)
            return plane.origin + (u * point.x) + (v * point.y)
        }
    }

    private func planeNormal(for plane: SketchPlane) throws -> Vector3D {
        switch plane {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        case let .plane(plane):
            return try plane.normal.normalized(tolerance: ModelingTolerance.standard.distance)
        }
    }

    private func circleParameter(for point: Point3D, on circle: Circle3D) throws -> Double {
        let (u, v) = try circleBasis(for: circle)
        let offset = point - circle.center
        return atan2(offset.dot(v), offset.dot(u))
    }

    private func circleBasis(for circle: Circle3D) throws -> (Vector3D, Vector3D) {
        let normal = try circle.normal.normalized(tolerance: ModelingTolerance.standard.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: ModelingTolerance.standard.distance)
        let v = normal.cross(u)
        return (u, v)
    }
}
