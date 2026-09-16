import XCTest

/// Drives the workspace operations only the shipped chrome reaches: the Model
/// menu drafts, the Analysis and Scene rail sections, the measure tool, and
/// the CAD-to-mesh editing route. Each test builds what it needs from the
/// GUI, so none of them depends on a launch fixture.
final class AppOperationCoverageUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        let windowMenu = app.menuBarItems["Window"]
        XCTAssertTrue(windowMenu.waitForExistence(timeout: 15))
        windowMenu.click()
        let zoom = app.menuItems["Zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.click()
        return app
    }

    @MainActor
    private func waitForCanvas(in app: XCUIApplication) -> XCUIElement {
        let viewport = app.descendants(matching: .any)["CanvasViewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 25))
        return viewport
    }

    @MainActor
    private func accessibilityValue(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    /// Every identifier the workspace publishes a failure on.
    ///
    /// A surface that renders a failure without an identifier cannot be read
    /// from a test at all, so a stalled control reports only that it never
    /// became ready. Naming the surfaces here lets both the error-absence
    /// assertion and the wait diagnostics quote what the application showed.
    private static let errorSurfaceIdentifiers = [
        "Modeling.error",
        "Modeling.mesh.error",
        "Modeling.historyPreview.error",
        "Modeling.meshOverlay.error",
        "Modeling.meshTarget.error",
        "WorkspaceDomainCommand.error",
        "WorkspaceObjectTransform.error",
        "WorkspaceObjectTransform.componentsError",
    ]

    /// Reads whatever failure text the application currently displays.
    @MainActor
    private func errorSurfaceReport(in app: XCUIApplication) -> String? {
        var displayed: [String] = []
        for identifier in Self.errorSurfaceIdentifiers {
            let surface = app.descendants(matching: .any)[identifier].firstMatch
            guard surface.exists else { continue }
            displayed.append("\(identifier): \(accessibilityValue(of: surface))")
        }
        return displayed.isEmpty ? nil : displayed.joined(separator: " | ")
    }

    @MainActor
    private func assertNoErrorSurface(
        in app: XCUIApplication,
        after step: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let report = errorSurfaceReport(in: app) else { return }
        XCTFail("\(step) left an error on screen: \(report)", file: file, line: line)
    }

    /// Names an element in a diagnostic, falling back when its label is empty.
    @MainActor
    private func diagnosticName(of element: XCUIElement) -> String {
        if element.label.isEmpty == false { return element.label }
        if element.identifier.isEmpty == false { return element.identifier }
        return "The awaited element"
    }

    @MainActor
    private func waitUntilEnabled(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ready = expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: element
        )
        guard XCTWaiter().wait(for: [ready], timeout: timeout) != .completed else {
            return
        }
        let displayed = errorSurfaceReport(in: app) ?? "no error surface was shown"
        XCTFail(
            "\(diagnosticName(of: element)) stayed disabled for \(timeout)s and \(displayed).",
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitUntilGone(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let gone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: element
        )
        guard XCTWaiter().wait(for: [gone], timeout: timeout) != .completed else {
            return
        }
        let displayed = errorSurfaceReport(in: app) ?? "no error surface was shown"
        XCTFail(
            "\(diagnosticName(of: element)) stayed on screen for \(timeout)s and \(displayed).",
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitForValue(
        _ expected: String,
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let matched = expectation(
            for: NSPredicate(format: "value == %@", expected),
            evaluatedWith: element
        )
        return XCTWaiter().wait(for: [matched], timeout: timeout) == .completed
    }

    /// Clicks the canvas where a captured marker frame projects.
    ///
    /// A sub-shape marker exists only while the select tool holds the object
    /// selection, so a test that clicks with another tool active captures the
    /// frame first and aims the canvas click at it afterwards.
    @MainActor
    private func clickCanvas(_ canvas: XCUIElement, at frame: CGRect) {
        let bounds = canvas.frame
        let normalized = CGVector(
            dx: (frame.midX - bounds.minX) / max(bounds.width, 1.0),
            dy: (frame.midY - bounds.minY) / max(bounds.height, 1.0)
        )
        canvas.coordinate(withNormalizedOffset: normalized).click()
    }

    /// Creates one box with the solid tool and returns its outline row.
    @MainActor
    private func createBox(in app: XCUIApplication, canvas: XCUIElement) -> XCUIElement {
        let solidTool = app.buttons["CanvasTool.solid"]
        XCTAssertTrue(solidTool.waitForExistence(timeout: 10))
        solidTool.click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let box = app.outlines.staticTexts["Box"].firstMatch
        XCTAssertTrue(box.waitForExistence(timeout: 15))
        return box
    }

    /// Selects the body in the outline and waits for the object affordance.
    @MainActor
    private func selectBody(_ box: XCUIElement, in app: XCUIApplication) {
        let selectTool = app.buttons["CanvasTool.select"]
        XCTAssertTrue(selectTool.waitForExistence(timeout: 10))
        selectTool.click()
        box.click()
        let affordance = app.descendants(matching: .any)["CanvasSelectionAffordance"]
        XCTAssertTrue(affordance.waitForExistence(timeout: 10))
    }

    @MainActor
    private func modelMenu(in app: XCUIApplication) -> XCUIElement {
        let menu = app.descendants(matching: .any)["WorkspaceCommand.model"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        return menu
    }

    @MainActor
    func testModelMenuPublishesEveryDraftAndCommitsABoxFromTheToolbar() throws {
        let app = launchApp()
        _ = waitForCanvas(in: app)
        XCTAssertFalse(app.outlines.staticTexts["Box"].exists)

        let menu = modelMenu(in: app)
        menu.click()
        let kinds = [
            "Box", "Cylinder", "Sphere", "Extrude", "Revolve",
            "Sweep", "Loft", "Boolean", "Fillet", "Chamfer",
        ]
        for kind in kinds {
            let item = app.menuItems["Modeling.begin.\(kind)"]
            XCTAssertTrue(item.waitForExistence(timeout: 5), kind)
            XCTAssertTrue(item.isEnabled, kind)
        }
        app.menuItems["Modeling.begin.Box"].click()

        let draft = app.descendants(matching: .any)["Modeling.operation"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        let preview = app.buttons["Modeling.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        preview.click()
        let apply = app.buttons["Modeling.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        waitUntilEnabled(apply, in: app, timeout: 40)
        apply.click()

        XCTAssertTrue(
            app.outlines.staticTexts["Box"].firstMatch.waitForExistence(timeout: 30)
        )
        waitUntilGone(draft, in: app, timeout: 30)
        assertNoErrorSurface(in: app, after: "Committing a box")
    }

    @MainActor
    func testAnalysisAndSceneRailSectionsPublishControlsAndReadouts() throws {
        let app = launchApp()
        _ = waitForCanvas(in: app)

        let analysisDestination = app.buttons["WorkspaceUtilityRail.analysis"]
        XCTAssertTrue(analysisDestination.waitForExistence(timeout: 15))
        XCTAssertTrue(analysisDestination.isHittable)
        analysisDestination.click()
        let rail = app.descendants(matching: .any)["WorkspaceUtilityRail.expanded"]
        XCTAssertTrue(rail.waitForExistence(timeout: 10))

        let overlay = app.descendants(matching: .any)["WorkspaceAnalysis.overlay"]
        XCTAssertTrue(overlay.waitForExistence(timeout: 10))
        XCTAssertEqual(accessibilityValue(of: overlay), "Comb + Dir + Trim")

        let combs = app.buttons["WorkspaceSurfaceAnalysis.curvatureCombs"]
        XCTAssertTrue(combs.waitForExistence(timeout: 5))
        XCTAssertTrue(combs.isHittable)
        XCTAssertEqual(accessibilityValue(of: combs), "On")
        combs.click()
        XCTAssertTrue(waitForValue("Off", of: combs, timeout: 10))
        XCTAssertTrue(waitForValue("Dir + Trim", of: overlay, timeout: 10))

        let samples = app.descendants(matching: .any)["WorkspaceAnalysis.samples"]
        XCTAssertTrue(samples.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibilityValue(of: samples), "5 x 5")
        let highDensity = app.buttons["WorkspaceSurfaceAnalysis.density.high"]
        XCTAssertTrue(highDensity.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibilityValue(of: highDensity), "Available")
        highDensity.click()
        XCTAssertTrue(waitForValue("Selected", of: highDensity, timeout: 10))
        XCTAssertTrue(waitForValue("9 x 9", of: samples, timeout: 10))

        let bodies = app.descendants(matching: .any)["WorkspaceScene.bodies"]
        let nodes = app.descendants(matching: .any)["WorkspaceScene.nodes"]
        let issues = app.descendants(matching: .any)["WorkspaceScene.issues"]
        XCTAssertTrue(bodies.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibilityValue(of: bodies), "0")
        XCTAssertEqual(accessibilityValue(of: nodes), "1")
        XCTAssertEqual(accessibilityValue(of: issues), "None")
        assertNoErrorSurface(in: app, after: "Reading the Analysis and Scene sections")
    }

    @MainActor
    func testMeasureToolReportsDistanceBetweenTwoPointsOnABody() throws {
        let app = launchApp()
        let canvas = waitForCanvas(in: app)
        let box = createBox(in: app, canvas: canvas)
        selectBody(box, in: app)

        let topMarker = app.descendants(matching: .any)["CanvasBodyFace.top"]
        let rightMarker = app.descendants(matching: .any)["CanvasBodyFace.right"]
        XCTAssertTrue(topMarker.waitForExistence(timeout: 10))
        XCTAssertTrue(rightMarker.waitForExistence(timeout: 10))
        let firstPoint = topMarker.frame
        let secondPoint = rightMarker.frame
        XCTAssertNotEqual(firstPoint, secondPoint)

        let measureTool = app.buttons["CanvasTool.measure"]
        XCTAssertTrue(measureTool.waitForExistence(timeout: 5))
        measureTool.click()
        let status = app.descendants(matching: .any)["WorkspaceMeasure.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))

        clickCanvas(canvas, at: firstPoint)
        XCTAssertTrue(
            waitForValue("Select a second point.", of: status, timeout: 15),
            accessibilityValue(of: status)
        )
        clickCanvas(canvas, at: secondPoint)

        let distance = app.descendants(matching: .any)["WorkspaceMeasure.distance"]
        XCTAssertTrue(
            distance.waitForExistence(timeout: 20),
            accessibilityValue(of: status)
        )
        XCTAssertFalse(accessibilityValue(of: distance).isEmpty)
        assertNoErrorSurface(in: app, after: "Measuring between two points")
    }

    @MainActor
    func testMeshEditingPanelCommitsAFaceDeletionFromTheCADRoute() throws {
        let app = launchApp()
        let canvas = waitForCanvas(in: app)
        let box = createBox(in: app, canvas: canvas)
        selectBody(box, in: app)

        let menu = modelMenu(in: app)
        menu.click()
        let makeEditable = app.menuItems["Make Selected CAD Editable as Mesh…"]
        XCTAssertTrue(makeEditable.waitForExistence(timeout: 5))
        XCTAssertTrue(makeEditable.isEnabled)
        makeEditable.click()

        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        let confirm = sheet.buttons["action-button-1"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "Make Editable")
        confirm.click()
        waitUntilGone(sheet, in: app, timeout: 15)
        // The Model menu is disabled while a modeling operation runs, so it
        // reads as enabled again only once the mesh source exists.
        waitUntilEnabled(menu, in: app, timeout: 60)
        XCTAssertTrue(app.staticTexts["Mesh Editing"].waitForExistence(timeout: 15))
        assertNoErrorSurface(in: app, after: "Making the selected CAD editable as Mesh")

        menu.click()
        let editMesh = app.menuItems["Edit Mesh Elements"]
        XCTAssertTrue(editMesh.waitForExistence(timeout: 5))
        editMesh.click()

        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let meshPanel = app.descendants(matching: .any)["Modeling.mesh"]
        XCTAssertTrue(meshPanel.waitForExistence(timeout: 20))
        for domain in ["Vertex", "Edge", "Face"] {
            XCTAssertTrue(meshPanel.radioButtons[domain].exists, domain)
        }

        let operation = meshPanel.popUpButtons.firstMatch
        XCTAssertTrue(operation.waitForExistence(timeout: 5))
        XCTAssertEqual(accessibilityValue(of: operation), "Move Elements")
        operation.click()
        let operations = [
            "Move Elements", "Set Vertex Position", "Extrude Faces",
            "Delete Faces", "Add Face",
        ]
        for kind in operations {
            XCTAssertTrue(app.menuItems[kind].waitForExistence(timeout: 5), kind)
        }
        app.menuItems["Delete Faces"].click()
        XCTAssertTrue(waitForValue("Delete Faces", of: operation, timeout: 10))

        let preview = meshPanel.buttons["Preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.isEnabled)
        preview.click()
        let apply = meshPanel.buttons["Apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        waitUntilEnabled(apply, in: app, timeout: 60)
        apply.click()
        // A committed mesh edit clears the draft and returns the select tool;
        // a rejected one keeps the panel open with its error.
        waitUntilGone(meshPanel, in: app, timeout: 60)
        assertNoErrorSurface(in: app, after: "Committing a face deletion")
    }

    /// A refusal the panel can evaluate is read before the press, not after
    /// it. Booleans need two bodies, so a Boolean draft in an empty document
    /// refuses deterministically through the shipped Model menu: Preview has
    /// to be disabled, the reason has to be beside it, and the Logs pane has
    /// to stay empty, because the reason is a function of the draft being
    /// shown rather than an event. See `RupaUI/DESIGN.md`, "Failure surfacing".
    @MainActor
    func testAPanelRefusalIsReadBeforeThePressAndRecordsNothing() throws {
        let app = launchApp()
        _ = waitForCanvas(in: app)

        let menu = modelMenu(in: app)
        menu.click()
        let boolean = app.menuItems["Modeling.begin.Boolean"]
        XCTAssertTrue(boolean.waitForExistence(timeout: 5))
        boolean.click()

        let draft = app.descendants(matching: .any)["Modeling.operation"]
        XCTAssertTrue(draft.waitForExistence(timeout: 10))

        let refusal = "Select target CAD bodies, then a separate tool body last."
        let reason = app.descendants(matching: .any)["Modeling.refusal"].firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 10))
        XCTAssertTrue(
            accessibilityValue(of: reason) == refusal || reason.label == refusal,
            "The panel showed \"\(reason.label)\" instead of the draft's reason."
        )

        // The press whose only outcome is that refusal is not offered, and the
        // reason is guidance rather than the report of a run that failed.
        let preview = app.buttons["Modeling.preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertFalse(
            preview.isEnabled,
            "Preview stayed pressable for a draft that names no command."
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["Modeling.error"].firstMatch.exists,
            "A refusal the panel evaluated was shown as a failed run."
        )

        // Nothing ran, so nothing is recorded. The Logs pane renders no
        // failure header at all while the log is empty, so the header's
        // absence is the read.
        let logs = app.buttons["WorkspaceCommand.logs"]
        XCTAssertTrue(logs.waitForExistence(timeout: 10))
        logs.click()
        let count = app.descendants(matching: .any)["WorkspaceFailureLog.count"]
        XCTAssertFalse(
            count.waitForExistence(timeout: 5),
            "A refusal the panel had already shown was recorded as a failure."
        )

        // Cancelling releases the draft and takes the reason with it.
        let cancel = draft.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.click()
        waitUntilGone(draft, in: app, timeout: 15)
        XCTAssertFalse(
            app.descendants(matching: .any)["Modeling.refusal"].firstMatch.exists
        )
    }

    /// Validate is a read, so pressing it reports what the evaluation found and
    /// records nothing. The command it names mutates no source, and a project
    /// source transaction carries only source-mutating commands, so the button
    /// asks the workspace to evaluate the published snapshot again instead.
    /// See `RupaUI/DESIGN.md`, "Contracts and Invariants".
    @MainActor
    func testValidateReportsTheEvaluationItRanAndRecordsNoFailure() throws {
        let app = launchApp()
        _ = waitForCanvas(in: app)

        // The Scene section reads the merged diagnostics, so it is where the
        // outcome of a press becomes visible.
        let sceneDestination = app.buttons["WorkspaceUtilityRail.scene"]
        XCTAssertTrue(sceneDestination.waitForExistence(timeout: 15))
        sceneDestination.click()
        let rail = app.descendants(matching: .any)["WorkspaceUtilityRail.expanded"]
        XCTAssertTrue(rail.waitForExistence(timeout: 10))
        let issues = app.descendants(matching: .any)["WorkspaceScene.issues"]
        XCTAssertTrue(issues.waitForExistence(timeout: 10))
        XCTAssertEqual(accessibilityValue(of: issues), "None")

        let validate = app.buttons["WorkspaceCommand.validate"]
        XCTAssertTrue(validate.waitForExistence(timeout: 10))
        XCTAssertTrue(validate.isEnabled)
        validate.click()

        // The press publishes one progress line and no failure, so the readout
        // moves to exactly one info entry with the failure count still at zero.
        XCTAssertTrue(
            waitForValue("0 failures, 0 errors, 0 warnings, 1 info", of: issues, timeout: 20),
            "Validate left the Scene readout at \"\(accessibilityValue(of: issues))\"."
        )

        // The Logs pane renders no failure header at all while the log is
        // empty, so the header's absence is the read.
        let logs = app.buttons["WorkspaceCommand.logs"]
        XCTAssertTrue(logs.waitForExistence(timeout: 10))
        logs.click()
        let count = app.descendants(matching: .any)["WorkspaceFailureLog.count"]
        XCTAssertFalse(
            count.waitForExistence(timeout: 5),
            "Validating a document the workspace could evaluate was recorded as a failure."
        )
        assertNoErrorSurface(in: app, after: "Validating the launch document")
    }
}
