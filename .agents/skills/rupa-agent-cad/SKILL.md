---
name: rupa-agent-cad
description: Change CAD, Mesh, or project data in an open Rupa project through its Agent API. Use only when the user explicitly asks to create, edit, transform, delete, or save Rupa project data. Do not trigger for questions, explanations, reviews, status reports, JSON-file interpretation, benchmark interpretation, or other read-only inspection.
---

# Rupa Agent CAD

Use Rupa as the authority when changing CAD, Mesh, or project data. Treat the
skill as a mutation workflow, not as a general source-reading or explanation
guide.

## Trigger boundary

- Use this skill only when the user authorizes a change to Rupa project data.
- Do not use this skill to explain what a JSON file means, inspect Git changes,
  report status, review an implementation, or answer a conceptual question.
- Read-only questions may inspect the repository or artifact normally without
  loading this skill.
- Verification reads that follow an authorized mutation remain part of this
  skill because they prove that the requested change reached the authoritative
  project state.

## Route the request

- For every authorized live-project mutation, read
  [references/authority.md](references/authority.md).
- When selecting a supported modeling operation for that mutation, read
  [references/capabilities.md](references/capabilities.md).
- Read [references/benchmark.md](references/benchmark.md) only when benchmark
  evidence is needed to choose or constrain the requested mutation. Do not load
  it merely to answer a benchmark question.

## Preserve authority

Send operation intent through the registered Agent API into `ProjectAgentCommandController`, `ProjectWorkspace`, and `ProjectController`. Never mutate `.rupa` entries, `DesignDocument`, `EditorSession`, CAD storage, Mesh storage, or the swift-CAD kernel as a replacement for an API operation.

For an open document, resolve one live session explicitly. Do not use automatic live/file selection, file-mode mutation, or forced file editing. Refresh session coordinates after every published mutation.

## Execute a modeling request

1. Discover the current live session and semantic-operation descriptors. Select
   operations from their declared meaning, input types, output bindings,
   version, effects, and limits; do not plan from a remembered operation-ID
   table.
2. Read the current immutable project view and generation coordinates.
3. Give every consumed source explicit provenance: either a local output from an
   earlier node in the same program or an exact existing reference read from
   the same live session. Never invent an identity or carry one across sessions.
4. Decompose the requested shape into the smallest coherent semantic direct or
   program request supported by the discovered descriptors.
5. Treat `sourceReferenceUnavailable` as an unpublished planning/provenance
   failure, not as an unsupported capability. Refresh the view and form a new
   plan only when the user's intent still applies.
6. Submit once through the live Agent API. Preserve typed failure,
   cancellation, stale-coordinate, and outcome-unknown results. After dispatch
   may have reached publication, inspect authoritative state before any new
   mutation; never retry the same request blindly.
7. Re-read source and evaluated state from the same workspace. Match receipt
   source/output bindings to the planned references and outputs.
8. Verify exact dimensions, placement, relationships, source identities,
   body/topology counts, analytic surface kinds, measurements, and publication
   coordinates relevant to the request.
9. Save only after those checks pass. When persistence is required, verify the
   explicit package save and reload separately.

## Verify the mutation

A successful response or a visible viewport is not sufficient evidence. A
modeling operation is complete only when the receipt bindings, authoritative
source, and exact CAD/B-Rep observations satisfy the requested geometry and the
publication belongs to the expected live session.

If benchmark evidence was used to select a mutation capability, remember that
the T12 corpus contains 100 benchmark cases rather than 100 independent public
APIs. Do not treat a recorded benchmark result as proof that the current live
mutation succeeded.
