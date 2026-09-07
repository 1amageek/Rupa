import AppKit
import Metal
import RealityKit
import SwiftUI
import Testing
import simd

/// Tests the native engine boundary, independently of CAD scene adaptation.
@Suite(.serialized)
@MainActor
struct RealityKitNativeRuntimeTests {
    @Test(.timeLimit(.minutes(1)))
    func nativeGeometryCameraAndCollisionExecuteOnGPU() async throws {
        _ = NSApplication.shared
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try RealityRenderer()
        renderer.cameraSettings.colorBackground = .color(CGColor(gray: 0, alpha: 1))
        renderer.cameraSettings.isToneMappingEnabled = false
        let camera = Entity()
        var lens = OrthographicCameraComponent()
        lens.near = 0.01
        lens.far = 100
        lens.scale = 2
        camera.components.set(lens)
        camera.position = [0, 0, 3]
        renderer.activeCamera = camera
        let boxMesh = MeshResource.generateBox(size: 0.5)
        let box = ModelEntity(mesh: boxMesh, materials: [UnlitMaterial(color: .red)])
        let collision = try await ShapeResource.generateStaticMesh(from: boxMesh)
        box.components.set(CollisionComponent(shapes: [collision]))

        var extrusion = MeshResource.ShapeExtrusionOptions()
        extrusion.extrusionMethod = .linear(depth: 0)
        let outline = Path(roundedRect: CGRect(x: -0.2, y: -0.1, width: 0.4, height: 0.2), cornerRadius: 0.04)
        let pathMesh = try await MeshResource(extruding: outline, extrusionOptions: extrusion)
        let path = ModelEntity(mesh: pathMesh, materials: [UnlitMaterial(color: .blue)])
        path.position = [0.55, 0.55, 0]
        let text = ModelEntity(
            mesh: .generateText("CAD", extrusionDepth: 0, font: .systemFont(ofSize: 0.2)),
            materials: [UnlitMaterial(color: .yellow)]
        )
        text.position = [-0.7, 0.55, 0]

        var descriptor = LowLevelMesh.Descriptor()
        descriptor.vertexCapacity = 4
        descriptor.indexCapacity = 4
        descriptor.vertexAttributes = [.init(semantic: .position, format: .float3, offset: 0)]
        descriptor.vertexLayouts = [.init(bufferIndex: 0, bufferStride: MemoryLayout<SIMD3<Float>>.stride)]
        descriptor.indexType = .uint32
        let mesh = try LowLevelMesh(descriptor: descriptor)
        // RealityKit owns the initialized buffers; these scoped borrows do not escape.
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { bytes in
            let points = bytes.bindMemory(to: SIMD3<Float>.self)
            points[0] = [-0.8, -0.7, 0]
            points[1] = [0.8, -0.7, 0]
            points[2] = [-0.7, -0.8, 0]
            points[3] = [-0.7, 0.8, 0]
        }
        mesh.withUnsafeMutableIndices { bytes in
            let indices = bytes.bindMemory(to: UInt32.self)
            for index in 0..<4 { indices[index] = UInt32(index) }
        }
        mesh.parts.replaceAll([.init(indexCount: 4, topology: .line, bounds: .init(min: [-1, -1, -1], max: [1, 1, 1]))])
        let lineMesh = try await MeshResource(from: mesh)
        let lines = ModelEntity(mesh: lineMesh, materials: [UnlitMaterial(color: .green)])
        renderer.entities.append(contentsOf: [camera, box, lines, path, text])

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 256, height: 256, mipmapped: false)
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        let texture = try #require(device.makeTexture(descriptor: textureDescriptor))
        let output = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: texture))
        var centroids: [Double] = []
        for frame in 0..<3 {
            camera.position.x = frame == 1 ? 0.25 : 0
            if frame == 2 {
                camera.components.remove(OrthographicCameraComponent.self)
                let lens = simd_float4x4(
                    SIMD4<Float>(0.5, 0, 0, 0), SIMD4<Float>(0, 0.5, 0, 0),
                    SIMD4<Float>(0, 0, 1 / 99.99, 0), SIMD4<Float>(0.2, 0, 100 / 99.99, 1)
                )
                camera.components.set(ProjectiveTransformCameraComponent(projectionMatrix: lens))
            }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                do {
                    try renderer.updateAndRender(deltaTime: 1.0 / 60, cameraOutput: output, onComplete: { _ in
                        continuation.resume()
                    })
                } catch { continuation.resume(throwing: error) }
            }
            var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
            texture.getBytes(&bytes, bytesPerRow: 256 * 4, from: MTLRegionMake2D(0, 0, 256, 256), mipmapLevel: 0)
            var red = 0
            var green = 0
            var blue = 0
            var yellow = 0
            var redX = 0
            for pixel in 0..<(256 * 256) {
                let offset = pixel * 4
                if bytes[offset + 2] > 150 && bytes[offset + 1] < 60 {
                    red += 1
                    redX += pixel % 256
                }
                if bytes[offset + 1] > 150 && bytes[offset + 2] < 60 { green += 1 }
                if bytes[offset] > 150 && bytes[offset + 2] < 60 { blue += 1 }
                if bytes[offset + 1] > 150 && bytes[offset + 2] > 150 { yellow += 1 }
            }
            try #require(red > 100)
            #expect(green > 100)
            #expect(blue > 40)
            #expect(yellow > 5)
            centroids.append(Double(redX) / Double(red))
        }
        #expect(centroids[1] < centroids[0] - 10)
        #expect(centroids[2] > centroids[0] + 20)
        let scene = try #require(box.scene)
        let hit = try #require(scene.raycast(origin: [0, 0, 3], direction: [0, 0, -1], length: 10).first)
        #expect(hit.entity === box)
        let triangle = try #require(hit.triangleHit)
        #expect((0..<12).contains(triangle.faceIndex))
        #expect(abs(hit.position.z - 0.25) < 0.0001)
    }
}
