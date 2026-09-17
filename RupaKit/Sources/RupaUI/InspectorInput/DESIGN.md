# Inspector Input

## Purpose and Scope

Child of [RupaUI](../DESIGN.md). Owns transient numeric text/slider interaction,
not project values. No children.

## Responsibilities and Boundaries

Freeze conversion, units and slider bounds for an interaction. Retain the latest
requested value while editing or awaiting submission. ProjectWorkspace remains
the sole authority after settlement, including rejected edits.

## Related Designs

| Design | Relationship | Contract used | Caution |
|---|---|---|---|
| [RupaUI](../DESIGN.md) | parent | Ordered source/workspace submission | Completion must include publication or failure reporting. |

## Architecture

```text
Text / Slider -> transient input -> synchronous callback -> operation sequencer
                     ^                                      |
                     +---- latest request acknowledgement ---+
Project snapshot ---------------------------------> idle display
```

## Contracts and Invariants

- Incomplete text is retained but never submitted as a number.
- Numeric text uses the normal foreground color, including negative values and
  incomplete signed input. Parsing does not determine text color.
- Mapping is frozen until editing ends and the latest request settles.
- Earlier acknowledgements cannot retire newer requests.
- Numeric callbacks submit absolute values. Consecutive unstarted requests from
  the same control may replace each other; other commands are ordering barriers.
- Waiting for acknowledgement does not cancel source work or add queue barriers.
- Selection/document identity changes discard transient input, not queued work.
- Explicit operation drafts remain local until their Apply action.

## State, Ownership, and Lifecycle

SwiftUI owns one MainActor input state per control identity. Pending work is
owned by the existing sequencer; the view retains only the latest completion
observer. It cancels that observer on disappearance. All supported UI platforms
use the same MainActor isolation; there is no Embedded implementation.

## Failure, Concurrency, and Constraints

Submission errors are reported by the source boundary before acknowledgement.
After focus/drag ends, failed input returns to published state. Replacement is
bounded to one unstarted slot per consecutive control run; running work finishes.

## Verification and Change Impact

`RupaUIPackageTests/InspectorNumericInputTests.swift` owns delayed publication,
frozen mapping, incomplete text and stale acknowledgement checks. Sequencer
tests own barrier ordering. Parent source/workspace callbacks and the App build
must be checked when changing submission context or acknowledgement capture.

| Inspector family | Input path | Submission owner |
|---|---|---|
| Object center, size, schema, local transform | Shared length/number/scale input | MainView source sequencer; current-source command builders |
| Construction plane origin/normal | Shared length/number input | Current construction-plane edit builder |
| Pattern distances, axis, angle, twist, scale, copies | Shared numeric input | PatternArrayEditingService current-context operation |
| Surface CV coordinates/weight, knot value | Shared numeric input | Current CV resolver or absolute source command |
| Sketch dimension, arc angles, bridge parameter/tension | Shared numeric input | Absolute source parameter / current bridge endpoint edit |
| Ruler minor/major/span | Shared numeric input with existing ruler mapping | Current workspace ruler configuration |
| Topology, trim domain, spline move/slide, knot insertion drafts | Shared numeric input; local bindings | Explicit action submits the operation; never coalesced as a delta |
| Material, visibility, lock, boolean schema and pattern modes | Discrete pickers | Ordered source transactions, not numeric replacement |
| Surface analysis, selection indexes and local operation choices | Local bindings | Existing workspace/selection or explicit operation callback |
| Parameter definitions | Explicit text drafts | Single in-flight async submission; draft retained on failure |

This inventory records input ownership, not visual acceptance of every geometry
operation. Hidden native checks must not activate a window or post input events.
