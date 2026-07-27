import Foundation
import RupaAgentProtocol
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

    @discardableResult
    func registerNew(
        session: EditorSession,
        path: URL? = nil,
        id: UUID = UUID()
    ) throws -> UUID {
        guard entries[id] == nil else {
            throw EditorError(
                code: .commandInvalid,
                message: "Session \(id.uuidString) is already registered."
            )
        }
        if let path,
           let existingID = registeredSessionID(for: path) {
            throw EditorError(
                code: .documentOpenInApp,
                message: "Document \(path.standardizedFileURL.path) is already open in session \(existingID.uuidString)."
            )
        }
        entries[id] = Entry(session: session, path: path?.standardizedFileURL)
        return id
    }

    public func unregister(id: UUID) {
        entries[id] = nil
    }

    public func session(id: UUID) throws -> EditorSession {
        guard let entry = entries[id] else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No open session exists for \(id.uuidString)."
            )
        }
        return entry.session
    }

    public func documentURL(id: UUID) throws -> URL {
        guard let entry = entries[id] else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No open session exists for \(id.uuidString)."
            )
        }
        guard let path = entry.path else {
            throw EditorError(
                code: .commandInvalid,
                message: "The open session does not have a file path to save."
            )
        }
        return path
    }

    func registeredSessionID(for url: URL) -> UUID? {
        let normalizedPath = url.standardizedFileURL.path
        return entries.first { _, entry in
            entry.path?.standardizedFileURL.path == normalizedPath
        }?.key
    }

    func summary(id: UUID) throws -> WorkspaceSessionSummary {
        guard let entry = entries[id] else {
            throw EditorError(
                code: .sessionNotFound,
                message: "No open session exists for \(id.uuidString)."
            )
        }
        return Self.summary(id: id, entry: entry)
    }

    public func summaries() -> [WorkspaceSessionSummary] {
        entries
            .map { id, entry in
                Self.summary(id: id, entry: entry)
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private static func summary(id: UUID, entry: Entry) -> WorkspaceSessionSummary {
        WorkspaceSessionSummary(
            id: id,
            path: entry.path?.path,
            displayName: entry.session.document.cadDocument.metadata.name ?? "Untitled",
            dirty: entry.session.isDirty,
            generation: entry.session.generation,
            workspaceRevision: entry.session.workspaceState.revision
        )
    }
}
