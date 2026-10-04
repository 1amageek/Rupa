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
///
/// Reblend (bodies only) recomputes the body's round fillets on the deformed faces at their radii.
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
    public var reblends: Bool
    /// The source curves stay; without it Deform replaces them.
    public var keepsTools: Bool

    public init(
        scaleU: Double = 1, scaleV: Double = 1, scaleN: Double = 1,
        offsetU: Double = 0, offsetV: Double = 0, offsetN: CADExpression = .length(0, .meter),
        mirrors: Bool = false, flipsUV: Bool = false, flipsNormal: Bool = false,
        reblends: Bool = false, keepsTools: Bool = false
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
        self.reblends = reblends
        self.keepsTools = keepsTools
    }

    private enum CodingKeys: String, CodingKey {
        case scaleU, scaleV, scaleN, offsetU, offsetV, offsetN, mirrors, flipsUV, flipsNormal, reblends, keepsTools
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scaleU = try container.decode(Double.self, forKey: .scaleU)
        scaleV = try container.decode(Double.self, forKey: .scaleV)
        scaleN = try container.decode(Double.self, forKey: .scaleN)
        offsetU = try container.decode(Double.self, forKey: .offsetU)
        offsetV = try container.decode(Double.self, forKey: .offsetV)
        offsetN = try container.decode(CADExpression.self, forKey: .offsetN)
        mirrors = try container.decode(Bool.self, forKey: .mirrors)
        flipsUV = try container.decode(Bool.self, forKey: .flipsUV)
        flipsNormal = try container.decode(Bool.self, forKey: .flipsNormal)
        // Values written before Reblend existed bend fillets with the body.
        reblends = try container.decodeIfPresent(Bool.self, forKey: .reblends) ?? false
        keepsTools = try container.decode(Bool.self, forKey: .keepsTools)
    }

    /// The values as Swift-CAD's UVN map.
    var wrapOptions: WrapOptions {
        WrapOptions(
            scaleU: scaleU, scaleV: scaleV, scaleN: scaleN, offsetU: offsetU, offsetV: offsetV, offsetN: offsetN,
            mirrors: mirrors, flipsUV: flipsUV, flipsNormal: flipsNormal, reblends: reblends
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
