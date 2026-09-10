import RupaCore

/// Stable identity of one pattern array's radial angle handle.
///
/// A radial pattern owns exactly one angle handle, so the source address is the
/// complete identity. The handle names the pattern array feature the commit
/// edits, never a scene-derived index or a rendered object.
struct ViewportPatternArrayRadialAngleHandleIdentity: Equatable, Sendable {
    var sourceID: PatternArraySourceID
}
