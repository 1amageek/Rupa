import Foundation
import SwiftCAD

public struct BridgeCurveSource: Codable, Hashable, Identifiable, Sendable {
    public var id: BridgeCurveSourceID
    public var featureID: FeatureID
    public var entityID: SketchEntityID
    public var firstEndpoint: BridgeCurveEndpoint
    public var secondEndpoint: BridgeCurveEndpoint
    public var continuity: BridgeCurveContinuity
    public var trimsSourceCurves: Bool
    /// What trimming the source curves changed, kept so Trim can be turned off again; absent while
    /// the sources are untrimmed, and on bridges trimmed before it was recorded.
    public var trimRecord: BridgeCurveTrimRecord?

    public init(
        id: BridgeCurveSourceID = BridgeCurveSourceID(),
        featureID: FeatureID,
        entityID: SketchEntityID,
        firstEndpoint: BridgeCurveEndpoint,
        secondEndpoint: BridgeCurveEndpoint,
        continuity: BridgeCurveContinuity,
        trimsSourceCurves: Bool = false,
        trimRecord: BridgeCurveTrimRecord? = nil
    ) {
        self.id = id
        self.featureID = featureID
        self.entityID = entityID
        self.firstEndpoint = firstEndpoint
        self.secondEndpoint = secondEndpoint
        self.continuity = continuity
        self.trimsSourceCurves = trimsSourceCurves
        self.trimRecord = trimRecord
    }
}

/// The source curves and ends a Bridge Curve's trim replaced, and the curves it left.
public struct BridgeCurveTrimRecord: Codable, Hashable, Sendable {
    /// The ends the bridge joined before the trim, with their parameters on the untrimmed curves.
    public var untrimmedFirstEndpoint: BridgeCurveEndpoint
    public var untrimmedSecondEndpoint: BridgeCurveEndpoint
    /// The source curves as they were before the trim.
    public var untrimmedEntities: [SketchEntityID: SketchEntity]
    /// The source curves as the trim left them; a curve edited since then is not restored.
    public var trimmedEntities: [SketchEntityID: SketchEntity]

    public init(
        untrimmedFirstEndpoint: BridgeCurveEndpoint,
        untrimmedSecondEndpoint: BridgeCurveEndpoint,
        untrimmedEntities: [SketchEntityID: SketchEntity],
        trimmedEntities: [SketchEntityID: SketchEntity]
    ) {
        self.untrimmedFirstEndpoint = untrimmedFirstEndpoint
        self.untrimmedSecondEndpoint = untrimmedSecondEndpoint
        self.untrimmedEntities = untrimmedEntities
        self.trimmedEntities = trimmedEntities
    }
}
