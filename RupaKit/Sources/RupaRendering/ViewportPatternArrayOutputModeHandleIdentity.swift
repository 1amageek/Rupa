import RupaCore

/// Stable identity of one pattern array's output mode handle.
///
/// A pattern array owns exactly one output mode handle, so the source address
/// is the complete identity. The mode the handle would commit is derived from
/// the document at press time and is not part of the identity.
struct ViewportPatternArrayOutputModeHandleIdentity: Equatable, Sendable {
    var sourceID: PatternArraySourceID
}
