import XCTest

final class RupaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["CanvasTool.select"].waitForExistence(timeout: 8))
    }

    @MainActor
    func testCanvasShowsCoordinateGridAndInPlaneRuler() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["CanvasTool.select"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.otherElements["CanvasCoordinateGrid"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["CanvasGridRuler"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["CanvasAxisTriad"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["CanvasProjectionIndicator"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testCanvasToolbarToolsReachEditorState() throws {
        let app = XCUIApplication()
        app.launch()
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
    func testSelectingObjectShowsViewportAffordance() throws {
        let app = XCUIApplication()
        app.launch()
        let canvas = app.otherElements["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))

        let solidTool = app.buttons["CanvasTool.solid"]
        XCTAssertTrue(solidTool.waitForExistence(timeout: 8))
        solidTool.click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.50)).click()

        let box = app.staticTexts["Box"]
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
            XCUIApplication().launch()
        }
    }
}
