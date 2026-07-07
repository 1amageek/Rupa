import RupaCore
import SwiftUI

@MainActor
struct WorkspaceAgentSessionPublisher: ViewModifier {
    var host: (any WorkspaceAgentHost)?
    var session: EditorSession
    var path: URL?

    @State private var publication = WorkspaceAgentSessionPublication()

    func body(content: Content) -> some View {
        content
            .task(id: WorkspaceAgentSessionPublication.Key(
                host: host,
                session: session,
                path: path
            )) {
                publication.publish(
                    host: host,
                    session: session,
                    path: path
                )
            }
            .onDisappear {
                publication.deactivate()
            }
    }
}

extension View {
    func workspaceAgentSessionPublisher(
        host: (any WorkspaceAgentHost)?,
        session: EditorSession,
        path: URL?
    ) -> some View {
        modifier(WorkspaceAgentSessionPublisher(
            host: host,
            session: session,
            path: path
        ))
    }
}
