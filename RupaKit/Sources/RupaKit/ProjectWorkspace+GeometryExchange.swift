import Foundation
import RupaCoreTypes
import RupaProject

extension ProjectWorkspace {
    /// Writes one frozen geometry snapshot. Atomic file publication is not cancellable.
    public func exportGeometry(to url: URL, format: ProjectGeometryFileFormat, unit: LengthDisplayUnit) async throws {
        try Task.checkCancellation()
        guard let snapshot = view else {
            throw ProjectWorkspaceActionError(code: .snapshotUnavailable, message: "Export requires a published project view.")
        }
        let task = Task.detached {
            let data = try ProjectGeometryExport.data(from: snapshot, format: format, unit: unit)
            try Task.checkCancellation()
            // Foundation owns same-directory staging and atomic replacement. No
            // cancellation check after this publish point may hide a written file.
            try data.write(to: url, options: .atomic)
        }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    @discardableResult
    public func importGeometry(
        from url: URL,
        format: ProjectGeometryFileFormat,
        unitForUnmarkedData: LengthDisplayUnit?,
        operationGuard: @escaping ProjectOperationGuard = {}
    ) async throws -> ProjectWorkspaceActionResult {
        guard let snapshot = view else {
            throw ProjectWorkspaceActionError(code: .snapshotUnavailable, message: "Import requires a published project view.")
        }
        try operationGuard()
        let task = Task.detached {
            try Task.checkCancellation()
            return try ProjectGeometryImport.transaction(
                from: url, format: format, unitForUnmarkedData: unitForUnmarkedData, snapshot: snapshot
            )
        }
        let transaction = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        try Task.checkCancellation()
        try operationGuard()
        return try await perform(.source(transaction), operationGuard: operationGuard)
    }
}
