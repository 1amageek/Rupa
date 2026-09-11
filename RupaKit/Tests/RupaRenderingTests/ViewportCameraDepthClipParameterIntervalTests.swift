import Testing
@testable import RupaRendering

/// Proof that generalising the segment clip to any affine scalar left the depth
/// clip exactly as it was, and that a third bound of the section's shape
/// narrows the same interval past what depth alone retained.
///
/// The oracle below is a verbatim copy of the implementation
/// `clippedParameterInterval(startDepth:endDepth:to:)` had before the
/// generalisation. It is frozen: it is never edited to follow the production
/// code, because its only value is disagreeing with it.
@Suite struct ViewportCameraDepthClipParameterIntervalTests {
    /// One row of the sweep: a segment's two depths, a frame's interval, and
    /// the branch the row is there to reach.
    private struct DepthCase {
        let startDepth: Double
        let endDepth: Double
        let interval: ClosedRange<Double>
        let branch: String
    }

    /// The previous implementation, kept verbatim as the comparison oracle.
    private static func frozenClippedParameterInterval(
        startDepth: Double,
        endDepth: Double,
        to interval: ClosedRange<Double>
    ) -> (lower: Double, upper: Double)? {
        guard startDepth.isFinite, endDepth.isFinite,
              ViewportCameraDepthClip.canClip(against: interval) else {
            return nil
        }
        var constraints: [(bound: Double, retainsAbove: Bool)] = [(interval.lowerBound, true)]
        if interval.upperBound.isFinite {
            constraints.append((interval.upperBound, false))
        }
        var lower = 0.0
        var upper = 1.0
        let delta = endDepth - startDepth
        guard delta.isFinite else { return nil }
        for (bound, retainsAbove) in constraints {
            guard delta != 0 else {
                let retained = retainsAbove ? startDepth >= bound : startDepth <= bound
                if retained == false { return nil }
                continue
            }
            let crossing = (bound - startDepth) / delta
            guard crossing.isFinite else { return nil }
            if (delta > 0) == retainsAbove {
                lower = max(lower, crossing)
            } else {
                upper = min(upper, crossing)
            }
        }
        guard lower <= upper else { return nil }
        return (lower, upper)
    }

    /// Every branch of the clip, swept against the frozen oracle.
    ///
    /// A row asserts nothing about the value itself: the claim under test is
    /// that the two implementations answer identically, so a row that both
    /// refuse is as much evidence as a row that both retain.
    @Test func generalisedDepthClipAnswersExactlyWhatTheFrozenClipAnswered() {
        let huge = Double.greatestFiniteMagnitude
        let cases: [DepthCase] = [
            DepthCase(startDepth: 2, endDepth: 8, interval: 1...10,
                      branch: "wholly inside both bounds"),
            DepthCase(startDepth: 0, endDepth: 8, interval: 1...10,
                      branch: "near crossing inside, increasing depth"),
            DepthCase(startDepth: 8, endDepth: 0, interval: 1...10,
                      branch: "near crossing inside, decreasing depth"),
            DepthCase(startDepth: 0, endDepth: 20, interval: 1...10,
                      branch: "both bounds cross the same segment"),
            DepthCase(startDepth: 1, endDepth: 10, interval: 1...10,
                      branch: "crossings exactly at 0 and at 1"),
            DepthCase(startDepth: 0, endDepth: 0.5, interval: 1...10,
                      branch: "near crossing above 1"),
            DepthCase(startDepth: 20, endDepth: 30, interval: 1...10,
                      branch: "far crossing below 0"),
            DepthCase(startDepth: 12, endDepth: 11, interval: 1...10,
                      branch: "wholly beyond the far bound"),
            DepthCase(startDepth: 5, endDepth: 5, interval: 1...10,
                      branch: "constant depth retained by both bounds"),
            DepthCase(startDepth: 0, endDepth: 0, interval: 1...10,
                      branch: "constant depth rejected by the near bound"),
            DepthCase(startDepth: 20, endDepth: 20, interval: 1...10,
                      branch: "constant depth rejected by the far bound"),
            DepthCase(startDepth: 2, endDepth: 8, interval: 1...Double.infinity,
                      branch: "unbounded far plane contributes no constraint"),
            DepthCase(startDepth: 0, endDepth: 8, interval: 1...Double.infinity,
                      branch: "unbounded far plane, near crossing inside"),
            DepthCase(startDepth: 0, endDepth: 0.5, interval: 1...Double.infinity,
                      branch: "unbounded far plane, near crossing above 1"),
            DepthCase(startDepth: 0, endDepth: 0, interval: 1...Double.infinity,
                      branch: "unbounded far plane, constant depth rejected"),
            DepthCase(startDepth: 0, endDepth: 10, interval: 5...5,
                      branch: "degenerate interval retains one parameter"),
            DepthCase(startDepth: 5, endDepth: 5, interval: 5...5,
                      branch: "degenerate interval, constant depth on it"),
            DepthCase(startDepth: Double.nan, endDepth: 8, interval: 1...10,
                      branch: "start depth is not a number"),
            DepthCase(startDepth: 2, endDepth: Double.nan, interval: 1...10,
                      branch: "end depth is not a number"),
            DepthCase(startDepth: Double.infinity, endDepth: 8, interval: 1...10,
                      branch: "start depth is infinite"),
            DepthCase(startDepth: 2, endDepth: -Double.infinity, interval: 1...10,
                      branch: "end depth is infinite"),
            DepthCase(startDepth: -huge, endDepth: huge, interval: 1...10,
                      branch: "difference of the depths overflows"),
            DepthCase(startDepth: -huge, endDepth: 0, interval: (-huge)...huge,
                      branch: "far crossing overflows"),
            DepthCase(startDepth: 2, endDepth: 8, interval: (-Double.infinity)...10,
                      branch: "interval names no camera"),
            DepthCase(startDepth: Double.nan, endDepth: 8, interval: (-Double.infinity)...10,
                      branch: "interval names no camera and the depth is not a number"),
        ]
        for row in cases {
            let expected = Self.frozenClippedParameterInterval(
                startDepth: row.startDepth, endDepth: row.endDepth, to: row.interval
            )
            let actual = ViewportCameraDepthClip.clippedParameterInterval(
                startDepth: row.startDepth, endDepth: row.endDepth, to: row.interval
            )
            let comment = Comment(rawValue: row.branch)
            switch (expected, actual) {
            case (nil, nil):
                continue
            case let (expected?, actual?):
                #expect(actual.lower == expected.lower, comment)
                #expect(actual.upper == expected.upper, comment)
            default:
                Issue.record(comment)
            }
        }
    }

    /// A section-shaped third bound narrows past what the depth interval left.
    ///
    /// The scalar here is the signed distance a frame's section half-space
    /// reports at the two endpoints, bounded at `-tolerance` and retaining the
    /// side at or above it, which is the bound
    /// `RealityViewport.sectionParameterBound(from:to:revision:)` vends.
    @Test func aSectionBoundNarrowsTheSameIntervalPastTheDepthInterval() {
        let depthOnly = ViewportCameraDepthClip.clippedParameterInterval(
            startDepth: 1, endDepth: 10, to: 1...10
        )
        #expect(depthOnly?.lower == 0)
        #expect(depthOnly?.upper == 1)

        var parameters = ViewportCameraDepthClip.ParameterInterval.whole
        let narrowedByNear = parameters.narrow(
            by: ViewportCameraDepthClip.AffineScalarBound(
                start: 1, end: 10, bound: 1, retainsValuesAtLeastBound: true
            )
        )
        #expect(narrowedByNear)
        let narrowedByFar = parameters.narrow(
            by: ViewportCameraDepthClip.AffineScalarBound(
                start: 1, end: 10, bound: 10, retainsValuesAtLeastBound: false
            )
        )
        #expect(narrowedByFar)
        let narrowedBySection = parameters.narrow(
            by: ViewportCameraDepthClip.AffineScalarBound(
                start: -1, end: 1, bound: 0, retainsValuesAtLeastBound: true
            )
        )
        #expect(narrowedBySection)
        #expect(parameters.isEmpty == false)
        #expect(parameters.lower == 0.5)
        #expect(parameters.upper == 1)
    }

    /// A constant section scalar on the removed side empties the interval, and
    /// an empty interval is an answer rather than a refusal.
    @Test func aConstantSectionScalarBehindTheCutEmptiesTheInterval() {
        var parameters = ViewportCameraDepthClip.ParameterInterval.whole
        let narrowed = parameters.narrow(
            by: ViewportCameraDepthClip.AffineScalarBound(
                start: -3, end: -3, bound: 0, retainsValuesAtLeastBound: true
            )
        )
        #expect(narrowed)
        #expect(parameters.isEmpty)
    }

    /// A bound the clip cannot represent is reported apart from an interval a
    /// bound emptied: the interval it was narrowed against is left untouched,
    /// so the caller refuses the segment instead of reporting it excluded.
    @Test func anUnrepresentableBoundLeavesTheIntervalUntouched() {
        let unrepresentable = [
            ViewportCameraDepthClip.AffineScalarBound(
                start: .nan, end: 1, bound: 0, retainsValuesAtLeastBound: true
            ),
            ViewportCameraDepthClip.AffineScalarBound(
                start: -1, end: .nan, bound: 0, retainsValuesAtLeastBound: true
            ),
            ViewportCameraDepthClip.AffineScalarBound(
                start: -1, end: 1, bound: .infinity, retainsValuesAtLeastBound: true
            ),
            ViewportCameraDepthClip.AffineScalarBound(
                start: -Double.greatestFiniteMagnitude,
                end: Double.greatestFiniteMagnitude,
                bound: 0,
                retainsValuesAtLeastBound: true
            ),
            ViewportCameraDepthClip.AffineScalarBound(
                start: -Double.greatestFiniteMagnitude,
                end: 0,
                bound: Double.greatestFiniteMagnitude,
                retainsValuesAtLeastBound: false
            ),
        ]
        for bound in unrepresentable {
            var parameters = ViewportCameraDepthClip.ParameterInterval.whole
            let narrowed = parameters.narrow(by: bound)
            #expect(narrowed == false)
            #expect(parameters.isEmpty == false)
            #expect(parameters.lower == 0)
            #expect(parameters.upper == 1)
        }
    }
}
