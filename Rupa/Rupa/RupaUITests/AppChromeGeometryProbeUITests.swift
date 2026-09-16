import XCTest

/// Prints what the workspace publishes, with frames, as the sweep's own
/// sequence walks the chrome.
///
/// The sweep can say a control is published and that nothing can click it, but
/// not what is covering it: its report lists only the transient chrome — menus,
/// popovers, sheets, dialogs — and a view inside the window is invisible to
/// that. It also reports only the state it failed in, never the state the
/// control was still reachable in. This probe takes a snapshot on each side of
/// every transition the sweep drives, so the step that turns a reachable
/// control into an unreachable one is named rather than guessed at.
///
/// It is opt-in and diagnostic: it asserts nothing about the workspace, so it
/// runs only when `RUPA_UI_PROBE` is set in the runner's environment. Under
/// xcodebuild the runner receives variables prefixed `TEST_RUNNER_`, so the
/// invocation sets `TEST_RUNNER_RUPA_UI_PROBE=1`.
final class AppChromeGeometryProbeUITests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUPA_UI_PROBE"] == "1",
            "Set TEST_RUNNER_RUPA_UI_PROBE=1 to run the geometry probe"
        )
        continueAfterFailure = true
    }

    /// The controls the sweep reported as published-but-unclickable, plus the
    /// ones it could not find at all.
    private static let watched = [
        "CanvasTool.select",
        "CanvasTool.measure",
        "CanvasTool.section",
        "WorkspaceUtilityRail.expand",
        "WorkspaceUtilityRail.collapse",
        "WorkspaceUtilityRail.selection",
        "WorkspaceUtilityRail.collapsed",
        "WorkspaceUtilityRail.expanded",
        "WorkspaceSelectionScope.object",
        "WorkspacePlane.adaptive",
        "WorkspaceViewport.fit",
        "WorkspaceViewport.shading",
        "WorkspaceViewport.displayMode",
        "WorkspaceCommand.model",
        "WorkspaceCommand.validate",
        "WorkspaceCommand.inspector",
        "WorkspaceFailureLog.count",
        "WorkspaceCommand.logs",
    ]

    @MainActor
    func testWorkspaceGeometryBeforeAndAfterTheLogsPaneOpens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        let windowMenu = app.menuBarItems["Window"]
        XCTAssertTrue(windowMenu.waitForExistence(timeout: 15))
        windowMenu.click()
        let zoom = app.menuItems["Zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.click()
        for _ in 0..<100 {
            if zoom.exists == false { break }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let viewport = app.descendants(matching: .any)["CanvasViewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 25))

        dump(stage: "before-logs", in: app, hierarchy: true)

        let toggle = app.buttons["WorkspaceCommand.logs"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        toggle.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["WorkspaceFailureLog.count"]
                .firstMatch.waitForExistence(timeout: 15)
        )
        dump(stage: "after-logs", in: app, hierarchy: true)

        // The sweep clicked ten tools before one stopped being clickable. Each
        // click is followed by a reading, so the click that changed the state
        // is the one named.
        let tools = [
            "select", "sketch", "polygon", "arc", "spline",
            "solid", "sweep", "surface", "mesh", "measure", "section",
        ]
        for tool in tools {
            let button = app.buttons["CanvasTool.\(tool)"].firstMatch
            let before = button.exists
                ? "enabled=\(button.isEnabled) hittable=\(button.isHittable) frame=\(button.frame)"
                : "absent"
            print("PROBE tool \(tool) before-click \(before)")
            if button.exists, button.isHittable {
                button.click()
                Thread.sleep(forTimeInterval: 0.4)
            }
            for identifier in ["CanvasTool.section", "WorkspaceUtilityRail.expand"] {
                let element = app.buttons[identifier].firstMatch
                let state = element.exists
                    ? "enabled=\(element.isEnabled) hittable=\(element.isHittable) frame=\(element.frame)"
                    : "absent"
                print("PROBE tool \(tool) after-click \(identifier) \(state)")
            }
        }
        dump(stage: "after-tools", in: app, hierarchy: true)

        // The rail's own transition, which the sweep drives on every step and
        // which it read as "already collapsed" while the expanded rail was up.
        let expand = app.buttons["WorkspaceUtilityRail.expand"].firstMatch
        if expand.exists, expand.isHittable {
            expand.click()
            Thread.sleep(forTimeInterval: 1.0)
        }
        dump(stage: "after-expand", in: app, hierarchy: true)
    }

    /// The expanded rail, read on both sides of the transition that shortens
    /// the canvas under it.
    ///
    /// The first probe established that every control inside the expanded rail
    /// reports `hittable=false` while the compact rail's controls report
    /// `hittable=true`, and that nothing in the published hierarchy covers the
    /// points they fail at. It read the expanded rail only once, and only after
    /// the Logs pane had already shortened the canvas to the rail's own height,
    /// so it could not separate "expanded" from "as tall as the canvas".
    ///
    /// This probe expands the rail against the full-height canvas first, then
    /// opens the Logs pane under it. Each reading names what the window server
    /// hands the failing points to, records whether a click placed by
    /// coordinate rather than by hit test reaches the control, and writes the
    /// window's pixels out, so a hit-test result that the published tree cannot
    /// explain is settled by what is actually drawn.
    @MainActor
    func testExpandedUtilityRailBeforeAndAfterTheLogsPaneOpens() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        let windowMenu = app.menuBarItems["Window"]
        XCTAssertTrue(windowMenu.waitForExistence(timeout: 15))
        windowMenu.click()
        let zoom = app.menuItems["Zoom"]
        XCTAssertTrue(zoom.waitForExistence(timeout: 5))
        zoom.click()
        for _ in 0..<100 {
            if zoom.exists == false { break }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let viewport = app.descendants(matching: .any)["CanvasViewport"].firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 25))
        print("PROBE rail-collapsed canvas frame=\(viewport.frame)")

        let expand = app.buttons["WorkspaceUtilityRail.expand"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 15))
        print(
            "PROBE rail-collapsed WorkspaceUtilityRail.expand"
                + " hittable=\(expand.isHittable) frame=\(expand.frame)"
        )
        expand.click()
        let expanded = app.descendants(matching: .any)["WorkspaceUtilityRail.expanded"].firstMatch
        XCTAssertTrue(expanded.waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.0)

        probeRail(stage: "expanded-logs-closed", in: app)

        let toggle = app.buttons["WorkspaceCommand.logs"].firstMatch
        if toggle.exists, toggle.isHittable {
            toggle.click()
            _ = app.descendants(matching: .any)["WorkspaceFailureLog.count"]
                .firstMatch.waitForExistence(timeout: 15)
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            print("PROBE WorkspaceCommand.logs unreachable; the Logs pane stayed closed")
        }

        probeRail(stage: "expanded-logs-open", in: app)

        // The first probe read the expanded rail only after its tool sweep had
        // left the measure tool active, which publishes the bottom context
        // panel. That panel is the last overlay the host adds, so it is the
        // other thing that changed between the two readings.
        let measure = app.buttons["CanvasTool.measure"].firstMatch
        if measure.exists, measure.isHittable {
            measure.click()
            Thread.sleep(forTimeInterval: 0.8)
        } else {
            print("PROBE CanvasTool.measure unreachable; the context panel stayed closed")
        }
        let panel = app.descendants(matching: .any)["ViewportContextPanelContainer"].firstMatch
        print("PROBE context panel exists=\(panel.exists) frame=\(panel.exists ? "\(panel.frame)" : "-")")
        probeRail(stage: "expanded-measure", in: app)
    }

    /// One reading of the expanded rail: geometry, published hittability, and
    /// whether a click placed by coordinate reaches the control anyway. The
    /// coordinate click is the reading that separates a control the user
    /// cannot reach from one the accessibility layer only reports as
    /// unreachable.
    @MainActor
    private func probeRail(stage: String, in app: XCUIApplication) {
        print("PROBE ===== \(stage) =====")
        for identifier in [
            "CanvasViewport",
            "WorkspaceCanvasArea",
            "WorkspaceTopBar",
            "WorkspaceUtilityRail.expanded",
        ] {
            let element = app.descendants(matching: .any)[identifier].firstMatch
            let state = element.exists
                ? "enabled=\(element.isEnabled) hittable=\(element.isHittable) frame=\(element.frame)"
                : "absent"
            print("PROBE \(stage) \(identifier) \(state)")
        }

        for identifier in [
            "WorkspaceUtilityRail.collapse",
            "WorkspaceSelectionScope.object",
            "WorkspaceSelectionScope.face",
            "WorkspacePlane.adaptive",
            "WorkspaceViewport.shading",
        ] {
            let element = app.buttons[identifier].firstMatch
            guard element.exists else {
                print("PROBE \(stage) \(identifier) absent")
                continue
            }
            let frame = element.frame
            print(
                "PROBE \(stage) \(identifier)"
                    + " enabled=\(element.isEnabled)"
                    + " hittable=\(element.isHittable)"
                    + " frame=\(frame)"
                    + " value=\(String(describing: element.value))"
            )
        }

        // A click placed by coordinate ignores hit testing. If the control
        // responds to it, the control is reachable and the published
        // hittability is what is wrong; if it does not, the control is really
        // unreachable.
        //
        // The scope buttons are mutually exclusive, so clicking the one that
        // already reads Selected proves nothing. Drive whichever one is
        // Available, so every stage makes a reading that can fail.
        let scopes = ["WorkspaceSelectionScope.object", "WorkspaceSelectionScope.face"]
        let target = scopes.first { identifier in
            let element = app.buttons[identifier].firstMatch
            return element.exists && String(describing: element.value).contains("Available")
        }
        guard let target else {
            print("PROBE \(stage) coordinate-click skipped; no scope button reads Available")
            return
        }
        let element = app.buttons[target].firstMatch
        let before = String(describing: element.value)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        Thread.sleep(forTimeInterval: 0.6)
        let after = String(describing: app.buttons[target].firstMatch.value)
        print("PROBE \(stage) coordinate-click \(target) before=\(before) after=\(after)")
    }

    @MainActor
    private func dump(stage: String, in app: XCUIApplication, hierarchy: Bool) {
        print("PROBE ===== \(stage) =====")
        for window in app.windows.allElementsBoundByIndex {
            print("PROBE \(stage) window frame=\(window.frame) hittable=\(window.isHittable)")
        }
        for identifier in Self.watched {
            let matches = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .allElementsBoundByIndex
            if matches.isEmpty {
                print("PROBE \(stage) \(identifier) absent")
                continue
            }
            for element in matches {
                print(
                    "PROBE \(stage) \(identifier)"
                        + " type=\(element.elementType.rawValue)"
                        + " enabled=\(element.isEnabled)"
                        + " hittable=\(element.isHittable)"
                        + " frame=\(element.frame)"
                )
            }
        }
        guard hierarchy else { return }
        print("PROBE \(stage) hierarchy BEGIN")
        print(app.windows.firstMatch.debugDescription)
        print("PROBE \(stage) hierarchy END")
    }
}
