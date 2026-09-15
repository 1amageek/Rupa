import SwiftUI

/// Presents `WorkspaceFailureLog` above the evaluation diagnostics in Logs.
///
/// The red inline labels show one control's newest failure and are cleared by
/// the next interaction; this is where a failure stays readable afterwards.
/// It renders nothing while the log is empty, so a session without failures
/// keeps the Logs pane exactly as it was.
/// See `RupaUI/DESIGN.md`, "Failure surfacing".
struct WorkspaceFailureLogView: View {
    let records: [WorkspaceFailureRecord]
    let onClear: () -> Void

    var body: some View {
        if records.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        // Newest first: the failure just seen is the one read.
                        ForEach(records.reversed()) { record in
                            row(record)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                Divider()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("Failures", systemImage: "exclamationmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
            Text("\(records.count)")
                .font(.headline.monospacedDigit())
                .accessibilityIdentifier("WorkspaceFailureLog.count")
            Spacer(minLength: 0)
            Button("Clear", action: onClear)
                .accessibilityIdentifier("WorkspaceFailureLog.clear")
        }
    }

    private func row(_ record: WorkspaceFailureRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary(of: record))
                .font(.callout)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .accessibilityIdentifier("WorkspaceFailureLog.entry")
            if let detail = record.detail {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("WorkspaceFailureLog.detail")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(of record: WorkspaceFailureRecord) -> String {
        let time = record.timestamp.formatted(date: .omitted, time: .standard)
        return "\(time) · \(record.operation) · \(record.message)"
    }
}

#Preview("Recorded failures") {
    WorkspaceFailureLogView(
        records: [
            WorkspaceFailureRecord(
                operation: "previewModelingOperation()",
                message: "Select target CAD bodies, then a separate tool body last.",
                errorType: "RupaCoreTypes.EditorError",
                detail: #"EditorError(code: .commandInvalid, message: "…")"#
            ),
            WorkspaceFailureRecord(
                operation: "handleViewportSketchTransformCommit(_:)",
                message: "Sketch transforms need the Select tool in object scope."
            ),
        ],
        onClear: {}
    )
}

#Preview("No failures") {
    WorkspaceFailureLogView(records: [], onClear: {})
}
