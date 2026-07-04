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
    private func accessibilityValue(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    @MainActor
    private func dragElement(_ element: XCUIElement, by offset: CGVector) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.12, thenDragTo: start.withOffset(offset))
    }

    @MainActor
    private func waitForAccessibilityValueChange(
        of element: XCUIElement,
        from initialValue: String
    ) {
        let predicate = NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement else {
                return false
            }
            return (element.value as? String) != initialValue
        }
        expectation(for: predicate, evaluatedWith: element)
        waitForExpectations(timeout: 3)
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
    func testSelectedCustomConstructionPlaneLaunchFixtureExposesInspectorEditingControls() throws {
        let app = launchApp(arguments: ["--rupa-ui-fixture=selected-custom-cplane"])
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))
        XCTAssertTrue(
            app.descendants(matching: .any)["CanvasConstructionPlaneHandle.origin"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["CanvasConstructionPlaneHandle.normal"]
                .waitForExistence(timeout: 3)
        )

        let inspectorButton = app.buttons["WorkspaceCommand.inspector"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 3))
        inspectorButton.click()

        XCTAssertTrue(app.otherElements["InspectorPane"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["InspectorConstructionPlane.name"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["InspectorConstructionPlane.origin.x"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["InspectorConstructionPlane.origin.y"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["InspectorConstructionPlane.origin.z"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["InspectorConstructionPlane.normal.x"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["InspectorConstructionPlane.normal.y"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["InspectorConstructionPlane.normal.z"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertFalse(app.buttons["InspectorConstructionPlane.activate"].isEnabled)
        XCTAssertTrue(app.buttons["InspectorConstructionPlane.fromView"].exists)
    }

    @MainActor
    func testSelectedCustomConstructionPlaneViewportHandlesCommitDragEdits() throws {
        let app = launchApp(arguments: ["--rupa-ui-fixture=selected-custom-cplane"])
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))

        let originHandle = app.descendants(matching: .any)["CanvasConstructionPlaneHandle.origin"]
        XCTAssertTrue(originHandle.waitForExistence(timeout: 3))
        let initialOriginValue = accessibilityValue(of: originHandle)
        dragElement(originHandle, by: CGVector(dx: 72.0, dy: -28.0))
        waitForAccessibilityValueChange(of: originHandle, from: initialOriginValue)

        let normalHandle = app.descendants(matching: .any)["CanvasConstructionPlaneHandle.normal"]
        XCTAssertTrue(normalHandle.waitForExistence(timeout: 3))
        let initialNormalValue = accessibilityValue(of: normalHandle)
        dragElement(normalHandle, by: CGVector(dx: -48.0, dy: -44.0))
        waitForAccessibilityValueChange(of: normalHandle, from: initialNormalValue)
    }

    @MainActor
    func testSelectedCustomConstructionPlaneLaunchFixtureSupportsPlaneRailRename() throws {
        let app = launchApp(arguments: ["--rupa-ui-fixture=selected-custom-cplane"])
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))

        expandUtilityRailIfNeeded(in: app)
        let renameButton = app.buttons["Rename Arbitrary CPlane"]
        XCTAssertTrue(renameButton.waitForExistence(timeout: 3))
        renameButton.click()

        let renameField = app.textFields["Construction Plane Name"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 3))
        renameField.click()
        renameField.typeKey("a", modifierFlags: .command)
        renameField.typeText("Renamed CPlane")

        let commitButton = app.buttons["Commit Construction Plane Name"]
        XCTAssertTrue(commitButton.waitForExistence(timeout: 3))
        commitButton.click()

        XCTAssertTrue(app.buttons["Select Renamed CPlane"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testFaceSelectionCreatesSavedConstructionPlaneFromContextPanel() throws {
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

        let faceScope = app.buttons["WorkspaceSelectionScope.face"]
        XCTAssertTrue(faceScope.waitForExistence(timeout: 3))
        faceScope.click()
        XCTAssertEqual(faceScope.value as? String, "Selected")

        let frontFace = app.descendants(matching: .any)["CanvasBodyFace.front"]
        XCTAssertTrue(frontFace.waitForExistence(timeout: 3))
        frontFace.click()

        let createPlane = app.buttons["WorkspaceConstructionPlane.createFromSelection"]
        XCTAssertTrue(createPlane.waitForExistence(timeout: 3))
        createPlane.click()

        expandUtilityRailIfNeeded(in: app)
        let activePlane = app.descendants(matching: .any)["WorkspacePlane.activeName"]
        XCTAssertTrue(activePlane.waitForExistence(timeout: 3))
        XCTAssertEqual(activePlane.value as? String, "Custom Plane")
        XCTAssertTrue(app.buttons["Select Custom Plane"].waitForExistence(timeout: 3))
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
