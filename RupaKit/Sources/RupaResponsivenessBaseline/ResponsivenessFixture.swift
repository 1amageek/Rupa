import Foundation
import RupaCoreTypes
import RupaEvaluation
import RupaGeometry
import RupaProjectModel
import RupaViewportScene
import SwiftCAD

/// The fixed multi-body fixture every responsiveness baseline is recorded
/// against.
///
/// The fixture models the shape a valid multi-body workflow actually produces:
/// several cylindrical bodies whose lateral surfaces are tessellated at the
/// segment count `TessellationOptions.standard` implies. Its faces are
/// triangles because that is what B-rep tessellation emits.
public struct ResponsivenessFixture: Sendable {
    /// The versioned parameters that fully determine the fixture content.
    public struct Parameters: Equatable, Sendable, Codable {
        public var version: Int
        public var name: String
        public var bodyCount: Int
        public var segmentCount: Int
        public var baseRadiusMeters: Double
        public var radiusStepMeters: Double
        public var lengthMeters: Double
        public var bodySpacingMeters: Double

        public init(
            version: Int,
            name: String,
            bodyCount: Int,
            segmentCount: Int,
            baseRadiusMeters: Double,
            radiusStepMeters: Double,
            lengthMeters: Double,
            bodySpacingMeters: Double
        ) {
            self.version = version
            self.name = name
            self.bodyCount = bodyCount
            self.segmentCount = segmentCount
            self.baseRadiusMeters = baseRadiusMeters
            self.radiusStepMeters = radiusStepMeters
            self.lengthMeters = lengthMeters
            self.bodySpacingMeters = bodySpacingMeters
        }

        /// The segment count a full circle receives under the standard
        /// tessellation options, which is what the product evaluates with.
        public static var standardFullCircleSegmentCount: Int {
            Int(ceil(2.0 * Double.pi / TessellationOptions.standard.angularTolerance))
        }

        public static let standard = Parameters(
            version: 1,
            name: "multi-body-cylinder-assembly",
            bodyCount: 12,
            segmentCount: Parameters.standardFullCircleSegmentCount,
            baseRadiusMeters: 0.030,
            radiusStepMeters: 0.002,
            lengthMeters: 0.45,
            bodySpacingMeters: 0.20
        )

        /// The triangle count the parameters predict, used to prove the plan
        /// admitted the whole fixture.
        public var predictedTriangleCount: Int {
            // Two lateral triangles and two cap triangles per segment, per body.
            bodyCount * segmentCount * 4
        }

        func validate() throws {
            guard version > 0 else {
                throw ResponsivenessBaselineError(
                    code: .invalidFixtureParameters,
                    message: "Fixture version must be positive."
                )
            }
            guard !name.isEmpty else {
                throw ResponsivenessBaselineError(
                    code: .invalidFixtureParameters,
                    message: "Fixture name must not be empty."
                )
            }
            guard bodyCount > 0 else {
                throw ResponsivenessBaselineError(
                    code: .invalidFixtureParameters,
                    message: "Fixture body count must be positive."
                )
            }
            guard segmentCount >= 3 else {
                throw ResponsivenessBaselineError(
                    code: .invalidFixtureParameters,
                    message: "Fixture segment count must be at least three."
                )
            }
            guard baseRadiusMeters.isFinite,
                  baseRadiusMeters > 0.0,
                  radiusStepMeters.isFinite,
                  radiusStepMeters >= 0.0,
                  lengthMeters.isFinite,
                  lengthMeters > 0.0,
                  bodySpacingMeters.isFinite,
                  bodySpacingMeters > 0.0 else {
                throw ResponsivenessBaselineError(
                    code: .invalidFixtureParameters,
                    message: "Fixture dimensions must be finite and positive."
                )
            }
        }
    }

    public let parameters: Parameters
    public let scene: UniversalViewportScene
    /// SHA-256 over the materialized positions and face corner references.
    public let contentDigest: String
    public let vertexCount: Int
    public let faceCount: Int

    public static func build(_ parameters: Parameters = .standard) throws -> ResponsivenessFixture {
        try parameters.validate()

        var hasher = StableSHA256Hasher()
        hasher.update(string: "rupa-responsiveness-fixture-v\(parameters.version)")
        hasher.update(string: parameters.name)
        hasher.update(count: parameters.bodyCount)
        hasher.update(count: parameters.segmentCount)

        var totalVertexCount = 0
        var totalFaceCount = 0
        var objectDefinitions: [ObjectDefinitionID: ObjectDefinition] = [:]
        var occurrences: [SceneOccurrenceID: SceneOccurrence] = [:]
        var evaluatedOccurrences: [SceneOccurrenceID: EvaluatedOccurrenceSnapshot] = [:]
        var authoredMeshAssets: [GeometrySourceID: AuthoredMeshAsset] = [:]
        var rootOccurrenceIDs: [SceneOccurrenceID] = []

        for bodyIndex in 0..<parameters.bodyCount {
            let sourceID = GeometrySourceID(
                rawValue: "mesh.\(parameters.name).\(bodyIndex)"
            )
            let radius = parameters.baseRadiusMeters
                + parameters.radiusStepMeters * Double(bodyIndex)
            let mesh = try makeCylinderSource(
                identity: sourceID,
                radiusMeters: radius,
                lengthMeters: parameters.lengthMeters,
                segmentCount: parameters.segmentCount,
                hasher: &hasher
            )
            totalVertexCount += 2 * parameters.segmentCount + 2
            totalFaceCount += 4 * parameters.segmentCount

            let definitionID = ObjectDefinitionID(
                rawValue: "object.\(parameters.name).\(bodyIndex)"
            )
            let representationID = GeometryRepresentationID(
                rawValue: "representation.\(parameters.name).\(bodyIndex)"
            )
            let occurrenceID = SceneOccurrenceID(
                rawValue: "occurrence.\(parameters.name).\(bodyIndex)"
            )
            let reference = GeometrySourceReference.authoredMesh(sourceID)
            let transform = try translation(
                x: Double(bodyIndex) * parameters.bodySpacingMeters,
                y: 0.0,
                z: 0.0
            )

            objectDefinitions[definitionID] = ObjectDefinition(
                id: definitionID,
                name: "Body \(bodyIndex)",
                representations: GeometryRepresentationSet(
                    representations: [
                        representationID: GeometryRepresentation(
                            id: representationID,
                            source: reference
                        ),
                    ],
                    selection: GeometryRepresentationSelection(
                        modeling: representationID,
                        presentation: representationID
                    )
                )
            )
            occurrences[occurrenceID] = SceneOccurrence(
                id: occurrenceID,
                definitionID: definitionID
            )
            do {
                evaluatedOccurrences[occurrenceID] = EvaluatedOccurrenceSnapshot(
                    occurrenceID: occurrenceID,
                    definitionID: definitionID,
                    representationID: representationID,
                    reference: reference,
                    mesh: mesh,
                    worldTransform: transform,
                    worldBounds: try mesh.bounds().transformed(by: transform)
                )
                authoredMeshAssets[sourceID] = try AuthoredMeshAsset(
                    source: mesh,
                    provenance: .created
                )
            } catch let error as ResponsivenessBaselineError {
                throw error
            } catch {
                throw ResponsivenessBaselineError(
                    code: .fixtureConstructionFailed,
                    message: "Fixture body \(bodyIndex) could not be published: \(error)."
                )
            }
            rootOccurrenceIDs.append(occurrenceID)
        }

        let projectID = ProjectID(rawValue: "project.\(parameters.name)")
        let scene: UniversalViewportScene
        do {
            let project = try ProjectSourceModel(
                id: projectID,
                name: "Responsiveness baseline",
                authoredMeshAssets: authoredMeshAssets,
                objectDefinitions: objectDefinitions,
                occurrences: occurrences,
                rootOccurrenceIDs: rootOccurrenceIDs
            )
            let snapshot = EvaluatedProjectSnapshot(
                id: EvaluationSnapshotID(
                    projectID: projectID,
                    purpose: .presentation,
                    sourceRevision: DocumentTransactionRevision()
                ),
                projectID: projectID,
                occurrences: evaluatedOccurrences,
                copyTelemetry: GeometryCopyTelemetry()
            )
            scene = try UniversalViewportSceneBuilder().build(
                from: snapshot,
                project: project
            )
        } catch {
            throw ResponsivenessBaselineError(
                code: .sceneConstructionFailed,
                message: "The fixture scene could not be built: \(error)."
            )
        }

        return ResponsivenessFixture(
            parameters: parameters,
            scene: scene,
            contentDigest: hasher.hexDigest(),
            vertexCount: totalVertexCount,
            faceCount: totalFaceCount
        )
    }

    /// Builds one cylinder whose faces are triangles, hashing every position and
    /// every face corner reference as it is materialized.
    private static func makeCylinderSource(
        identity: GeometrySourceID,
        radiusMeters: Double,
        lengthMeters: Double,
        segmentCount: Int,
        hasher: inout StableSHA256Hasher
    ) throws -> MeshSource {
        var builder = MeshSourceBuilder(identity: identity)
        hasher.update(string: identity.rawValue)
        do {
            try builder.reserveCapacity(
                vertexCount: 2 * segmentCount + 2,
                faceCount: 4 * segmentCount,
                cornerCount: 12 * segmentCount
            )
        } catch {
            throw ResponsivenessBaselineError(
                code: .fixtureConstructionFailed,
                message: "Fixture \(identity.rawValue) could not reserve capacity: \(error)."
            )
        }

        var bottomVertices: [MeshVertexID] = []
        var topVertices: [MeshVertexID] = []
        bottomVertices.reserveCapacity(segmentCount)
        topVertices.reserveCapacity(segmentCount)

        let bottomCenter = try addVertex(
            GeometryPoint3D(x: 0.0, y: 0.0, z: 0.0),
            to: &builder,
            identity: identity,
            hasher: &hasher
        )
        let topCenter = try addVertex(
            GeometryPoint3D(x: 0.0, y: 0.0, z: lengthMeters),
            to: &builder,
            identity: identity,
            hasher: &hasher
        )
        for index in 0..<segmentCount {
            let angle = 2.0 * Double.pi * Double(index) / Double(segmentCount)
            let x = radiusMeters * cos(angle)
            let y = radiusMeters * sin(angle)
            bottomVertices.append(
                try addVertex(
                    GeometryPoint3D(x: x, y: y, z: 0.0),
                    to: &builder,
                    identity: identity,
                    hasher: &hasher
                )
            )
            topVertices.append(
                try addVertex(
                    GeometryPoint3D(x: x, y: y, z: lengthMeters),
                    to: &builder,
                    identity: identity,
                    hasher: &hasher
                )
            )
        }

        for index in 0..<segmentCount {
            let nextIndex = (index + 1) % segmentCount
            // Lateral quad, emitted as the two triangles tessellation produces.
            try addTriangle(
                bottomVertices[index],
                bottomVertices[nextIndex],
                topVertices[nextIndex],
                corners: (2 + 2 * index, 2 + 2 * nextIndex, 3 + 2 * nextIndex),
                to: &builder,
                identity: identity,
                hasher: &hasher
            )
            try addTriangle(
                bottomVertices[index],
                topVertices[nextIndex],
                topVertices[index],
                corners: (2 + 2 * index, 3 + 2 * nextIndex, 3 + 2 * index),
                to: &builder,
                identity: identity,
                hasher: &hasher
            )
            // Cap fans, wound outward from each centre vertex.
            try addTriangle(
                bottomCenter,
                bottomVertices[nextIndex],
                bottomVertices[index],
                corners: (0, 2 + 2 * nextIndex, 2 + 2 * index),
                to: &builder,
                identity: identity,
                hasher: &hasher
            )
            try addTriangle(
                topCenter,
                topVertices[index],
                topVertices[nextIndex],
                corners: (1, 3 + 2 * index, 3 + 2 * nextIndex),
                to: &builder,
                identity: identity,
                hasher: &hasher
            )
        }

        do {
            return try builder.build()
        } catch {
            throw ResponsivenessBaselineError(
                code: .fixtureConstructionFailed,
                message: "Fixture \(identity.rawValue) failed to build: \(error)."
            )
        }
    }

    private static func addVertex(
        _ point: GeometryPoint3D,
        to builder: inout MeshSourceBuilder,
        identity: GeometrySourceID,
        hasher: inout StableSHA256Hasher
    ) throws -> MeshVertexID {
        hasher.update(point.x.bitPattern)
        hasher.update(point.y.bitPattern)
        hasher.update(point.z.bitPattern)
        do {
            return try builder.addVertex(point)
        } catch {
            throw ResponsivenessBaselineError(
                code: .fixtureConstructionFailed,
                message: "Fixture \(identity.rawValue) rejected a vertex: \(error)."
            )
        }
    }

    private static func addTriangle(
        _ first: MeshVertexID,
        _ second: MeshVertexID,
        _ third: MeshVertexID,
        corners: (Int, Int, Int),
        to builder: inout MeshSourceBuilder,
        identity: GeometrySourceID,
        hasher: inout StableSHA256Hasher
    ) throws {
        hasher.update(count: corners.0)
        hasher.update(count: corners.1)
        hasher.update(count: corners.2)
        do {
            _ = try builder.addFace(vertexIDs: [first, second, third])
        } catch {
            throw ResponsivenessBaselineError(
                code: .fixtureConstructionFailed,
                message: "Fixture \(identity.rawValue) rejected a face: \(error)."
            )
        }
    }

    private static func translation(
        x: Double,
        y: Double,
        z: Double
    ) throws -> GeometryTransform3D {
        do {
            return try GeometryTransform3D(values: [
                1, 0, 0, x,
                0, 1, 0, y,
                0, 0, 1, z,
                0, 0, 0, 1,
            ])
        } catch {
            throw ResponsivenessBaselineError(
                code: .fixtureConstructionFailed,
                message: "Fixture placement transform is invalid: \(error)."
            )
        }
    }
}
