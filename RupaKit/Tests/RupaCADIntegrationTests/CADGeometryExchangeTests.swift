import Foundation
@testable import RupaCADIntegration
import RupaEvaluation
import RupaGeometry
import SwiftCAD
import Testing

@Test(.timeLimit(.minutes(1)))
func cadGeometryExchangeImportsOBJWithExactUnitsAndAttributes() throws {
    let data = Data(
        """
        # Swift-CAD OBJ
        # unit millimeter
        v 0 0 0
        v 10 0 0
        v 0 20 0
        vt 0 0
        vt 1 0
        vt 0 1
        vn 0 0 1
        f 1/1/1 2/2/1 3/3/1
        """.utf8
    )

    let result = try withExchangeFile(data, pathExtension: "obj") { url in
        try CADGeometryExchange().import(
            from: url,
            format: .obj,
            unitForUnmarkedData: .meter,
            tolerance: .standard
        )
    }

    let mesh = try #require(result.meshes.first)
    #expect(result.cadDocument == nil)
    #expect(result.meshes.count == 1)
    #expect(result.units == UnitSystem(length: .millimeter, angle: .radian))
    #expect(result.provenance.domain == "rupa.exchange.obj.millimeter")
    #expect(result.provenance.fingerprint.algorithm == "sha256-rupa-exchange-obj-v1")
    #expect(abs(mesh.vertexPositions[1].x - 0.01) < 1.0e-12)
    #expect(abs(mesh.vertexPositions[2].y - 0.02) < 1.0e-12)
    #expect(mesh.attributes.layer(for: "cad.normal") != nil)
    #expect(mesh.attributes.layer(for: "cad.uv") != nil)
    #expect(mesh.attributes.layer(for: "cad.color") == nil)
    #expect(try mesh.resourceUsage().triangleCount == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadGeometryExchangeImportsSTLWithExactUnitsAndNormals() throws {
    let data = makeBinarySTL(
        header: "Swift-CAD binary STL unit=millimeter",
        normal: (0, 0, 1),
        points: [(0, 0, 0), (10, 0, 0), (0, 20, 0)]
    )

    let result = try withExchangeFile(data, pathExtension: "stl") { url in
        try CADGeometryExchange().import(
            from: url,
            format: .stl,
            unitForUnmarkedData: .meter,
            tolerance: .standard
        )
    }

    let mesh = try #require(result.meshes.first)
    #expect(result.units == UnitSystem(length: .millimeter, angle: .radian))
    #expect(abs(mesh.vertexPositions[1].x - 0.01) < 1.0e-12)
    #expect(abs(mesh.vertexPositions[2].y - 0.02) < 1.0e-12)
    #expect(mesh.attributes.layer(for: "cad.normal") != nil)
    #expect(try mesh.resourceUsage().faceCount == 1)
}

@Test(.timeLimit(.minutes(1)))
func cadGeometryExchangeUsesExplicitUnitOnlyForUnitlessOBJ() throws {
    let data = Data(
        """
        v 0 0 0
        v 10 0 0
        v 0 20 0
        f 1 2 3
        """.utf8
    )

    let result = try withExchangeFile(data, pathExtension: "obj") { url in
        try CADGeometryExchange().import(
            from: url,
            format: .obj,
            unitForUnmarkedData: .centimeter,
            tolerance: .standard
        )
    }

    #expect(result.units.length == .centimeter)
    #expect(result.provenance.domain == "rupa.exchange.obj.centimeter")
    let mesh = try #require(result.meshes.first)
    #expect(abs(mesh.vertexPositions[1].x - 0.1) < 1.0e-12)
}

@Test(.timeLimit(.minutes(1)))
func cadGeometryExchangeRejectsMissingUnitMalformedInputAndUnsupportedFormat() throws {
    let unitless = Data(
        """
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """.utf8
    )
    let unitlessError = try withExchangeFile(unitless, pathExtension: "obj") { url in
        do {
            _ = try CADGeometryExchange().import(
                from: url,
                format: .obj,
                tolerance: .standard
            )
            return nil as Error?
        } catch {
            return error
        }
    }
    guard let unitlessImportError = unitlessError as? ImportError else {
        Issue.record("Expected the native OBJ parser to reject an unmarked input with ImportError.invalidData.")
        return
    }
    if case .invalidData = unitlessImportError {
        // The native OBJ parser owns unit-marker validation and its typed error.
    } else {
        Issue.record("Expected the native OBJ parser to reject an unmarked input with ImportError.invalidData.")
    }

    let malformed = Data("# unit meter\nv 0 nope 0\n".utf8)
    let malformedError = try withExchangeFile(malformed, pathExtension: "obj") { url in
        do {
            _ = try CADGeometryExchange().import(
                from: url,
                format: .obj,
                tolerance: .standard
            )
            return nil as Error?
        } catch {
            return error
        }
    }
    #expect(malformedError is ImportError)

    let unsupportedError: CADGeometryExchangeError?
    do {
        _ = try CADGeometryExchange().import(
            from: URL(fileURLWithPath: "/does-not-exist.iges"),
            format: .iges,
            tolerance: .standard
        )
        unsupportedError = nil
    } catch let error as CADGeometryExchangeError {
        unsupportedError = error
    }
    #expect(unsupportedError == .unsupportedFormat(.iges))
}

@Test(.timeLimit(.minutes(1)))
func cadGeometryExchangeRejectsInputBeforeParsingWhenByteLimitIsExceeded() throws {
    let data = Data("# unit meter\nv 0 0 0\n".utf8)
    let limits = ExchangeResourceLimits(
        maximumBytes: 8,
        maximumEntities: 64,
        maximumNesting: 8,
        maximumIterations: 64,
        maximumProcessingDuration: .seconds(1)
    )
    let error: CADGeometryExchangeError?
    do {
        try withExchangeFile(data, pathExtension: "obj") { url in
            _ = try CADGeometryExchange(resourceLimits: limits).import(
                from: url,
                format: .obj,
                tolerance: .standard
            )
        }
        error = nil
    } catch let caught as CADGeometryExchangeError {
        error = caught
    }
    #expect(error == .fileTooLarge(actual: data.count, maximum: 8))
}

@Test(.timeLimit(.minutes(1)))
func cadGeometryExchangePreservesCancellationBeforeFileRead() async throws {
    let task = Task {
        try CADGeometryExchange().import(
            from: URL(fileURLWithPath: "/does-not-exist.obj"),
            format: .obj,
            tolerance: .standard
        )
    }
    task.cancel()
    do {
        _ = try await task.value
        Issue.record("A cancelled exchange import unexpectedly succeeded.")
    } catch is CancellationError {
        // The adapter must not translate caller cancellation into a parse error.
    } catch {
        Issue.record("Expected CancellationError, got \(error).")
    }
}

@Test(.timeLimit(.minutes(1)))
func cadGeometryExchangeForwardsSTLEntityAdmissionBeforeConversion() throws {
    var data = makeBinarySTL(
        header: "Swift-CAD binary STL unit=millimeter", normal: (0, 0, 1),
        points: [(0, 0, 0), (10, 0, 0), (0, 20, 0)]
    )
    let triangle = data[84..<134]
    data[80] = 2
    data.append(triangle)
    let limits = ExchangeResourceLimits(
        maximumBytes: 4_096, maximumEntities: 1, maximumNesting: 8,
        maximumIterations: 64, maximumProcessingDuration: .seconds(1)
    )
    try withExchangeFile(data, pathExtension: "stl") { url in
        do {
            _ = try CADGeometryExchange(resourceLimits: limits).import(from: url, format: .stl, tolerance: .standard)
            Issue.record("STL imported above the adapter's entity limit.")
        } catch let error as CADGeometryExchangeError {
            guard case .resourceExhausted = error else { Issue.record("Unexpected error: \(error)"); return }
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func cadGeometryExchangeChargesUniversalUsageBeforeMaterialization() throws {
    let data = Data(
        """
        # unit meter
        v 0 0 0
        v 1 0 0
        v 0 1 0
        f 1 2 3
        """.utf8
    )
    let standard = try withExchangeFile(data, pathExtension: "obj") { url in
        try CADGeometryExchange().import(
            from: url,
            format: .obj,
            tolerance: .standard
        )
    }
    let standardMesh = try #require(standard.meshes.first)
    let usage = try standardMesh.resourceUsage()
    let exactAllowance = EvaluationAllowance(
        sourceCount: 1,
        vertexCount: usage.vertexCount,
        faceCount: usage.faceCount,
        cornerCount: usage.cornerCount,
        triangleCount: usage.triangleCount,
        byteCount: usage.byteCount
    )
    let belowByteAllowance = EvaluationAllowance(
        sourceCount: 1,
        vertexCount: usage.vertexCount,
        faceCount: usage.faceCount,
        cornerCount: usage.cornerCount,
        triangleCount: usage.triangleCount,
        byteCount: usage.byteCount - 1
    )

    let exact = try withExchangeFile(data, pathExtension: "obj") { url in
        try CADGeometryExchange().import(
            from: url,
            format: .obj,
            tolerance: .standard,
            allowance: exactAllowance
        )
    }
    #expect(exact.meshes.count == 1)

    let error: CADGeometryExchangeError?
    do {
        try withExchangeFile(data, pathExtension: "obj") { url in
            _ = try CADGeometryExchange().import(
                from: url,
                format: .obj,
                tolerance: .standard,
                allowance: belowByteAllowance
            )
        }
        error = nil
    } catch let caught as CADGeometryExchangeError {
        error = caught
    }
    #expect(error != nil)
    if case .resourceExhausted? = error {
        // Expected: universal bytes are charged before MeshSource allocation.
    } else {
        Issue.record("Expected a typed resource exhaustion, got \(String(describing: error)).")
    }
}

private func withExchangeFile<Result>(
    _ data: Data,
    pathExtension: String,
    _ body: (URL) throws -> Result
) throws -> Result {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("rupa-exchange-\(UUID().uuidString)")
        .appendingPathExtension(pathExtension)
    try data.write(to: url, options: .atomic)
    defer {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // Test fixture cleanup is best effort after the import has released its mmap.
        }
    }
    return try body(url)
}

private func makeBinarySTL(
    header: String,
    normal: (Float32, Float32, Float32),
    points: [(Float32, Float32, Float32)]
) -> Data {
    var data = Data(header.utf8.prefix(80))
    data.append(Data(repeating: 0, count: 80 - data.count))
    appendUInt32LE(1, to: &data)
    appendFloat32LE(normal.0, to: &data)
    appendFloat32LE(normal.1, to: &data)
    appendFloat32LE(normal.2, to: &data)
    for point in points {
        appendFloat32LE(point.0, to: &data)
        appendFloat32LE(point.1, to: &data)
        appendFloat32LE(point.2, to: &data)
    }
    data.append(contentsOf: [0, 0])
    return data
}

private func appendUInt32LE(_ value: UInt32, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

private func appendFloat32LE(_ value: Float32, to data: inout Data) {
    var bits = value.bitPattern.littleEndian
    withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
}
