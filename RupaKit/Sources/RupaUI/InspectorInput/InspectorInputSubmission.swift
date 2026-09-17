import SwiftUI

enum InspectorInputSubmission {
    @TaskLocal static var controlID: UUID?
}

extension EnvironmentValues {
    @Entry var inspectorInputSequencer: ProjectWorkspaceOperationSequencer?
}
