import SwiftUI

enum InspectorInputSubmission {
    @TaskLocal static var controlID: UUID?
}

extension EnvironmentValues {
    @Entry var inspectorInputDidSubmit: (@MainActor () -> Void)?
    @Entry var inspectorInputSequencer: ProjectWorkspaceOperationSequencer?
}
