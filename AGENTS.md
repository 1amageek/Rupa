# Project Instructions

## Rupa Verification Restarts

- After application fixes, restarting the rebuilt Rupa application is mandatory before reporting completion; no additional confirmation is required.
- Preserve unsaved document edits through the application's save workflow before restarting; never discard edits to facilitate verification.
- Restart the rebuilt application and verify that the intended executable and document are active.

## CAD Intersection and Proximity Policy

- The geometric intersection foundation distinguishes intersection and coincidence of the original authored geometry from proximity within a specified modeling tolerance. Exactness is relative to the authoritative source representation and selected parameter domains, including their canonical primitive semantics; it does not assert physical manufacturing accuracy.
- Distance and angular tolerances do not redefine source equality, erase distinct roots, merge branches, or establish topology identity. Numerical approximation accuracy, source uncertainty, proximity thresholds, and repair allowances are separate contracts.
- Intersection results identify original common points, curves, or coincident regions and retain source parameter correspondence and coverage evidence. A small residual or sampled agreement alone does not prove intersection or coincidence.
- Proximity is a separate query/result that identifies the compared domains, correspondence, metric, threshold, and certified distance bounds. Proximity may coexist with intersection; it is not an exclusive substitute for an intersection result, and pairwise proximity is not transitive identity.
- A successful empty intersection result requires exclusion over the entire requested domain. Insufficient evidence, unsupported required coverage, cancellation, or exhausted resources propagate explicit failure or an explicit indeterminate result; they never become absence, coincidence, or partial complete success.
- Sewing, healing, snapping, and tolerance-based Boolean processing own an explicit policy for accepting proximity and changing geometry or connectivity. They record the applied tolerance, displacement/deviation evidence, and resulting correspondence; the intersection foundation does not silently perform these changes.
- Existing tolerance-based coincidence paths require an explicit migration to these contracts. Record a path as unconverted until its public success, absence, coincidence, proximity, and indeterminate behavior are verified; documentation alone does not complete implementation.
