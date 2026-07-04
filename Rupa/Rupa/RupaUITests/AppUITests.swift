import XCTest

final class AppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchArguments += arguments
        app.launch()
        return app
    }

    @MainActor
    private func expandUtilityRailIfNeeded(in app: XCUIApplication) {
        let expandButton = app.buttons["WorkspaceUtilityRail.expand"]
        if expandButton.waitForExistence(timeout: 1) {
            expandButton.click()
        }
    }

    @MainActor
    func testExample() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["CanvasTool.select"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testCanvasShowsCoordinateGridAndInPlaneRuler() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["CanvasTool.select"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["CanvasCoordinateGrid"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["CanvasGridRuler"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["CanvasAxisTriad"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["CanvasProjectionIndicator"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testWorkspaceChromeExposesSnapPlaneAndContextControls() throws {
        let app = launchApp()

        XCTAssertTrue(app.buttons["CanvasTool.select"].waitForExistence(timeout: 8))

        let objectScope = app.buttons["WorkspaceSelectionScope.object"]
        XCTAssertTrue(objectScope.waitForExistence(timeout: 3))
        XCTAssertEqual(objectScope.value as? String, "Selected")

        let faceScope = app.buttons["WorkspaceSelectionScope.face"]
        XCTAssertTrue(faceScope.waitForExistence(timeout: 3))
        XCTAssertEqual(faceScope.value as? String, "Available")
        faceScope.click()
        XCTAssertEqual(faceScope.value as? String, "Selected")

        let edgeScope = app.buttons["WorkspaceSelectionScope.edge"]
        XCTAssertTrue(edgeScope.waitForExistence(timeout: 3))
        XCTAssertTrue(edgeScope.isEnabled)
        XCTAssertEqual(edgeScope.value as? String, "Available")
        edgeScope.click()
        XCTAssertEqual(edgeScope.value as? String, "Selected")

        let gridSnap = app.buttons["WorkspaceSnap.grid"]
        XCTAssertTrue(gridSnap.waitForExistence(timeout: 3))
        XCTAssertEqual(gridSnap.value as? String, "On")
        gridSnap.click()
        XCTAssertEqual(gridSnap.value as? String, "Off")

        let objectTargeting = app.buttons["WorkspaceSnap.object"]
        XCTAssertTrue(objectTargeting.waitForExistence(timeout: 3))
        XCTAssertEqual(objectTargeting.value as? String, "On")

        let xyPlane = app.buttons["WorkspacePlane.xy"]
        XCTAssertTrue(xyPlane.waitForExistence(timeout: 3))
        XCTAssertEqual(xyPlane.value as? String, "Available")
        xyPlane.click()
        XCTAssertEqual(xyPlane.value as? String, "Selected")

        XCTAssertTrue(app.buttons["WorkspaceCommand.validate"].exists)
        XCTAssertTrue(app.buttons["WorkspaceCommand.inspector"].exists)
    }

    @MainActor
    func testFaceSelectionModeShowsSubobjectTarget() throws {
        let app = launchApp()
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))

        let solidTool = app.buttons["CanvasTool.solid"]
        XCTAssertTrue(solidTool.waitForExistence(timeout: 3))
        solidTool.click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).click()

        let box = app.outlines.staticTexts["Box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["CanvasSelectionAffordance"].waitForExistence(timeout: 3))

        let selectTool = app.buttons["CanvasTool.select"]
        XCTAssertTrue(selectTool.waitForExistence(timeout: 3))
        selectTool.click()

        let faceScope = app.buttons["WorkspaceSelectionScope.face"]
        XCTAssertTrue(faceScope.waitForExistence(timeout: 3))
        faceScope.click()
        XCTAssertEqual(faceScope.value as? String, "Selected")

        let frontFace = app.descendants(matching: .any)["CanvasBodyFace.front"]
        XCTAssertTrue(frontFace.waitForExistence(timeout: 3))
        frontFace.click()

        let targetValue = app.staticTexts["WorkspaceSelection.target"]
        XCTAssertTrue(targetValue.waitForExistence(timeout: 3))
        let displayedTarget = (targetValue.value as? String) ?? targetValue.label
        XCTAssertTrue(displayedTarget.hasSuffix("Face"), displayedTarget)
    }

    @MainActor
    func testEdgeSelectionModeShowsChamferCommand() throws {
        let app = launchApp()
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))

        let solidTool = app.buttons["CanvasTool.solid"]
        XCTAssertTrue(solidTool.waitForExistence(timeout: 3))
        solidTool.click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).click()

        let box = app.outlines.staticTexts["Box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3))

        let selectTool = app.buttons["CanvasTool.select"]
        XCTAssertTrue(selectTool.waitForExistence(timeout: 3))
        selectTool.click()

        let edgeScope = app.buttons["WorkspaceSelectionScope.edge"]
        XCTAssertTrue(edgeScope.waitForExistence(timeout: 3))
        edgeScope.click()
        XCTAssertEqual(edgeScope.value as? String, "Selected")

        let leftTopEdge = app.descendants(matching: .any)["CanvasBodyEdge.leftTop"]
        XCTAssertTrue(leftTopEdge.waitForExistence(timeout: 3))
        leftTopEdge.click()

        let targetValue = app.staticTexts["WorkspaceSelection.target"]
        XCTAssertTrue(targetValue.waitForExistence(timeout: 3))
        let displayedTarget = (targetValue.value as? String) ?? targetValue.label
        XCTAssertTrue(displayedTarget.hasSuffix("Edge"), displayedTarget)
        let inspectorButton = app.buttons["WorkspaceCommand.inspector"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 3))
        inspectorButton.click()
        XCTAssertTrue(app.buttons["InspectorEdge.fillet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["InspectorEdge.chamfer"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCanvasToolbarToolsReachEditorState() throws {
        let app = launchApp()
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))

        let sketchTool = app.buttons["CanvasTool.sketch"]
        XCTAssertTrue(sketchTool.waitForExistence(timeout: 8))
        sketchTool.click()
        XCTAssertEqual(app.buttons["CanvasTool.sketch"].value as? String, "Selected")
        XCTAssertFalse(app.staticTexts["Rectangle Sketch"].exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).click()
        XCTAssertTrue(app.staticTexts["Rectangle Sketch"].waitForExistence(timeout: 3))

        let solidTool = app.buttons["CanvasTool.solid"]
        XCTAssertTrue(solidTool.waitForExistence(timeout: 3))
        solidTool.click()
        XCTAssertEqual(app.buttons["CanvasTool.solid"].value as? String, "Selected")
        XCTAssertFalse(app.staticTexts["Box"].exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.35)).click()
        XCTAssertTrue(app.staticTexts["Box"].waitForExistence(timeout: 3))

        let surfaceTool = app.buttons["CanvasTool.surface"]
        XCTAssertTrue(surfaceTool.waitForExistence(timeout: 3))
        surfaceTool.click()
        XCTAssertEqual(app.buttons["CanvasTool.surface"].value as? String, "Selected")
        XCTAssertFalse(app.staticTexts["Circle Sketch"].exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.40)).click()
        XCTAssertTrue(app.staticTexts["Circle Sketch"].waitForExistence(timeout: 3))

        let sectionTool = app.buttons["CanvasTool.section"]
        XCTAssertTrue(sectionTool.waitForExistence(timeout: 3))
        sectionTool.click()
        XCTAssertEqual(app.buttons["CanvasTool.section"].value as? String, "Selected")
        XCTAssertFalse(app.staticTexts["Section Plane"].exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.35)).click()
        XCTAssertTrue(app.staticTexts["Section Plane"].waitForExistence(timeout: 3))

        let measureTool = app.buttons["CanvasTool.measure"]
        XCTAssertTrue(measureTool.waitForExistence(timeout: 3))
        measureTool.click()
        XCTAssertEqual(app.buttons["CanvasTool.measure"].value as? String, "Selected")

        let meshTool = app.buttons["CanvasTool.mesh"]
        XCTAssertTrue(meshTool.waitForExistence(timeout: 3))
        meshTool.click()
        XCTAssertEqual(app.buttons["CanvasTool.mesh"].value as? String, "Selected")
    }

    @MainActor
    func testActiveCustomConstructionPlaneLaunchFixtureSupportsCanvasCreation() throws {
        let app = launchApp(arguments: ["--rupa-ui-fixture=active-custom-cplane"])
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))

        expandUtilityRailIfNeeded(in: app)
        let activePlane = app.descendants(matching: .any)["WorkspacePlane.activeName"]
        XCTAssertTrue(activePlane.waitForExistence(timeout: 3))
        XCTAssertEqual(activePlane.value as? String, "Arbitrary CPlane")

        let sketchTool = app.buttons["CanvasTool.sketch"]
        XCTAssertTrue(sketchTool.waitForExistence(timeout: 3))
        sketchTool.click()
        XCTAssertEqual(sketchTool.value as? String, "Selected")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.44, dy: 0.56)).click()
        XCTAssertTrue(app.staticTexts["Rectangle Sketch"].waitForExistence(timeout: 3))

        let solidTool = app.buttons["CanvasTool.solid"]
        XCTAssertTrue(solidTool.waitForExistence(timeout: 3))
        solidTool.click()
        XCTAssertEqual(solidTool.value as? String, "Selected")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.42)).click()
        XCTAssertTrue(app.staticTexts["Box"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testSelectingObjectShowsViewportAffordance() throws {
        let app = launchApp()
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))

        let solidTool = app.buttons["CanvasTool.solid"]
        XCTAssertTrue(solidTool.waitForExistence(timeout: 8))
        solidTool.click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).click()

        let box = app.outlines.staticTexts["Box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 3))

        let selectTool = app.buttons["CanvasTool.select"]
        XCTAssertTrue(selectTool.waitForExistence(timeout: 3))
        selectTool.click()
        box.click()

        XCTAssertTrue(app.otherElements["CanvasSelectionAffordance"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            _ = launchApp()
        }
    }
}
