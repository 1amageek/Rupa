import SwiftCAD
import RupaCoreTypes

public struct PatternArrayCurvePathGeometryService: Sendable {
    private let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance = .standard) {
        self.tolerance = tolerance
    }

    public func distributionGeometry(
        for curve: CurvePatternArray,
        parameters: ParameterTable,
        cadDocument: CADDocument?
    ) throws -> PatternArrayCurveDistributionGeometry {
        try curve.validate(tolerance: tolerance)
        let pathGeometry = try pathGeometry(for: curve.path, cadDocument: cadDocument)
        let distributionLength = try distributionLength(
            for: curve,
            pathLength: pathGeometry.totalLength,
            parameters: parameters
        )
        return PatternArrayCurveDistributionGeometry(
            path: pathGeometry,
            distributionLength: distributionLength
        )
    }

    public func pathGeometry(
        for path: PatternArrayCurvePath,
        cadDocument: CADDocument?
    ) throws -> PatternArrayCurvePathGeometry {
        let sampler = CurvePatternPathSampler(tolerance: tolerance)
        let geometry: CurvePatternPathSampler.Geometry
        switch path {
        case .polyline(let points, let normal):
            geometry = try sampler.geometry(
                points: points,
                referenceNormal: normal ?? .unitZ
            )
        case .sketchEntity(let featureID, let entityID):
            guard let cadDocument else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array sketch paths require a CAD document."
                )
            }
            guard let node = cadDocument.designGraph.nodes[featureID],
                  case let .sketch(sketch) = node.operation,
                  sketch.entities[entityID] != nil else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Curve pattern array sketch path could not be resolved."
                )
            }
            let resolvedParameters = try ParameterResolver().resolve(cadDocument.parameters)
            let curves = try SketchCurveExtractor(tolerance: tolerance).extractCurves(
                from: sketch,
                sourceFeatureID: featureID,
                parameters: resolvedParameters
            )
            guard let curve = curves.first(where: { $0.source == .sketchEntity(entityID) }) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Curve pattern array sketch path must reference a curve entity."
                )
            }
            geometry = try sampler.geometry(
                for: curve,
                referenceNormal: try sketchPlaneNormal(sketch.plane)
            )
        }
        return PatternArrayCurvePathGeometry(storage: geometry, tolerance: tolerance)
    }

    public func distributionLength(
        for curve: CurvePatternArray,
        pathLength: Double,
        parameters: ParameterTable
    ) throws -> Double {
        let expressionResolver = PatternArrayExpressionResolver(parameters: parameters)
        switch curve.extentMode {
        case .distance:
            let distance = try expressionResolver.lengthMeters(for: curve.extent)
            guard distance.isFinite,
                  distance > tolerance.distance,
                  distance <= pathLength + tolerance.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array distance extent must fit within the path length."
                )
            }
            return min(distance, pathLength)
        case .ratio:
            let ratio = try expressionResolver.scalarValue(for: curve.extent)
            guard ratio.isFinite,
                  ratio > 0.0,
                  ratio <= 1.0 else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array ratio extent must resolve to a scalar greater than 0 and no greater than 1."
                )
            }
            let distance = pathLength * ratio
            guard distance > tolerance.distance else {
                throw EditorError(
                    code: .commandInvalid,
                    message: "Curve pattern array ratio extent must resolve to a positive path distance."
                )
            }
            return distance
        }
    }

    private func sketchPlaneNormal(_ plane: SketchPlane) throws -> Vector3D {
        switch plane {
        case .xy:
            return .unitZ
        case .yz:
            return .unitX
        case .zx:
            return .unitY
        case .plane(let plane):
            return try plane.normal.normalized(tolerance: tolerance.distance)
        }
    }
}

public struct PatternArrayCurveDistributionGeometry: Sendable {
    public var path: PatternArrayCurvePathGeometry
    public var distributionLength: Double

    public init(
        path: PatternArrayCurvePathGeometry,
        distributionLength: Double
    ) {
        self.path = path
        self.distributionLength = distributionLength
    }
}

public struct PatternArrayCurvePathGeometry: Sendable {
    private let storage: CurvePatternPathSampler.Geometry
    private let tolerance: ModelingTolerance

    init(
        storage: CurvePatternPathSampler.Geometry,
        tolerance: ModelingTolerance
    ) {
        self.storage = storage
        self.tolerance = tolerance
    }

    public var referenceNormal: Vector3D {
        storage.referenceNormal
    }

    public var totalLength: Double {
        storage.totalLength
    }

    public var origin: Point3D {
        storage.origin
    }

    public func sample(at distance: Double) throws -> PatternArrayCurvePathSample {
        let sample = try storage.sample(at: distance, tolerance: tolerance)
        return PatternArrayCurvePathSample(
            point: sample.point,
            tangent: sample.tangent
        )
    }
}

public struct PatternArrayCurvePathSample: Sendable {
    public var point: Point3D
    public var tangent: Vector3D

    public init(
        point: Point3D,
        tangent: Vector3D
    ) {
        self.point = point
        self.tangent = tangent
    }
}
