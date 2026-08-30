import Testing
@testable import RupaUI

@Test func projectTitlePresentationUsesPublishedProjectName() {
    #expect(
        ProjectTitlePresentation.title(projectName: "Loaded Gearbox")
            == "Loaded Gearbox"
    )
}

@Test func projectTitlePresentationFallsBackForAnEmptyProjectName() {
    #expect(ProjectTitlePresentation.title(projectName: "") == "Untitled")
    #expect(ProjectTitlePresentation.title(projectName: "  \n") == "Untitled")
}
