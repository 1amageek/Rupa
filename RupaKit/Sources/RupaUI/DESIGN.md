# RupaUI

## Purpose and Scope

`RupaUI` presents immutable `ProjectViewSnapshot` state and submits user intent
to the App-owned `ProjectWorkspace`. It is a child of the
[RupaKit package design](../../DESIGN.md) and has no child designs.

## Responsibilities and Boundaries

The module owns workspace presentation, viewport/UI interaction, visible
project-title projection, and observation of the existing render-plan cache.
It does not own project source, package persistence, file URLs, application
process authority, Agent transport, geometry preparation, or a second mutable
document model.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaKit package](../../DESIGN.md) | parent | module dependency and authority direction | Places UI above the workspace snapshot. | UI must not bypass the workspace. |
| [Rupa App](../../../Rupa/Rupa/Rupa/DESIGN.md) | used by | application file lifecycle and composition | Supplies the App-owned workspace and file activation. | File names are not project-title authority. |
| [RupaKit integration](../RupaKit/DESIGN.md) | depends on | `ProjectWorkspace` and `ProjectViewSnapshot` | Publishes the exact view consumed by `MainView`. | Snapshot coordinates remain immutable evidence. |
| [RupaRendering](../RupaRendering/DESIGN.md) | depends on | Snapshot-matched asynchronous render-plan state | Supplies bounded ready data or typed preparation failure. | UI never builds or repairs geometry. |

## Architecture

```mermaid
flowchart LR
    Snapshot["ProjectViewSnapshot"] --> Main["MainView"]
    Main --> Title["snapshot.projectName"]
    Main --> Viewport["Viewport presentation"]
    Viewport --> Cache["Existing plan cache"]
    Cache --> State["idle / preparing / ready / failed"]
    State --> Canvas["Existing Canvas"]
    Main --> Workspace["ProjectWorkspace intent APIs"]
    Workspace --> Controller["ProjectController"]
```

## Contracts and Invariants

1. `ProjectViewSnapshot.projectName` is the sole navigation/window title input.
2. Empty project names display the bounded fallback `Untitled`; CAD metadata,
   file names, transport state, and Agent responses never replace a nonempty
   snapshot name.
3. `MainView` sends intent to its injected workspace and retains no source or
   package authority.
4. A failed application file activation leaves the prior snapshot and all
   visible UI derived from it unchanged.
5. A new viewport snapshot starts preparation through the existing cache and
   renders only a matching `ready` plan. `preparing` and typed `failed` states
   remain explicit; neither displays stale geometry as current.
6. UI code performs no tessellation, Mesh validation, world transformation, or
   triangle-plan construction. Canvas projects ready positions and draws a
   bounded number of visual-state batches, not one path operation per triangle.
7. Viewport teardown releases the cache, cancels its build task, and discards
   every late completion; no render task or plan is retained by stale UI.

## Runtime Flows

The application coordinator publishes a new workspace view only after
`ProjectController` accepts a load or transaction. `MainView` derives title and
viewport from that view in the same publication lifetime, then lets the cache
prepare derived render data outside `MainActor`. Only a completion matching the
current snapshot replaces the UI cache state. Title projection uses the
published project name and has no dependency on CAD metadata.

## State, Ownership, and Lifecycle

SwiftUI owns transient camera, interaction, and render-cache observation state.
The existing cache owns one cancellable build task and matching result;
the injected workspace owns the observable view; `ProjectController` owns
source state and publication. The UI does not retain source authority,
security-scoped URLs, or transport resources.

## Failure, Concurrency, and Constraints

UI state and Canvas calls are MainActor-isolated; render-plan construction is
not. Project and render failures remain typed at their owning boundaries and
are not converted into empty successful views. MainActor work is bounded by
admitted plan positions and batches. Title projection performs no CAD, file,
or transport reads.

## Verification and Change Impact

Focused tests must verify title projection, matching
idle/preparing/ready/failed state, stale/teardown completion rejection, and
bounded Canvas batch calls alongside
successful `.rupa` load and failed dirty/invalid activation preserving the same
visible snapshot. A MainActor progress probe and the actual signed-App
multi-body run must verify the window, viewport, interaction, and Agent response
remain live. No change adds or changes save-as behavior.
