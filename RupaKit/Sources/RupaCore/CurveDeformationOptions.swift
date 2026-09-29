import SwiftCAD

/// Deform's dialog values, for curves and bodies alike. A point reads as UVN coordinates on the
/// reference face (`FaceUVNChart`: s and t across the face's parameter extent, n its height along
/// the outward normal) and is placed at the mapped coordinates on the target face, by Swift-CAD's
/// `WrapOptions` (curves here, bodies in the kernel's Wrap):
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

    /// The values as Swift-CAD's UVN map.
    var wrapOptions: WrapOptions {
        WrapOptions(
            scaleU: scaleU, scaleV: scaleV, scaleN: scaleN, offsetU: offsetU, offsetV: offsetV, offsetN: offsetN,
            mirrors: mirrors, flipsUV: flipsUV, flipsNormal: flipsNormal
        )
    }

    /// The target coordinate for a reference coordinate; `offsetN` is resolved, in meters.
    func mapped(_ coordinate: UVNCoordinate, offsetN: Double) -> UVNCoordinate {
        let mapped = wrapOptions.mapped(s: coordinate.s, t: coordinate.t, n: coordinate.n, offsetN: offsetN)
        return UVNCoordinate(s: mapped.s, t: mapped.t, n: mapped.n)
    }

    /// A curve may be flattened onto the target face (N scale 0); a body may not, which the
    /// kernel's Wrap refuses.
    func validate() throws {
        guard [scaleU, scaleV, scaleN, offsetU, offsetV].allSatisfy(\.isFinite),
              scaleU != 0, scaleV != 0 else {
            throw EditorError(code: .commandInvalid, message: "Deform needs finite values and nonzero U and V scales.")
        }
    }
}
