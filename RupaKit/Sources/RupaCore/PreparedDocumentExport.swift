import Foundation

/// One fully evaluated export staged beside its final destination.
///
/// The caller owns the value and must invoke exactly one of `publish()` or
/// `discard()` when `stagedURL` is present.
public struct PreparedDocumentExport: Sendable {
    public let result: ExportResult

    private let stagedURL: URL?
    private let destinationURL: URL
    private let destinationPolicy: ExportPreset.DestinationPolicy

    init(
        result: ExportResult,
        stagedURL: URL?,
        destinationURL: URL,
        destinationPolicy: ExportPreset.DestinationPolicy
    ) {
        self.result = result
        self.stagedURL = stagedURL
        self.destinationURL = destinationURL
        self.destinationPolicy = destinationPolicy
    }

    public func publish() throws -> ExportResult {
        guard let stagedURL else {
            return result
        }
        do {
            let fileManager = FileManager.default
            switch destinationPolicy {
            case .overwrite:
                if fileManager.fileExists(atPath: destinationURL.path) {
                    _ = try fileManager.replaceItemAt(
                        destinationURL,
                        withItemAt: stagedURL
                    )
                } else {
                    try fileManager.moveItem(at: stagedURL, to: destinationURL)
                }
            case .prompt, .versioned:
                try fileManager.moveItem(at: stagedURL, to: destinationURL)
            }
            return result
        } catch {
            throw EditorError(
                code: .exportFailed,
                message: "Staged export could not be published atomically to \(destinationURL.path): \(error.localizedDescription)"
            )
        }
    }

    public func discard() throws {
        guard let stagedURL,
              FileManager.default.fileExists(atPath: stagedURL.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: stagedURL)
        } catch {
            throw EditorError(
                code: .exportFailed,
                message: "Staged export could not be discarded at \(stagedURL.path): \(error.localizedDescription)"
            )
        }
    }
}
