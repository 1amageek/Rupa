import RupaCore

/// The viewport's overlay memo for the document it presents, replaced when the document identity
/// changes.
///
/// A `ViewportSourceIdentity` names one document: a document generation or presentation snapshot
/// never names two different documents. Non-observable, so asking during body evaluation cannot
/// invalidate that body; all access stays on the viewport's main actor.
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
