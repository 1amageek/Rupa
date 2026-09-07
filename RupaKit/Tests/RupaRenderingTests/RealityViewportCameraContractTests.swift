import CoreGraphics
import Testing
@testable import RupaRendering

@Test
func axisFrontPresetsAreTrueRigidOrientations() {
    for axis in ViewportCoordinateAxis.allCases {
        let basis = ViewportProjectionBasis.axisFront(axis)
        #expect(basis.isRigidOrientation)

        switch axis {
        case .x:
            #expect(basis.xDirection == CGVector(dx: 0, dy: 0))
            #expect(basis.yDirection == CGVector(dx: 0, dy: -1))
            #expect(basis.zDirection == CGVector(dx: -1, dy: 0))
        case .y:
            #expect(basis.xDirection == CGVector(dx: 1, dy: 0))
            #expect(basis.yDirection == CGVector(dx: 0, dy: 0))
            #expect(basis.zDirection == CGVector(dx: 0, dy: 1))
        case .z:
            #expect(basis.xDirection == CGVector(dx: 1, dy: 0))
            #expect(basis.yDirection == CGVector(dx: 0, dy: -1))
            #expect(basis.zDirection == CGVector(dx: 0, dy: 0))
        }
    }
}

@Test
func rigidBasisPairsProduceRigidQuaternionMidpoints() {
    let bases: [ViewportProjectionBasis] = [
        .isometric,
        .axisFront(.x),
        .axisFront(.y),
        .axisFront(.z),
        .orbit(yaw: -0.7, elevation: 0.52),
    ]

    for start in bases {
        for end in bases {
            let midpoint = ViewportProjectionBasis.interpolated(
                from: start,
                to: end,
                progress: 0.5
            )
            #expect(midpoint.isRigidOrientation)
            #expect(ViewportProjectionBasis.interpolated(from: start, to: end, progress: 0) == start)
            #expect(ViewportProjectionBasis.interpolated(from: start, to: end, progress: 1) == end)
        }
    }
}

@Test
func invalidBasisRemainsInvalidDuringInterpolation() {
    let invalidStart = ViewportProjectionBasis(
        mode: .orbit,
        xDirection: CGVector(dx: 2, dy: 0),
        yDirection: CGVector(dx: 0, dy: -1),
        zDirection: .zero
    )
    let invalidEnd = ViewportProjectionBasis(
        mode: .orbit,
        xDirection: CGVector(dx: 0, dy: 0),
        yDirection: CGVector(dx: 0, dy: -1),
        zDirection: .zero
    )
    let target = ViewportProjectionBasis.isometric

    #expect(!invalidStart.isRigidOrientation)
    #expect(!invalidEnd.isRigidOrientation)
    #expect(ViewportProjectionBasis.interpolated(from: invalidStart, to: target, progress: 0) == invalidStart)
    #expect(ViewportProjectionBasis.interpolated(from: invalidStart, to: target, progress: 1) == target)

    let invalidMidpoint = ViewportProjectionBasis.interpolated(
        from: invalidStart,
        to: invalidEnd,
        progress: 0.5
    )
    #expect(invalidMidpoint == invalidStart)
    #expect(!invalidMidpoint.isRigidOrientation)

    let validToInvalid = ViewportProjectionBasis.interpolated(
        from: target,
        to: invalidEnd,
        progress: 0.5
    )
    #expect(validToInvalid == invalidEnd)
    #expect(!validToInvalid.isRigidOrientation)

    let nonfiniteProgress = ViewportProjectionBasis.interpolated(
        from: target,
        to: target,
        progress: .nan
    )
    #expect(!nonfiniteProgress.isRigidOrientation)
    #expect(!nonfiniteProgress.xDirection.dx.isFinite)
}
