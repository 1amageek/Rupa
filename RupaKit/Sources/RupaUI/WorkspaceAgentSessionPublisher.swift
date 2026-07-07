import RupaCore
import SwiftUI

@MainActor
struct WorkspaceAgentSessionPublisher: ViewModifier {
    var publisher: (any WorkspaceAgentSessionPublishing)?
    var session: EditorSession
    var path: URL?

    @State private var publication = WorkspaceAgentSessionPublication()

    func body(content: Content) -> some View {
        content
            .task(id: WorkspaceAgentSessionPublication.Key(
                publisher: publisher,
                session: session,
                path: path
            )) {
                publication.publish(
                    publisher: publisher,
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
        publisher: (any WorkspaceAgentSessionPublishing)?,
        session: EditorSession,
        path: URL?
    ) -> some View {
        modifier(WorkspaceAgentSessionPublisher(
            publisher: publisher,
            session: session,
            path: path
        ))
    }
}
