#!/usr/bin/env python3
"""Generate deterministic P2 mechanical loads and semantic architecture."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
from typing import Any


class MechanicalAnalysisError(ValueError):
    """Raised when mechanical requirements or dependencies are invalid."""


def require_positive(name: str, value: Any) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise MechanicalAnalysisError(f"{name} must be numeric")
    converted = float(value)
    if not math.isfinite(converted) or converted <= 0:
        raise MechanicalAnalysisError(f"{name} must be finite and positive")
    return converted


def require_integer(name: str, value: Any) -> int:
    converted = int(require_positive(name, value))
    if converted != value:
        raise MechanicalAnalysisError(f"{name} must be an integer")
    return converted


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def rounded(value: float, digits: int = 9) -> float:
    return round(value, digits)


def acceleration_at_tdc(crank_radius: float, rod_length: float, rpm: float) -> float:
    angular_speed = rpm * 2 * math.pi / 60
    return crank_radius * angular_speed**2 * (1 + crank_radius / rod_length)


def make_part(
    part_id: str,
    subsystem: str,
    material_intent: str,
    representation: str,
    dependencies: list[str],
) -> dict[str, Any]:
    return {
        "partID": part_id,
        "subsystem": subsystem,
        "materialIntent": material_intent,
        "cadRepresentation": representation,
        "calculationDependencies": dependencies,
    }


def semantic_architecture(requirements: dict[str, Any]) -> dict[str, Any]:
    mechanical = requirements["mechanical"]
    cylinders = require_integer("engine.cylinders", requirements["engine"]["cylinders"])
    cylinders_per_bank = cylinders // 2
    pitch = require_positive("mechanical.cylinderPitchMeters", mechanical["cylinderPitchMeters"])
    deck_height = require_positive(
        "mechanical.crankAxisToDeckMeters", mechanical["crankAxisToDeckMeters"]
    )
    bank_half_angle = math.radians(
        require_positive("mechanical.bankAngleDegrees", mechanical["bankAngleDegrees"]) / 2
    )
    sine = math.sin(bank_half_angle)
    cosine = math.cos(bank_half_angle)
    bank_vectors = {"L": [0.0, -sine, cosine], "R": [0.0, sine, cosine]}
    x_positions = [
        (index - (cylinders_per_bank - 1) / 2) * pitch
        for index in range(cylinders_per_bank)
    ]

    parts = [
        make_part("structure.block", "short-block", "closed-deck-aluminum", "p2-structural-envelope", ["GEO-BORE-001", "GEO-PITCH-001", "GEO-DECK-001"]),
        make_part("structure.bedplate", "short-block", "aluminum-bedplate", "p2-structural-envelope", ["GEO-MAIN-001", "LOAD-MAIN-INTERFACE"]),
        make_part("structure.lower-crankcase", "lubrication", "cast-aluminum", "p2-fluid-envelope", ["THERM-OIL-FLOW", "ARCH-DRY-SUMP"]),
        make_part("head.L", "heads", "aluminum-head", "p2-structural-envelope", ["LOAD-HEAD-CLAMP", "ARCH-VALVE"]),
        make_part("head.R", "heads", "aluminum-head", "p2-structural-envelope", ["LOAD-HEAD-CLAMP", "ARCH-VALVE"]),
        make_part("cover.cam.L", "heads", "cast-magnesium-or-aluminum", "p2-service-envelope", ["ARCH-CAM"]),
        make_part("cover.cam.R", "heads", "cast-magnesium-or-aluminum", "p2-service-envelope", ["ARCH-CAM"]),
        make_part("crankshaft", "cranktrain", "forged-steel", "p2-rotating-envelope", ["LOAD-ROD-COMPRESSION", "LOAD-ROD-TENSION", "GEO-MAIN-001", "GEO-CRANKPIN-001"]),
        make_part("flywheel-interface", "cranktrain", "forged-steel", "p2-interface-envelope", ["DATUM-FLYWHEEL"]),
        make_part("torsional-damper", "cranktrain", "steel-elastomer-system", "p2-interface-envelope", ["OPEN-TORSION"]),
    ]
    for index in range(require_integer("mechanical.mainBearingCount", mechanical["mainBearingCount"])):
        parts.append(make_part(f"bearing.main.{index + 1}", "cranktrain", "supplier-bearing-system", "p2-interface-envelope", ["GEO-MAIN-001", "OPEN-BEARING-001"]))
    for bank in ("L", "R"):
        for cam in ("intake", "exhaust"):
            parts.append(make_part(f"camshaft.{bank}.{cam}", "valvetrain", "forged-or-billet-steel", "p2-rotating-envelope", ["ARCH-CAM", "OPEN-VALVETRAIN-DYNAMICS"]))

    for bank in ("L", "R"):
        for index in range(cylinders_per_bank):
            cylinder = f"{bank}{index + 1}"
            prefix = f"cylinder.{cylinder}"
            parts.extend(
                [
                    make_part(f"{prefix}.liner", "short-block", "plasma-coated-aluminum-bore", "p2-bore-envelope", ["GEO-BORE-001", "LOAD-CYLINDER-PRESSURE"]),
                    make_part(f"{prefix}.piston", "cranktrain", "forged-aluminum", "p2-rotating-envelope", ["LOAD-GAS", "LOAD-INERTIA", "THERM-OIL-JET"]),
                    make_part(f"{prefix}.wrist-pin", "cranktrain", "hardened-steel", "p2-rotating-envelope", ["LOAD-WRIST-PIN"]),
                    make_part(f"{prefix}.connecting-rod", "cranktrain", "forged-steel", "p2-rotating-envelope", ["LOAD-ROD-COMPRESSION", "LOAD-ROD-TENSION", "LOAD-ROD-BUCKLING"]),
                    make_part(f"{prefix}.big-end-bearing", "cranktrain", "supplier-bearing-system", "p2-interface-envelope", ["LOAD-CRANKPIN-BEARING", "OPEN-BEARING-001"]),
                    make_part(f"{prefix}.spark-plug", "fuel-and-ignition", "supplier-component", "p2-service-envelope", ["OPEN-COMBUSTION-001"]),
                    make_part(f"{prefix}.di-injector", "fuel-and-ignition", "supplier-component", "p2-service-envelope", ["LOAD-INJECTION-MASS", "OPEN-COMBUSTION-001"]),
                    make_part(f"{prefix}.pfi-injector", "fuel-and-ignition", "supplier-component", "p2-service-envelope", ["LOAD-INJECTION-MASS", "OPEN-EMISSIONS-001"]),
                    make_part(f"{prefix}.ignition-coil", "fuel-and-ignition", "supplier-component", "p2-service-envelope", ["OPEN-COMBUSTION-001"]),
                    make_part(f"{prefix}.oil-jet", "lubrication", "steel-or-brass-nozzle", "p2-fluid-interface", ["THERM-OIL-FLOW", "THERM-OIL-JET"]),
                ]
            )
            for valve_index in range(2):
                parts.append(make_part(f"{prefix}.intake-valve.{valve_index + 1}", "valvetrain", "temperature-rated-valve-alloy", "p2-motion-envelope", ["ARCH-INTAKE-CURTAIN", "OPEN-VALVETRAIN-DYNAMICS"]))
                parts.append(make_part(f"{prefix}.exhaust-valve.{valve_index + 1}", "valvetrain", "high-temperature-valve-alloy", "p2-motion-envelope", ["ARCH-EXHAUST-CURTAIN", "OPEN-VALVETRAIN-DYNAMICS"]))

    shared_parts = [
        ("air.filter.L", "air-path", "supplier-component", "p2-service-envelope", ["THERM-AIR-FLOW"]),
        ("air.filter.R", "air-path", "supplier-component", "p2-service-envelope", ["THERM-AIR-FLOW"]),
        ("turbo.L.compressor", "air-path", "aluminum-compressor-housing", "p2-flow-envelope", ["THERM-COMPRESSOR-MAP"]),
        ("turbo.R.compressor", "air-path", "aluminum-compressor-housing", "p2-flow-envelope", ["THERM-COMPRESSOR-MAP"]),
        ("turbo.L.core", "air-path", "water-cooled-bearing-system", "p2-service-envelope", ["THERM-TURBO-POWER", "THERM-HT-FLOW"]),
        ("turbo.R.core", "air-path", "water-cooled-bearing-system", "p2-service-envelope", ["THERM-TURBO-POWER", "THERM-HT-FLOW"]),
        ("turbo.L.turbine", "exhaust", "1050C-rated-turbine-housing", "p2-thermal-envelope", ["THERM-TURBINE-INLET", "OPEN-GAS-EXCHANGE"]),
        ("turbo.R.turbine", "exhaust", "1050C-rated-turbine-housing", "p2-thermal-envelope", ["THERM-TURBINE-INLET", "OPEN-GAS-EXCHANGE"]),
        ("charge-cooler.L", "low-temperature-cooling", "aluminum-heat-exchanger", "p2-flow-envelope", ["THERM-LT-REJECTION"]),
        ("charge-cooler.R", "low-temperature-cooling", "aluminum-heat-exchanger", "p2-flow-envelope", ["THERM-LT-REJECTION"]),
        ("throttle.L", "air-path", "supplier-component", "p2-interface-envelope", ["THERM-AIR-FLOW"]),
        ("throttle.R", "air-path", "supplier-component", "p2-interface-envelope", ["THERM-AIR-FLOW"]),
        ("intake-plenum.L", "air-path", "cast-aluminum-or-composite", "p2-flow-envelope", ["THERM-MANIFOLD-PRESSURE", "OPEN-GAS-EXCHANGE"]),
        ("intake-plenum.R", "air-path", "cast-aluminum-or-composite", "p2-flow-envelope", ["THERM-MANIFOLD-PRESSURE", "OPEN-GAS-EXCHANGE"]),
        ("exhaust-manifold.L", "exhaust", "high-temperature-cast-alloy", "p2-thermal-envelope", ["THERM-TURBINE-INLET", "OPEN-GAS-EXCHANGE"]),
        ("exhaust-manifold.R", "exhaust", "high-temperature-cast-alloy", "p2-thermal-envelope", ["THERM-TURBINE-INLET", "OPEN-GAS-EXCHANGE"]),
        ("catalyst-interface.L", "exhaust", "supplier-aftertreatment", "p2-interface-envelope", ["OPEN-EMISSIONS-001"]),
        ("catalyst-interface.R", "exhaust", "supplier-aftertreatment", "p2-interface-envelope", ["OPEN-EMISSIONS-001"]),
        ("fuel.di-rail.L", "fuel-and-ignition", "high-pressure-steel", "p2-interface-envelope", ["LOAD-INJECTION-MASS"]),
        ("fuel.di-rail.R", "fuel-and-ignition", "high-pressure-steel", "p2-interface-envelope", ["LOAD-INJECTION-MASS"]),
        ("fuel.pfi-rail.L", "fuel-and-ignition", "aluminum-or-polymer", "p2-interface-envelope", ["LOAD-INJECTION-MASS"]),
        ("fuel.pfi-rail.R", "fuel-and-ignition", "aluminum-or-polymer", "p2-interface-envelope", ["LOAD-INJECTION-MASS"]),
        ("fuel.high-pressure-pump.L", "fuel-and-ignition", "supplier-component", "p2-service-envelope", ["LOAD-INJECTION-MASS"]),
        ("fuel.high-pressure-pump.R", "fuel-and-ignition", "supplier-component", "p2-service-envelope", ["LOAD-INJECTION-MASS"]),
        ("coolant.ht-jacket.L", "high-temperature-cooling", "water-glycol-volume", "p2-fluid-envelope", ["THERM-HT-REJECTION", "THERM-HT-FLOW"]),
        ("coolant.ht-jacket.R", "high-temperature-cooling", "water-glycol-volume", "p2-fluid-envelope", ["THERM-HT-REJECTION", "THERM-HT-FLOW"]),
        ("coolant.ht-pump", "high-temperature-cooling", "supplier-component", "p2-service-envelope", ["THERM-HT-FLOW"]),
        ("coolant.ht-thermostat", "high-temperature-cooling", "supplier-component", "p2-service-envelope", ["THERM-HT-TEMPERATURE"]),
        ("coolant.lt-pump", "low-temperature-cooling", "supplier-component", "p2-service-envelope", ["THERM-LT-REJECTION"]),
        ("coolant.lt-front-interface", "low-temperature-cooling", "vehicle-interface", "p2-interface-envelope", ["THERM-LT-REJECTION"]),
        ("coolant.ht-radiator-interface", "high-temperature-cooling", "vehicle-interface", "p2-interface-envelope", ["THERM-HT-REJECTION", "THERM-HT-UA"]),
        ("oil.dry-sump-pump", "lubrication", "six-stage-supplier-system", "p2-service-envelope", ["THERM-OIL-FLOW", "ARCH-DRY-SUMP"]),
        ("oil.tank", "lubrication", "aluminum-tank", "p2-service-envelope", ["ARCH-DRY-SUMP"]),
        ("oil.cooler-interface", "lubrication", "vehicle-interface", "p2-interface-envelope", ["THERM-OIL-REJECTION", "THERM-OIL-FLOW"]),
        ("oil.pressure-gallery", "lubrication", "oil-volume", "p2-fluid-envelope", ["THERM-OIL-FLOW", "OPEN-BEARING-001"]),
        ("oil.scavenge-gallery.L", "lubrication", "oil-aerated-volume", "p2-fluid-envelope", ["ARCH-DRY-SUMP"]),
        ("oil.scavenge-gallery.R", "lubrication", "oil-aerated-volume", "p2-fluid-envelope", ["ARCH-DRY-SUMP"]),
    ]
    parts.extend(make_part(*part) for part in shared_parts)

    datums: list[dict[str, Any]] = [
        {"datumID": "datum.crank-axis", "kind": "axis", "originMeters": [0, 0, 0], "direction": [1, 0, 0]},
        {"datumID": "datum.flywheel-face", "kind": "plane", "originMeters": [0.23, 0, 0], "normal": [1, 0, 0]},
        {"datumID": "datum.damper-face", "kind": "plane", "originMeters": [-0.23, 0, 0], "normal": [-1, 0, 0]},
    ]
    for bank in ("L", "R"):
        vector = bank_vectors[bank]
        datums.append({"datumID": f"datum.deck.{bank}", "kind": "plane", "originMeters": [0, vector[1] * deck_height, vector[2] * deck_height], "normal": vector})
        for index, x_position in enumerate(x_positions):
            datums.append({"datumID": f"datum.cylinder-axis.{bank}{index + 1}", "kind": "axis", "originMeters": [x_position, 0, 0], "direction": vector})
    datums.extend(
        [
            {"datumID": "datum.turbo-axis.L", "kind": "axis", "originMeters": [0, -0.36, 0.07], "direction": [1, 0, 0]},
            {"datumID": "datum.turbo-axis.R", "kind": "axis", "originMeters": [0, 0.36, 0.07], "direction": [1, 0, 0]},
            {"datumID": "datum.ht-coolant-out", "kind": "interface", "originMeters": [-0.18, 0, 0.32], "direction": [-1, 0, 0]},
            {"datumID": "datum.ht-coolant-in", "kind": "interface", "originMeters": [0.18, 0, -0.08], "direction": [1, 0, 0]},
            {"datumID": "datum.oil-pressure-out", "kind": "interface", "originMeters": [-0.18, -0.08, -0.14], "direction": [-1, 0, 0]},
            {"datumID": "datum.oil-scavenge-in", "kind": "interface", "originMeters": [0.18, 0.08, -0.14], "direction": [1, 0, 0]},
        ]
    )

    part_ids = [part["partID"] for part in parts]
    datum_ids = [datum["datumID"] for datum in datums]
    if len(part_ids) != len(set(part_ids)):
        raise MechanicalAnalysisError("semantic part IDs must be unique")
    if len(datum_ids) != len(set(datum_ids)):
        raise MechanicalAnalysisError("semantic datum IDs must be unique")
    return {
        "schemaVersion": "professional-v8.semantic-architecture.v1",
        "claimLevel": "P2-engineering-reference",
        "coordinateSystem": {
            "units": "meters",
            "x": "crank-axis-positive-toward-flywheel",
            "y": "vehicle-lateral-positive-right-bank",
            "z": "engine-up",
        },
        "parts": parts,
        "datums": datums,
        "fluidInterfaces": [
            {"interfaceID": "interface.ht-coolant", "designFlowLitersPerMinute": None, "source": "analysis-thermal.json"},
            {"interfaceID": "interface.lt-coolant", "designHeatKilowatts": None, "source": "analysis-thermal.json"},
            {"interfaceID": "interface.oil-cooler", "designFlowLitersPerMinute": None, "source": "analysis-thermal.json"},
        ],
    }


def analyze(requirements: dict[str, Any], thermal: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]], dict[str, Any]]:
    if requirements.get("schemaVersion") != "professional-v8.requirements.v1":
        raise MechanicalAnalysisError("unsupported requirements schema")
    if thermal.get("schemaVersion") != "professional-v8.thermal-analysis.v1":
        raise MechanicalAnalysisError("unsupported thermal analysis schema")

    engine = requirements["engine"]
    mechanical = requirements["mechanical"]
    cylinders = require_integer("engine.cylinders", engine["cylinders"])
    if cylinders != 8:
        raise MechanicalAnalysisError("professional V8 mechanical analysis requires eight cylinders")
    bore = require_positive("engine.boreMeters", engine["boreMeters"])
    stroke = require_positive("engine.strokeMeters", engine["strokeMeters"])
    redline = require_positive("engine.redlineRPM", engine["redlineRPM"])
    overspeed = require_positive("engine.overspeedRPM", engine["overspeedRPM"])
    if overspeed <= redline:
        raise MechanicalAnalysisError("overspeed must exceed redline")
    bank_angle = require_positive("mechanical.bankAngleDegrees", mechanical["bankAngleDegrees"])
    if abs(bank_angle - 90) > 1e-9:
        raise MechanicalAnalysisError("professional V8 architecture requires a 90-degree bank angle")
    pitch = require_positive("mechanical.cylinderPitchMeters", mechanical["cylinderPitchMeters"])
    rod_length = require_positive("mechanical.connectingRodLengthMeters", mechanical["connectingRodLengthMeters"])
    compression_height = require_positive("mechanical.pistonCompressionHeightMeters", mechanical["pistonCompressionHeightMeters"])
    deck_height = require_positive("mechanical.crankAxisToDeckMeters", mechanical["crankAxisToDeckMeters"])
    crank_radius = stroke / 2
    deck_closure = crank_radius + rod_length + compression_height
    deck_residual = deck_height - deck_closure
    if abs(deck_residual) > 1e-9:
        raise MechanicalAnalysisError("crank, rod, compression height, and deck height do not close")
    bore_bridge = pitch - bore
    if bore_bridge <= 0:
        raise MechanicalAnalysisError("cylinder pitch must exceed bore")

    reciprocating_mass = require_positive("mechanical.reciprocatingMassPerCylinderKilograms", mechanical["reciprocatingMassPerCylinderKilograms"])
    nominal_pressure = require_positive("mechanical.nominalPeakCylinderPressurePascals", mechanical["nominalPeakCylinderPressurePascals"])
    design_pressure = require_positive("mechanical.designCylinderPressurePascals", mechanical["designCylinderPressurePascals"])
    if design_pressure <= nominal_pressure:
        raise MechanicalAnalysisError("design pressure must exceed nominal peak pressure")
    piston_area = math.pi * bore**2 / 4
    nominal_gas_force = nominal_pressure * piston_area
    design_gas_force = design_pressure * piston_area
    redline_acceleration = acceleration_at_tdc(crank_radius, rod_length, redline)
    overspeed_acceleration = acceleration_at_tdc(crank_radius, rod_length, overspeed)
    redline_inertia_force = reciprocating_mass * redline_acceleration
    overspeed_inertia_force = reciprocating_mass * overspeed_acceleration
    gross_compression_envelope = design_gas_force + redline_inertia_force
    tensile_dynamic_factor = require_positive("mechanical.overspeedTensileDynamicFactor", mechanical["overspeedTensileDynamicFactor"])
    overspeed_tensile_envelope = overspeed_inertia_force * tensile_dynamic_factor

    rod_second_moment = require_positive("mechanical.connectingRodWeakAxisSecondMomentMeters4", mechanical["connectingRodWeakAxisSecondMomentMeters4"])
    rod_modulus = require_positive("mechanical.connectingRodYoungsModulusPascals", mechanical["connectingRodYoungsModulusPascals"])
    rod_effective_length = require_positive("mechanical.connectingRodEffectiveBucklingLengthMeters", mechanical["connectingRodEffectiveBucklingLengthMeters"])
    euler_load = math.pi**2 * rod_modulus * rod_second_moment / rod_effective_length**2
    buckling_ratio = euler_load / gross_compression_envelope
    minimum_buckling_ratio = require_positive("mechanical.minimumEulerBucklingRatio", mechanical["minimumEulerBucklingRatio"])
    if buckling_ratio < minimum_buckling_ratio:
        raise MechanicalAnalysisError("connecting rod Euler screening ratio is below its minimum")

    wrist_pin_diameter = require_positive("mechanical.wristPinDiameterMeters", mechanical["wristPinDiameterMeters"])
    wrist_pin_width = require_positive("mechanical.wristPinTotalBearingWidthMeters", mechanical["wristPinTotalBearingWidthMeters"])
    wrist_pin_projected_pressure = gross_compression_envelope / (wrist_pin_diameter * wrist_pin_width)
    crankpin_diameter = require_positive("mechanical.crankpinDiameterMeters", mechanical["crankpinDiameterMeters"])
    rod_big_end_width = require_positive("mechanical.connectingRodBigEndWidthMeters", mechanical["connectingRodBigEndWidthMeters"])
    crankpin_projected_pressure = gross_compression_envelope / (crankpin_diameter * rod_big_end_width)
    crankpin_journal_width = require_positive("mechanical.crankpinJournalWidthMeters", mechanical["crankpinJournalWidthMeters"])
    if crankpin_journal_width <= 2 * rod_big_end_width:
        raise MechanicalAnalysisError("crankpin journal width must leave side clearance for two rods")
    main_diameter = require_positive("mechanical.mainJournalDiameterMeters", mechanical["mainJournalDiameterMeters"])
    require_positive("mechanical.mainJournalWidthMeters", mechanical["mainJournalWidthMeters"])

    mean_piston_speed = 2 * stroke * redline / 60
    overspeed_mean_piston_speed = 2 * stroke * overspeed / 60
    maximum_mean_piston_speed = require_positive(
        "mechanical.maximumMeanPistonSpeedAtRedlineMetersPerSecond",
        mechanical["maximumMeanPistonSpeedAtRedlineMetersPerSecond"],
    )
    if mean_piston_speed > maximum_mean_piston_speed:
        raise MechanicalAnalysisError("mean piston speed exceeds the redline screening limit")
    crankpin_surface_speed = math.pi * crankpin_diameter * redline / 60
    main_surface_speed = math.pi * main_diameter * redline / 60

    head_fasteners_per_bank = require_integer("mechanical.headFastenersPerBank", mechanical["headFastenersPerBank"])
    fastener_preload = require_positive("mechanical.headFastenerPreloadNewtons", mechanical["headFastenerPreloadNewtons"])
    bank_clamp = head_fasteners_per_bank * fastener_preload
    clamp_to_one_cylinder_gas_ratio = bank_clamp / design_gas_force

    intake_count = require_integer("mechanical.intakeValvesPerCylinder", mechanical["intakeValvesPerCylinder"])
    exhaust_count = require_integer("mechanical.exhaustValvesPerCylinder", mechanical["exhaustValvesPerCylinder"])
    if intake_count != 2 or exhaust_count != 2:
        raise MechanicalAnalysisError("DOHC four-valve architecture requires two intake and two exhaust valves")
    intake_diameter = require_positive("mechanical.intakeValveHeadDiameterMeters", mechanical["intakeValveHeadDiameterMeters"])
    exhaust_diameter = require_positive("mechanical.exhaustValveHeadDiameterMeters", mechanical["exhaustValveHeadDiameterMeters"])
    intake_lift = require_positive("mechanical.intakeValveLiftMeters", mechanical["intakeValveLiftMeters"])
    exhaust_lift = require_positive("mechanical.exhaustValveLiftMeters", mechanical["exhaustValveLiftMeters"])
    intake_curtain_area = intake_count * math.pi * intake_diameter * intake_lift
    exhaust_curtain_area = exhaust_count * math.pi * exhaust_diameter * exhaust_lift

    full_power_fuel_kg_hour = require_positive("thermal.fullPowerFuelMass", thermal["fullPowerAirAndFuel"]["fuelMassKilogramsPerHour"])
    target_power_rpm = require_positive("performance.targetPowerRPM", requirements["performance"]["targetPowerRPM"])
    cycles_per_second_per_cylinder = target_power_rpm / 120
    fuel_mass_per_cycle = full_power_fuel_kg_hour / 3600 / cylinders / cycles_per_second_per_cylinder
    injection_margin = require_positive("mechanical.fuelInjectionCapacityMargin", mechanical["fuelInjectionCapacityMargin"])
    injection_capacity = fuel_mass_per_cycle * injection_margin
    dry_sump_stages = require_integer("mechanical.drySumpStages", mechanical["drySumpStages"])
    oil_jets = require_integer("mechanical.pistonOilJets", mechanical["pistonOilJets"])
    if oil_jets != cylinders:
        raise MechanicalAnalysisError("one piston oil jet is required per cylinder")
    if dry_sump_stages < 2:
        raise MechanicalAnalysisError("dry sump stage count is invalid")

    main_bearing_count = require_integer("mechanical.mainBearingCount", mechanical["mainBearingCount"])
    crankpin_count = require_integer("mechanical.crankpinCount", mechanical["crankpinCount"])
    counterweight_count = require_integer("mechanical.counterweightCount", mechanical["counterweightCount"])
    if (main_bearing_count, crankpin_count, counterweight_count, dry_sump_stages) != (5, 4, 8, 6):
        raise MechanicalAnalysisError("cross-plane V8 cranktrain and dry-sump inventory is inconsistent")
    crankpin_angles = mechanical["crankpinAnglesDegrees"]
    if not isinstance(crankpin_angles, list) or len(crankpin_angles) != crankpin_count:
        raise MechanicalAnalysisError("crankpin angle inventory is inconsistent")
    normalized_angles = []
    for index, angle in enumerate(crankpin_angles):
        converted = require_positive(f"mechanical.crankpinAnglesDegrees[{index}]", angle) if angle != 0 else 0.0
        normalized_angles.append(converted % 360)
    if len(set(normalized_angles)) != crankpin_count:
        raise MechanicalAnalysisError("crankpin angles must be unique")
    firing_order = mechanical["firingOrder"]
    expected_cylinders = {f"{bank}{index}" for bank in ("L", "R") for index in range(1, 5)}
    if not isinstance(firing_order, list) or len(firing_order) != cylinders or set(firing_order) != expected_cylinders:
        raise MechanicalAnalysisError("firing order must contain every cylinder exactly once")

    architecture = semantic_architecture(requirements)
    circuits = thermal["installedCircuitRequirements"]
    for interface in architecture["fluidInterfaces"]:
        if interface["interfaceID"] == "interface.ht-coolant":
            interface["designFlowLitersPerMinute"] = circuits["highTemperatureCircuit"]["minimumCoolantVolumeFlowLitersPerMinute"]
        elif interface["interfaceID"] == "interface.lt-coolant":
            interface["designHeatKilowatts"] = circuits["lowTemperatureCircuit"]["installedRejectionKilowatts"]
        elif interface["interfaceID"] == "interface.oil-cooler":
            interface["designFlowLitersPerMinute"] = circuits["oilCircuit"]["minimumOilVolumeFlowLitersPerMinute"]

    load_cases = [
        {"loadCaseID": "nominal-cylinder-pressure", "quantity": "piston-gas-force", "value": rounded(nominal_gas_force), "unit": "N", "claim": "nominal-screen"},
        {"loadCaseID": "design-cylinder-pressure", "quantity": "piston-gas-force", "value": rounded(design_gas_force), "unit": "N", "claim": "design-screen"},
        {"loadCaseID": "redline-tdc-inertia", "quantity": "reciprocating-inertia-force", "value": rounded(redline_inertia_force), "unit": "N", "claim": "kinematic-screen"},
        {"loadCaseID": "gross-rod-compression", "quantity": "unsigned-gas-plus-redline-inertia-envelope", "value": rounded(gross_compression_envelope), "unit": "N", "claim": "conservative-screen-not-pressure-trace"},
        {"loadCaseID": "overspeed-rod-tension", "quantity": "factored-tdc-overlap-inertia", "value": rounded(overspeed_tensile_envelope), "unit": "N", "claim": "kinematic-screen"},
        {"loadCaseID": "rod-euler", "quantity": "weak-axis-euler-load", "value": rounded(euler_load), "unit": "N", "claim": "ideal-column-screen-only"},
        {"loadCaseID": "wrist-pin-projected", "quantity": "gross-projected-bearing-pressure", "value": rounded(wrist_pin_projected_pressure / 1e6), "unit": "MPa", "claim": "geometry-screen-not-oil-film"},
        {"loadCaseID": "crankpin-projected", "quantity": "gross-projected-bearing-pressure-per-rod", "value": rounded(crankpin_projected_pressure / 1e6), "unit": "MPa", "claim": "geometry-screen-not-oil-film"},
        {"loadCaseID": "head-bank-preload", "quantity": "aggregate-fastener-preload", "value": rounded(bank_clamp), "unit": "N", "claim": "inventory-not-sealing-proof"},
    ]
    report = {
        "schemaVersion": "professional-v8.mechanical-analysis.v1",
        "claimLevel": "P2-engineering-reference",
        "status": "p2-mechanical-screening-passed-release-analysis-open",
        "geometry": {
            "rodToStrokeRatio": rounded(rod_length / stroke, 6),
            "crankRadiusMillimeters": rounded(crank_radius * 1000, 6),
            "deckClosureMillimeters": rounded(deck_closure * 1000, 6),
            "deckClosureResidualMicrometers": rounded(deck_residual * 1e6, 6),
            "boreBridgeMillimeters": rounded(bore_bridge * 1000, 6),
            "bankAngleDegrees": bank_angle,
            "bankBoreEnvelopeLengthMillimeters": rounded(((cylinders // 2 - 1) * pitch + bore) * 1000, 6),
        },
        "kinematics": {
            "meanPistonSpeedAtRedlineMetersPerSecond": rounded(mean_piston_speed, 6),
            "meanPistonSpeedAtOverspeedMetersPerSecond": rounded(overspeed_mean_piston_speed, 6),
            "peakTDCAccelerationAtRedlineMetersPerSecondSquared": rounded(redline_acceleration, 6),
            "peakTDCAccelerationAtRedlineG": rounded(redline_acceleration / 9.80665, 6),
            "peakTDCAccelerationAtOverspeedMetersPerSecondSquared": rounded(overspeed_acceleration, 6),
            "crankpinSurfaceSpeedAtRedlineMetersPerSecond": rounded(crankpin_surface_speed, 6),
            "mainJournalSurfaceSpeedAtRedlineMetersPerSecond": rounded(main_surface_speed, 6),
        },
        "loadScreens": {
            "nominalGasForceKilonewtons": rounded(nominal_gas_force / 1000, 6),
            "designGasForceKilonewtons": rounded(design_gas_force / 1000, 6),
            "redlineInertiaForceKilonewtons": rounded(redline_inertia_force / 1000, 6),
            "grossRodCompressionEnvelopeKilonewtons": rounded(gross_compression_envelope / 1000, 6),
            "overspeedRodTensionEnvelopeKilonewtons": rounded(overspeed_tensile_envelope / 1000, 6),
            "rodEulerLoadKilonewtons": rounded(euler_load / 1000, 6),
            "rodEulerToGrossCompressionRatio": rounded(buckling_ratio, 6),
            "minimumRodEulerRatio": minimum_buckling_ratio,
            "wristPinProjectedPressureMegapascals": rounded(wrist_pin_projected_pressure / 1e6, 6),
            "crankpinProjectedPressureMegapascals": rounded(crankpin_projected_pressure / 1e6, 6),
            "bankHeadClampKilonewtons": rounded(bank_clamp / 1000, 6),
            "bankClampToOneCylinderDesignGasRatio": rounded(clamp_to_one_cylinder_gas_ratio, 6),
        },
        "valvetrainAndFuel": {
            "totalValveCount": cylinders * (intake_count + exhaust_count),
            "intakeCurtainAreaPerCylinderSquareMillimeters": rounded(intake_curtain_area * 1e6, 6),
            "exhaustCurtainAreaPerCylinderSquareMillimeters": rounded(exhaust_curtain_area * 1e6, 6),
            "fullPowerFuelMassPerCylinderCycleMilligrams": rounded(fuel_mass_per_cycle * 1e6, 6),
            "minimumCombinedInjectionCapacityMilligramsPerCycle": rounded(injection_capacity * 1e6, 6),
        },
        "architectureInventory": {
            "semanticPartCount": len(architecture["parts"]),
            "datumCount": len(architecture["datums"]),
            "mainBearings": main_bearing_count,
            "crankpins": crankpin_count,
            "counterweights": counterweight_count,
            "drySumpStages": dry_sump_stages,
            "pistonOilJets": oil_jets,
            "firingOrder": firing_order,
            "crankpinAnglesDegrees": crankpin_angles,
        },
        "thermalInterfaces": circuits,
        "openReleaseGates": [
            "combustion pressure traces and abnormal combustion cases",
            "temperature-dependent material allowables and forging/casting processes",
            "rod, piston, pin, crankshaft, block, head, and fastener nonlinear FEA",
            "crankshaft torsional and bending dynamics with damper optimization",
            "hydrodynamic main, rod, pin, and cam bearing analysis",
            "valvetrain dynamics, spring surge, contact stress, and piston-to-valve clearance",
            "head-gasket sealing, bore distortion, thermal growth, and joint relaxation",
            "lubrication rig, aeration, windage, scavenge, and starvation validation",
            "physical fatigue, overspeed, thermal-cycle, and durability testing",
        ],
    }
    return report, load_cases, architecture


def render_csv(rows: list[dict[str, Any]]) -> bytes:
    fields = ["loadCaseID", "quantity", "value", "unit", "claim"]
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def generated_outputs(requirements_bytes: bytes, thermal_bytes: bytes, source_bytes: bytes) -> dict[str, bytes]:
    requirements = json.loads(requirements_bytes)
    thermal = json.loads(thermal_bytes)
    expected_requirements_hash = sha256_bytes(requirements_bytes)
    actual_requirements_hash = thermal.get("provenance", {}).get("requirementsSHA256")
    if actual_requirements_hash != expected_requirements_hash:
        raise MechanicalAnalysisError("thermal analysis does not match requirements")
    report, load_cases, architecture = analyze(requirements, thermal)
    provenance = {
        "requirementsSHA256": expected_requirements_hash,
        "thermalAnalysisSHA256": sha256_bytes(thermal_bytes),
        "calculationSourceSHA256": sha256_bytes(source_bytes),
    }
    report["provenance"] = provenance
    architecture["provenance"] = provenance
    return {
        "analysis-mechanical.json": (json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8"),
        "mechanical-load-cases.csv": render_csv(load_cases),
        "semantic-architecture.json": (json.dumps(architecture, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8"),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", type=Path, default=Path(__file__).with_name("requirements.json"))
    parser.add_argument("--thermal-analysis", type=Path, default=Path(__file__).with_name("analysis-thermal.json"))
    parser.add_argument("--output-directory", type=Path, default=Path(__file__).parent)
    arguments = parser.parse_args()
    requirements_bytes = arguments.requirements.read_bytes()
    thermal_bytes = arguments.thermal_analysis.read_bytes()
    outputs = generated_outputs(requirements_bytes, thermal_bytes, Path(__file__).read_bytes())
    arguments.output_directory.mkdir(parents=True, exist_ok=True)
    for filename, content in outputs.items():
        (arguments.output_directory / filename).write_bytes(content)


if __name__ == "__main__":
    main()
