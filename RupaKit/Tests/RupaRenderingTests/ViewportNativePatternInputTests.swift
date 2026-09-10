import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene
import SwiftCAD
import Testing
@testable import RupaRendering

private func radialAngleSource(
    angleRadians: Double = 0.2
) -> ViewportPatternAffordanceSource.RadialAngleHandle {
    .init(
        sourceID: .init(), title: "Angle", center: .origin, axis: .unitY,
        referencePoint: .init(x: 2, y: 0, z: 0), angleRadians: angleRadians,
        displayAngleRadians: nil, angleMode: .spacing, state: .normal
    )
}

private func curveCopyCountSource(
    copyCount: Int = 4
) -> ViewportPatternAffordanceSource.CopyCountHandle {
    .init(
        sourceID: .init(), slot: .curve, title: "Copies",
        guide: .curve(
            pathPoints: [.origin, .init(x: 1, y: 0, z: 0), .init(x: 1, y: 0, z: 3)],
            extentDistanceMeters: 2
        ),
        copyCount: copyCount, displayCopyCount: nil, state: .normal
    )
}

private func outputModeSource(
    outputMode: PatternArrayOutputMode = .componentInstance
) -> ViewportPatternAffordanceSource.OutputModeHandle {
    .init(
        sourceID: .init(), outputMode: outputMode, anchor: .origin,
        title: "Output", highlightedTitle: "Output", state: .normal
    )
}

/// The mounted camera of these tests: a scaled orthographic drop of the CAD
/// x/z plane. It never varies during a gesture, which is the contract the
/// retained projection depends on.
private func mountedProjection(_ point: Point3D) -> CGPoint {
    CGPoint(x: point.x * 10, y: point.z * 10)
}

@Test @MainActor
func nativePatternInputClaimsOnlyScreenBasisPatternRoutes() throws {
    #expect(ViewportNativePatternInput.claims(.patternArrayRadialAngle(radialAngleSource())))
    #expect(ViewportNativePatternInput.claims(.patternArrayCopyCount(curveCopyCountSource())))
    #expect(ViewportNativePatternInput.claims(.patternArrayOutputMode(outputModeSource())))

    let axis = ViewportSpatialPreparedInteractionTarget.patternArrayLinearAxis(.init(
        sourceID: .init(), axisSlot: .first, title: "Axis",
        basePoint: .origin, direction: .unitX, distanceMeters: 0.5,
        displayDistanceMeters: nil, distanceMode: .spacing, state: .normal
    ))
    #expect(!ViewportNativePatternInput.claims(axis))

    let record = try ViewportSpatialInteractionRecord(target: axis)
    let input = try ViewportNativePatternInput(record: record, project: mountedProjection)
    #expect(input == nil)
}

@Test @MainActor
func nativePatternInputRefusesCollinearRadialBasisAtPress() throws {
    let record = try ViewportSpatialInteractionRecord(
        target: .patternArrayRadialAngle(radialAngleSource())
    )
    // This camera collapses the radial and tangent samples onto one screen
    // line, so no pointer sample could name a rotation about the CAD axis.
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportNativePatternInput(record: record) { CGPoint(x: $0.x + $0.z, y: 0) }
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try ViewportNativePatternInput(record: record) { _ in CGPoint(x: CGFloat.nan, y: 0) }
    }
}

@Test @MainActor
func nativePatternInputReadsNoValueAtProjectedCentre() throws {
    let record = try ViewportSpatialInteractionRecord(
        target: .patternArrayRadialAngle(radialAngleSource())
    )
    let input = try #require(
        try ViewportNativePatternInput(record: record, project: mountedProjection)
    )
    // The projected centre names no direction, so the update carries no value
    // and the caller keeps the one it already retained.
    #expect(try input.value(start: .zero, current: .zero) == nil)
    #expect(try input.value(start: CGPoint(x: 20, y: 0), current: .zero) == nil)

    let moved = try #require(try input.value(start: CGPoint(x: 20, y: 0), current: CGPoint(x: 0, y: -20)))
    guard case .angleRadians(let angleRadians) = moved else {
        Issue.record("The radial route read a value of another kind.")
        return
    }
    #expect(angleRadians.isFinite)
}

@Test @MainActor
func nativePatternInputCommitsNothingWithoutAChange() throws {
    let radialRecord = try ViewportSpatialInteractionRecord(
        target: .patternArrayRadialAngle(radialAngleSource(angleRadians: 0.2))
    )
    let radial = try #require(
        try ViewportNativePatternInput(record: radialRecord, project: mountedProjection)
    )
    #expect(try radial.commit(value: nil) == nil)
    #expect(try radial.commit(value: .angleRadians(0.2)) == nil)
    guard case .patternArrayRadialAngle(let angleTarget)? = try radial.commit(value: .angleRadians(0.7)) else {
        Issue.record("A changed angle did not produce a commit payload.")
        return
    }
    #expect(angleTarget.angleRadians == 0.7)

    let copySource = curveCopyCountSource(copyCount: 4)
    let copyRecord = try ViewportSpatialInteractionRecord(
        target: .patternArrayCopyCount(copySource)
    )
    let copies = try #require(
        try ViewportNativePatternInput(record: copyRecord, project: mountedProjection)
    )
    #expect(try copies.commit(value: .copyCount(4)) == nil)
    guard case .patternArrayCopyCount(let copyTarget)? = try copies.commit(value: .copyCount(7)) else {
        Issue.record("A changed copy count did not produce a commit payload.")
        return
    }
    #expect(copyTarget.copyCount == 7)
    #expect(copyTarget.slot == .curve)
    #expect(copyTarget.sourceID == copySource.sourceID)
}

@Test @MainActor
func nativePatternInputRefusesAValueFromAnotherRoute() throws {
    let record = try ViewportSpatialInteractionRecord(
        target: .patternArrayRadialAngle(radialAngleSource())
    )
    let input = try #require(
        try ViewportNativePatternInput(record: record, project: mountedProjection)
    )
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try input.commit(value: .copyCount(3))
    }
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try input.commit(value: .angleRadians(.nan))
    }
}

@Test @MainActor
func nativePatternInputTogglesOutputModeOnlyInsideTheRetainedRect() throws {
    let source = outputModeSource(outputMode: .componentInstance)
    let record = try ViewportSpatialInteractionRecord(target: .patternArrayOutputMode(source))
    let input = try #require(
        try ViewportNativePatternInput(record: record, project: mountedProjection)
    )
    // The output-mode route holds no drag state: it commits on release.
    #expect(try input.value(start: .zero, current: CGPoint(x: 40, y: 40)) == nil)
    #expect(try input.commit(value: nil) == nil)

    guard case .patternArrayOutputMode(let toggled)? = try input.outputModeCommit(
        releasedAt: CGPoint(x: 46, y: -34)
    ) else {
        Issue.record("A release on the retained label did not toggle the output mode.")
        return
    }
    #expect(toggled.sourceID == source.sourceID)
    #expect(toggled.outputMode == .independentCopy)

    #expect(try input.outputModeCommit(releasedAt: CGPoint(x: 400, y: 400)) == nil)
    #expect(throws: MeshSourcePresentationRenderError.self) {
        try input.outputModeCommit(releasedAt: CGPoint(x: CGFloat.nan, y: 0))
    }
}

@Test @MainActor
func nativePatternInputProjectsOncePerPressAndNeverReprojects() throws {
    let record = try ViewportSpatialInteractionRecord(
        target: .patternArrayRadialAngle(radialAngleSource())
    )
    var projectionCount = 0
    let input = try #require(
        try ViewportNativePatternInput(record: record) { point in
            projectionCount += 1
            return mountedProjection(point)
        }
    )
    let pressCount = projectionCount
    #expect(pressCount > 0)

    _ = try input.value(start: CGPoint(x: 20, y: 0), current: CGPoint(x: 0, y: -20))
    _ = try input.value(start: CGPoint(x: 20, y: 0), current: CGPoint(x: -20, y: 0))
    _ = try input.commit(value: .angleRadians(0.9))

    // Every update reads the sample retained at press: a mid-gesture camera
    // change must end the gesture, never silently reproject it.
    #expect(projectionCount == pressCount)
}
