import SwiftCAD

/// Deform Curve's dialog values. A curve point reads as UVN coordinates on the reference face
/// (`FaceUVNChart`: s and t across the face's parameter box, n its height along the outward
/// normal) and is placed at the mapped coordinates on the target face:
///
/// 1. UV swaps s and t; Mirror reflects s across the face's middle (s → 1 − s).
/// 2. U and V scale about the face's middle and then shift by their offset, a fraction of the
///    target face (s → ½ + (s − ½)·scaleU + offsetU).
/// 3. N scales the height, adds its offset (a length) and Normal flips the result.
public struct CurveDeformationOptions: Codable, Equatable, Sendable {
    public var scaleU: Double
    public var scaleV: Double
    public var scaleN: Double
    public var offsetU: Double
    public var offsetV: Double
    public var offsetN: CADExpression
    public var mirrors: Bool
    public var flipsUV: Bool
    public var flipsNormal: Bool
    /// The source curves stay; without it Deform replaces them.
    public var keepsTools: Bool

    public init(
        scaleU: Double = 1, scaleV: Double = 1, scaleN: Double = 1,
        offsetU: Double = 0, offsetV: Double = 0, offsetN: CADExpression = .length(0, .meter),
        mirrors: Bool = false, flipsUV: Bool = false, flipsNormal: Bool = false,
        keepsTools: Bool = false
    ) {
        self.scaleU = scaleU
        self.scaleV = scaleV
        self.scaleN = scaleN
        self.offsetU = offsetU
        self.offsetV = offsetV
        self.offsetN = offsetN
        self.mirrors = mirrors
        self.flipsUV = flipsUV
        self.flipsNormal = flipsNormal
        self.keepsTools = keepsTools
    }

    /// The target coordinate for a reference coordinate; `offsetN` is resolved, in meters.
    func mapped(_ coordinate: UVNCoordinate, offsetN: Double) -> UVNCoordinate {
        var s = coordinate.s, t = coordinate.t
        if flipsUV { swap(&s, &t) }
        if mirrors { s = 1 - s }
        let n = coordinate.n * scaleN + offsetN
        return UVNCoordinate(
            s: 0.5 + (s - 0.5) * scaleU + offsetU,
            t: 0.5 + (t - 0.5) * scaleV + offsetV,
            n: flipsNormal ? -n : n
        )
    }

    func validate() throws {
        guard [scaleU, scaleV, scaleN, offsetU, offsetV].allSatisfy(\.isFinite),
              scaleU != 0, scaleV != 0 else {
            throw EditorError(code: .commandInvalid, message: "Deform needs finite values and nonzero U and V scales.")
        }
    }
}
