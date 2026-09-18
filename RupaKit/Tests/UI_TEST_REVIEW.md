# UI verification replacement

## Execution contract

Run `bash scripts/test-ui-contracts.sh` from RupaKit. This is the supported
UI verification entry point, not the App scheme's empty Test action.
It runs reviewed identifiers in bounded batches, checks every requested
identifier in xcresult, and rejects zero results, missing tests, skips and
failures. Static isolation checks run before compilation.

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
| LAYOUT | WorkspaceCanvasToolbarNativeTests, WorkspaceCanvasOverlayTrailingChromeTests, WorkspaceEditorSplitNativeTests, WorkspaceInspectorNativeLayoutTests | Visible clipping, hover hints, focus and screen composition |
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

On macOS 27.0, all 224 selected test functions have passing runtime evidence:
60 RupaUIPackageTests and 164 RupaRenderingTests. Parameterized executions are
not counted as additional functions. No selected identifier is missing, skipped
or left failing. This is reconciled evidence, not a claim that every initial
batch passed: two fixture failures in the integration run were closed by focused
reruns after fixing readiness/layout pumping. A separate red/green native
remount test proved the production owner-removal correction.

Evidence (22 result bundles):

- `/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/rupa-ui-contracts.GzrSbt/`
- `/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/rupa-ui-remaining.y7VYPS/`
- `/tmp/rupa-hidden-frame-readiness-20260917.xcresult`
- `/tmp/rupa-hidden-face-layout-20260917.xcresult`

The full invocation also ran one pre-existing, uncommitted saved-view test;
it passed but is excluded from the 224-function replacement manifest and proof.
Passed tests whose assumptions did not change were not repeated after the two
local fixture fixes. Actual GPU evidence includes native axes texture readback,
materials, spatial resources, camera calibration and frame/selection tests.
Static isolation guard, exact-result verifier negative checks, scheme XML and
project plist validation passed. Visible/OS acceptance remains unverified.
