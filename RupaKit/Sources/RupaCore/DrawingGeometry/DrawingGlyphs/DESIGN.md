# Drawing Glyphs

## Purpose and Scope
Child of [DrawingGeometry](../DESIGN.md), with no children. Resolves an explicitly
requested Native font and shapes original Unicode dimension text into original
Bezier outlines in final bottom-left paper points.

## Responsibilities and Boundaries
CoreText owns Native font matching, shaping and immutable glyph paths. This
producer verifies requested/resolved font identity, owns scoped run borrows and
application outline commands. CADExchange owns publication of the same commands
and text/font provenance. The original contour adapter converts those commands
into native degree-one/two/three z=0 Bezier laws for the Kernel contact/region
producer, retaining the original outline as provenance. Page composition owns baseline/origin/font size.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DrawingGeometry](../DESIGN.md) | parent | current-source dimensions | Supplies text and baseline | Font and paper coordinates are explicit |
| [BRepDrawingExchange](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADExchange/BRepDrawingExchange/DESIGN.md) | depends on | glyph commands and cumulative usage | Publishes original outlines | No independently reset resource ledger |

## Architecture
```text
original text + explicit font/allowed fallbacks + paper baseline
 -> exact PostScript identity check -> Native attributed line/run shaping
 -> resolved run font check -> retained run glyph/position borrow
 -> original Native glyph path -> original Bezier commands -> page writer
```

## Contracts and Invariants
The requested PostScript font must resolve to exactly that name. Only explicitly
allowed fallback run fonts may appear. Font size and baseline are finite, and no
zero-size default is accepted. Positions and paths preserve original Native run
shaping/text matrix. As specified by CTRunGetTextMatrix, its translation is
replaced by the authored current text position: glyph positions receive the run's
linear matrix, then the paper baseline. Stored run translation is not added twice. No fitting, text encoding into a different PDF font or missing
glyph success occurs. The caller's same drawing usage charges strings, Native
operations and all application arrays/commands before allocation or append.

## State, Ownership, and Lifecycle
Invocation-local line/run/font owners retain Native buffers through scoped borrows.
Glyph/position/original-string-index pointers never escape. Empty runs never
pass nil buffer addresses to Native copy calls. A missing outline is accepted only
for its original Unicode cluster when that entire cluster is whitespace; other
glyphs in the same run cannot conceal a missing non-whitespace glyph. Native glyph
zero is the missing-glyph marker and never publishes a substitute outline. RTL cluster
indices are interpreted by their original text order, with searches charged to the
same work ledger. Resolved PostScript strings and generated run identities are
admitted before application materialization. Native run bridging storage is admitted before materialization. If the SDK does not expose contiguous run
buffers, initialized arrays are charged before allocation and filled by the SDK.
CoreGraphics path callbacks are synchronous CF_NOESCAPE in the fixed SDK header;
local commands/error and the exclusive caller ledger remain in that one scope.
No callback crosses a Sendable/isolation boundary.

## Failure, Concurrency, and Constraints
Invalid font identity, unapproved substitution, malformed run ranges, unsupported
non-outline glyphs, coordinate overflow, cancellation and cumulative capacity
exhaustion propagate typed EditorError or original exchange resource errors.
Native opaque font/driver internals are not claimed as measured application bytes.
Unsupported platforms and colored/non-outline glyph families are explicit pending
capabilities, not blank successful annotations.

## Verification and Change Impact
After the complete source phase, use actual Native fonts to exercise Unicode,
ligatures/kerning, approved fallback, reversed-direction runs, original Bezier
geometry, failed font matching, cancellation and bounded publication through
DXF/SVG/PDF. Compare actual requested glyph appearance and source provenance.
No compilation or runtime evidence has been acquired in the source phase.

### Original Planar Contour Bridge
`OriginalDrawingGlyphContourBuilder` retains the complete original outline and
assigns invocation-unique contour, segment and vertex identities from a caller
counter. Commands remain final paper points; there is no additional scale or
flattening. Each line/quadratic/cubic is a whole clamped native [0,1] B-spline
with the original control points and unit weights. Native fill closure creates
the authored closing line at close, next move or end of path. Shared directed
endpoints bind the same exact stored coordinates; returning to the contour
start reuses that original vertex identity. Empty move-only contours are not
published as filled glyph geometry. The same drawing usage admits physical
arrays, records, source visits and cancellation before allocation. Caller identity
state changes only after complete conversion. The returned contours do not
claim completed contacts or nonzero union; the Kernel OriginalPlanarContours
producer owns those later phases and must receive the same allowance.

The exact original contour producer is a dependency on
[OriginalPlanarContours](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADKernel/OriginalPlanarContours/DESIGN.md).
Deferred tests compare original line/quadratic/cubic commands, implicit closure,
repeated endpoint identity, malformed command ordering, overflow, cancellation
and unchanged caller identity on failure. Nonzero overlaps require real region
boundaries before DXF HATCH publication.

Explicit close preserves the Native current point at the original subpath start.
A following drawing command without a move starts a new contour at that same
original vertex; repeated closes publish no empty contour. A new move and final
completion clear the cursor after implicit closure.

Native outlining makes fill closure explicit before publication: an open Native
subpath receives close before the next move or glyph end, and a drawing command
after explicit close receives move at the original current/start point. These
commands expose the identical Native filled contour law without adding a
geometric segment or changing controls. The exact contour adapter and Exchange
strict source validator therefore consume the same unambiguous partitions.
Command capacity growth is admitted before allocation while old/new buffers
coexist.

### Nonzero Boundary Publication
The caller supplies one live OriginalCurveContactAllowance and an explicit paper-point ModelingTolerance for the entire page. DefaultDrawingGlyphBoundaryResolver passes that allowance and the same DrawingExchangeUsage work-unit/byte callbacks through Kernel contact preparation, global winding and exact boundary cycles. Only actual zero/nonzero transition loops become DrawingResolvedGlyphBoundary receipts. Original glyph text/font/commands/fill rule and directed Bezier controls are bound by the Exchange validator before page publication. No outline is reinterpreted as parity. Independent algebra-depth policy is a lower issuer contract; a curve subdivision limit cannot create that capability. The caller-owned allowance is never constructed or reset here.

DrawingGeometricPage.resolvingGlyphBoundaries preserves the complete original scene/section identity and all paper paths, styles, dimensions and original contours. Current source validation precedes preparation. Existing immutable receipts use Native copy-on-write retention; only the new boundary array is allocated under the same usage. Legacy pages without nonzero receipts remain rejected by DXF for nonempty nonzero glyphs. SVG/PDF retain their existing authored fill law. Public generate/write/export methods with the live allowance compose these actual receipts before legal output, including atomic URL publication. The eventual focused tests must cover overlapping same-winding contours, cancelling contours, holes, tangency, exact source endpoints, current/stale source, lowered capacities and glyph mismatch.

DrawingGlyphPreparation is the public live-allowance issuer. It constructs one contact allowance with explicitly requested cell/work limits, the DrawingExchangeUsage's distinct subdivision/algebra ceilings and callbacks from that same shared accountant. It retains a usage copy only as accountant identity, not as a detached budget. Subsequent preparation rejects a different accounting owner before proof. Its retained contact counters never reset between glyphs or page stages. This makes Graph proof visits part of the actual drawing owner, rather than assuming an external raw allowance happened to carry matching callbacks.


The page glyph contact issuer forwards the drawing accountant's explicit source
nesting capability into `OriginalCurveContactAllowance.remainingSourceDepth`,
retaining the lower producer's historical intrinsic maximum of 32. Source nesting
is independent of geometric subdivision and algebraic root depth; a caller's
stricter source cap is never replaced by either. No fresh allowance is created
between contour preparation, global merge, winding, boundary extraction and
format publication.
