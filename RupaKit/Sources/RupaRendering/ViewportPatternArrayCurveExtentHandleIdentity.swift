import RupaCore

/// Stable identity of one curve pattern array's extent handle.
///
/// A curve pattern owns exactly one extent handle, so the source address is the
/// complete identity. Whether the extent is authored as a distance or a ratio
/// is a value of the edit, not a distinct handle.
struct ViewportPatternArrayCurveExtentHandleIdentity: Equatable, Sendable {
    var sourceID: PatternArraySourceID
}
