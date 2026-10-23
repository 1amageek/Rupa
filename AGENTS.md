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

## Test Policy

- Every test is independent: it builds its own inputs, state, temporary files, and resources, and its outcome does not depend on other tests, execution order, or which tests share its process.
- Tests run in parallel by default. Do not make a test pass by serializing it, ordering it, or retrying it; a test that passes only alone, only in the full suite, or only in one order has an isolation defect in the test or in the code under test.
- Give each test its own copy of anything it mutates: a unique temporary directory, an injected dependency instead of static or process-global mutable state, and its own document, session, or fixture instance.
- When a resource cannot be duplicated per test (for example a display-bound renderer or a single device), route every test that touches it through one shared exclusive-access helper, keep the exclusion to that resource only, and record why it cannot be isolated next to the helper.
- Keep each test small enough to run beside others: split independent scenarios into separate tests or parameterized cases so they run side by side, and do not let one long test bound the suite's wall time.
- A test's time limit is part of its contract and is measured in the same parallel run it is executed in; a test that exceeds it under parallel load is reported, not given a looser limit or moved to a serial run.
- Run suites with the package's parallel runner (for swift-CAD, `Scripts/swift-test-parallel.py`) rather than serial whole-suite commands, and run single tests in their own process when isolating a failure.

### Adding Tests

- Add a test only when it falsifies one contract, invariant, or defect that no existing test already proves; name that target in the test.
- Assert the actual success and failure behavior of the implementation path; a test that checks only types, declarations, or existence does not count as evidence.
- For a defect fix, observe the new test failing against the unfixed code before the fix lands.
- Place the test in the test target of the module that owns the contract, and keep it traceable from that owner's `DESIGN.md`.
- When adding a test, measure it in the package's parallel run and assign its lane and time limit from that measurement; each package's `DESIGN.md` verification section owns the lane names, budgets, and limit rules.
- Before accepting a heavy test, reduce its input to the smallest one that still proves the same contract; when it must stay long, split its independent scenarios into separate tests or parameterized cases.
- When a new test subsumes an existing one, delete the existing test in the same change; the number of tests is not a measure of progress.
- A new test that needs a resource that cannot be duplicated uses the shared exclusive-access helper under the same conditions as above.
