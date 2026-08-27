# T11-R Evidence — Professional Bicycle Reference

## Purpose and status

This document is the evidence record for T11-R. It separates observed
implementation behavior, primary-source constraints, T11 design choices,
derived candidate values, and unresolved decisions. It is an input to T11-A;
it is not a manufacturing drawing, a safety assessment, a certification
record, or an L2 artifact acceptance report.

Evidence was reviewed on 2026-08-28. The source links below are direct
official-source locators. “Observed” means that the named implementation path
was executed; an API declaration or a source catalogue entry is not treated as
behavioral proof.

### Result at a glance

    Registered ProjectAgent route
        -> ProjectWorkspace generation guard
        -> AutomationRunner
        -> EditorSession CAD source
        -> exact evaluation
        -> package / renderer

    CAD source -------------------------------> design authority
       |                                             |
       +--> derived Mesh snapshot -------------------+--> presentation
       |
       +--> explicit Make Editable -> independent Authored Mesh

The current route is operational, but the former ten-primitive bicycle remains
a concept-level fixture. It does not satisfy the T11 L2 contract. Two bounded
production-route probes are recorded separately: Probe A establishes the
16/14 mm annular profile, 100 mm straight path, and observed topology/radii;
Probe B establishes its own 15/12 mm profile and 400 mm path together with
successful general validation, evaluation, and stale-publication behavior.
Probe A's dimensions are not evidence for Probe B, and Probe B's validation is
not a formal B-rep watertight report. The required frame, fork, wheel,
cockpit, interface, and drivetrain coverage remains an implementation and
validation gap owned by T11-A/T11-V.

## 1. Provenance and authority model

The following labels are used throughout this document:

| Label | Meaning |
|---|---|
| source constraint | A value or rule stated by an official standard, regulator, or component manufacturer. Applicability remains limited to the cited scope. |
| observed implementation | A behavior measured on the current production route or an explicitly identified test route. |
| design choice | A value selected for the T11 reference scenario; it is not claimed to be imposed by a source. |
| derived candidate | A calculation from named source values or choices. It must be recomputed and accepted by T11-A. |
| unresolved | Evidence is insufficient, applicability is conditional, or a manufacturing/approval decision is still missing. |

### Provenance matrix

| ID | Candidate fact or parameter | Classification | Canonical unit | Applicability and interpretation | Authority / evidence | State |
|---|---|---|---|---|---|---|
| BASE-01 | Adult size-M / 54-equivalent, rigid, traditional diamond, endurance-road reference | design choice | n/a | Bounds the T11 reference scenario; not a rider-specific fit or a product claim | T11-0 design contract, DESIGN.md | fixed category baseline |
| ISO-4210-2 | Design, assembly, and safety/performance requirements for covered bicycle categories | source constraint | n/a | Official abstract identifies the standard scope; normative text and test values are not available in this task | ISO 4210-2:2023, https://www.iso.org/standard/78077.html | scope only; no compliance claim |
| ISO-4210-6 | Frame and fork test-method scope | source constraint | n/a | Identifies a later test-method authority; no pass/fail value is inferred from the abstract | ISO 4210-6:2023, https://www.iso.org/standard/78081.html | scope only; no compliance claim |
| UCI-01 | Overall bicycle envelope 1850 x 500 | source constraint | mm | Competition-equipment rule, not a general safety limit; applicable bicycle class and measurement convention must be confirmed in T11-A | UCI Part 1, 01.01.2026, Art. 1.3.012, https://assets.ctfassets.net/761l7gh5x5an/MiBPXV3F9Y4jGKqffTUNr/f417c1265a606205d6a21179fc39ec4c/1-GEN-20260101-E.pdf | compatibility check only |
| UCI-02 | Bottom-bracket height 240–300 | source constraint | mm | Competition envelope; no frame BB height is selected from it alone | UCI Part 1, Art. 1.3.015, same PDF | compatibility check only |
| UCI-03 | Front-center 540–650; rear-center 350–500 | source constraint | mm | Competition envelope for the cited rule; T11-A must derive geometry from explicit datums | UCI Part 1, Art. 1.3.016, same PDF | compatibility check only |
| UCI-04 | Fork inside max 115; rear-triangle inside max 145 | source constraint | mm | Competition clearances; not a tire or structural safety guarantee | UCI Part 1, Art. 1.3.017, same PDF | compatibility check only |
| UCI-05 | Wheel including tire 550–700; mass-start rim height max 65; at least 12 spokes | source constraint | mm / count | Competition rule; wheel construction and tire fit still require component evidence | UCI Part 1, Art. 1.3.018, same PDF | compatibility check only |
| UCI-06 | Traditional main triangle; frame element max height 80, min thickness 10; fork min thickness 10 | source constraint | mm | Competition geometry rule; not a tube strength or manufacturing rule | UCI Part 1, Art. 1.3.020, same PDF | compatibility check only |
| UCI-07 | Road/cyclocross bar outside width min 400; current lever inside extremities min 280 | source constraint | mm | Competition rule; cockpit reach, flare, controls, and rider fit are separate decisions | UCI Part 1, Art. 1.3.022, same PDF | compatibility check only |
| TREK-D54 | Size 54 realism envelope: 700C, seat 500, seat angle 73.7°, head tube 160, head angle 71.3°, ETT 542, BB drop 80, chainstay 420, fork offset 53, trail 59, wheelbase 1010, standover 754, reach 374, stack 575 | source observation used as design reference | mm / degrees | Official current product geometry; use as a realism envelope, not as authority to copy a proprietary frame or as a universal fit | Trek OCC geometry API, https://api.trekbikes.com/occ/v2/de/products/47131/sizing | candidate envelope |
| TREK-SERVICE | Product-specific front 100 / rear 142, tapered steerer 28.6 / 38.1, 140/160 rotors, max tire 38 | source constraint | mm | Domane carbon/T47 service context; cannot be transferred to a generic steel reference without a compatibility decision | Trek Domane SL/SLR MY23 Service Manual, https://media.trekbikes.com/image/upload/v1691156199/TK_DomaneSL-SLR_MY23_ServiceManual.Rev1.pdf | conditional; do not adopt blindly |
| DED-TT | MTO317A502 top tube: OD 31.7, length 600, wall 0.6 / 0.45 / 0.6, butt regions 120 / 20 / 400 / 20 / 40; head-tube painted side marked DON'T CUT | source constraint | mm | 2025 catalogue part geometry; orientation and butt regions must be preserved if selected | Dedacciai Steel Tubes Catalogue 2025, p.3, https://dedacciai.com/pub/media/wysiwyg/download/dedacciai-steel-tubes-catalog-2025.pdf | candidate tube |
| DED-DT | MTQ350A702 down tube: OD 35, length 650, wall 0.65 / 0.45 / 0.65, butt regions 60 / 30 / 490 / 30 / 40; head-tube side marked DON'T CUT | source constraint | mm | Same limitation as DED-TT; catalogue dimensions are not strength evidence | Dedacciai Steel Tubes Catalogue 2025, p.5, same PDF | candidate tube |
| DED-ST | MTV286B301 seat tube: OD 28.6, ID 27.4, length 650, wall 0.6 then 0.8; final 150 and transition 60 at BB side marked DON'T CUT | source constraint | mm | Seat-post/BB fit and butt orientation require a separate interface design | Dedacciai Steel Tubes Catalogue 2025, p.8, same PDF | candidate tube |
| DED-CS | MPO240C202 road-disc chainstay: length 445, dropout OD 12.5, BB-side oval 16 x 30, wall 0.7 then 1.0 | source constraint | mm | Candidate road-disc chainstay; exact miter and dropout joint remain unresolved | Dedacciai Steel Tubes Catalogue 2025, p.10, same PDF | candidate tube |
| DED-SS | MPV160B210 road seatstay: length 560, OD 12.5 -> 16, wall 0.7 | source constraint | mm | Candidate seatstay stock; joint and bend/process are not specified by this evidence | Dedacciai Steel Tubes Catalogue 2025, p.10, same PDF | candidate tube |
| DED-HT | MTS460 head tube: OD 46, wall 1.1; catalogue shows Deda headset compatibility context | source constraint | mm | Nominal ID derived as approximately 43.8 mm is not an accepted machined fit; reaming, tolerance, stack, and headset choice remain open | Dedacciai Steel Tubes Catalogue 2025, p.16, same PDF | candidate tube; interface unresolved |
| DEDA-FORK | Allroad fork: 700C, A-C 370, rake 45, 12 x 100, flat mount 140/160, max 622 x 35, min blade clearance 5, tapered 1 1/8–1.5, wheel centering ±1.5 | source constraint | mm | External candidate fork envelope; it is not a frame-fork fabrication specification | Deda Allroad Fork, https://dedaelementi.com/allroad-fork | candidate component |
| DEDA-HEADSET | Classic1: head-tube ID 44, upper 1 1/8, lower external 1.5 | source constraint | mm / inch interface | Headset product interface; compatibility with DED-HT must be checked after machining and stack selection | Deda Classic1 Headset, https://dedaelementi.com/classic1-headset | candidate interface |
| FORK-CONFIG-CONFLICT | Trek size-54 geometry records fork offset 53 and trail 59; the Deda candidate records rake/offset 45 | unresolved | mm | These are mutually exclusive fork geometry configurations. If Deda is selected, Trek's offset/trail values must not be retained; trail must be recomputed from actual wheel radius, selected head angle, and rake 45 | TREK-D54 + DEDA-FORK | T11-A must select one |
| SHI-FC | FC-R7100: chainline 44.5, Q-factor 148, 50/34, 172.5 crank reference, threaded shell 68/70 | source constraint | mm / tooth count | Drivetrain product specification; selected crank length and shell width are not universal | Shimano FC-R7100, https://productinfo.shimano.com/en/product/FC-R7100 | candidate interface |
| SHI-CS | CS-R7100-12 range 11–34 | source constraint | tooth count | Candidate 12-speed road drivetrain envelope; derailleur capacity and freehub must be checked as a set | Shimano CS-R7100-12, https://productinfo.shimano.com/en/product/CS-R7100-12 | superseded by coherent set below |
| SHI-R7100-SET | Shimano road 2x12 lineup row names FC-R7100, CS-R7101-12, WH-RS710-C32-TL-F/R, BR-R7170, and 140/160 rotors as one lineup | source constraint | mm / tooth count | The same row in the current 2026–2027 v024 chart is the compatibility authority for the candidate component set. The 2025–2026 v025 URL is retained only as a historical locator, not as current authority | Shimano current Road Bike lineup chart, https://productinfo.shimano.com/pdfs/product/latest/Line-up_chart_en.pdf; historical 2025–2026 locator supplied for T11-R, https://productinfo.shimano.com/pdfs/product/thisyear/2025-2026_Line-up_chart_v025_en.pdf | resolved compatibility candidate |
| SHI-RS710 | WH-RS710-C32-TL-F/R: tubeless, 700C 622 x 21C, front 100 x 12, rear 142 x 12, rim height 32, internal 21, external 28, 24 spokes, recommended tire 25-622–32-622; rear 12/11 speeds and HG spline L | source constraint | mm / count | Candidate wheel set is tubeless and therefore compatible in type with a tubeless 32-622 reference tire; exact hub/rotor/axle stack remains a frame decision | Shimano WH-RS710-C32-TL-R, https://productinfo.shimano.com/ja/product/WH-RS710-C32-TL-R; front product page, https://productinfo.shimano.com/en/product/WH-RS710-C32-TL-F | candidate component |
| SCH-32 | Pro One 32-622, Tubeless Easy (TLE) tire | source constraint | mm ETRTO | Candidate reference tire requiring a tubeless-compatible wheel setup; 32 is nominal size, not a guaranteed inflated casing or frame clearance | Schwalbe Pro One Tubeless, https://www.schwalbe.com/en/PRO-One-Tubeless-11654225; tire-size FAQ, https://www.schwalbe.com/en/technology-faq/tire-sizes/ | candidate component |
| SHI-RS171-REJECT | WH-RS171 clincher wheel was previously paired with a tubeless-only Pro One candidate and a different freehub compatibility assumption | observed conflict | n/a | Do not retain WH-RS171 in the baseline; the conflict is resolved by revising the baseline to WH-RS710 tubeless wheels and the Shimano lineup row | Shimano WH-RS171 pages, https://productinfo.shimano.com/en/product/WH-RS171-CL-F12-700C and https://productinfo.shimano.com/en/product/WH-RS171-CL-R12-700C | rejected candidate |
| SRAM-BSA | BSA shell 68 ± 0.5, BC 1.37 x 24 RH/LH; road flat-mount and 142 spacing drawings | source constraint | mm / thread | Candidate steel-road interface; actual shell, facing, thread, brake, and dropout stack are T11-A decisions | SRAM Road Frame Fit Specifications 2024, https://www.sram.com/globalassets/document-hierarchy/frame-fit-specifications/road/2024-road-frame-fit-specifications.pdf | candidate interface |
| PMW-BSA | BB2007: 4130 steel, OD 1.5 in, supplied 68.5 for finishing, 1.370-24 L/R | source constraint | inch / mm / thread | Framebuilder component drawing; exact source locator currently returned 404 by the direct audit, so reacquisition is required before adoption | Paragon BSA drawing, https://paragonmachineworks.com/files/public-docs/PMW%20BSA_WEB.pdf | provisional; locator gap |
| PMW-DR | DR1102 12 mm flat-mount dropout with bolt-on brake insert and eyelets | source constraint | mm interface | Component drawing, not proof of a complete frame dropout joint; exact current locator returned 404 in the audit | Paragon DR1102 drawing, https://paragonmachineworks.com/files/public-docs/DR1102.PDF | provisional; locator gap |
| OBS-PROBE-A | Probe A accepted a constrained two-circle profile (r16/r14 mm) -> 100 mm line path -> sweep, then returned topology with observed cylindrical radii | observed implementation | mm / count | Probe A is limited to profile/path/sweep/topology. It has no validateDocument, evaluation, or stale-publication claim attached | Temporary probe package source /tmp/rupa-t11-probe-package/Sources/T11Probe/main.swift and bounded execution record | observed success |
| OBS-PROBE-B | Probe B accepted an unconstrained two-circle profile (r15/r12 mm) -> 400 mm line path -> sweep, then executed validation, evaluation, and stale-generation checks | observed implementation | mm / generation / revision / publication | Probe B owns the 15/12/400 input-to-validation claim and the guard result. Its topology is a bounded single-shell observation; formal DefaultBRepTopologyValidator watertight reporting was not run | Temporary probe source /tmp/rupa-t11-r1-annulus.F8MCVp/Sources/RupaT11AnnulusProbe/Probe.swift and log /tmp/rupa-t11-r1-annulus.F8MCVp/annulus-probe.log | observed success; formal watertight proof open |
| OBS-T10 | Agent bicycle path produced ten CAD bodies, ten Authored Mesh sources, package round trip, and ten renderer items | observed implementation | count / bytes | Existing T10 fixture behavior; geometry is concept-level and cannot support an L2 claim | Tests/RupaUIPackageTests/AgentBicycleArtifactTests.swift:19-299 and /tmp/rupa-t11-r1.OWaA64/agent-bicycle-report.json | observed route, insufficient fidelity |
| CHOICE-TIRE | Use 32-622 as the initial reference tire for T11-A | design choice | mm ETRTO | Chosen because it is inside the WH-RS710 recommendation and Deda 35 mm fork maximum; actual installed clearance remains open | Depends on SHI-RS710, SCH-32, DEDA-FORK | proposed |
| CHOICE-WHEEL | Use WH-RS710-C32-TL-F/R instead of WH-RS171 | design choice informed by source | mm / count | Makes tire type, axle spacing, rim, spoke, and Shimano drivetrain family coherent at the candidate level | Depends on SHI-R7100-SET, SHI-RS710 | proposed |
| CHOICE-AXLES | Start with 12 x 100 front and 12 x 142 rear | design choice | mm | Consistent candidate set from the wheel/fork/frame-fit sources; exact dropout construction is still open | Depends on DEDA-FORK, SHI-RS710, SRAM-BSA | proposed |
| CHOICE-BB | Start with threaded BSA 68 | design choice | mm / thread | Keeps the generic steel reference separate from Trek's product-specific T47; exact shell component and finish allowance remain open | Depends on SHI-FC, SRAM-BSA, PMW-BSA | proposed |
| CHOICE-STEEL | Evaluate a TIG-welded 25CrMo4 tube reference | design choice informed by source | n/a | Dedacciai catalogue identifies seamless EN 10305-1 25CrMo4 stock; it does not specify this frame's process, heat treatment, weld qualification, or strength | Depends on DED-* | proposed; manufacturing unresolved |
| DERIVED-WHEEL | Nominal 622 + 2 x 32 = 686 outside diameter | derived candidate | mm | Uses nominal rim/tire labels only; actual mounted tire envelope must be measured or sourced | SHI-RS710 + SCH-32 | T11-A must recompute |
| DERIVED-BB | Nominal BB height approximately 686/2 - 80 = 263 | derived candidate | mm | Uses Trek 54 BB drop as a realism input and nominal tire OD; not a selected geometry or UCI compliance result | TREK-D54 + DERIVED-WHEEL | T11-A must recompute |
| DERIVED-FC | With Trek BB drop 80 and chainstay length 420 treated as a straight axle-to-BB segment, horizontal rear projection is sqrt(420^2 - 80^2) = 412.311 and front-center is approximately 1010 - 412.311 = 597.689 | derived candidate | mm | Conditional geometry cross-check only; the API record does not directly expose front-center and the assumption must be confirmed before use | TREK-D54 | T11-A must choose |
| R3-INT-001 | WH-RS171 clincher versus tubeless-only Pro One was a type mismatch | resolved by baseline revision | n/a | Replace WH-RS171 with tubeless WH-RS710-C32-TL-F/R; retain 32-622 only with a tubeless wheel family | SHI-RS710 + SCH-32 | resolved |
| R3-INT-002 | WH-RS171 HG spline L versus the intended HG spline L2 12-speed assumption was not a complete compatibility proof | resolved by baseline revision | n/a | Use the same row in Shimano's current 2026–2027 v024 lineup chart naming WH-RS710 and CS-R7101-12; the 2025–2026 v025 URL is historical only; do not infer a mixed product set from isolated labels | SHI-R7100-SET | resolved |

## 2. Direct-source locator audit

The audit was run on 2026-08-28 using curl -k -L --max-time 15 only to
check locator reachability. The local CA chain rejected the same hosts in
Python's default verifier; -k does not prove source authenticity. Source
authority comes from the official HTTPS host and the reviewed document/page,
not from the bypassed TLS check.

| Source family | URL result in this audit | Availability interpretation |
|---|---:|---|
| ISO 4210-2, ISO 4210-6, ISO ICS catalogue | 403 | Official pages are present but block this audit client; only the public abstract/catalogue scope is used. |
| UCI Part 1 PDF | 200 application/pdf | Current 01.01.2026 PDF reachable. |
| Trek geometry API | 200 application/json | Current product JSON reachable. |
| Trek service manual | 200 application/pdf | PDF reachable. |
| Dedacciai 2025 catalogue | 200 application/pdf | PDF reachable and visually reviewed at the cited pages. |
| Deda Allroad / Classic1 | 307 | Official host redirects; product locators are retained and page content was reviewed. |
| Shimano FC/CS/WH-RS171 product pages | 200 text/html | Official product pages reachable; WH-RS171 is retained only as the rejected conflict record. |
| Shimano current lineup chart | 200 application/pdf; latest locator redirected to 2026–2027_Line-up_chart_v024_en.pdf | Current official lineup row is reachable and used for R3-INT-002 resolution. The historical 2025–2026 v025 locator supplied for the original resolution now returns 404 and is retained only as a historical locator. |
| Shimano WH-RS710 product page | 200/search-cached official page | Official product record was reviewed; current product locator is retained. |
| Schwalbe product and sizing FAQ | 200 text/html | Official pages reachable. |
| SRAM Road Frame Fit 2024 | 200 application/pdf | PDF reachable and reviewed. |
| Paragon BSA / DR1102 PDFs | 404 in current direct audit | The task designer previously reviewed the official drawings and values. The current locator gap is recorded deliberately; T11-A must reacquire or replace these references before treating them as accepted interface authority. |

No search-result snippet, secondary article, or reseller specification is used
as a design authority. The two Paragon records are retained only as
provisional evidence because their official drawing content was previously
reviewed, while current availability is unresolved.

## 3. Registered Agent path and authority transitions

### Production path traced to implementation

| Stage | Current implementation | Contract observed |
|---|---|---|
| Registration and lease | Sources/RupaAgentRuntime/ProjectAgentCommandController.swift:11-65 | A workspace is registered under a session ID and each request obtains a lease. |
| Single command route | Sources/RupaAgentRuntime/ProjectAgentCommandController.swift:228-266 | The controller captures the current view, checks document generation and workspace revision, then routes to the workspace. |
| Batch route | Sources/RupaAgentRuntime/ProjectAgentCommandController.swift:268-302 | Batch effect and expected coordinates are checked before execution; results publish as one batch response. |
| Sketch request | Sources/RupaAutomation/AutomationCommand.swift:74-96 and Sources/RupaAutomation/AutomationRunner.swift:1207-1231 | createSketch carries the complete typed sketch, including multiple entities, and delegates to EditorSession. |
| Sweep request | Sources/RupaAutomation/AutomationCommand.swift:229-244 and Sources/RupaAutomation/AutomationRunner.swift:2443-2464 | createSweep is a real source operation; it is not replaced by a render primitive. |
| Exact topology | Sources/RupaCore/TopologySummaryService.swift:10-45 and Sources/RupaCore/TopologySnapshotService.swift:70-177 | Topology is read from the evaluated B-rep and exposes body shell count and face loop count. |
| Application-owned persistence | Sources/RupaAgentRuntime/ProjectAgentCommandController.swift:183-187 and T10 test path | Agent save is typed commandUnsupported; application-owned workspace save is the persistence boundary. |

### Existing T10 end-to-end run

The existing focused test was run with a bounded Python timeout:

    RUPA_BICYCLE_ARTIFACT_DIR=/tmp/rupa-t11-r1.OWaA64
      swift test --package-path RupaKit
      --filter agentBuildsEditsPersistsAndRendersBicycleArtifact

The package build completed in approximately 4.95 seconds and the test
passed in 6.872 seconds (one test, @Test(.timeLimit(.minutes(5)))). The
captured report is /tmp/rupa-t11-r1.OWaA64/agent-bicycle-report.json; the
transcript is /tmp/rupa-t11-r1.OWaA64/agent-bicycle-agent-transcript.json.

| Observation | Measured result | Meaning |
|---|---:|---|
| CAD bodies | 10 | All ten fixture commands created persistent CAD bodies. |
| Authored Mesh assets | 10 | Make Editable created independent Mesh authorities. |
| Renderer items | 10 | Loaded evaluation reached the renderer. |
| Render triangles | 1044 | The fixture is a very low-detail primitive assembly. |
| Presentation buffers shared | true | T10 zero-copy sharing contract was observed for the presentation path. |
| Preview published | false | Preview remained staged/non-published. |
| Mesh edit copied bytes | 7920 in one event | Copy occurs at the explicit editable mutation boundary, not during read/evaluation. |
| Package size | 302235 bytes | Package was saved and loaded through the application-owned route. |
| Package entries | manifest.json, source/product.json, source/cad.json, source/mesh-assets.json, 10 content-addressed blobs | The v3 source separation is present; no source/rupa.json entry was produced. |
| Agent save | failure:command.unsupported | File/window lifecycle remains application-owned. |

The fixture's source definitions are explicitly primitive: wheels and crank
use createExtrudedCircle, frame members and cockpit parts use
createExtrudedRectangle, and placement uses scene-node transforms
(Tests/RupaUIPackageTests/AgentBicycleArtifactTests.swift:500-530,
:645-721). This is valid route evidence but a hard L0/L1 result, not an L2
professional bicycle.

### Bounded production-route annulus probes

The two temporary probes used the registered
ProjectAgentCommandController path but are independent executions with
different inputs and evidence scopes. Both were compiled against the existing
Debug product modules with Swift
swift-6.4.x-DEVELOPMENT-SNAPSHOT-2026-08-14-a, target
arm64-apple-macos26.0, and the MacOSX 27.0 SDK. Each was bounded by a
60-second process timeout and completed with exit status 0. No repository
source or test was added.

#### Probe A — profile, straight path, sweep, and topology

Probe A source is
/tmp/rupa-t11-probe-package/Sources/T11Probe/main.swift. Its bounded
execution record is retained with that temporary probe package. It did not
run validateDocument, currentEvaluation, or a stale request.

| Request | Input and result |
|---|---|
| Profile sketch | createSketch with two circles, outer radius 16 mm and inner radius 14 mm, plus a concentric constraint; success at generation 1, transaction 1, publication 2 |
| Straight line path | createLineSketch with one 100 mm line; success at generation 2, transaction 2, publication 3 |
| Sweep | createSweep using the profile and path; success at generation 3, transaction 3, publication 4 |
| Topology | one body, one shell, 10 faces, 24 edges, 16 vertices; outer/inner cylindrical faces observed at radii 16/14 mm; planar start/end caps each had two loops |

The topology and radius observations in this table belong only to Probe A.
They do not provide validation, evaluation, or stale-publication evidence for
Probe B.

#### Probe B — validation, evaluation, and stale-publication guard

Probe B source is
/tmp/rupa-t11-r1-annulus.F8MCVp/Sources/RupaT11AnnulusProbe/Probe.swift.
The execution log is
/tmp/rupa-t11-r1-annulus.F8MCVp/annulus-probe.log. This independent run used
an unconstrained two-circle profile (outer radius 15 mm, inner radius 12 mm)
and a 400 mm line path created by createSketch, not the Probe A inputs.

| Request | Input and result |
|---|---|
| Profile sketch | createSketch with two circles, input radii 15/12 mm and no concentric constraint; success at generation 1 |
| Straight line path | createSketch with one 400 mm line; success at generation 2 |
| Sweep | createSweep using the profile and path; success at generation 3 |
| Validation | validateDocument success at generation 3, didMutate=false, zero diagnostics; this is general document validation, not the formal B-rep watertight validator |
| Topology | one body, one shell, 10 faces, 24 edges, 16 vertices; two planar end faces each had two loops and eight cylindrical side faces each had one loop |
| Evaluation | one CAD occurrence with 25262 vertices and 25242 faces |
| Stale rename | typed failure document.generationMismatch; expected generation 0 while current generation was 3 |
| Post-failure state | generation 3, transaction revision 3, publication sequence 4, name unchanged (T11 Annulus Probe) |

The successful validation claim is coupled only to Probe B's own 15/12 mm
profile and 400 mm path. Probe B's topology establishes a bounded single-shell
case, while its input radii are not presented as an independently extracted
radius measurement. Probe A is the independent radius observation at 16/14 mm.
Neither probe is a formal DefaultBRepTopologyValidator watertight report.
Generated IDs and tessellation counts are observations, not design
parameters. No probe proves every hollow tube, oval profile, miter, trim, or
curved sweep.

Neither annulus probe claims curved-path support. Existing
kernel/Agent modeling tests show that the connected multi-entity
path-normal case returns typed evaluationFailed containing
sweepPathNormalUnavailable and leaves the created path feature and generation
unchanged (Tests/RupaAgentModelingTests/AgentSolidSweepRevolveIntegrationTests.swift:1010-1041).
That test uses the Agent modeling fixture route, so it is a capability
boundary reference rather than a substitute for the registered production
probe.

## 4. L2 operation feasibility and exact gaps

“Available” below means an operation is exposed or observed. It does not mean
that the operation is sufficient for an L2 bicycle part. A later task must
retain the semantic part identity and prove the actual interface.

| L2 requirement | Current route evidence | Current result | Exact gap; T11-A input |
|---|---|---|---|
| Straight hollow circular tube | Probe A: r16/r14, 100 mm createLineSketch, sweep, topology/radius; Probe B: r15/r12, 400 mm createSketch line, sweep, validateDocument, topology, evaluation | observed-success only for the two separately recorded bounded circular straight cases | Parameterize tube OD/ID, datum orientation, length, and end conditions; preserve annular profile through frame-joint operations. |
| Hollow oval tube | Typed sketch API has general sketch entities, but no successful registered Agent oval-profile run is in this evidence | unproven | Choose an exact supported oval/ellipse profile representation or report a typed capability gap; do not substitute a rectangular or solid primitive. |
| Tube miter/trim and fit at joints | createFaceKnife, sketch trim/cut operations, and body edits are exposed; no frame-tube miter was observed | unproven | Establish an operation sequence that trims both tube and joint owner, preserves hollow walls, and validates contact/no residual material. |
| Tapered fork body and wheel envelope | createLoft/createSweep are exposed and a separate loft test evaluates a solid; no production fork with rake, A-C, steerer, blade clearance, axle, and brake mount was observed | unproven | Model fork as a semantic part with a reproducible rake/A-C datum and verify 700C/35 envelope and 12 x 100/flat-mount interfaces. |
| Rim / tire / hub / spoke assembly | Circles and primitives pass in the T10 fixture; no annular rim section, tire casing, hub axle, spoke count/placement, or wheel interface was observed | unproven | Build a 622 rim/tire/hub/spoke hierarchy from component constraints; a solid disk is explicitly rejected by T11-0. |
| Dropout / bottom bracket / headset | Boolean and primitive operations exist; candidate BSA, dropout, and headset sources are recorded; no interface fit check or joint closure was observed | unproven | Resolve shell machining, threads, bearing seats, axle faces, brake mount, headtube ID, steerer, and tolerance stack. |
| Drivetrain and brake interfaces | Shimano values, the coherent lineup row, and flat-mount sources are available; current route has no semantic chainline/cassette/rotor/derailleur or brake-clearance assembly proof | unproven | Implement named interface datums and validate chainline, 11–34 capacity, 140/160 rotor choice, and service clearances. |
| Multi-entity or curved tube path | Existing modeling tests report typed sweepPathNormalUnavailable for the tested connected path-normal case | observed-failure for that case | Do not generalize path support; T11-A must either remain with proven straight cases or define a new capability test with explicit acceptance. |
| CAD-to-Mesh presentation | T10 route evaluates CAD and reaches the renderer; buffers are shared | observed-success as presentation path | The current result is low-detail; T11-V must add deterministic views and geometric acceptance evidence. |
| Authored Mesh transition | T10 Make Editable creates independent Mesh assets while retaining CAD fingerprint and selecting Mesh for presentation | observed-success as authority transition | Mesh editing is not the professional CAD design source; any later bake/edit must preserve independent provenance. |

No operation marked unproven may be silently replaced with a primitive,
render-only Mesh, or visual approximation while retaining an L2 claim.

## 5. Baseline consistency check

The baseline can be retained as a design target. No source contradiction was
found at the category level, but the following are only compatibility
cross-checks:

| Check | Calculation or source value | Result |
|---|---:|---|
| Wheel family | 622 mm rim and nominal 32 mm tire | 700C family remains consistent. |
| Tire and wheel type | WH-RS710 tubeless recommendation includes 32-622; SCH-32 is tubeless | The earlier WH-RS171/Pro One conflict is removed by the baseline revision. |
| Nominal wheel outside diameter | 622 + 2 x 32 = 686 mm | Inside UCI's 550–700 mm competition envelope; actual mounted casing still requires measurement. |
| Nominal BB height cross-check | 686 / 2 - Trek's 80 mm BB drop approximately 263 mm | Inside UCI's 240–300 mm envelope; Trek's drop is a realism input, not a selected T11 value. |
| Trek size-54 realism front-center | Assuming the 420 mm chainstay is the straight axle-to-BB segment and the 80 mm BB drop is the vertical component: sqrt(420^2 - 80^2) = 412.311 rear projection, so 1010 - 412.311 approximately 597.689 mm | Conditional derived check inside UCI's 540–650 mm front-center envelope; Trek's API does not directly expose front-center, so T11-A must confirm the measurement convention. |
| Trek size-54 realism rear-center | 420 mm | Inside UCI's 350–500 mm rear-center envelope for that product record. |
| Front axle/fork candidate | Deda 12 x 100 and 700C max 622 x 35 | Consistent with the proposed 32-622 reference tire, subject to blade and brake clearance. |
| Fork geometry authority | Trek offset 53 / trail 59 and Deda rake/offset 45 | Mutually exclusive alternatives; if Deda is selected, do not retain Trek offset/trail and recompute trail from actual wheel radius, selected head angle, and rake 45. |
| Rear axle/wheel candidate | Shimano 142 x 12 | Consistent with the proposed road-disc candidate, subject to dropout construction. |
| Frame topology | T11-0 traditional diamond | Consistent with the category baseline and UCI traditional-triangle rule; no competition compliance is claimed. |
| Drivetrain family | Shimano current 2026–2027 v024 lineup row | Provides one current compatibility authority for FC-R7100, CS-R7101-12, WH-RS710-C32-TL-F/R, and BR-R7170; the 2025–2026 chart is historical only and isolated product mixing is avoided. |

The check does not establish a safe, race-legal, manufacturable, or
rider-correct bicycle. Overall envelope, bar width, lever position, fork and
rear-triangle inside clearances, structural load cases, and all tolerances
remain T11-A/T11-V work. The baseline therefore remains consistent as a
bounded reference scenario, not complete as a product specification.

## 6. T11-A input set

T11-A owns the final parameter graph, equations, datums, semantic hierarchy,
and operation mapping. The following is the bounded input set it may evaluate:

| Input group | Candidate values | Classification | T11-A obligation |
|---|---|---|---|
| Category | adult 54-equivalent, 700C, rigid, diamond, endurance-road | design choice | Keep the category unless a direct contradiction is demonstrated. |
| Geometry envelope | Trek D54 values; UCI ranges | source constraint + realism reference | Select independent datums and do not copy a proprietary frame. |
| Wheel/tire | WH-RS710 622 x 21C tubeless wheel, 32-622 tubeless tire, nominal 686 OD | source constraint + design choice + derived candidate | Recompute installed tire envelope, rim/tire interface, and clearances. |
| Axles/fork | 12 x 100 front, 12 x 142 rear, Deda A-C370/rake45 candidate | source constraint + design choice + unresolved alternative | Select either the Trek geometry fork values or the Deda rake45 configuration; never combine them. If Deda is selected, recompute trail from actual wheel radius and selected head angle. Resolve steerer, dropout, brake, and wheel-centering stack. |
| Frame tubes | Dedacciai 25CrMo4 stock candidates and butt/orientation data | source constraint + design choice | Decide whether stock is appropriate; do not infer strength or process qualification. |
| BB/headset | BSA 68 candidate; MTS460/Classic1 candidate stack | source constraint + design choice + unresolved fit | Resolve actual shell dimensions, threads, machining, bearing seats, and tolerances. |
| Drivetrain | Shimano lineup row: FC-R7100, CS-R7101-12, WH-RS710, BR-R7170; chainline44.5 and Q148 | source constraint + design choice | Create interface datums and check clearances and serviceability. |
| Brakes | Flat mount 140/160 candidate, BR-R7170 and CENTER LOCK wheel family | source constraint + design choice | Choose rotor size and validate mount/dropout/frame clearance. |
| Manufacturing | TIG/25CrMo4 is a candidate direction only | design choice; manufacturing unresolved | Obtain process, joint, HAZ, heat-treatment, tolerance, and strength evidence before any manufacturing claim. |

## 7. Unresolved decisions and explicit non-claims

The following are still open and are not filled with plausible defaults:

1. Rider population, fit method, saddle/handlebar contact points, and size
   range.
2. Intended use, total system mass, impact/load envelope, and applicable
   market/regulatory regime.
3. Exact tube miter/trim operation, weld/joint construction, HAZ treatment,
   finishing allowance, and manufacturing tolerances.
4. Fork geometry authority: Trek offset 53/trail 59 versus Deda rake/offset
   45. T11-A must select one; with Deda, recompute trail and discard the Trek
   offset/trail values.
5. Exact headset shell machining and steerer/bearing stack; nominal MTS460 /
   Classic1 numbers are not by themselves a fit proof.
6. Dropout orientation, axle faces, hanger, eyelets, flat-mount insert, and
   rotor/chainstay clearances.
7. Rim drilling, spoke lacing, hub bearings/axle, tire bead/casing, and wheel
   service dimensions.
8. Drivetrain component stack, chainline validation, derailleur capacity,
   brake hose routing, and service access.
9. Curved or multi-entity sweep behavior beyond the explicitly tested typed
   failure.
10. Current direct availability of the two Paragon drawing locators.
11. ISO normative acceptance values and any certification or physical test.

Accordingly, this record makes no claim of structural safety, fatigue life,
manufacturability, production readiness, rider fit, race legality,
regulatory compliance, or certification. It also does not promote a
CAD-derived Mesh snapshot to source authority.

## 8. Verification record and change impact

Completed for this evidence record:

- official-source locator and availability audit recorded above;
- visual review of the cited Dedacciai catalogue pages and exact butt/orientation
  notes;
- existing focused T10 production-path execution recorded above;
- two independent bounded registered Agent annulus probes, with Probe A
  limited to topology/radius and Probe B covering validation, evaluation,
  stale-generation, and publication-state observations;
- source-level trace from Agent request through AutomationRunner and
  EditorSession;
- skltn headers-only map of the RupaAgentRuntime target was generated, and
  narrow Swift diagnostics for Sources/RupaAgentRuntime reported no
  diagnostics;
- rg audit found no FIXME(INCOMPLETE_IMPLEMENTATION), no target-conditional
  synchronization branch, and only the existing ProjectWorkspaceRegistry
  Mutex state owner in the observed Agent route;
- this evidence record does not alter production code; parent review still
  owns the final scope and design approval.

The evidence changes no production source or test. Any change to the following
requires rechecking this record and the T11-0 design authority:

- the registered Agent route or its typed failure/publication behavior;
- CAD/Mesh authority or Make Editable semantics;
- selected source values, units, applicability, or derivation;
- the L2 acceptance boundary;
- the official source versions or their availability.
