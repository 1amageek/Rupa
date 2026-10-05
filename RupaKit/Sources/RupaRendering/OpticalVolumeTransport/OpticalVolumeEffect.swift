import Foundation
import Metal
import RealityKit
import Synchronization
import simd

/// Native postprocessing with immutable original-scene inputs and explicit failure status.
struct OpticalVolumeEffect: PostProcessEffect {
    let scene: OpticalVolumeScene
    let pipeline: any MTLComputePipelineState
    let publicationPipeline: any MTLComputePipelineState
    let images: OpticalVolumeFrameStore
    let worldFromView: simd_float4x4
    let section: SIMD4<Float>
    let background: SIMD4<Float>
    let studioRotation: Float
    let specularEnabled: Bool
    let nativeSurfaceVisible: Bool
    let mediumCapacity: UInt32
    let status: OpticalVolumeFrameStatus

    nonisolated mutating func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        var outputEncoded = false
        // Callback failures remain explicit in status. Retain a complete image even
        // when admission fails before the transport encoder exists.
        defer { if !outputEncoded { encodeRetainedFailure(context: context) } }
        guard context.sourceColorTexture.width == context.targetColorTexture.width,
              context.sourceColorTexture.height == context.targetColorTexture.height,
              context.sourceDepthTexture.width == context.targetColorTexture.width,
              context.sourceDepthTexture.height == context.targetColorTexture.height else {
            status.fail(.init(code: .gpuFailure, message: "Optical native color/depth dimensions disagree."))
            return
        }
        let width = context.targetColorTexture.width
        let height = context.targetColorTexture.height
        let (pixelCount, pixelsOverflow) = width.multipliedReportingOverflow(by: height)
        let pixelStride: Int
        switch context.targetColorTexture.pixelFormat {
        case .rgba8Unorm, .rgba8Unorm_sRGB, .bgra8Unorm, .bgra8Unorm_sRGB, .rgb10a2Unorm, .bgr10a2Unorm: pixelStride = 4
        case .rgba16Float: pixelStride = 8
        case .rgba32Float: pixelStride = 16
        default:
            status.fail(.init(code: .gpuFailure, message: "Optical native color format has no admitted RGBA representation."))
            return
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: context.targetColorTexture.pixelFormat,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        let imageFootprint = context.device.heapTextureSizeAndAlign(descriptor: descriptor).size
        let (logicalImageBytes, imageOverflow) = pixelCount.multipliedReportingOverflow(by: pixelStride)
        let imageBytes = max(logicalImageBytes, imageFootprint)
        let (stackElements, stackOverflow) = pixelCount.multipliedReportingOverflow(by: mediumCapacity <= 4 ? 0 : Int(mediumCapacity))
        let (logicalStackBytes, bytesOverflow) = stackElements.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        let stackLength = max(4, logicalStackBytes)
        let stackBytes = max(stackLength, context.device.heapBufferSizeAndAlign(length: stackLength, options: .storageModePrivate).size)
        let resultBytes = max(MemoryLayout<UInt32>.stride,
            context.device.heapBufferSizeAndAlign(length: MemoryLayout<UInt32>.stride, options: .storageModeShared).size)
        guard !pixelsOverflow, !imageOverflow, !stackOverflow, !bytesOverflow, pixelCount > 0,
              imageBytes <= scene.limits.maxRetainedByteCount - scene.byteCount - resultBytes,
              width <= Int(UInt32.max), height <= Int(UInt32.max),
              stackBytes <= scene.limits.maxRetainedByteCount - scene.byteCount - imageBytes - resultBytes,
              UInt64(pixelCount) <= scene.limits.maxTraversalWork else {
            status.fail(.init(code: .resourceExhausted, message: "Optical frame scratch or traversal admission exhausted."))
            return
        }
        let (scratchAndImage, reserveOverflow) = stackBytes.addingReportingOverflow(imageBytes)
        let (additionalBytes, resultOverflow) = scratchAndImage.addingReportingOverflow(resultBytes)
        guard !reserveOverflow, !resultOverflow else {
            status.fail(.init(code: .resourceExhausted, message: "Optical frame reservation overflowed."))
            return
        }
        let receipt: OpticalVolumeFrameStore.Receipt
        do { receipt = try images.candidate(additionalBytes: additionalBytes) }
        catch let error as MeshSourcePresentationRenderError {
            if error.code == .frameNotReady { status.deferForPreparation() } else { status.fail(error) }
            return
        }
        catch { status.fail(.init(code: .failed, message: "Optical frame capture failed.")); return }
        var submitted = false
        defer { if !submitted { images.finish(receipt, completed: nil) } }
        let perPixelWork = min(UInt64(UInt32.max), scene.limits.maxTraversalWork / UInt64(pixelCount))
        guard let candidate = context.device.makeTexture(descriptor: descriptor),
              let stack = context.device.makeBuffer(length: stackLength, options: .storageModePrivate),
              let result = context.device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let encoder = context.commandBuffer.makeComputeCommandEncoder() else {
            status.fail(.init(code: .gpuFailure, message: "Optical frame GPU allocation or command encoding failed."))
            return
        }
        guard candidate.allocatedSize <= imageBytes, stack.allocatedSize <= stackBytes,
              result.allocatedSize <= resultBytes else {
            encoder.endEncoding()
            status.fail(.init(code: .resourceExhausted, message: "Optical native allocation exceeds its admitted footprint."))
            return
        }
        result.contents().storeBytes(of: UInt32(0), as: UInt32.self)
        var parameters = OpticalVolumeParameters(
            worldFromView: worldFromView, viewFromWorld: simd_inverse(worldFromView),
            projection: context.projection, inverseProjection: simd_inverse(context.projection),
            section: section, frame: [UInt32(width), UInt32(height), scene.triangleCount, scene.nodeCount],
            limits: [scene.limits.maxInteractionCount, UInt32(perPixelWork), mediumCapacity, specularEnabled ? 1 : 0],
            studio: [studioRotation, 0, 0, nativeSurfaceVisible ? 1 : 0], background: background
        )
        guard (0..<4).allSatisfy({ column in (0..<4).allSatisfy { parameters.inverseProjection[column][$0].isFinite } }) else {
            encoder.endEncoding()
            status.fail(.init(code: .invalidTransform, message: "Optical native projection is singular."))
            return
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(scene.triangles, offset: 0, index: 0)
        encoder.setBuffer(scene.nodes, offset: 0, index: 1)
        encoder.setBytes(&parameters, length: MemoryLayout<OpticalVolumeParameters>.stride, index: 2)
        encoder.setBuffer(stack, offset: 0, index: 3)
        encoder.setBuffer(result, offset: 0, index: 4)
        encoder.setBuffer(scene.opticalOccurrences, offset: 0, index: 5)
        encoder.setTexture(context.sourceColorTexture, index: 0)
        encoder.setTexture(context.sourceDepthTexture, index: 1)
        encoder.setTexture(candidate, index: 2)
        let groupWidth = pipeline.threadExecutionWidth
        let groupHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / groupWidth)
        encoder.dispatchThreads(.init(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: .init(width: groupWidth, height: groupHeight, depth: 1))
        encoder.endEncoding()
        guard let publisher = context.commandBuffer.makeComputeCommandEncoder() else {
            status.fail(.init(code: .gpuFailure, message: "Optical atomic image publication encoding failed."))
            return
        }
        publisher.setComputePipelineState(publicationPipeline)
        publisher.setBuffer(result, offset: 0, index: 0)
        let previous = compatiblePrevious(receipt.previous, width: width, height: height)
        var hasPrevious: UInt32 = previous == nil ? 0 : 1
        publisher.setBytes(&hasPrevious, length: MemoryLayout<UInt32>.stride, index: 1)
        publisher.setTexture(candidate, index: 0)
        publisher.setTexture(previous ?? context.sourceColorTexture, index: 1)
        publisher.setTexture(context.targetColorTexture, index: 2)
        publisher.dispatchThreads(.init(width: width, height: height, depth: 1),
                                 threadsPerThreadgroup: .init(width: groupWidth, height: groupHeight, depth: 1))
        publisher.endEncoding()
        outputEncoded = true
        let images = images
        let status = status
        let retainedScene = scene
        // Only scoped typed access to this initialized four-byte result. The
        // command buffer retains it until completion; the borrow never escapes.
        context.commandBuffer.addCompletedHandler { command in
            defer { withExtendedLifetime(retainedScene) {} }
            if command.status == .error {
                images.finish(receipt, completed: nil)
                status.fail(.init(code: .gpuFailure, message: command.error?.localizedDescription ?? "Optical GPU command failed."))
                return
            }
            let code = result.contents().load(as: UInt32.self)
            switch code {
            case 0:
                images.finish(receipt, completed: candidate)
                status.complete()
            case 1: images.finish(receipt, completed: nil); status.fail(.init(code: .resourceExhausted, message: "Optical original-ray work budget exhausted."))
            case 2: images.finish(receipt, completed: nil); status.fail(.init(code: .invalidSceneItem, message: "Optical volume interface incidence is inconsistent."))
            default: images.finish(receipt, completed: nil); status.fail(.init(code: .gpuFailure, message: "Optical original-ray arithmetic is not finite."))
            }
        }
        submitted = true
    }

    private nonisolated func compatiblePrevious(_ texture: (any MTLTexture)?, width: Int, height: Int) -> (any MTLTexture)? {
        guard let texture, texture.width == width, texture.height == height else { return nil }
        return texture
    }

    private nonisolated func encodeRetainedFailure(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        guard let encoder = context.commandBuffer.makeComputeCommandEncoder() else { return }
        encoder.setComputePipelineState(publicationPipeline)
        var failure: UInt32 = 1
        let receipt = images.retainedFailure()
        let previous = compatiblePrevious(receipt.previous, width: context.targetColorTexture.width,
            height: context.targetColorTexture.height)
        var hasPrevious: UInt32 = previous == nil ? 0 : 1
        let retained = previous ?? context.sourceColorTexture
        encoder.setBytes(&failure, length: MemoryLayout<UInt32>.stride, index: 0)
        encoder.setBytes(&hasPrevious, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setTexture(context.sourceColorTexture, index: 0)
        encoder.setTexture(retained, index: 1)
        encoder.setTexture(context.targetColorTexture, index: 2)
        let width = publicationPipeline.threadExecutionWidth
        let height = max(1, publicationPipeline.maxTotalThreadsPerThreadgroup / width)
        encoder.dispatchThreads(.init(width: context.targetColorTexture.width, height: context.targetColorTexture.height, depth: 1),
            threadsPerThreadgroup: .init(width: width, height: height, depth: 1))
        encoder.endEncoding()
        let images = images
        context.commandBuffer.addCompletedHandler { _ in images.finish(receipt, completed: nil) }
    }
}
