# Professional V8 Primary-Source Evidence

Access date: 2026-08-30.

This record separates external facts from original design choices. OEM outputs
are feasibility benchmarks only; no OEM geometry is copied.

| ID | Primary source | Observed fact | Applicability and interpretation |
|---|---|---|---|
| SRC-SAE-J1349 | [SAE J1349_202511](https://saemobilus.sae.org/standards/j1349_202511-engine-power-test-code-spark-ignition-compression-ignition-installed-net-power-torque-rating) | Defines repeatable as-installed net engine power and torque measurement. | `REQ-PWR-001` and `REQ-TRQ-001` are target net ratings; calculations are not certification. |
| SRC-AMG-4L | [Mercedes-AMG 4.0 L biturbo V8](https://media.mercedes-benz.com/en/article/fd874439-9493-43c9-98f4-33c2f76c446d) | OEM reports 450 kW and 850 N·m from a 4.0 L biturbo V8. | Establishes that 450 kW is a real product-class benchmark. It supplies no dimensions to this design. |
| SRC-FORD-BLOCK | [2024 Ford Mustang technical specification](https://media.ford.com/content/dam/fordmedia/Europe/en/2024/01/NewMustang/2024_Ford_Mustang_technical_specification_EU.pdf) | Lists a cast-aluminum block and head, plasma-transfer wire-arc cylinder liners, and DOHC valvetrain for a production V8. | Supports the feasibility of aluminum closed-deck/head and coated-bore architecture, not final material or coating selection. |
| SRC-FORD-TRACK-COOLING | [Ford Mustang Dark Horse engineering release](https://media.ford.com/content/fordmedia/fna/ca/en/news/2022/09/16/ford-introduces-mustang-dark-horse.html) | Track duty adds an auxiliary engine-oil cooler, enhanced radiator, and stronger fans. | Supports separate engine-oil and high-temperature cooling budgets for `REQ-APP-001`. |
| SRC-GM-LT6 | [GM LT6 engineering release](https://news.gm.com/home.detail.html/Pages/news/us/en/2021/oct/1026-corvette-z06.html) | Documents aluminum block, DOHC heads, forged pistons/rods, six-stage dry sump, tuned intake/exhaust, and SAE J1349 output in an endurance-derived V8. | Supports subsystem choices for high-speed track duty. The current design retains a cross-plane crank and lower speed. |
| SRC-GM-OIL-JET | [Chevrolet Corvette technical specification](https://media.chevrolet.com/content/dam/Media/documents/INTL/chevrolet/tech-data/corvette-stingray/Chevrolet-Corvette-Stingray-TechSpecs_EN.pdf) | Documents a dry-sump system with oil-spray piston cooling. | Supports dry-sump plus per-piston cooling-jet architecture. Flow remains a design calculation. |
| SRC-MAHLE-PISTON-COOLING | [MAHLE Technical Messenger 02/2026](https://www.mahle-aftermarket.com/media/media-global-%26-europe/products-and-services/technical_messenger/tm_issues_2026/technical_messenger_2_2026_en.pdf) | Explains that oil jets reduce piston/ring-zone temperature and that jet loss can cause overheating and seizure. | Makes piston jets a required thermal architecture and a failure-sensitive service item. |
| SRC-GARRETT-MAP | [Garrett compressor-map guidance](https://www.garrettmotion.com/knowledge-center-category/oem/expert/) | Defines compressor pressure ratio, surge, choke, speed lines, and efficiency islands. | Requires explicit operating points; advertised horsepower alone cannot accept a turbo. |
| SRC-GARRETT-G25 | [Garrett G25-550](https://www.garrettmotion.com/es/racing-and-performance/performance-catalog/turbo/g-series-g25-550/) | Publishes 300–550 hp, 1.4–3.0 L range, 48/60 mm compressor, 54/49 mm turbine, and housing options. | Each 2.0 L bank targets about 300 hp. Map coordinates and margins still require verification. |
| SRC-GARRETT-TEMP | [Garrett G25-660](https://www.garrettmotion.com/racing-and-performance/performance-catalog/turbo/g-series-g25-660/) | Publishes 79% peak compressor efficiency, 165 krpm maximum speed, and turbine/housing temperature rating to 1,050 °C. | Supplies component capability context; the design keeps 950 °C continuous and 1,000 °C transient turbine-inlet targets. |
| SRC-MIT-SLIDER | [MIT 2.141 mechanism notes](https://ocw.mit.edu/courses/2-141-modeling-and-simulation-of-dynamic-systems-fall-2006/dfb7d1ed209da291ee93b7ec5bf41608_modulated_transf.pdf) | Provides the crank/rod piston-position relation. | Used for exact bank-axis piston closure and acceleration derivation. |
| SRC-MIT-THERMO | [MIT unified thermodynamics](https://ocw.mit.edu/ans7870/16/16.unified/thermoF03/chapter_5.htm) | Applies the first law to heat-engine work and heat flows. | Used as the governing energy-balance principle, not as a source for the chosen empirical heat split. |
| SRC-DOE-EXHAUST | [US DOE exhaust-energy overview](https://www.energy.gov/cmei/vehicles/materials-energy-recovery-systems-and-controlling-exhaust-gases) | Notes that about 30% of ICE chemical energy is commonly lost through hot exhaust. | Supports the order of magnitude of the provisional 34% full-power exhaust fraction. Exact split requires dyno heat-balance measurement. |

## Original Design Choices

| ID | Choice | Reason | Release status |
|---|---|---|---|
| CHOICE-ARCH-001 | 90-degree cross-plane V8, 3,996.46 cc | Smooth road duty and continuity with the requested V8 class | Fixed for P2 |
| CHOICE-BOOST-001 | One outside-V G25-550-class turbo per bank | Keeps each compressor near a 2.0 L/300 hp duty and reduces valley heat | Exact map/A/R and manifold require P3 gas-exchange work |
| CHOICE-CR-001 | 9.5:1 compression ratio | Pump-fuel boost/response compromise | Knock/combustion CFD and dyno calibration required |
| CHOICE-PMAX-001 | 18 MPa nominal, 20 MPa design cylinder pressure | P2 structural load envelope | Pressure trace and abnormal-combustion cases required |
| CHOICE-THERMAL-001 | 34% brake, 31.5% pre-turbine exhaust, 22% HT coolant, 3.5% oil, 2.5% charge cooling, 6.5% ambient/unmodeled | The earlier provisional 34% exhaust split failed the 950 °C continuous turbine-inlet screening limit; the revised split closes the first law and gives a 906 °C steady sensible-enthalpy screen consistent with the cited exhaust order of magnitude | Still a P2 allocation that must be replaced by measured dyno heat balance |
| CHOICE-LUBE-001 | Six-stage dry sump and eight piston jets | Sustained track lateral/longitudinal acceleration and piston cooling | Pump, tank, deaeration, and scavenge sizing require rig validation |
| CHOICE-CAD-001 | Explicit flow envelopes instead of fake finished passages | Current CAD must remain honest about P2 detail | Hollow/boolean capability gaps remain visible |
| CHOICE-CURVE-001 | Eleven full-load points from 1,000 to 7,000 rpm with 22–35% assumed brake efficiency | Makes the requested 450 kW/750 N·m envelope recomputable instead of implying a flat scalar rating | Requires 1D gas exchange, combustion analysis, and dyno calibration |
| CHOICE-FUEL-MODEL-001 | 42.7 MJ/kg lower heating value and 12.5:1 full-load air/fuel mass ratio | P2 fuel and air-flow sizing assumptions for 98 RON gasoline | Certified regional fuel properties, injector characterization, emissions, and knock calibration remain open |
| CHOICE-AIR-MODEL-001 | 95% volumetric efficiency, 75% compressor efficiency, 3 kPa inlet loss, 12 kPa charge-path loss, and 50 °C manifold target | Produces explicit compressor coordinates and charge-cooler load at the hot-ambient design point | Requires digitized maps, measured pressure losses, 1D gas exchange, and vehicle charge-circuit validation |
| CHOICE-FLUID-MODEL-001 | HT coolant 3.8 kJ/kg·K and 1,050 kg/m³ over 15 K; oil 2.1 kJ/kg·K and 850 kg/m³ over 20 K; 10–15% flow/capacity margins | First-order pump, cooler, and radiator interface sizing | Fluid supplier curves, pump maps, pressure drop, boiling/cavitation, and vehicle airflow remain P3/P4 gates |
| CHOICE-ROTATING-001 | 0.55 kg reciprocating mass, 22 mm wrist pin, 54 mm crankpin, 65 mm mains, and 3.0×10⁻⁹ m⁴ rod weak-axis screen | Makes 7,000/7,350 rpm inertia, projected bearing pressure, surface speed, and Euler load explicit for P2 packaging | Mass optimization, counterweights, torsion, oil-film analysis, temperature-dependent allowables, fatigue, and FEA remain open |
| CHOICE-CLAMP-001 | Ten 65 kN head fasteners per bank | Provides an aggregate clamp inventory against one-cylinder design gas force | Fastener grade, joint stiffness, thermal relaxation, local bore distortion, and gasket sealing remain open |
| CHOICE-VALVE-001 | Two 34 mm intake and two 29 mm exhaust valves per cylinder at 11.5/10.5 mm lift | Provides a DOHC four-valve package and first-order curtain areas | Port flow, seat geometry, spring dynamics, cam profiles, piston clearance, and combustion remain open |

## Unresolved Production Decisions

| ID | Missing authority | Why it blocks P3/P4 |
|---|---|---|
| OPEN-EMISSIONS-001 | Target market and emissions cycle | Determines catalyst volume, cold start, OBD, calibration, and hardware |
| OPEN-FUEL-001 | Certified fuel envelope and ethanol range | Determines knock, seals, injection capacity, and calibration |
| OPEN-MATERIAL-001 | Supplier/process/temperature-dependent material allowables | Required for fatigue, thermal distortion, and machining release |
| OPEN-BEARING-001 | Bearing supplier, oil grade, clearance, and temperature map | Required for journal sizing and hydrodynamic validation |
| OPEN-COOLING-001 | Vehicle radiator, duct, fan, and airflow package | Required to prove 40 °C track heat rejection |
| OPEN-COMBUSTION-001 | Chamber/port/injector/spark model and pressure traces | Required for knock, emissions, burn rate, and actual cylinder loads |
| OPEN-DURABILITY-001 | Duty cycle and DV/PV test matrix | Required to substantiate the 200,000 km target |
