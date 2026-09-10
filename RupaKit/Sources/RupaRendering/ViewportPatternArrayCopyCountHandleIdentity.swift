import RupaCore

/// Stable identity of one pattern array's copy count handle.
///
/// A pattern array exposes one copy count handle per populated slot, so the
/// slot is part of the identity: two handles of the same source differ only by
/// which count they edit.
struct ViewportPatternArrayCopyCountHandleIdentity: Equatable, Sendable {
    var sourceID: PatternArraySourceID
    var slot: ViewportPatternArrayCopyCountSlot
}
