# Drawing Pages

## Purpose and Scope
Child of [DrawingGeometry](../DESIGN.md). Its [AngularDimensions](AngularDimensions/DESIGN.md)
child owns exact original direction-bound circular sectors.
The [RadialDimensions](RadialDimensions/DESIGN.md) child binds actual original
circular measurements to single generated-edge annotations. Composes retained
current placed original curves and resolved dimensions into final paper points.
Geometric page publication is distinct from complete hidden-line/section assembly.

## Responsibilities and Boundaries
The caller authors the page extent, points-per-metre scale, translation, deviation,
font and font size. This producer applies that one mapping. Original curve interval
linearization and Native glyph shaping retain their own source receipts; exchange
owns format publication. No fit-to-page, scale inference or font substitution occurs. The existing authored
DrawingProjectionExportStyle maps all seven stroke categories into the exchange
style value without normalization; material fill remains an explicit caller value.
Widths and dash lengths stay paper points and never receive geometry scale.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DrawingGeometry](../DESIGN.md) | parent | current placed evaluation and dimensions | Supplies source receipt | Validate the complete current scene before writing |
| [AngularDimensions](AngularDimensions/DESIGN.md) | child | retained native sector and exact paper action | Supplies original angular dimension source | Preserve independent caller caps |
| [RadialDimensions](RadialDimensions/DESIGN.md) | child | original radial source receipt | Adds current center/radius/boundary anchors | Display midpoints are excluded |
| [DrawingGlyphs](../DrawingGlyphs/DESIGN.md) | depends on | explicit font outlines | Original shaped commands | Unsupported glyphs fail |
| [BRepDrawingExchange](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADExchange/BRepDrawingExchange/DESIGN.md) | depends on | cumulative linearization/page writer | Publishes final paper coordinates | Reuse the same usage across composition and publication |

## Architecture
```text
one current exact evaluation -> placed source curves + resolved dimensions
 -> original interval linearization -> one authored paper mapping
 -> actual Native glyph outlines/leader primitives -> immutable page receipt
 -> complete current-source validation -> format writer using the same ledger
```

## Contracts and Invariants
Page coordinates use bottom-left origin, x right and y up, in points. The positive
stored scale is the exact authored points-per-metre law; no second model/output
unit conversion belongs here. Half the caller curve deviation is reserved for the
original source chord proof and half for checked outward paper-rounding error.
Native directed parameters accompany every mapped curve sample. Label baselines
use their original resolved projected point plus the explicit caller paper offset;
font size is already in points. Geometry stays unclassified until a certified
visibility producer supplies actual partitions. Leaders retain original layout
endpoints. A label with unresolved source or missing original metric never enters
this page path. The immutable annotation receipt retains complete original document,
saved view, evaluation configuration and B-rep; composition validates it and the
placed projection against the same current evaluation before using its values. Strings, mapped arrays, commands and publication use one cumulative
DrawingExchangeUsage. Stale scene/document/evaluation fails before publication.

## State, Ownership, and Lifecycle
Results are immutable values retaining the original placed projection receipt and
its current complete document. COW arrays retain geometry and glyph source paths;
no borrowed pointers escape. The writer receives the same source-validated result.

## Failure, Concurrency, and Constraints
Invalid authored page law, precision overflow, cancellation, exhausted original
curve/glyph/resource allowance and stale source propagate typed failures. No
clipped or empty successful page substitutes for a failed required primitive.

## Verification and Change Impact
After the complete source phase, exercise public source-to-SVG/PDF/DXF paths for
curved/reversed geometry, multi-body occurrences, Unicode/font substitution,
manual dimensions, one-scale units, rounding refusal, cancellation and stale
placement. Hidden-line and placed section domain completion remain separate gates;
this source composition is not evidence for those domains or target execution.

## Placed Section Page Composition

The section overload consumes the same current original occurrence receipt and
one explicitly indexed contribution per occurrence. Every material region and
hatch span must originate from that exact section invocation, cutting plane and
placement. Actual original world curve laws are projected into the page view,
linearized under the same caller DrawingExchangeUsage, and mapped by the same
explicit paper law. Coincident source loops use the retained world-law visitor.
Closed material outer/hole loops publish DrawingPageRegion; section contour,
contact and hatch paths retain separate style roles and original source identity.
Hatch world lines retain the original section frame in an affine curve law rather
than approximating their plane coordinates. The result retains whole current
section and scene authority alongside the original projection. Complete SSI,
visibility and nonzero glyph union remain lower source requirements. Deferred
verification covers multiple placements, cut-plane mismatch, reflected material
holes, single-map units and cumulative page resource refusal.

Material-loop publication reserves one quarter of page deviation for original
curve chord error, one half for page-map rounding and one quarter for directed
endpoint joining. Every paper endpoint join and final closure is outward-admitted
before dropping the next duplicated endpoint or closing the fill path. A model
tolerance success does not override a stricter caller page deviation.

Transverse section segments retain their two original endpoint values as a
degree-one native B-spline on [0,1]. The page path never constructs a singular
affine frame from an arbitrary segment and fixed unused axes. Both endpoint
control values and all knot/weight storage are admitted before construction;
existing original whole-interval linearization and paper precision apply.

### Atomic File Publication
The public file route resolves and validates the same immutable current page as
the sink route, then delegates single-file atomic replacement to
OfficialFormatExchange using the existing caller usage. Composition and writer
share work/storage admission; no second page mapping or inferred scale occurs.
Any stale source, cancellation, format loss or exhausted allowance fails before
a complete candidate file replaces the destination. Native execution and failure
retention evidence are deferred until the source phase is complete.

Hatch page publication consumes the source-bound segment `originalCurve` port
using the same drawing usage and its explicit source/curve/algebra capabilities.
Its normalized [0,1] law retains cutting UV endpoints and original local plane
word. Only that world source is projected into the page frame; output frame
never reconstructs the selected cutting plane. Existing authored frame sections
retain their original direct-column source meaning.

### Original Glyph Contour Composition
Page composition retains each shaped original outline and its exact Bezier
contours through DrawingGlyphs, with one invocation identity counter and the
same drawing usage. The page receipt keeps this contour provenance through
section composition and current-source validation. Original Kernel contact and
nonzero region production consume these contours; retaining them alone is not
a nonzero-union or DXF HATCH success. SVG/PDF continue publishing the original
glyph commands and fill rule.

Original glyph record arrays grow through explicitly admitted contiguous
capacities, covering old and new buffers while Native run results coexist.
Source command arrays are retained COW; page composition does not duplicate
Bezier control buffers or glyph command contents.

### Explicit Paper Dimension Layout
`DrawingDimensionLayout` binds one current annotation identity to an explicitly
authored layout and `DrawingDimensionStyle`. Lengths, offsets, gaps, overshoot
and arrow dimensions are final paper points; no default size or fitting law is
inferred. The original model-to-paper mapper applies once to current annotation
anchors; presentation offsets apply afterward. The same page receipt retains
the authored layout and the original measurement/anchor provenance.

The stroke producer uses the same canonical start/end, center/boundary and
center/side anchor semantics as current resolved measurements. Linear layouts
produce true dimension and extension strokes; radial/diameter layouts preserve
original centers and endpoints; point-anchored perimeter/area layouts retain
the complete directed original projected boundary. Open/closed-outline arrows
use the caller's explicit length/width; none produces no arrow. All strokes use
annotation style, not material fill. Collapsed projected anchors and unavailable
original center/boundary geometry fail explicitly. Angular arc layout needs a
complete original direction-to-phase source port and remains marked; it cannot
return an empty successful dimension. Existing label/leader-only authoring is
compatible but is not full dimension-layout completion. Caller capacities,
array bytes, cancellation and coordinate overflow are checked before publication.
Deferred verification covers vertical/horizontal/slanted dimensions, signed
offsets, exact original center selection, full boundary order, arrow styles,
missing/duplicate identity, scale once and unsupported angular source failure.

Original nonzero glyph boundary publication is owned by [DrawingGlyphs](../DrawingGlyphs/DESIGN.md). The page retains those immutable receipts when adding section paths/regions; no new scale or fill law is inferred. Public publication with caller-live allowance checks complete current page identity before the lower boundary producer and legal format writer.

Native dimension layout/style codecs retain all explicit caller fields. The automation page adapter reconstructs their throwing initializers before execution; decoding does not grant geometric or resource admission.


### Original Direction-Bound Angular Layout

[Angular Dimensions](AngularDimensions/DESIGN.md) owns exact native circular
sectors selected by the current original projected rays. Explicit paper tolerance
is supplied by the caller; absence is a capability failure, never an inferred
font/model tolerance. Root-span publication consumes the same live page owner.


`DrawingGeometricPageOptions.paperTolerance` is an additive optional caller
capability for original angular construction. Legacy options preserve nil; the
actual Native page request forwards its existing required `paperTolerance`.
Neither font defaults nor model tolerance substitute for this paper authority.


Dimension producers validate the decoded layout and style before allocating
strokes, including direct public calls. Codable synthesis is not a semantic
finite-length/arrow admission receipt; actual Native requests and direct callers
share the same validation contract.

The page retains optional DrawingOccurrenceSilhouettes alongside its complete
original placed projection. Every exact trim/contact/atlas/coincident-domain
receipt belongs to that same current evaluation and original occurrence order.
Section and glyph-boundary composition preserve this receipt rather than dropping
contour provenance. Paper paths still require the actual source-bound contour
linearizer; retaining a receipt alone is not drawing or visibility completion.

Optional contour pages use DrawingSilhouettePreparation for both extraction and
actual paper paths on one original source snapshot and live page accountant.
The page retains the complete contour receipt; accepting contour options cannot
produce a successful edge-only page. Native exact point-event output is a
separate lower publication gate, and contour output asserts no visibility.

A page containing only single generated-edge radius/diameter measurements uses
the paid original identity/circular producer directly. It does not construct a
display topology snapshot before admission. Other legacy dimension measurement
preparation remains a separate bounded-source integration gap; it cannot inherit
this radial route's resource evidence.

The dimension producer's additive source-bound operation receives the immutable
radial measurement and original screen frame. Each generated radial stroke binds
its exact identity to DrawingRadialDimensionSource on the same page accountant.
Native format provenance retains original curve/station/placement/body/occurrence
and measurement identity plus paper law; midpoint boxes remain proposals only.
External custom producers must explicitly implement this source-bound operation
for radial receipts, rather than silently drop source provenance.
