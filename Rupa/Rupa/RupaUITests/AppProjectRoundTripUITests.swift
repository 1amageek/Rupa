import AppKit
import XCTest

/// Exercises the end-to-end product path a user takes in the shipped app:
/// create a solid, select it, edit one of its faces, save the project through
/// the sandbox save panel, quit, and reopen the saved file.
final class AppProjectRoundTripUITests: XCTestCase {

    private var workingDirectoryURL: URL?

    /// Every failure the workspace recorded while the round trip ran, in the
    /// order the two launches reported them. Nothing on this path is meant to
    /// be refused, so a non-empty list is the defect the sweep exists to find.
    private var recordedFailures: [String] = []

    /// What each launch read back without judging it. A passing round trip
    /// asserts only that nothing was recorded, so the readouts that carry the
    /// counts are printed as well, and a green run still says what it saw.
    private var observations: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RupaProjectRoundTrip", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        workingDirectoryURL = directory
    }

    override func tearDownWithError() throws {
        if !recordedFailures.isEmpty {
            print("Workspace failures recorded during the round trip:")
            for failure in recordedFailures {
                print("  - \(failure)")
            }
        }
        recordedFailures.removeAll()
        if !observations.isEmpty {
            print("Round trip observations:")
            for observation in observations {
                print("  - \(observation)")
            }
        }
        observations.removeAll()
        guard let workingDirectoryURL else { return }
        if FileManager.default.fileExists(atPath: workingDirectoryURL.path) {
            try FileManager.default.removeItem(at: workingDirectoryURL)
        }
        self.workingDirectoryURL = nil
    }

    // MARK: - Round trip

    @MainActor
    func testProjectSurvivesCreateSelectEditSaveAndReload() throws {
        let workingDirectory = try XCTUnwrap(workingDirectoryURL)
        let savedProjectURL = workingDirectory
            .appendingPathComponent("RoundTrip.rupa", isDirectory: false)

        let app = launchApp()
        let canvas = app.descendants(matching: .any)["CanvasViewport"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        assertProjectIsAvailable(in: app)

        // Create.
        let solidTool = app.buttons["CanvasTool.solid"]
        XCTAssertTrue(solidTool.waitForExistence(timeout: 5))
        solidTool.click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.outlines.staticTexts["Box"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["CanvasPresentationFailure"].exists)

        // Select.
        let selectTool = app.buttons["CanvasTool.select"]
        XCTAssertTrue(selectTool.waitForExistence(timeout: 5))
        selectTool.click()
        let createdBounds = measureWorldBounds(in: app)
        XCTAssertFalse(
            createdBounds.isEmpty,
            "The workspace reports no world bounds for the created solid."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["CanvasSelectionAffordance"]
                .waitForExistence(timeout: 10),
            """
            The select tool draws no object affordance for the created solid, \
            so the workspace resolved no exact CAD context for it and the \
            face scope cannot reach its topology either.
            """
        )

        // Edit one face.
        expandSelectionRail(in: app)
        let faceScope = app.buttons["WorkspaceSelectionScope.face"]
        XCTAssertTrue(
            faceScope.waitForExistence(timeout: 5),
            "Selection scope is unreachable. Application elements: \(app.debugDescription)"
        )
        faceScope.click()
        XCTAssertEqual(faceScope.value as? String, "Selected")
        selectFaceOnCanvas(in: app, canvas: canvas)
        let offsetPositive = revealFaceInspector(in: app)
        XCTAssertTrue(offsetPositive.isHittable)
        offsetPositive.click()
        // The face stays the selected target after the edit, and the workspace
        // measures whole bodies only, so return the scope to the body first.
        let objectScope = app.buttons["WorkspaceSelectionScope.object"]
        XCTAssertTrue(objectScope.waitForExistence(timeout: 5))
        objectScope.click()
        XCTAssertEqual(objectScope.value as? String, "Selected")
        let editedBounds = measureWorldBounds(in: app, settlingFrom: createdBounds)
        XCTAssertFalse(
            editedBounds.isEmpty,
            "The world bounds readout never reported a measurement after the edit."
        )
        XCTAssertNotEqual(
            editedBounds,
            createdBounds,
            "Face offset did not change the measured world bounds."
        )

        // Save.
        try saveProjectAs(
            app,
            directory: workingDirectory,
            fileName: savedProjectURL.lastPathComponent
        )
        XCTAssertTrue(
            waitForFile(at: savedProjectURL, timeout: 30),
            """
            The save panel completed but no project file was written to \
            \(savedProjectURL.path). \
            \(projectFailureAlertReport(in: app) ?? "The app reported no failure.")
            """
        )
        assertProjectIsAvailable(in: app)
        harvestRecordedFailures(in: app, stage: "create, edit and save")
        app.terminate()

        // Reload.
        let reopened = launchApp(arguments: ["--rupa-project=\(savedProjectURL.path)"])
        let reopenedCanvas = reopened.descendants(matching: .any)["CanvasViewport"]
        XCTAssertTrue(reopenedCanvas.waitForExistence(timeout: 20))
        assertProjectIsAvailable(in: reopened)
        XCTAssertTrue(reopened.outlines.staticTexts["Box"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(reopened.descendants(matching: .any)["CanvasPresentationFailure"].exists)

        let reopenedSelectTool = reopened.buttons["CanvasTool.select"]
        XCTAssertTrue(reopenedSelectTool.waitForExistence(timeout: 5))
        reopenedSelectTool.click()
        XCTAssertEqual(
            measureWorldBounds(in: reopened),
            editedBounds,
            "The reopened project does not measure the geometry that was saved."
        )
        harvestRecordedFailures(in: reopened, stage: "reload")
        reopened.terminate()

        XCTAssertTrue(
            recordedFailures.isEmpty,
            """
            The round trip recorded workspace failures: \
            \(recordedFailures.joined(separator: " | "))
            """
        )
    }

    // MARK: - Failure record helpers

    /// Reads back what the workspace recorded, the way a user checks it: the
    /// scene rail reports how many failures the session holds, and the Logs
    /// pane keeps their text after the red inline labels are gone. The record
    /// is process-wide, so one read before a launch ends covers every
    /// operation that launch performed.
    /// See `RupaUI/DESIGN.md`, "Failure surfacing".
    @MainActor
    private func harvestRecordedFailures(in app: XCUIApplication, stage: String) {
        let issues = app.descendants(matching: .any)["WorkspaceScene.issues"]
        // An expanded rail already publishes the whole readout; a collapsed one
        // publishes compact destinations instead, and any of them expands it.
        if !issues.exists {
            let destinations = [
                "WorkspaceUtilityRail.scene",
                "WorkspaceUtilityRail.selection",
                "WorkspaceUtilityRail.expand",
            ]
            guard let opener = destinations
                .map({ app.buttons[$0] })
                .first(where: { $0.waitForExistence(timeout: 5) })
            else {
                recordedFailures.append(
                    "\(stage): the utility rail publishes neither the scene readout nor a way to open it."
                )
                return
            }
            opener.click()
        }
        guard issues.waitForExistence(timeout: 10) else {
            recordedFailures.append("\(stage): the scene rail published no issue readout.")
            return
        }
        let summary = (issues.value as? String) ?? issues.label
        observations.append("\(stage): issues read \(summary)")
        // "None" is the readout with no diagnostics and no records at all.
        guard summary != "None", !summary.hasPrefix("0 failures") else { return }
        let logs = app.buttons["WorkspaceCommand.logs"]
        guard logs.waitForExistence(timeout: 10) else {
            recordedFailures.append(
                "\(stage): issues read \(summary), and the Logs command is unreachable."
            )
            return
        }
        logs.click()
        let count = app.descendants(matching: .any)["WorkspaceFailureLog.count"]
        guard count.waitForExistence(timeout: 10) else {
            recordedFailures.append(
                "\(stage): issues read \(summary), but the Logs pane lists no record."
            )
            return
        }
        // Records without an `Error` value carry no detail row, so the two
        // lists do not line up by index. Report each list on its own terms.
        for entry in texts(of: "WorkspaceFailureLog.entry", in: app) {
            recordedFailures.append("\(stage): \(entry)")
        }
        for detail in texts(of: "WorkspaceFailureLog.detail", in: app) {
            recordedFailures.append("\(stage) detail: \(detail)")
        }
    }

    @MainActor
    private func texts(of identifier: String, in app: XCUIApplication) -> [String] {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .allElementsBoundByIndex
            .map { ($0.value as? String) ?? $0.label }
    }

    // MARK: - App helpers

    @MainActor
    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchArguments += arguments
        app.launch()
        zoomWindow(app)
        return app
    }

    /// The workspace opens at a size that leaves the inspector's face edit
    /// section below the visible area, so its controls never become hittable.
    /// Zoom the window once per launch so the pane reports the whole report.
    @MainActor
    private func zoomWindow(_ app: XCUIApplication) {
        let windowMenu = app.menuBarItems["Window"]
        XCTAssertTrue(windowMenu.waitForExistence(timeout: 15))
        windowMenu.click()
        let zoom = app.menuItems["Zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.click()
    }

    @MainActor
    private func assertProjectIsAvailable(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let alertReport = projectFailureAlertReport(in: app) {
            XCTFail(alertReport, file: file, line: line)
            return
        }
        let unavailable = app.descendants(matching: .any)["ApplicationProject.unavailable"]
        guard unavailable.exists else { return }
        let reasons = unavailable.descendants(matching: .staticText)
            .allElementsBoundByIndex
            .map(\.label)
            .joined(separator: " | ")
        XCTFail(
            "The project is unavailable: \(reasons.isEmpty ? unavailable.label : reasons)",
            file: file,
            line: line
        )
    }

    /// Reports the coordinator's failure alert, which is the only place the app
    /// surfaces a failed open, save, or commit.
    @MainActor
    private func projectFailureAlertReport(in app: XCUIApplication) -> String? {
        for container in [app.dialogs, app.sheets] {
            for alert in container.allElementsBoundByIndex {
                let labels = alert.descendants(matching: .staticText)
                    .allElementsBoundByIndex
                    .map(\.label)
                guard labels.contains(where: { $0.hasPrefix("Project Operation") }) else {
                    continue
                }
                return "The app reported a project failure: " + labels.joined(separator: " | ")
            }
        }
        return nil
    }

    /// Selection scope lives in the workspace utility rail, which ships
    /// collapsed. Opening the rail on its selection destination is the path a
    /// user takes to reach face scope.
    @MainActor
    private func expandSelectionRail(in app: XCUIApplication) {
        let selectionButton = app.buttons["WorkspaceUtilityRail.selection"]
        if selectionButton.waitForExistence(timeout: 5) {
            selectionButton.click()
            return
        }
        let expandButton = app.buttons["WorkspaceUtilityRail.expand"]
        if expandButton.waitForExistence(timeout: 2) {
            expandButton.click()
        }
    }

    // MARK: - Selection helpers

    /// Face scope commits through a canvas click, which is the path the shipped
    /// native hit test serves. The viewport centres the model bounds inside the
    /// chrome-inset fitting rectangle, so the created body does not stay under
    /// the point it was placed at. Each body face marker reports where one face
    /// of the body projects, and clicking the canvas there drives the same
    /// production pick a pointer over that face would. The markers cover the
    /// faces the camera hides as well, so the first point the frame resolves a
    /// face at answers the scope and the failure report names every point that
    /// resolved nothing.
    @MainActor
    private func selectFaceOnCanvas(in app: XCUIApplication, canvas: XCUIElement) {
        let target = app.staticTexts["WorkspaceSelection.target"]
        XCTAssertTrue(
            target.waitForExistence(timeout: 10),
            """
            The selection context panel does not report a target before the \
            canvas hit. Application elements: \(app.debugDescription)
            """
        )
        let placedTarget = targetSummary(of: target)
        let markers = projectedBodyFacePoints(in: app)
        guard !markers.isEmpty else {
            XCTFail(
                """
                No body accessibility marker reports where the created solid \
                is projected. Application elements: \(app.debugDescription)
                """
            )
            return
        }
        var refusals: [String] = []
        for marker in markers {
            click(canvas, at: marker.point)
            if waitForTargetSummary(target, hasSuffix: "Face", timeout: 5) { return }
            refusals.append(
                "\(marker.identifier) at \(marker.point) left \(targetSummary(of: target))"
            )
        }
        XCTFail(
            """
            Face scope resolved no face target from any canvas hit inside \
            \(canvas.frame). Target before the hits: \(placedTarget). \
            Refused hits: \(refusals.joined(separator: "; ")).
            """
        )
    }

    /// Returns where each face of the created body projects, in screen
    /// coordinates, paired with the marker identifier a failure report names.
    @MainActor
    private func projectedBodyFacePoints(
        in app: XCUIApplication
    ) -> [(identifier: String, point: CGPoint)] {
        let markers = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'CanvasBodyFace.'")
        )
        return (0 ..< markers.count).map { index in
            let element = markers.element(boundBy: index)
            let frame = element.frame
            return (element.identifier, CGPoint(x: frame.midX, y: frame.midY))
        }
    }

    @MainActor
    private func click(_ canvas: XCUIElement, at point: CGPoint) {
        let frame = canvas.frame
        let normalized = CGVector(
            dx: (point.x - frame.minX) / max(frame.width, 1.0),
            dy: (point.y - frame.minY) / max(frame.height, 1.0)
        )
        canvas.coordinate(withNormalizedOffset: normalized).click()
    }

    @MainActor
    private func targetSummary(of element: XCUIElement) -> String {
        guard element.exists else { return "" }
        return (element.value as? String) ?? element.label
    }

    @MainActor
    private func waitForTargetSummary(
        _ element: XCUIElement,
        hasSuffix suffix: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement, element.exists else {
                return false
            }
            let raw = (element.value as? String) ?? element.label
            return raw.hasSuffix(suffix)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The workspace ships with the inspector presented, so the command button
    /// is a toggle rather than a way to open it. Only use it when the face edit
    /// section is absent, which is the state a closed inspector reports.
    @MainActor
    private func revealFaceInspector(in app: XCUIApplication) -> XCUIElement {
        let offsetPositive = app.buttons["InspectorFace.offsetPositive"]
        if offsetPositive.waitForExistence(timeout: 10) { return offsetPositive }
        let inspectorButton = app.buttons["WorkspaceCommand.inspector"]
        XCTAssertTrue(inspectorButton.waitForExistence(timeout: 5))
        inspectorButton.click()
        XCTAssertTrue(
            offsetPositive.waitForExistence(timeout: 10),
            """
            The inspector reports no face edit section for the selected face. \
            Application elements: \(app.debugDescription)
            """
        )
        return offsetPositive
    }

    // MARK: - Measurement helpers

    @MainActor
    private func boundsSummary(of element: XCUIElement) -> String {
        guard element.exists else { return "" }
        let raw = (element.value as? String) ?? element.label
        return raw.replacingOccurrences(of: " (ruler hidden)", with: "")
    }

    @MainActor
    private func waitForBoundsSummary(
        _ element: XCUIElement,
        toDifferFrom initialSummary: String,
        timeout: TimeInterval
    ) -> String {
        let predicate = NSPredicate { candidate, _ in
            guard let element = candidate as? XCUIElement, element.exists else {
                return false
            }
            let raw = (element.value as? String) ?? element.label
            let summary = raw.replacingOccurrences(of: " (ruler hidden)", with: "")
            // The readout empties itself while the edit rebuilds the body, and
            // an empty measurement is not a measured change.
            return !summary.isEmpty && summary != initialSummary
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        _ = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return boundsSummary(of: element)
    }

    /// The workspace only reports world bounds while a scene node is the
    /// selection, so a face selection hides the readout. Measure the way a
    /// user reads the value back: select the body in the outline, then read.
    @MainActor
    private func measureWorldBounds(
        in app: XCUIApplication,
        settlingFrom previousSummary: String? = nil
    ) -> String {
        let row = app.outlines.staticTexts["Box"].firstMatch
        guard row.waitForExistence(timeout: 10) else {
            XCTFail(
                """
                The outline lists no body to measure. \
                Application elements: \(app.debugDescription)
                """
            )
            return ""
        }
        row.click()
        let bounds = app.staticTexts["WorkspaceMeasure.worldBounds"]
        guard bounds.waitForExistence(timeout: 10) else {
            XCTFail(
                """
                The workspace shows no world bounds readout for the body. \
                Application elements: \(app.debugDescription)
                """
            )
            return ""
        }
        guard let previousSummary else { return boundsSummary(of: bounds) }
        return waitForBoundsSummary(bounds, toDifferFrom: previousSummary, timeout: 8)
    }

    // MARK: - Save panel helpers

    @MainActor
    private func saveProjectAs(
        _ app: XCUIApplication,
        directory: URL,
        fileName: String
    ) throws {
        try invokeSaveProjectAs(in: app)
        let panel = try XCTUnwrap(
            waitForSavePanel(presentedBy: app),
            """
            "Save Project As…" did not present a save panel. \
            Application elements: \(app.debugDescription)
            """
        )
        // The panel runs modally inside the application, so drive it with key
        // events aimed at the front window instead of element actions.
        let goToSheet = panel.sheets.firstMatch
        app.typeKey("g", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            goToSheet.waitForExistence(timeout: 5),
            "\"Go to Folder\" did not open on the save panel."
        )
        // Typing a path lets the sheet rewrite the characters that follow its
        // inline completion, so hand over the whole destination at once and
        // let the completion settle before committing it.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(directory.path, forType: .string)
        app.typeKey("v", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
        app.typeKey(.return, modifierFlags: [])
        let goToDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: goToSheet
        )
        if XCTWaiter().wait(for: [goToDismissed], timeout: 10) != .completed {
            XCTFail(
                """
                The save panel's go-to sheet stayed open.
                """
            )
        }
        app.typeKey("a", modifierFlags: .command)
        app.typeText(fileName)
        app.typeKey(.return, modifierFlags: [])
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: panel
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [dismissed], timeout: 20),
            .completed,
            "The save panel stayed open: \(panel.debugDescription)"
        )
    }

    /// Uses the File menu so the test covers the shipped command wiring, and
    /// falls back to the shortcut the same command declares.
    @MainActor
    private func invokeSaveProjectAs(in app: XCUIApplication) throws {
        let fileMenu = app.menuBars.menuBarItems["File"]
        guard fileMenu.waitForExistence(timeout: 10) else {
            app.typeKey("s", modifierFlags: [.command, .shift])
            return
        }
        fileMenu.click()
        let saveAs = app.menuItems["Save Project As…"]
        guard saveAs.waitForExistence(timeout: 5) else {
            app.typeKey(.escape, modifierFlags: [])
            app.typeKey("s", modifierFlags: [.command, .shift])
            return
        }
        XCTAssertTrue(saveAs.isEnabled, "\"Save Project As…\" is disabled.")
        saveAs.click()
    }

    @MainActor
    private func waitForSavePanel(presentedBy app: XCUIApplication) -> XCUIElement? {
        let hostedDialog = app.dialogs.firstMatch
        if hostedDialog.waitForExistence(timeout: 10) {
            return hostedDialog
        }
        let hostedSheet = app.sheets.firstMatch
        if hostedSheet.waitForExistence(timeout: 5) {
            return hostedSheet
        }
        let service = XCUIApplication(
            bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService"
        )
        let remoteDialog = service.dialogs.firstMatch
        if remoteDialog.waitForExistence(timeout: 5) {
            return remoteDialog
        }
        let remoteWindow = service.windows.firstMatch
        if remoteWindow.waitForExistence(timeout: 5) {
            return remoteWindow
        }
        return nil
    }

    // MARK: - File helpers

    private func waitForFile(at url: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
