# Material Assignment

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), no children. Owns Set Material, Fork Material
and Remove Material on selected objects, editing a library material, the
material library's create, rename and delete, and the mass a material's density
gives measured solids.

## Responsibilities and Boundaries

Owns: expanding a selection to the objects a material reaches (a group reaches
every object inside it), assigning, forking and removing materials on them,
library edits and their effect on the objects and face bindings that name a
material, and `SceneMass`.

Does not own: the material's fields and their ranges (Swift-CAD `Material`), a
node's resolved appearance (`DesignDocument.appearance(of:)`), face material
bindings as such (`setTopologyMaterialBinding`), solid volumes (MeasurementService
through Swift-CAD), drawing (RupaRendering) or the dialog and keys (RupaUI).

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | `SceneNodeHierarchy`, `MaterialLibrary`, `MaterialComponentEdit` | Library and node material IDs | Pattern outputs take their appearance from the source |
| [CADIR](../../../../swift-CAD/Sources/CADIR/DESIGN.md) | depends on | `Material` | Physical layers and density | Ranges are validated there |
| [RupaUI](../../RupaUI/DESIGN.md) | used by | commands, `SceneMass` | M, Shift-M, Alt-M, library panel, mass readout | — |

## Architecture

```text
selection ──materialTargets (groups → contained objects)──▶ objects
objects ──assignMaterial / forkMaterial / removeMaterial──▶ node material IDs (+ face bindings on remove)
library ──createMaterial / renameMaterial / deleteMaterial / editMaterial──▶ materials (users follow)
MeasurementResult.solids ──presenting node's material density──▶ SceneMass
```

## Contracts and Invariants

- A selection reaches every body, sketch and mesh object it names or that a
  named group contains; groups themselves carry no material, and nodes held by
  an object (its profile sketches, carried presenters) belong to that object. Pattern array outputs are refused, since
  their appearance belongs to the pattern source.
- Set Material (`assignMaterial`) gives the reached objects one material: a
  named library material, else the one they already share, or else a new
  library material copied from the first object's appearance, named after it. Fork Material gives them a new copy of
  the first object's appearance under a new identity. Remove Material clears
  their material and their face material bindings, so they draw with the
  document default.
- `editMaterial` changes one component of one library material, so every object
  and face naming it changes together. Rename keeps names unique; delete
  unassigns every node and face binding naming the material and clears the
  library default when it was the default.
- `SceneMass` sums volume × density over measured solids whose presenting object
  has a material with a density, and counts the solids it could not weigh.
- Each is one undoable source command; any refusal leaves the document unchanged.

## Verification and Change Impact

`MaterialAssignmentTests` prove group expansion, shared-versus-new assignment,
fork independence, removal of node and face materials, editing a shared
material, rename uniqueness, delete unassignment and default clearing, the
pattern output refusal, and mass with and without density. A change re-checks
the material dialog and the mass readout (RupaUI).
