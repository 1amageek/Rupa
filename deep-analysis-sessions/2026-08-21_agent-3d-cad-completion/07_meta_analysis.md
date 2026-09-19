# Meta Analysis

## 2026-08-21 initial synthesis

The current architecture contains substantial exact analytic and rational B-spline machinery, validated coedge topology, strict capability inventory, and command parity infrastructure. The main completion blocker is not a shortage of feature enum cases. It is the absence of a geometry-level certified procedural vocabulary for valid shapes that are not generally rationally parameterizable.

Sweep exposes this root cause clearly. The planner rejects twist, general moving-frame path-normal motion, curved/multiple guides, round corners, and simplify before geometry generation. A historical curved path-normal implementation sampled 32 fixed sections and joined them with ruled patches; it was correctly removed because it carried no tolerance-related error enclosure and therefore could not be the source of CAD truth.

The architectural hypothesis is that a package-owned certified procedural surface foundation can remove several operation-specific shape envelopes at once: general Sweep motion, curved Thicken offsets, and triangular PolySpline patches. This hypothesis remains under investigation until downstream projection, intersection, topology validation, volume, tessellation, persistence, and exact exchange adapters are mapped and proven.

