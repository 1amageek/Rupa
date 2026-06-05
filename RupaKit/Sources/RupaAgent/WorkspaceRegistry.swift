import Foundation
import RupaCore

public final class WorkspaceRegistry {
    private struct Entry {
        var session: EditorSession
        var path: URL?
    }

    private var entries: [UUID: Entry]

    public init(entries: [UUID: (EditorSession, URL?)] = [:]) {
        self.entries = entries.mapValues { entry in
            Entry(session: entry.0, path: entry.1)
        }
    }

    @discardableResult
    public func register(
        session: EditorSession,
        path: URL? = nil,
        id: UUID = UUID()
    ) -> UUID {
        entries[id] = Entry(session: session, path: path)
        return id
    }

    public func unregister(id: UUID) {
        entries[id] = nil
    }

    public func session(id: UUID) throws -> EditorSession {
        guard let entry = entries[id] else {
            throw RupaError(
                code: .sessionNotFound,
                message: "No open session exists for \(id.uuidString)."
            )
        }
        return entry.session
    }

    public func documentURL(id: UUID) throws -> URL {
        guard let entry = entries[id] else {
            throw RupaError(
                code: .sessionNotFound,
                message: "No open session exists for \(id.uuidString)."
            )
        }
        guard let path = entry.path else {
            throw RupaError(
                code: .commandInvalid,
                message: "The open session does not have a file path to save."
            )
        }
        return path
    }

    public func summaries() -> [WorkspaceSessionSummary] {
        entries
            .map { id, entry in
                WorkspaceSessionSummary(
                    id: id,
                    path: entry.path?.path,
                    displayName: entry.session.document.cadDocument.metadata.name ?? "Untitled",
                    dirty: entry.session.isDirty,
                    generation: entry.session.generation
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }
}
