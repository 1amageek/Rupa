import Foundation

enum ProjectTitlePresentation {
    static func title(projectName: String) -> String {
        guard !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Untitled"
        }
        return projectName
    }
}
