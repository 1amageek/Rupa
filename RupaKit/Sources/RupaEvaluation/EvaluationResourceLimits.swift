/// A checked cumulative ceiling for one complete project evaluation.
///
/// The ceilings bound the whole invocation, not one source, so an evaluation
/// cannot exhaust memory by requesting many admissible sources. A caller may
/// only narrow them through `lowered(to:)`; `validate()` refuses any value that
/// exceeds `hardCeiling`, so a product policy can never widen what this module
/// owns.
public struct EvaluationResourceLimits: Codable, Equatable, Hashable, Sendable {
    public var maximumSourceCount: Int
    public var maximumVertexCount: Int
    public var maximumFaceCount: Int
    public var maximumCornerCount: Int
    public var maximumTriangleCount: Int
    public var maximumByteCount: Int

    public init(
        maximumSourceCount: Int,
        maximumVertexCount: Int,
        maximumFaceCount: Int,
        maximumCornerCount: Int,
        maximumTriangleCount: Int,
        maximumByteCount: Int
    ) {
        self.maximumSourceCount = maximumSourceCount
        self.maximumVertexCount = maximumVertexCount
        self.maximumFaceCount = maximumFaceCount
        self.maximumCornerCount = maximumCornerCount
        self.maximumTriangleCount = maximumTriangleCount
        self.maximumByteCount = maximumByteCount
    }

    /// The widest ceiling this module admits.
    ///
    /// The mesh dimensions are at or above the matching `TessellationLimits`
    /// hard ceiling swift-CAD owns (vertices `8_388_608`, indices `50_331_648`
    /// which a `MeshSource` records as corners, triangles `16_777_216`), so a
    /// CAD request derived from an allowance can only lower the kernel ceiling
    /// and never widen it. `maximumByteCount` is four times the kernel's
    /// `402_653_184`, because a `MeshSource` stores per-element identity and
    /// per-corner topology the kernel's position-and-index mesh does not. The
    /// factor is derived, not measured: RESPI-0.4 recorded both byte rows as
    /// `notMeasured`, so the two footprints are computed from the recorded
    /// element counts and the two representations' strides, giving roughly
    /// 44.6 MB as a `MeshSource` against roughly 10.9 MB as a kernel `Mesh`.
    /// `maximumSourceCount` bounds the distinct geometry sources one evaluation
    /// resolves.
    public static let hardCeiling = EvaluationResourceLimits(
        maximumSourceCount: 4_096,
        maximumVertexCount: 8_388_608,
        maximumFaceCount: 16_777_216,
        maximumCornerCount: 50_331_648,
        maximumTriangleCount: 16_777_216,
        maximumByteCount: 1_610_612_736
    )

    /// The ceiling an evaluation uses when the product states no narrower one.
    ///
    /// Every dimension is a quarter of `hardCeiling`, which admits the recorded
    /// RESPI-0.4 `multi-body-cylinder-assembly` v1 fixture (12 sources, 150,840
    /// vertices, 301,632 faces, 904,896 corners, 301,632 triangles) with about
    /// fourteen times headroom on the element dimensions. Its footprint is
    /// derived rather than measured, because RESPI-0.4 recorded both byte rows
    /// as `notMeasured`: the fixture's bodies are closed triangulated manifolds,
    /// so each body's edge count is three halves of its face count, and the
    /// buffers `MeshSource.resourceUsage()` charges come to 44,642,304 bytes,
    /// which leaves about nine times headroom on bytes. The fixture is the
    /// largest content this project has measured end to end, so the headroom
    /// bounds growth without refusing work the application is known to perform.
    public static let standard = EvaluationResourceLimits(
        maximumSourceCount: 1_024,
        maximumVertexCount: 2_097_152,
        maximumFaceCount: 4_194_304,
        maximumCornerCount: 12_582_912,
        maximumTriangleCount: 4_194_304,
        maximumByteCount: 402_653_184
    )

    public func limit(for resource: EvaluationResource) -> Int {
        switch resource {
        case .sourceCount: maximumSourceCount
        case .vertexCount: maximumVertexCount
        case .faceCount: maximumFaceCount
        case .cornerCount: maximumCornerCount
        case .triangleCount: maximumTriangleCount
        case .byteCount: maximumByteCount
        }
    }

    /// Refuses a ceiling that admits nothing or that widens what this module owns.
    public func validate() throws {
        for resource in EvaluationResource.allCases {
            let value = limit(for: resource)
            guard value > 0, value <= Self.hardCeiling.limit(for: resource) else {
                throw EvaluationError(
                    code: .invalidLimit,
                    message: "Evaluation resource limit \(resource.rawValue) must be positive and "
                        + "at most \(Self.hardCeiling.limit(for: resource)), not \(value)."
                )
            }
        }
    }

    /// The narrower of the two ceilings in every dimension.
    public func lowered(to other: EvaluationResourceLimits) -> EvaluationResourceLimits {
        EvaluationResourceLimits(
            maximumSourceCount: min(maximumSourceCount, other.maximumSourceCount),
            maximumVertexCount: min(maximumVertexCount, other.maximumVertexCount),
            maximumFaceCount: min(maximumFaceCount, other.maximumFaceCount),
            maximumCornerCount: min(maximumCornerCount, other.maximumCornerCount),
            maximumTriangleCount: min(maximumTriangleCount, other.maximumTriangleCount),
            maximumByteCount: min(maximumByteCount, other.maximumByteCount)
        )
    }
}
