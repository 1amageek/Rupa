import AppKit
import OSLog
import XCTest

/// Drives the operations the shipped chrome publishes and reads the workspace
/// failure record back after each one.
///
/// The coverage tests assert the result each operation is expected to produce.
/// None of them read `WorkspaceFailureLog`, so an operation that looks like it
/// succeeded while recording a failure passes all of them. This sweep closes
/// that gap: it performs an operation, reads the record, clears it, and reports
/// the operation that left an entry behind.
///
/// A record is not by itself a defect. `reportToolStatus` records a refused
/// operation as well as a thrown error, so a control that correctly refuses an
/// unmet precondition records too. The two are separable in the log: a thrown
/// error keeps its reflected value in `WorkspaceFailureLog.detail`, a refusal
/// carries none. `expectedRefusals` names the steps this workspace is supposed
/// to refuse; every other record is reported.
///
/// The sweep drives the real screen, so it has one environmental precondition
/// and states it rather than assuming it: nothing outside the app stands over
/// the app's window. `requireUnobstructedWindow` holds it, and a run that
/// cannot is stopped and named as an environment, not reported as a defect.
///
/// The sweep is opt-in. It drives the whole chrome and takes minutes, so it
/// runs only when `RUPA_UI_SWEEP` is set in the runner's environment. Under
/// xcodebuild the runner receives variables prefixed `TEST_RUNNER_`, so the
/// invocation sets `TEST_RUNNER_RUPA_UI_SWEEP=1`.
final class AppFailureSweepUITests: XCTestCase {
    /// Step markers. The app records failures through `os_log`, so a marker in
    /// the same timeline attributes a record to the step that was running.
    private static let marker = Logger(subsystem: "RupaUISweep", category: "step")

    /// Steps whose refusal is the shipped behaviour. A step named here is still
    /// reported when it records a thrown error rather than a refusal.
    private static let expectedRefusals: Set<String> = []

    /// Controls a step declined to click because the chrome published them
    /// disabled. A step that clicks nothing records nothing, and `sweep` would
    /// read that as clean, so the run reports them rather than passing over
    /// them in silence.
    private var declinedControls: [String] = []

    /// Menus the app publishes with nothing opened, measured once at launch.
    /// macOS publishes the menu bar's own menus, so a count is only evidence
    /// of chrome standing over the window when it exceeds this.

    /// What was found standing over the app's window, once anything was. The
    /// sweep stops measuring at that point: every later step would read as
    /// unclickable for a reason outside the app, and each of those reads costs
    /// a cross-process accessibility query.
    private var obstruction: String?

    /// The app this run drives, so a step that finds the screen covered can
    /// put it back in front before the run is stopped.
    private var drivenApp: XCUIApplication?

    /// Applications this run hid so the sweep could reach the app's window.
    /// They are put back when the run ends, whether or not it passed.
    private var hiddenApplications: [NSRunningApplication] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUPA_UI_SWEEP"] == "1",
            "Set TEST_RUNNER_RUPA_UI_SWEEP=1 to run the failure sweep"
        )
        // Every step reports on its own line; one refused control must not hide
        // the rest of the sweep.
        continueAfterFailure = true
    }

    override func tearDownWithError() throws {
        // A control the chrome published disabled was never exercised. The run
        // read no failure for it, which is not the same as the operation having
        // worked, so the coverage it did not reach is stated rather than left
        // to look like a clean pass.
        if declinedControls.isEmpty == false {
            Self.marker.error(
                "declined \(self.declinedControls.joined(separator: ","), privacy: .public)"
            )
        }
        declinedControls.removeAll()
        for application in hiddenApplications {
            application.unhide()
        }
        hiddenApplications.removeAll()
    }

    // MARK: - Sweeps

    /// Each group of controls the chrome publishes is its own test.
    ///
    /// The sweep drives the real app, so a run costs minutes, and a run that
    /// covers every group can only be repeated as a whole: a group already
    /// read clean has to be driven again to reach the group that has not been.
    /// Split by group, a clean group is not re-read, a failing group is re-read
    /// on its own, and a run stopped by the screen leaves the groups it did not
    /// reach individually runnable. Each test launches the app, so no group
    /// inherits another's document, selection, or chrome state.

    @MainActor
    func testCanvasToolsOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepCanvasTools(in: app, stage: "empty")
    }

    @MainActor
    func testUtilityRailOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepUtilityRail(in: app, stage: "empty")
    }

    @MainActor
    func testSelectionScopesOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepSelectionScopes(in: app, stage: "empty")
    }

    @MainActor
    func testPlaneModesOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepPlaneModes(in: app, stage: "empty")
    }

    @MainActor
    func testViewportControlsOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepViewportControls(in: app, stage: "empty")
    }

    @MainActor
    func testToolbarCommandsOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepToolbarCommands(in: app, stage: "empty")
    }

    @MainActor
    func testModelingDraftsOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepModelingDrafts(in: app, stage: "empty")
    }

    @MainActor
    func testSidebarOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepSidebar(in: app, stage: "empty")
    }

    @MainActor
    func testEditMenuOnTheLaunchDocument() throws {
        let app = prepareWorkspace()
        sweepEditMenu(in: app, stage: "empty")
    }

    @MainActor
    func testCreatingAndSelectingABody() throws {
        let app = prepareWorkspace()
        selectABody(in: app)
    }

    @MainActor
    func testCanvasToolsWithABodySelected() throws {
        let app = prepareWorkspace()
        selectABody(in: app)
        sweepCanvasTools(in: app, stage: "selected")
    }

    @MainActor
    func testSelectionScopesWithABodySelected() throws {
        let app = prepareWorkspace()
        selectABody(in: app)
        sweepSelectionScopes(in: app, stage: "selected")
    }

    @MainActor
    func testPlaneModesWithABodySelected() throws {
        let app = prepareWorkspace()
        selectABody(in: app)
        sweepPlaneModes(in: app, stage: "selected")
    }

    @MainActor
    func testViewportControlsWithABodySelected() throws {
        let app = prepareWorkspace()
        selectABody(in: app)
        sweepViewportControls(in: app, stage: "selected")
    }

    @MainActor
    func testToolbarCommandsWithABodySelected() throws {
        let app = prepareWorkspace()
        selectABody(in: app)
        sweepToolbarCommands(in: app, stage: "selected")
    }

    @MainActor
    func testModelingDraftsWithABodySelected() throws {
        let app = prepareWorkspace()
        selectABody(in: app)
        sweepModelingDrafts(in: app, stage: "selected")
    }

    @MainActor
    func testEditMenuWithABodySelected() throws {
        let app = prepareWorkspace()
        selectABody(in: app)
        sweepEditMenu(in: app, stage: "selected")
    }

    // MARK: - Fixtures

    /// Brings the workspace to the state every group is read from: the canvas
    /// mounted and the Logs pane open, since the pane is what publishes the
    /// failure record each step is read back out of.
    @MainActor
    private func prepareWorkspace() -> XCUIApplication {
        let app = launchApp()
        _ = waitForCanvas(in: app)
        openLogsPane(in: app)
        return app
    }

    /// Creates one body and selects it, which is the state the "selected"
    /// stage of a group is read in.
    ///
    /// Both steps are swept rather than merely performed, so a failure the app
    /// records while reaching that state is reported against the step that
    /// caused it instead of against the group under test.
    @MainActor
    private func selectABody(in app: XCUIApplication) {
        let canvas = waitForCanvas(in: app)
        sweep("solid: create a box", in: app, settle: 20.0) {
            let solidTool = app.buttons["CanvasTool.solid"]
            guard solidTool.waitForExistence(timeout: 10) else {
                XCTFail("CanvasTool.solid is missing")
                return
            }
            solidTool.click()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            XCTAssertTrue(app.outlines.staticTexts["Box"].firstMatch.waitForExistence(timeout: 20))
        }
        sweep("select: pick the box in the outline", in: app, settle: 10.0) {
            let selectTool = app.buttons["CanvasTool.select"]
            guard selectTool.waitForExistence(timeout: 10) else {
                XCTFail("CanvasTool.select is missing")
                return
            }
            selectTool.click()
            let box = app.outlines.staticTexts["Box"].firstMatch
            guard box.waitForExistence(timeout: 10) else {
                XCTFail("The outline never published the box")
                return
            }
            box.click()
            let affordance = app.descendants(matching: .any)["CanvasSelectionAffordance"]
            XCTAssertTrue(affordance.waitForExistence(timeout: 10))
        }
    }


    // MARK: - Groups

    @MainActor
    private func sweepCanvasTools(in app: XCUIApplication, stage: String) {
        let tools = [
            "select", "sketch", "polygon", "arc", "spline",
            "solid", "sweep", "surface", "mesh", "measure", "section",
        ]
        for tool in tools {
            sweep("\(stage)/tool.\(tool)", in: app) {
                self.click("CanvasTool.\(tool)", in: app)
            }
        }
        sweep("\(stage)/tool.select restore", in: app) {
            self.click("CanvasTool.select", in: app)
        }
    }

    @MainActor
    private func sweepUtilityRail(in app: XCUIApplication, stage: String) {
        let destinations = [
            "expand", "selection", "snap", "plane", "analysis", "views", "scene",
        ]
        for destination in destinations {
            sweep("\(stage)/rail.\(destination)", in: app) {
                self.collapseUtilityRail(in: app)
                self.click("WorkspaceUtilityRail.\(destination)", in: app)
            }
        }
    }

    @MainActor
    private func sweepSelectionScopes(in app: XCUIApplication, stage: String) {
        openUtilityRail(at: "selection", in: app)
        for scope in ["object", "face", "edge", "vertex", "region", "sketchEntity"] {
            sweep("\(stage)/scope.\(scope)", in: app) {
                self.click("WorkspaceSelectionScope.\(scope)", in: app)
            }
        }
        sweep("\(stage)/scope.object restore", in: app) {
            self.click("WorkspaceSelectionScope.object", in: app)
        }
    }

    @MainActor
    private func sweepPlaneModes(in app: XCUIApplication, stage: String) {
        openUtilityRail(at: "plane", in: app)
        for mode in ["adaptive", "xy", "yz", "zx"] {
            sweep("\(stage)/plane.\(mode)", in: app) {
                self.click("WorkspacePlane.\(mode)", in: app)
            }
        }
        sweep("\(stage)/plane.adaptive restore", in: app) {
            self.click("WorkspacePlane.adaptive", in: app)
        }
    }

    @MainActor
    private func sweepViewportControls(in app: XCUIApplication, stage: String) {
        sweep("\(stage)/viewport.fit", in: app, settle: 3.0) {
            // `Menu` with a primary action, so the chrome publishes it as a
            // pop-up button, and it stays disabled while the scene holds
            // nothing to fit.
            self.click("WorkspaceViewport.fit", as: .popUpButton, in: app)
        }
        for mode in ["Solid", "Solid + Mesh Edges", "Wireframe", "Normals"] {
            sweep("\(stage)/viewport.displayMode.\(mode)", in: app, settle: 3.0) {
                let identifier = "WorkspaceViewport.displayMode.\(mode)"
                guard self.openMenu(
                    "WorkspaceViewport.displayMode", expecting: identifier, in: app
                ) else {
                    return
                }
                app.menuItems[identifier].firstMatch.click()
            }
        }
        sweep("\(stage)/viewport.shading", in: app, settle: 3.0) {
            self.click("WorkspaceViewport.shading", in: app)
            self.click("WorkspaceViewport.shading", in: app)
        }
    }

    @MainActor
    private func sweepToolbarCommands(in app: XCUIApplication, stage: String) {
        sweep("\(stage)/command.validate", in: app, settle: 20.0) {
            self.click("WorkspaceCommand.validate", in: app)
        }
        sweep("\(stage)/command.inspector show", in: app, settle: 3.0) {
            self.click("WorkspaceCommand.inspector", in: app)
        }
        sweep("\(stage)/command.inspector hide", in: app, settle: 3.0) {
            self.click("WorkspaceCommand.inspector", in: app)
        }
    }

    @MainActor
    private func sweepModelingDrafts(in app: XCUIApplication, stage: String) {
        let kinds = [
            "Box", "Cylinder", "Sphere", "Extrude", "Revolve",
            "Sweep", "Loft", "Boolean", "Fillet", "Chamfer",
        ]
        for kind in kinds {
            sweep("\(stage)/model.begin.\(kind)", in: app, settle: 3.0) {
                let identifier = "Modeling.begin.\(kind)"
                guard self.openMenu(
                    "WorkspaceCommand.model", expecting: identifier, in: app
                ) else {
                    return
                }
                app.menuItems[identifier].firstMatch.click()
                XCTAssertTrue(
                    app.descendants(matching: .any)["Modeling.operation"].waitForExistence(timeout: 10),
                    "Modeling.begin.\(kind) opened no draft"
                )
            }
            sweep("\(stage)/model.preview.\(kind)", in: app, settle: 30.0) {
                let preview = app.buttons["Modeling.preview"]
                guard preview.waitForExistence(timeout: 5) else {
                    XCTFail("Modeling.preview is missing for \(kind)")
                    return
                }
                guard preview.isEnabled else {
                    // A disabled Preview is only correct when the panel is
                    // saying why it refuses the draft. Without that reason a
                    // dead button reads exactly like a refusal the panel saw.
                    XCTAssertTrue(
                        app.descendants(matching: .any)["Modeling.refusal"]
                            .firstMatch.waitForExistence(timeout: 5),
                        "Modeling.preview is disabled for \(kind) with no reason beside it"
                    )
                    return
                }
                preview.click()
            }
            sweep("\(stage)/model.cancel.\(kind)", in: app, settle: 3.0) {
                self.cancelModelingDraft(in: app)
            }
        }
        sweep("\(stage)/model.editMeshElements", in: app, settle: 3.0) {
            guard self.openMenu(
                "WorkspaceCommand.model", expecting: "Edit Mesh Elements", in: app
            ) else {
                return
            }
            app.menuItems["Edit Mesh Elements"].firstMatch.click()
        }
        sweep("\(stage)/model.editMeshElements cancel", in: app, settle: 3.0) {
            self.cancelModelingDraft(in: app)
        }
    }

    @MainActor
    private func sweepSidebar(in app: XCUIApplication, stage: String) {
        for section in ["History", "Scene"] {
            sweep("\(stage)/sidebar.\(section)", in: app, settle: 3.0) {
                let segment = app.radioButtons[section].firstMatch
                guard segment.waitForExistence(timeout: 5) else {
                    XCTFail("The sidebar segment \(section) is missing")
                    return
                }
                segment.click()
            }
        }
    }

    @MainActor
    private func sweepEditMenu(in app: XCUIApplication, stage: String) {
        for command in ["Undo", "Redo"] {
            sweep("\(stage)/edit.\(command)", in: app, settle: 10.0) {
                let edit = app.menuBarItems["Edit"]
                guard edit.waitForExistence(timeout: 5) else {
                    XCTFail("The Edit menu is missing")
                    return
                }
                edit.click()
                let item = app.menuItems[command].firstMatch
                guard item.waitForExistence(timeout: 5) else {
                    XCTFail("\(command) is missing")
                    return
                }
                if item.isEnabled {
                    item.click()
                } else {
                    edit.typeKey(.escape, modifierFlags: [])
                }
            }
        }
    }

    // MARK: - Step

    /// Runs one step, then reads what the workspace recorded while it ran.
    @MainActor
    private func sweep(
        _ name: String,
        in app: XCUIApplication,
        settle: TimeInterval = 1.0,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () -> Void
    ) {
        // Something outside the app was already found over its window. What a
        // step measures after that is about the screen, not the workspace.
        guard obstruction == nil else { return }
        Self.marker.error("sweep begin \(name, privacy: .public)")
        let declinedBefore = declinedControls.count
        body()
        requireClearChrome(after: name, in: app, file: file, line: line)
        let readout = waitForFailureRecord(in: app, timeout: settle)
        guard case .count(let count) = readout else {
            XCTFail(
                "\(name) could not read the failure record: \(readout.reason)",
                file: file, line: line
            )
            return
        }
        let declined = declinedControls.suffix(from: declinedBefore)
        guard count > 0 else {
            let outcome = declined.isEmpty ? "clean" : "clean but declined \(declined.joined(separator: ","))"
            Self.marker.error("sweep end \(name, privacy: .public) \(outcome, privacy: .public)")
            return
        }
        let entries = labels(of: "WorkspaceFailureLog.entry", in: app)
        let details = labels(of: "WorkspaceFailureLog.detail", in: app)
        let kind = details.isEmpty ? "refusal" : "error"
        Self.marker.error(
            "sweep end \(name, privacy: .public) \(kind, privacy: .public) \(entries.joined(separator: " | "), privacy: .public)"
        )
        if !(details.isEmpty && Self.expectedRefusals.contains(name)) {
            var report = "\(name) recorded \(count) \(kind): " + entries.joined(separator: " | ")
            if details.isEmpty == false {
                report += " || " + details.joined(separator: " | ")
            }
            XCTFail(report, file: file, line: line)
        }
        clearFailureRecord(in: app)
    }

    // MARK: - Failure record

    /// What the Logs pane says about the number of recorded failures.
    ///
    /// A pane that publishes nothing is not a pane that recorded nothing. If
    /// the readout goes away mid-sweep, every later step would read clean and
    /// the run would pass without having read anything at all, so the two are
    /// separate cases here rather than one optional.
    private enum FailureReadout {
        case count(Int)
        /// The Logs pane is not publishing the readout, so nothing can be read.
        case paneClosed
        /// The readout is published but does not read as a number.
        case unreadable(String)

        var reason: String {
            switch self {
            case .count(let value): return "read \(value)"
            case .paneClosed: return "the Logs pane is not publishing the readout"
            case .unreadable(let text): return "the readout says \"\(text)\""
            }
        }
    }

    /// `WorkspaceFailureLogView` publishes the count whether or not anything
    /// failed, so an absent readout means the pane is closed.
    @MainActor
    private func failureReadout(in app: XCUIApplication) -> FailureReadout {
        let element = app.descendants(matching: .any)["WorkspaceFailureLog.count"].firstMatch
        guard element.exists else { return .paneClosed }
        let text = element.label.isEmpty ? ((element.value as? String) ?? "") : element.label
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return .unreadable(trimmed) }
        return .count(value)
    }

    @MainActor
    private func waitForFailureRecord(
        in app: XCUIApplication, timeout: TimeInterval
    ) -> FailureReadout {
        let deadline = Date().addingTimeInterval(timeout)
        var last = failureReadout(in: app)
        repeat {
            last = failureReadout(in: app)
            if case .count(let value) = last, value > 0 { return last }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return last
    }

    @MainActor
    private func labels(of identifier: String, in app: XCUIApplication) -> [String] {
        app.descendants(matching: .any)
            .matching(identifier: identifier)
            .allElementsBoundByIndex
            .map { $0.label.isEmpty ? (($0.value as? String) ?? "") : $0.label }
    }

    /// Empties the record so the next step reads only what it recorded itself.
    ///
    /// A clear that does not take leaves the previous step's entry in front of
    /// the next one, which then reports a failure it did not cause.
    @MainActor
    private func clearFailureRecord(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let clear = resolve(
            "WorkspaceFailureLog.clear", as: .button, in: app, file: file, line: line
        ) else {
            return
        }
        clear.click()
        for _ in 0..<100 {
            if case .count(0) = failureReadout(in: app) { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail(
            "WorkspaceFailureLog.clear did not empty the log: "
                + failureReadout(in: app).reason,
            file: file, line: line
        )
    }

    // MARK: - Chrome

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        // A launch does not guarantee the app owns the screen it is about to
        // be clicked on. Activating it is the part of that the sweep can fix;
        // `requireUnobstructedWindow` below is what actually checks it, since
        // a floating window sits above the active app's own level.
        app.activate()
        let windowMenu = app.menuBarItems["Window"]
        XCTAssertTrue(windowMenu.waitForExistence(timeout: 15))
        windowMenu.click()
        let zoom = app.menuItems["Zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.click()
        // The Window menu this launch opened has to close before the run reads
        // the chrome it starts from, or the first step inherits it.
        for _ in 0..<100 {
            if zoom.exists == false { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        Self.marker.error("chrome at launch \(self.chromeInventory(in: app), privacy: .public)")
        drivenApp = app
        clearTheScreen(so: app)
        requireUnobstructedWindow(before: "the first step")
        return app
    }

    /// Names every menu the launch snapshot carries, open or not.
    ///
    /// `chromeState(in:)` reads "open" off a menu's area, so a tree that
    /// published no menu at all would let every step pass without checking
    /// anything. Recording the inventory once says which of those a clean run
    /// was: a menu bar the snapshot sees, or one it does not.
    @MainActor
    private func chromeInventory(in app: XCUIApplication) -> String {
        let root: XCUIElementSnapshot
        do {
            root = try app.snapshot()
        } catch {
            return "unreadable: \(error)"
        }
        var menus: [String] = []
        var pending = [root]
        while let node = pending.popLast() {
            pending.append(contentsOf: node.children)
            guard node.elementType == .menu else { continue }
            menus.append(Self.describe(node))
        }
        return menus.isEmpty
            ? "the snapshot published no menu"
            : menus.joined(separator: "; ")
    }

    @MainActor
    private func waitForCanvas(in app: XCUIApplication) -> XCUIElement {
        let viewport = app.descendants(matching: .any)["CanvasViewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 25))
        return viewport
    }

    /// `WorkspaceFailureLogView` lives in the Logs pane, which starts collapsed.
    /// Without this the sweep reads nothing and passes vacuously, so the run
    /// holds until the readout every step reads is on screen. The readout
    /// itself is what is waited for: any other label would leave the sweep
    /// reading a pane it never confirmed was open.
    @MainActor
    private func openLogsPane(in app: XCUIApplication) {
        let toggle = app.buttons["WorkspaceCommand.logs"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        toggle.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["WorkspaceFailureLog.count"]
                .firstMatch.waitForExistence(timeout: 15),
            "The Logs pane never published its readout, so no record can be read"
        )
    }

    /// Clicks one control the chrome publishes.
    ///
    /// The caller names the element type because the chrome publishes several:
    /// a plain control arrives as a button, and a `Menu` carrying a primary
    /// action arrives as a pop-up button. Looking for a button either way makes
    /// a control that is present read as absent, which is a different failure
    /// from the one it would be reporting.
    @MainActor
    private func click(
        _ identifier: String,
        as type: XCUIElement.ElementType = .button,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let element = resolve(identifier, as: type, in: app, file: file, line: line) else {
            return
        }
        guard element.isEnabled else {
            declinedControls.append(identifier)
            Self.marker.error("declined disabled \(identifier, privacy: .public)")
            return
        }
        element.click()
    }

    // MARK: - Environment

    /// The bundle the sweep drives. `XCUIApplication` publishes no process id,
    /// and the window server's listing is keyed by process.
    private static let applicationBundleIdentifier = "team.stamp.Rupa"

    /// One window, outside the app, standing over the app's window.
    private struct CoveringWindow {
        var owner: String
        var pid: Int
        var level: Int
        var frame: CGRect

        var described: String {
            "\(owner) (pid \(pid)) at \(frame) on level \(level)"
        }
    }

    /// What the window server says about the screen the sweep clicks on.
    private enum ScreenState {
        /// Nothing outside the app stands over its window.
        case clear
        /// Windows outside the app stand over its window.
        case covered(window: CGRect, by: [CoveringWindow])
        /// The screen could not be read, which is not the same as clear.
        case unreadable(String)

        /// What has to be reported, or `nil` when the precondition holds.
        var obstruction: String? {
            switch self {
            case .clear:
                return nil
            case .covered(let window, let covering):
                return "the app's window at \(window) is covered by "
                    + covering.map(\.described).joined(separator: "; ")
            case .unreadable(let reason):
                return reason
            }
        }
    }

    /// Reads what stands over the app's window.
    ///
    /// `isHittable` is answered by hit-testing the screen rather than the app,
    /// so a window belonging to another process over the app's window makes
    /// every control in it unhittable -- correctly. Reading that answer means
    /// querying the covering process through accessibility, which in one run
    /// cost a minute per control and then reported the app's own chrome as the
    /// thing nothing could click. Neither the delay nor that name is the app's.
    ///
    /// The window server says the same thing directly. Its listing is ordered
    /// front to back, and owner, process, level and bounds are readable with no
    /// accessibility or screen recording authorisation; the window's title,
    /// which would need one, is not read. Activating the app does not answer
    /// this question: a window at a floating level stays above the active
    /// application's own.
    ///
    /// A screen that cannot be read is not a clear screen, so it is reported
    /// rather than passed over: a precondition that cannot be established has
    /// not been established.
    @MainActor
    private func screenState() -> ScreenState {
        let running = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.applicationBundleIdentifier
        )
        guard running.count == 1, let process = running.first else {
            return .unreadable(
                "\(running.count) processes are running \(Self.applicationBundleIdentifier), "
                    + "so which window belongs to the app the sweep launched cannot be decided"
            )
        }
        let pid = Int(process.processIdentifier)
        guard let listing = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return .unreadable(
                "the window server published no window list, so nothing can be said about "
                    + "what stands over the app's window"
            )
        }
        func bounds(of entry: [String: Any]) -> CGRect? {
            guard let raw = entry[kCGWindowBounds as String] as? [String: Any] else {
                return nil
            }
            return CGRect(dictionaryRepresentation: raw as CFDictionary)
        }
        // The app's frontmost window at the normal level, not simply its
        // frontmost window: a menu or a tooltip the app opens itself sits above
        // everything being looked for, and taking that as the boundary would
        // leave the windows between it and the document unexamined.
        guard let index = listing.firstIndex(where: {
            $0[kCGWindowOwnerPID as String] as? Int == pid
                && ($0[kCGWindowLayer as String] as? Int ?? 0) == 0
        }) else {
            return .unreadable("the app has no window on screen at the normal window level")
        }
        guard let window = bounds(of: listing[index]) else {
            return .unreadable("the app's frontmost window publishes no bounds")
        }
        // The pointer draws itself above everything and is not chrome.
        let cursorLevel = Int(CGWindowLevelForKey(.cursorWindow))
        var covering: [CoveringWindow] = []
        for entry in listing[..<index] {
            guard let owner = entry[kCGWindowOwnerPID as String] as? Int, owner != pid else {
                continue
            }
            let level = entry[kCGWindowLayer as String] as? Int ?? 0
            guard level < cursorLevel else { continue }
            guard (entry[kCGWindowAlpha as String] as? Double ?? 1.0) > 0.0 else { continue }
            guard let frame = bounds(of: entry), frame.intersects(window) else { continue }
            covering.append(
                CoveringWindow(
                    owner: entry[kCGWindowOwnerName as String] as? String ?? "an unnamed process",
                    pid: owner,
                    level: level,
                    frame: frame
                )
            )
        }
        return covering.isEmpty ? .clear : .covered(window: window, by: covering)
    }

    /// Holds the sweep to its one environmental precondition, and stops it the
    /// first time the precondition does not hold.
    ///
    /// Continuing past a covered window measures nothing: every control reads
    /// as unclickable, each read costs a cross-process query, and the report
    /// each one produces names the app for a screen the app does not own.
    @MainActor
    @discardableResult
    private func requireUnobstructedWindow(
        before step: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard obstruction == nil else { return false }
        guard screenState().obstruction != nil else { return true }
        // A window that arrived mid-run is not the same thing as a screen this
        // run cannot be given. The app is put back in front and the screen is
        // read again, once, before the run is stopped.
        if let app = drivenApp { clearTheScreen(so: app) }
        guard let covering = screenState().obstruction else { return true }
        obstruction = covering
        XCTFail(
            "The sweep cannot drive the workspace: \(covering). That is the screen the run "
                + "took place on, not a defect in the app: macOS answers hittability by "
                + "hit-testing the screen, so every control in a covered window reads as "
                + "unclickable. Refused before \(step), and the rest of the sweep is not run. "
                + "Set TEST_RUNNER_RUPA_UI_SWEEP_CLEAR_SCREEN=1 to let the run hide the "
                + "applications in the way and put them back when it ends.",
            file: file, line: line
        )
        return false
    }

    /// Puts the app in front of the screen the sweep is about to click, and
    /// hides only what being in front does not settle.
    ///
    /// Activation costs the machine nothing and is not optional: the app the
    /// sweep drives belongs above every window at the normal level, and a run
    /// that never asks for it reads whatever the screen happened to be doing.
    /// It does not settle a window at a floating level, which stays above the
    /// active application's own, so hiding is kept for exactly that remainder,
    /// is asked for with `RUPA_UI_SWEEP_CLEAR_SCREEN`, names every application
    /// it hides, and is undone in `tearDownWithError`. Asking in this order is
    /// what keeps the run from hiding the windows activation would have moved
    /// on its own.
    ///
    /// The screen is not read once. Activation and hiding are both
    /// asynchronous, the window server reorders on its own clock, and a window
    /// that was not there a moment ago can arrive between the reading and the
    /// clicking, so this asks, reads back, and asks again until the screen is
    /// clear or the budget runs out. A window it cannot hide does not end the
    /// loop: the window server's own overlays appear while it reorders windows
    /// and go again on their own, and stopping at the first one this run has no
    /// authority over reports a screen that was about to clear itself. Whether
    /// it worked is still not assumed: `requireUnobstructedWindow` reads the
    /// screen afterwards and is what the run is held to.
    @MainActor
    private func clearTheScreen(so app: XCUIApplication) {
        let mayHide = ProcessInfo.processInfo.environment["RUPA_UI_SWEEP_CLEAR_SCREEN"] == "1"
        for _ in 0..<20 {
            app.activate()
            Thread.sleep(forTimeInterval: 0.25)
            guard case .covered(_, let covering) = screenState() else { return }
            guard mayHide else { return }
            for pid in Set(covering.map(\.pid)) {
                let alreadyHidden = hiddenApplications.contains {
                    $0.processIdentifier == pid_t(pid)
                }
                guard alreadyHidden == false else { continue }
                guard let owner = NSRunningApplication(processIdentifier: pid_t(pid)) else {
                    continue
                }
                let name = owner.bundleIdentifier ?? owner.localizedName ?? "pid \(pid)"
                guard owner.hide() else {
                    Self.marker.error("could not hide \(name, privacy: .public)")
                    continue
                }
                hiddenApplications.append(owner)
                Self.marker.error("hid \(name, privacy: .public) to clear the app's window")
            }
        }
    }

    // MARK: - Resolution

    /// Resolves the element a click has to land on, and says what the query
    /// found when it cannot.
    ///
    /// `firstMatch` over `.any` reported "exists but cannot be clicked" for
    /// unrelated states: the identifier resolved to something that is not the
    /// control, the control is published and declines input by being disabled,
    /// a window outside the app covers the screen the answer is hit-tested on,
    /// and the control is published with no click reaching it. A report that
    /// cannot separate them cannot be acted on, so this names the element type
    /// it expects, holds the screen precondition on both sides of the
    /// hittability it reads, and on a failure prints every element carrying the
    /// identifier together with what stands in front of the window, inside the
    /// app and outside it.
    @MainActor
    private func resolve(
        _ identifier: String,
        as type: XCUIElement.ElementType,
        in app: XCUIApplication,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement? {
        // Hittability is read below, and it is answered by hit-testing the
        // screen. Asking it while something outside the app covers the window
        // answers about that other window, slowly, so the precondition is held
        // first and the sweep stops rather than misnaming what it found.
        guard requireUnobstructedWindow(before: identifier, file: file, line: line) else {
            return nil
        }
        let element = app.descendants(matching: type).matching(identifier: identifier).firstMatch
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail(
                "\(identifier) publishes no element of type \(type.rawValue). \(report(identifier, in: app))",
                file: file, line: line
            )
            return nil
        }
        guard element.isEnabled else {
            // A disabled control declines input by design, and whether
            // anything could click it is not the question it is answering.
            // The caller records the refusal; reporting it as unreachable
            // would name the wrong failure.
            return element
        }
        if element.isHittable { return element }
        // Nothing outside the app covered the window when the precondition was
        // read, but hittability is answered by hit-testing the screen and the
        // window server reorders on its own clock: a window that arrives
        // between the two reads makes a reachable control read as unclickable,
        // and naming that the app's own chrome reports a defect the app does
        // not have. The screen is put back and the control read once more, so
        // an arriving window is reported as the screen it is.
        if let driven = drivenApp { clearTheScreen(so: driven) }
        guard requireUnobstructedWindow(before: identifier, file: file, line: line) else {
            return nil
        }
        guard element.isHittable else {
            // What is left is the app's own chrome over the control, or the
            // control lying outside the visible bounds of the container that
            // holds it. Hit-testing answers one question for both, so the
            // failure states what was read instead of naming one of them.
            XCTFail(
                "\(identifier) is published and enabled, nothing outside the app covers "
                    + "the window, and macOS still answers that no click reaches it: the "
                    + "app's own chrome is over it, or it lies outside the visible bounds "
                    + "of the container that holds it. " + report(identifier, in: app),
                file: file, line: line
            )
            return nil
        }
        return element
    }

    /// Everything the sweep can read about an unreachable control: every
    /// element carrying the identifier, and the chrome standing over the
    /// window that would be intercepting the click.
    @MainActor
    private func report(_ identifier: String, in app: XCUIApplication) -> String {
        var lines: [String] = []
        for element in app.descendants(matching: .any)
            .matching(identifier: identifier)
            .allElementsBoundByIndex
        {
            lines.append(
                "match type=\(element.elementType.rawValue)"
                    + " enabled=\(element.isEnabled)"
                    + " hittable=\(element.isHittable)"
                    + " frame=\(element.frame)"
            )
        }
        lines.append(
            "in front: \(chromeState(in: app).standing ?? "nothing standing")"
                + " sheets=\(app.sheets.count)"
                + " dialogs=\(app.dialogs.count)"
                + " windows=\(app.windows.count)"
        )
        for popover in app.popovers.allElementsBoundByIndex {
            lines.append("popover frame=\(popover.frame)")
        }
        for sheet in app.sheets.allElementsBoundByIndex {
            lines.append("sheet frame=\(sheet.frame)")
        }
        // Everything above is the app's own hierarchy, and a window belonging
        // to another process is not in it. Reading those counts alone once led
        // a run to conclude nothing was in front of a window another
        // application was sitting on top of.
        lines.append(
            "outside the app: "
                + (screenState().obstruction ?? "nothing covers the app's window")
                + ", frontmost="
                + (NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
        )
        return lines.joined(separator: " || ")
    }

    /// Opens a menu the chrome publishes as a menu button, and holds until one
    /// of its items is readable.
    ///
    /// A menu button whose menu never opens leaves the menu standing over the
    /// window, and every later step then reads as unclickable. The step that
    /// opened it is the one that has to report it, so this closes the menu
    /// before returning a failure.
    @MainActor
    @discardableResult
    private func openMenu(
        _ identifier: String,
        expecting item: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard let button = resolve(identifier, as: .menuButton, in: app, timeout: 10, file: file, line: line) else {
            return false
        }
        guard button.isEnabled else {
            XCTFail("\(identifier) stayed disabled", file: file, line: line)
            return false
        }
        button.click()
        // A menu item stays published while its menu is closed, so existence
        // alone does not say the menu opened. The item has to be clickable,
        // and a menu has to actually be standing open over the workspace.
        let menuItem = app.menuItems[item].firstMatch
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if menuItem.exists, menuItem.isHittable, chromeState(in: app).hasOpenMenu {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        XCTFail(
            "\(identifier) opened no menu carrying \(item). \(report(identifier, in: app))",
            file: file, line: line
        )
        dismissTransientChrome(in: app)
        return false
    }

    /// What the app is showing over its own workspace.
    ///
    /// The menu bar publishes its own menus whether or not one is open, so a
    /// count cannot say whether anything is standing; and the membership of
    /// that collection moves between reads, so the element a count named can
    /// be gone before it is resolved. One snapshot of the accessibility tree
    /// is atomic instead: what it says about a menu was true of the whole tree
    /// at that instant. An open menu occupies the screen and a published one
    /// has no area, which is the distinction a count cannot make.
    private enum ChromeState {
        case clear
        case standing(menus: [String], popovers: Int)
        case unreadable(String)

        /// The chrome to report, or `nil` when the workspace is uncovered.
        ///
        /// A tree that cannot be read is reported rather than passed over: a
        /// step that cannot be shown to have handed the workspace back has not
        /// been shown to have handed it back.
        var standing: String? {
            switch self {
            case .clear:
                return nil
            case let .standing(menus, popovers):
                let named = menus.isEmpty ? "none" : menus.joined(separator: "; ")
                return "open menus \(named), popovers=\(popovers)"
            case let .unreadable(reason):
                return "the accessibility tree could not be read: \(reason)"
            }
        }

        /// Whether a menu is open, which is the positive form the same
        /// question takes when a step is waiting for one to appear.
        var hasOpenMenu: Bool {
            guard case let .standing(menus, _) = self else { return false }
            return menus.isEmpty == false
        }
    }

    /// Names an element the way both the inventory and the check report it.
    @MainActor
    private static func describe(_ node: XCUIElementSnapshot) -> String {
        let title = node.identifier.isEmpty ? node.label : node.identifier
        return "\(title.isEmpty ? "unnamed" : title)\(node.frame)"
    }

    /// Reads the open chrome out of one atomic snapshot of the app's tree.
    @MainActor
    private func chromeState(in app: XCUIApplication) -> ChromeState {
        let root: XCUIElementSnapshot
        do {
            root = try app.snapshot()
        } catch {
            return .unreadable("\(error)")
        }
        var menus: [String] = []
        var popovers = 0
        var pending = [root]
        while let node = pending.popLast() {
            pending.append(contentsOf: node.children)
            switch node.elementType {
            case .menu:
                // A menu the bar publishes without opening has no area.
                guard node.frame.isEmpty == false else { continue }
                menus.append(Self.describe(node))
            case .popover:
                popovers += 1
            default:
                continue
            }
        }
        guard menus.isEmpty == false || popovers > 0 else { return .clear }
        return .standing(menus: menus, popovers: popovers)
    }

    /// Closes whatever is standing over the window so the next step starts from
    /// the workspace rather than from an open menu.
    @MainActor
    private func dismissTransientChrome(in app: XCUIApplication) {
        guard chromeState(in: app).standing != nil else { return }
        app.typeKey(.escape, modifierFlags: [])
        for _ in 0..<40 {
            if chromeState(in: app).standing == nil { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Holds a step to handing the workspace back the way it found it.
    ///
    /// Chrome left open belongs to the step that opened it. Without this, one
    /// step that fails to close a menu turns every later step into "cannot be
    /// clicked" and the step that actually broke is never named.
    @MainActor
    private func requireClearChrome(
        after name: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // A menu dismissed at the end of a step still occupies the screen
        // while it animates away. Chrome is only left standing if it is still
        // up after that, so the check holds briefly rather than reading the
        // frame the step happened to end on.
        var standing = chromeState(in: app).standing
        let deadline = Date().addingTimeInterval(2)
        while standing != nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            standing = chromeState(in: app).standing
        }
        guard let left = standing else { return }
        XCTFail(
            "\(name) left chrome standing over the workspace: \(left)",
            file: file, line: line
        )
        dismissTransientChrome(in: app)
    }

    /// Returns the rail to its compact form, which is where every destination
    /// button lives.
    ///
    /// The rail's state is the expanded container, not the hittability of the
    /// control that closes it: reading `isHittable` as "already collapsed"
    /// turns a control that cannot be clicked into a state the sweep believes
    /// it is already in, and every compact-only destination then reports as
    /// absent while the expanded rail is still standing.
    @MainActor
    private func collapseUtilityRail(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expanded = app.descendants(matching: .any)["WorkspaceUtilityRail.expanded"].firstMatch
        guard expanded.exists else { return }
        guard let collapse = resolve(
            "WorkspaceUtilityRail.collapse", as: .button, in: app, file: file, line: line
        ) else {
            return
        }
        collapse.click()
        for _ in 0..<100 {
            if expanded.exists == false { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail(
            "WorkspaceUtilityRail.collapse left the rail expanded. "
                + report("WorkspaceUtilityRail.expanded", in: app),
            file: file, line: line
        )
    }

    @MainActor
    private func openUtilityRail(at destination: String, in app: XCUIApplication) {
        collapseUtilityRail(in: app)
        guard let button = resolve(
            "WorkspaceUtilityRail.\(destination)", as: .button, in: app
        ) else {
            return
        }
        button.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["WorkspaceUtilityRail.expanded"].waitForExistence(timeout: 10)
        )
    }

    @MainActor
    private func cancelModelingDraft(in app: XCUIApplication) {
        // A draft that never opened leaves nothing to cancel. The step that
        // failed to open it already reported; this names the consequence so a
        // cancel that silently did nothing is not read as a cancel that worked.
        let cancel = app.buttons["Cancel"].firstMatch
        guard cancel.waitForExistence(timeout: 5), cancel.isHittable else {
            Self.marker.error("no modeling draft to cancel")
            return
        }
        cancel.click()
    }
}
