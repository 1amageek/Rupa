import RupaCore

/// The viewport's overlay memo for the document it presents, replaced when the document identity
/// changes.
///
/// A `ViewportSourceIdentity` names one document: a published document generation is never
/// reused for other content (undo and redo advance it), and a presentation's
/// `EvaluationSnapshotID` names one evaluated content (a preview candidate carries its own
/// token). Non-observable, so asking during body evaluation cannot invalidate that body; all
/// access stays on the viewport's main actor.
@MainActor
final class ViewportDocumentOverlayMemoCache {
    private var entry: (source: ViewportSourceIdentity, memo: ViewportDocumentOverlayMemo)?

    func memo(for source: ViewportSourceIdentity, document: DesignDocument) -> ViewportDocumentOverlayMemo {
        if let entry, entry.source == source { return entry.memo }
        let memo = ViewportDocumentOverlayMemo(document: document)
        entry = (source, memo)
        return memo
    }
}
