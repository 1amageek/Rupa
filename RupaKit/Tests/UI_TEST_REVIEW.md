# UI verification replacement

## Execution contract

Run `bash scripts/test-ui-contracts.sh` from RupaKit. This is the supported
UI verification entry point, not the App scheme's empty Test action.
It runs reviewed identifiers in bounded batches, checks every requested
identifier in xcresult, and rejects zero results, missing tests, skips and
failures. Static isolation checks run before compilation, and so does a
selection check. `scripts/ui-contract-tests.txt` is the only record of what
this entry point runs, so every identifier in it must name a test the sources
still declare, under the suite the identifier names, exactly once, in one of
the two supported targets. A test that is renamed, moved or deleted without
the manifest following it is then reported in a second, before any batch is
built, instead of surfacing minutes later as a result that never arrived.

```text
Production view / hidden native host
    -> hierarchy hit-test -> local NSEvent -> production input -> Workspace
Production RealityKit scene
    -> native projection / selection -> Metal texture readback
Visible App
    -> focused agent inspection -> manual evidence, never inferred from the above
```

Native hosts explicitly size their root before attaching it to a never-ordered
window. A generated input view is not readiness: its expected bounds must be
established before dispatch. Object-affordance clicks and drags resolve their
receiver through the actual hosted hierarchy; direct onPick calls are not
click evidence. Local dispatch does not emulate OS activation or menu tracking.

The foreground Xcode UI-testing target has been removed, including its build
phases, product, dependency and scheme reference, and its source directory is
deleted rather than kept as reference. A suite whose every assertion needs the
real desktop is not retained where it can be reattached, and an unbuilt copy of
it answers no question the ledger below does not already answer. That ledger
keeps each retired scenario name, so what still owes manual acceptance stays
named without the sources existing. No legacy test is counted as passing or
skipped.

## Findings resolved by the replacement

| Finding | Resolution and proof boundary |
|---|---|
| App launches, zooming and global pointer/key automation interrupt work | Retire the foreground target; no automated desktop input |
| Package membership does not imply non-interference | Remove window ordering from native fixtures; check hidden/non-key state |
| Button/handle existence is not functional behavior | Keep CAD/Mesh, binding, atomic transaction, stale/cancel and Undo assertions |
| Direct callbacks bypass native input and occlusion | Object-affordance fixture hits the native hierarchy before local event delivery |
| Non-visible hosting can leave the root at zero size | Assign the declared native content size before attaching; require input bounds readiness |
| Retiring RealityKit mount removed a root owned by its successor | Delegate removal exclusively to owner-checked unbind; exercise real SwiftUI identity replacement |
| Empty-scene test queried after attachment but before camera readiness | Wait for the production cache's hasReadyCamera contract, then assert the truthful empty hit |
| Inspector test expected 380px user resizing despite MainView's fixed 320px contract | Assert the declared width including divider and clamp after settling; do not change production layout to satisfy the obsolete expectation |
| A zero-test xcodebuild can exit successfully | Validate exact executed test identifiers, all outcomes and nested parameter results |
| Old Loft diagnostic expected a post-click error despite pre-refusal | Production refusal tests own the state; manual acceptance owns displayed disabled controls |

## Coverage owners

These are partial proofs with explicit boundaries, not equivalent replacements
for every OS-level assertion of the retired tests.

| Key | Automated owner selected by the runner | Remaining manual proof |
|---|---|---|
| LAYOUT | WorkspaceCanvasToolbarNativeTests, WorkspaceCanvasHeaderLayoutTests, WorkspaceCanvasHeaderSeatNativeTests, WorkspaceEditorSplitNativeTests, WorkspaceInspectorNativeLayoutTests | Visible clipping, hover hints, focus and screen composition |
| CAD | ModelingOperationDraftTests, ModelingAndMeshOperationCoverageTests, ModelingOperationViewContractTests, ModelingPreviewStateTests | Menu -> panel -> Preview/Apply reachability and visible refusal |
| MESH | MeshOperationDraftTests, ModelingAndMeshOperationCoverageTests | Make Editable confirmation, visible element/domain/operation selection |
| TRANSFORM | ViewportNativeObjectAffordancePressTests and CAD/Mesh native placement functions, ViewportBodyTransformInputTests, WorkspaceTransformMatrixTests | Visible XYZ colors/labels and cursor feedback agree with the named axis |
| INPUT | ViewportInputSurfaceTests, ViewportInputSurfaceExclusionTests | OS focus, first click and keyboard shortcut routing |
| SELECTION | Native object/face/edge/vertex/sketch/region point and rectangle tests | Scope control activation and visible highlight |
| FRAME | RealityViewportMountTests, native camera/frame/section tests, spatial resources and collision tests | Visible App frame is the same frame; no compositing artifacts |
| INSPECTOR | WorkspaceInspectorPropertyBatchTests, WorkspaceTransformMatrixTests, native layout tests | Picker/text-field activation, keyboard editing, command-Z routing |
| PLANES | WorkspaceConstructionPlaneEditBuilderTests, WorkspaceConstructionPlaneViewportDragCommitServiceTests, native plane marker/axis tests | Plane rail and inspector activation |
| VIEWS | WorkspaceSavedViewBuilderTests | Create/apply/update/remove buttons and persistence through visible App |
| MEASURE | ViewportMeasurementTests, WorkspaceMeasurementPresentationGateTests | Measure tool activation and displayed units/readout |
| LOG | WorkspaceFailureLogTests, ModelingOperationViewContractTests | Logs visibility, disabled guidance and Validate's displayed diagnostics |
| MANUAL | No complete automatic replacement claimed | Perform the scenario in an isolated test project; record result and errors |

## Retired scenario ledger

Every row retains its original scenario name. The automated column is only a
related lower-layer proof. **Every row still requires manual acceptance for its
visible/OS interaction portion; no row is implicitly green.** Work on a disposable
project, record the source revision, operation, observed state/geometry, Undo
where relevant, and any failure log entry. Inspect only the named workflow;
do not run a background sweep or hide unrelated apps. Save/reopen uses a unique
temporary .rupa file, never the user's current project.

| Retired scenario | Automated subset |
|---|---|
| `AppUITestsLaunchTests.testLaunch` | MANUAL |
| `AppChromeGeometryProbeUITests.testWorkspaceGeometryBeforeAndAfterTheLogsPaneOpens` | LAYOUT, FRAME |
| `AppChromeGeometryProbeUITests.testExpandedUtilityRailBeforeAndAfterTheLogsPaneOpens` | LAYOUT, FRAME |
| `AppUITests.testExample` | MANUAL |
| `AppUITests.testCanvasShowsCoordinateGridAndInPlaneRuler` | FRAME |
| `AppUITests.testNativeViewportMountsEmptyAndPopulatedFramesAcrossProjectionChanges` | FRAME |
| `AppUITests.testWorkspaceChromeExposesSnapPlaneAndContextControls` | LAYOUT |
| `AppUITests.testWorkspaceSavedViewRailCreatesAndExposesViewActions` | VIEWS |
| `AppUITests.testFaceSelectionModeShowsSubobjectTarget` | SELECTION |
| `AppUITests.testEdgeSelectionModeShowsChamferCommand` | SELECTION |
| `AppUITests.testCanvasToolHoverShowsNamesWithoutChangingButtonBounds` | LAYOUT, FRAME |
| `AppUITests.testLogsVisibilityRemainsUserControlledAcrossFailureAndSourceCommit` | LOG |
| `AppUITests.testCanvasFrameAndAxisTriadRemainStableAcrossEmptyBoxAndHoverUpdates` | LAYOUT, FRAME |
| `AppUITests.testCanvasSurfaceToolOpensSheetLoftAndRejectsMissingProfiles` | CAD, LOG |
| `AppUITests.testActiveCustomConstructionPlaneLaunchFixtureSupportsCanvasCreation` | PLANES |
| `AppUITests.testSelectedCustomConstructionPlaneLaunchFixtureExposesInspectorEditingControls` | PLANES |
| `AppUITests.testSelectedCustomConstructionPlaneViewportHandlesCommitDragEdits` | PLANES |
| `AppUITests.testSelectedCustomConstructionPlaneLaunchFixtureSupportsPlaneRailRename` | PLANES |
| `AppUITests.testFaceSelectionCreatesSavedConstructionPlaneFromContextPanel` | PLANES |
| `AppUITests.testSelectingObjectShowsViewportAffordance` | TRANSFORM |
| `AppUITests.testLaunchPerformance` | MANUAL |
| `AppOperationCoverageUITests.testModelMenuPublishesEveryDraftAndCommitsABoxFromTheToolbar` | CAD, LOG |
| `AppOperationCoverageUITests.testInspectorPropertyPickersPublishAndUndoTheirValues` | INSPECTOR |
| `AppOperationCoverageUITests.testAnalysisAndSceneRailSectionsPublishControlsAndReadouts` | MANUAL |
| `AppOperationCoverageUITests.testMeasureToolReportsDistanceBetweenTwoPointsOnABody` | MEASURE |
| `AppOperationCoverageUITests.testMeshEditingPanelCommitsAFaceDeletionFromTheCADRoute` | MESH |
| `AppOperationCoverageUITests.testAPanelRefusalIsReadBeforeThePressAndRecordsNothing` | CAD, LOG |
| `AppOperationCoverageUITests.testValidateReportsTheEvaluationItRanAndRecordsNoFailure` | LOG |
| `AppOperationCoverageUITests.testInspectorToggleRelaysTheSplitWithoutDroppingTheCanvas` | LAYOUT, FRAME |
| `AppFailureSweepUITests.testCanvasToolsOnTheLaunchDocument` | INPUT, CAD |
| `AppFailureSweepUITests.testUtilityRailOnTheLaunchDocument` | LAYOUT |
| `AppFailureSweepUITests.testSelectionScopesOnTheLaunchDocument` | SELECTION |
| `AppFailureSweepUITests.testPlaneModesOnTheLaunchDocument` | PLANES |
| `AppFailureSweepUITests.testViewportControlsOnTheLaunchDocument` | FRAME |
| `AppFailureSweepUITests.testToolbarCommandsOnTheLaunchDocument` | INPUT, LOG |
| `AppFailureSweepUITests.testModelingDraftsOnTheLaunchDocument` | CAD, LOG |
| `AppFailureSweepUITests.testSidebarOnTheLaunchDocument` | LAYOUT |
| `AppFailureSweepUITests.testEditMenuOnTheLaunchDocument` | INPUT, LOG |
| `AppFailureSweepUITests.testCreatingAndSelectingABody` | SELECTION |
| `AppFailureSweepUITests.testCanvasToolsWithABodySelected` | INPUT, CAD |
| `AppFailureSweepUITests.testSelectionScopesWithABodySelected` | SELECTION |
| `AppFailureSweepUITests.testPlaneModesWithABodySelected` | PLANES |
| `AppFailureSweepUITests.testViewportControlsWithABodySelected` | FRAME |
| `AppFailureSweepUITests.testToolbarCommandsWithABodySelected` | INPUT, LOG |
| `AppFailureSweepUITests.testModelingDraftsWithABodySelected` | CAD, LOG |
| `AppFailureSweepUITests.testEditMenuWithABodySelected` | INPUT, LOG |
| `AppProjectRoundTripUITests.testProjectSurvivesCreateSelectEditSaveAndReload` | MANUAL |

## Acceptance order and failure policy

1. Run hidden UI, input, geometry/Undo and actual Metal checks.
2. Inspect visible XYZ translation, rotation, scaling, selection and Inspector
   editing first; then panel/rail navigation, refusal/Logs and save/reopen.
3. A failing automated assertion remains a failure. Do not disable it, accept a
   mock answer or restore window ordering to get a green result.
4. Keep manual status separate. A lower-layer pass cannot close a visible
   activation, file-panel or focus gap. No current manual pass is recorded here.

## Runtime evidence

A bounded hidden NSHostingView experiment did not expose the palette and
modeling controls through the in-process accessibility traversal. It is not
counted as coverage. Those activations remain in the manual ledger; no direct
callback or fake accessibility tree is substituted for the missing proof.

On macOS 27.0, the 224 identifiers selected at the time of that run have
passing runtime evidence: 60 RupaUIPackageTests and 164 RupaRenderingTests.
Those counts describe that run, not the current manifest. An identifier
selected afterwards owes its own evidence and does not inherit this
paragraph's. Parameterized executions are not counted as additional
functions. No selected identifier is missing, skipped
or left failing. This is reconciled evidence, not a claim that every initial
batch passed: two fixture failures in the integration run were closed by focused
reruns after fixing readiness/layout pumping. A separate red/green native
remount test proved the production owner-removal correction.

Three selected identifiers were renamed in the sources afterwards without the
manifest following them, and the selection check named all three the first time
it ran against the real manifest. The manifest now carries
`axisScalingCrossesItsPivotButDoesNotCommitCollapse(centered:axis:)`,
`rotationCommitsGeometryRatherThanOnlyAnOrientationPreview(axis:)` and
`pendingSketchMutationRetainsOneNativeBaselineForGeometryAndHandles()`, and
those three were run by themselves on macOS 27.0 and read by the exact-result
verifier, which reported three passing functions and no skip or failure.

The two guards that hold canvas and construction-plane drag snapping to the
caller's evaluation context are selected as well. They were run by themselves
on macOS 27.0 and read by the same verifier, which reported two passing
functions and no skip or failure.

Evidence (22 result bundles from that run, and one bundle for each
identifier selected since):

- `/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/rupa-ui-contracts.GzrSbt/`
- `/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/rupa-ui-remaining.y7VYPS/`
- `/tmp/rupa-hidden-frame-readiness-20260917.xcresult`
- `/tmp/rupa-hidden-face-layout-20260917.xcresult`
- `t13-rename.xcresult` for the three renamed identifiers
- `t13b-drag.xcresult` for the two drag snap guards

The full invocation also ran one pre-existing, uncommitted saved-view test;
it passed but is excluded from that run's replacement manifest and proof.
Passed tests whose assumptions did not change were not repeated after the two
local fixture fixes. Actual GPU evidence includes native axes texture readback,
materials, spatial resources, camera calibration and frame/selection tests.
Static isolation guard, exact-result verifier negative checks, scheme XML and
project plist validation passed. Visible/OS acceptance remains unverified.

## Direct App acceptance in progress (2026-09-17)

The current worktree at HEAD `1ed8b016`, including pre-existing uncommitted
changes, produced a Debug App using Xcode-beta and
`.verification/RupaMCPDerived`. The first bounded build timed out during
compilation; the incremental continuation exited 0 and strict deep signature
verification passed. Xcode emitted an anomalous "command failed with exit code
0" MainView diagnostic and compiler warnings, so this is not a warning-free
build claim. The updated executable timestamp was September 17, 13:31:46 JST.

- Executable SHA-256: `cdc6adc0e9cc10d43f10a3afd2d07db88376aef02d29f74f5a71f5d62fdf38e6`.
- Debug implementation dylib SHA-256: `19e000d9a4244e27a8ebcb268ab7acbc7db077a6161b8b5a3167e2c84e3ecce9`.
- The freshly launched Untitled workspace displayed the native canvas, grid,
  Inspector, sidebar and tool palette without a startup error. No saved user
  project was opened. Fit was correctly disabled with no geometry.
- Direct opening of Model exposed Box, Cylinder, Sphere, Extrude, Revolve,
  Sweep, Loft, Boolean, Fillet and Chamfer. This proves menu reachability only,
  not operation execution.
- A subsequent action was rejected because user interaction changed the app
  state. The state was read again; no stale index was clicked. Further direct
  manipulation is paused to avoid competing with the user's desktop activity.

No creation, transform, property edit, Undo or save/reopen acceptance is closed
by these observations. The older pre-build binary was opened briefly and quit;
its screen is explicitly excluded from current-source acceptance.
