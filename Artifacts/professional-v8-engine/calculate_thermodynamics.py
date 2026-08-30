#!/usr/bin/env python3
"""Generate deterministic P2 power, air-path, and thermal evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
from pathlib import Path
from typing import Any


class AnalysisError(ValueError):
    """Raised when a requirement or derived invariant is invalid."""


def require_finite_positive(name: str, value: Any) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise AnalysisError(f"{name} must be numeric")
    converted = float(value)
    if not math.isfinite(converted) or converted <= 0:
        raise AnalysisError(f"{name} must be finite and positive")
    return converted


def require_fraction(name: str, value: Any) -> float:
    converted = require_finite_positive(name, value)
    if converted >= 1:
        raise AnalysisError(f"{name} must be less than one")
    return converted


def require_margin(name: str, value: Any) -> float:
    converted = require_finite_positive(name, value)
    if converted < 1:
        raise AnalysisError(f"{name} must be at least one")
    return converted


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def round_value(value: float, digits: int = 9) -> float:
    return round(value, digits)


def analyze(requirements: dict[str, Any]) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    if requirements.get("schemaVersion") != "professional-v8.requirements.v1":
        raise AnalysisError("unsupported requirements schema")

    engine = requirements["engine"]
    performance = requirements["performance"]
    combustion = requirements["combustion"]
    air = requirements["airSystem"]
    thermal = requirements["thermal"]
    tolerances = requirements["tolerances"]

    cylinders = int(require_finite_positive("engine.cylinders", engine["cylinders"]))
    if cylinders != engine["cylinders"] or cylinders % 2 != 0:
        raise AnalysisError("engine.cylinders must be an even integer")
    bore = require_finite_positive("engine.boreMeters", engine["boreMeters"])
    stroke = require_finite_positive("engine.strokeMeters", engine["strokeMeters"])
    require_finite_positive("engine.compressionRatio", engine["compressionRatio"])
    redline_rpm = require_finite_positive("engine.redlineRPM", engine["redlineRPM"])
    overspeed_rpm = require_finite_positive("engine.overspeedRPM", engine["overspeedRPM"])
    if overspeed_rpm <= redline_rpm:
        raise AnalysisError("engine.overspeedRPM must exceed engine.redlineRPM")
    require_finite_positive(
        "application.roadLifeTargetKilometers",
        requirements["application"]["roadLifeTargetKilometers"],
    )
    displacement = cylinders * math.pi * bore * bore * stroke / 4
    target_power = require_finite_positive(
        "performance.targetPowerWatts", performance["targetPowerWatts"]
    )
    target_power_rpm = require_finite_positive(
        "performance.targetPowerRPM", performance["targetPowerRPM"]
    )
    if target_power_rpm > redline_rpm:
        raise AnalysisError("performance.targetPowerRPM must not exceed engine.redlineRPM")
    target_peak_torque = require_finite_positive(
        "performance.targetPeakTorqueNewtonMeters",
        performance["targetPeakTorqueNewtonMeters"],
    )
    maximum_bmep_bar = require_finite_positive(
        "performance.maximumBMEPBar", performance["maximumBMEPBar"]
    )
    fuel_lhv = require_finite_positive(
        "combustion.fuelLowerHeatingValueJoulesPerKilogram",
        combustion["fuelLowerHeatingValueJoulesPerKilogram"],
    )
    afr = require_finite_positive(
        "combustion.fullLoadAirFuelMassRatio", combustion["fullLoadAirFuelMassRatio"]
    )

    gas_constant = require_finite_positive(
        "airSystem.gasConstantJoulesPerKilogramKelvin",
        air["gasConstantJoulesPerKilogramKelvin"],
    )
    gamma = require_finite_positive("airSystem.specificHeatRatio", air["specificHeatRatio"])
    if gamma <= 1:
        raise AnalysisError("airSystem.specificHeatRatio must be greater than one")
    cp_air = require_finite_positive(
        "airSystem.airSpecificHeatJoulesPerKilogramKelvin",
        air["airSpecificHeatJoulesPerKilogramKelvin"],
    )
    cp_exhaust = require_finite_positive(
        "airSystem.exhaustSpecificHeatJoulesPerKilogramKelvin",
        air["exhaustSpecificHeatJoulesPerKilogramKelvin"],
    )
    volumetric_efficiency = require_fraction(
        "airSystem.volumetricEfficiency", air["volumetricEfficiency"]
    )
    ambient_temperature = require_finite_positive(
        "application.hotAmbientKelvin", requirements["application"]["hotAmbientKelvin"]
    )
    ambient_pressure = require_finite_positive(
        "airSystem.ambientPressurePascals", air["ambientPressurePascals"]
    )
    intake_loss = require_finite_positive(
        "airSystem.intakePressureLossPascals", air["intakePressureLossPascals"]
    )
    charge_loss = require_finite_positive(
        "airSystem.chargePathPressureLossPascals",
        air["chargePathPressureLossPascals"],
    )
    compressor_inlet_pressure = ambient_pressure - intake_loss
    if compressor_inlet_pressure <= 0:
        raise AnalysisError("intake pressure loss must be lower than ambient pressure")
    charge_target_temperature = require_finite_positive(
        "airSystem.chargeManifoldTargetKelvin", air["chargeManifoldTargetKelvin"]
    )
    if charge_target_temperature <= ambient_temperature:
        raise AnalysisError("charge manifold target must exceed hot ambient for this P2 model")
    compressor_efficiency = require_fraction(
        "airSystem.compressorIsentropicEfficiency",
        air["compressorIsentropicEfficiency"],
    )
    turbo_mechanical_efficiency = require_fraction(
        "airSystem.turboMechanicalEfficiency", air["turboMechanicalEfficiency"]
    )
    compressor_count = int(require_finite_positive("airSystem.compressors", air["compressors"]))
    if compressor_count != air["compressors"]:
        raise AnalysisError("airSystem.compressors must be an integer")
    reference_temperature = require_finite_positive(
        "airSystem.referenceTemperatureKelvin", air["referenceTemperatureKelvin"]
    )
    reference_pressure = require_finite_positive(
        "airSystem.referencePressurePascals", air["referencePressurePascals"]
    )

    fractions = thermal["energyFractions"]
    required_fraction_names = (
        "brake",
        "exhaustBeforeTurbine",
        "highTemperatureCoolant",
        "oil",
        "chargeCooling",
        "ambientAndUnmodeled",
    )
    fraction_values = {
        name: require_fraction(f"thermal.energyFractions.{name}", fractions[name])
        for name in required_fraction_names
    }
    fraction_sum = sum(fraction_values.values())
    closure_tolerance = require_finite_positive(
        "tolerances.energyClosureRelative", tolerances["energyClosureRelative"]
    )
    if abs(fraction_sum - 1) > closure_tolerance:
        raise AnalysisError("thermal energy fractions must sum to one")

    curve = performance["curve"]
    if not isinstance(curve, list) or len(curve) < 2:
        raise AnalysisError("performance.curve must contain at least two points")
    previous_rpm = 0.0
    points: list[dict[str, Any]] = []
    for index, source_point in enumerate(curve):
        rpm = require_finite_positive(f"performance.curve[{index}].rpm", source_point["rpm"])
        if rpm <= previous_rpm:
            raise AnalysisError("performance.curve RPM values must be strictly increasing")
        previous_rpm = rpm
        torque = require_finite_positive(
            f"performance.curve[{index}].torqueNewtonMeters",
            source_point["torqueNewtonMeters"],
        )
        bte = require_fraction(
            f"performance.curve[{index}].brakeThermalEfficiency",
            source_point["brakeThermalEfficiency"],
        )
        power = 2 * math.pi * rpm * torque / 60
        bmep_bar = (4 * math.pi * torque / displacement) / 100000
        fuel_energy_rate = power / bte
        fuel_mass_flow = fuel_energy_rate / fuel_lhv
        air_mass_flow = fuel_mass_flow * afr
        engine_volume_flow = displacement * rpm * volumetric_efficiency / 120
        manifold_pressure = (
            air_mass_flow * gas_constant * charge_target_temperature / engine_volume_flow
        )
        required_compressor_outlet_pressure = manifold_pressure + charge_loss
        compressor_outlet_pressure = max(
            compressor_inlet_pressure, required_compressor_outlet_pressure
        )
        pressure_ratio = compressor_outlet_pressure / compressor_inlet_pressure
        compressor_active = pressure_ratio > 1.000001
        isentropic_outlet_temperature = ambient_temperature * pressure_ratio ** (
            (gamma - 1) / gamma
        )
        compressor_outlet_temperature = ambient_temperature + (
            isentropic_outlet_temperature - ambient_temperature
        ) / compressor_efficiency
        charge_cooler_heat = max(
            0,
            air_mass_flow
            * cp_air
            * (compressor_outlet_temperature - charge_target_temperature),
        )
        compressor_shaft_power = max(
            0,
            air_mass_flow
            * cp_air
            * (compressor_outlet_temperature - ambient_temperature),
        )
        turbine_extracted_power = compressor_shaft_power / turbo_mechanical_efficiency
        per_compressor_mass_flow = air_mass_flow / compressor_count
        corrected_mass_flow = per_compressor_mass_flow * math.sqrt(
            ambient_temperature / reference_temperature
        ) / (compressor_inlet_pressure / reference_pressure)
        bsfc = fuel_mass_flow * 3.6e9 / power
        points.append(
            {
                "rpm": int(rpm),
                "torqueNewtonMeters": round_value(torque, 6),
                "powerKilowatts": round_value(power / 1000, 6),
                "bmepBar": round_value(bmep_bar, 6),
                "brakeThermalEfficiency": bte,
                "bsfcGramsPerKilowattHour": round_value(bsfc, 6),
                "fuelMassFlowKilogramsPerSecond": round_value(fuel_mass_flow, 9),
                "airMassFlowKilogramsPerSecond": round_value(air_mass_flow, 9),
                "manifoldAbsolutePressureKilopascals": round_value(
                    manifold_pressure / 1000, 6
                ),
                "compressorPressureRatio": round_value(pressure_ratio, 6),
                "compressorActive": compressor_active,
                "compressorOutletKelvin": round_value(compressor_outlet_temperature, 6),
                "chargeCoolerHeatKilowatts": round_value(charge_cooler_heat / 1000, 6),
                "compressorShaftPowerKilowatts": round_value(
                    compressor_shaft_power / 1000, 6
                ),
                "turbineExtractedPowerKilowatts": round_value(
                    turbine_extracted_power / 1000, 6
                ),
                "perCompressorMassFlowKilogramsPerSecond": round_value(
                    per_compressor_mass_flow, 9
                ),
                "perCompressorCorrectedMassFlowPoundsPerMinute": round_value(
                    corrected_mass_flow * 132.2773573, 6
                ),
                "compressorMapAssessment": "requires-digitized-vendor-map",
            }
        )

    target_points = [point for point in points if point["rpm"] == int(target_power_rpm)]
    if len(target_points) != 1:
        raise AnalysisError("performance curve must contain the target power RPM exactly once")
    if points[-1]["rpm"] != int(redline_rpm):
        raise AnalysisError("performance curve must end at the configured redline")
    full_power_point = target_points[0]
    calculated_target_power = full_power_point["powerKilowatts"] * 1000
    power_tolerance = require_finite_positive(
        "tolerances.targetPowerWatts", tolerances["targetPowerWatts"]
    )
    if abs(calculated_target_power - target_power) > power_tolerance:
        raise AnalysisError("target power point does not match target power")
    peak_bmep = max(point["bmepBar"] for point in points)
    peak_torque = max(point["torqueNewtonMeters"] for point in points)
    if abs(peak_torque - target_peak_torque) > 1e-6:
        raise AnalysisError("performance curve does not match target peak torque")
    if peak_bmep > maximum_bmep_bar:
        raise AnalysisError("peak BMEP exceeds the configured limit")

    full_bte = full_power_point["brakeThermalEfficiency"]
    if abs(full_bte - fraction_values["brake"]) > closure_tolerance:
        raise AnalysisError("full-power efficiency must equal the brake energy fraction")
    full_fuel_energy_rate = target_power / full_bte
    full_fuel_mass_flow = full_fuel_energy_rate / fuel_lhv
    full_air_mass_flow = full_fuel_mass_flow * afr
    full_exhaust_mass_flow = full_air_mass_flow + full_fuel_mass_flow
    heat_watts = {
        name: full_fuel_energy_rate * fraction_values[name]
        for name in required_fraction_names
    }
    allocated_sum = sum(heat_watts.values())
    closure_error = allocated_sum - full_fuel_energy_rate
    if abs(closure_error) / full_fuel_energy_rate > closure_tolerance:
        raise AnalysisError("derived thermal energy balance does not close")

    charge_cooler_actual = full_power_point["chargeCoolerHeatKilowatts"] * 1000
    charge_reserve = heat_watts["chargeCooling"] - charge_cooler_actual
    minimum_charge_reserve = float(tolerances["chargeCoolingReserveWatts"])
    if not math.isfinite(minimum_charge_reserve):
        raise AnalysisError("charge cooling reserve tolerance must be finite")
    if charge_reserve < minimum_charge_reserve:
        raise AnalysisError("charge cooler heat exceeds the allocated thermal budget")

    estimated_turbine_inlet_temperature = ambient_temperature + heat_watts[
        "exhaustBeforeTurbine"
    ] / (full_exhaust_mass_flow * cp_exhaust)
    turbine_extracted_power = full_power_point["turbineExtractedPowerKilowatts"] * 1000
    exhaust_after_turbine = heat_watts["exhaustBeforeTurbine"] - turbine_extracted_power
    if exhaust_after_turbine <= 0:
        raise AnalysisError("compressor power exceeds the exhaust enthalpy budget")
    estimated_turbine_outlet_temperature = ambient_temperature + exhaust_after_turbine / (
        full_exhaust_mass_flow * cp_exhaust
    )
    continuous_turbine_limit = require_finite_positive(
        "airSystem.continuousTurbineInletLimitKelvin",
        air["continuousTurbineInletLimitKelvin"],
    )
    transient_turbine_limit = require_finite_positive(
        "airSystem.transientTurbineInletLimitKelvin",
        air["transientTurbineInletLimitKelvin"],
    )
    turbine_tolerance = float(tolerances["continuousTurbineTemperatureKelvin"])
    if not math.isfinite(turbine_tolerance) or turbine_tolerance < 0:
        raise AnalysisError("continuous turbine temperature tolerance must be finite and nonnegative")
    if estimated_turbine_inlet_temperature > continuous_turbine_limit + turbine_tolerance:
        raise AnalysisError("estimated continuous turbine inlet temperature exceeds its limit")
    if estimated_turbine_inlet_temperature > transient_turbine_limit:
        raise AnalysisError("estimated turbine inlet temperature exceeds its transient limit")
    if continuous_turbine_limit >= transient_turbine_limit:
        raise AnalysisError("continuous turbine limit must be lower than transient limit")

    ht = thermal["highTemperatureCircuit"]
    ht_cp = require_finite_positive(
        "thermal.highTemperatureCircuit.coolantSpecificHeatJoulesPerKilogramKelvin",
        ht["coolantSpecificHeatJoulesPerKilogramKelvin"],
    )
    ht_density = require_finite_positive(
        "thermal.highTemperatureCircuit.coolantDensityKilogramsPerCubicMeter",
        ht["coolantDensityKilogramsPerCubicMeter"],
    )
    ht_rise = require_finite_positive(
        "thermal.highTemperatureCircuit.engineTemperatureRiseKelvin",
        ht["engineTemperatureRiseKelvin"],
    )
    ht_capacity_margin = require_margin(
        "thermal.highTemperatureCircuit.installedCapacityMargin",
        ht["installedCapacityMargin"],
    )
    ht_flow_margin = require_margin(
        "thermal.highTemperatureCircuit.flowMargin", ht["flowMargin"]
    )
    ht_inlet = require_finite_positive(
        "thermal.highTemperatureCircuit.engineInletKelvin", ht["engineInletKelvin"]
    )
    ht_outlet = require_finite_positive(
        "thermal.highTemperatureCircuit.engineOutletKelvin", ht["engineOutletKelvin"]
    )
    if abs((ht_outlet - ht_inlet) - ht_rise) > 1e-9:
        raise AnalysisError("HT circuit temperatures do not match configured temperature rise")
    mean_coolant_temperature = (ht_inlet + ht_outlet) / 2
    radiator_approach = mean_coolant_temperature - ambient_temperature
    if radiator_approach <= 0:
        raise AnalysisError("HT radiator mean coolant temperature must exceed ambient")
    ht_design_heat = heat_watts["highTemperatureCoolant"] * ht_capacity_margin
    ht_mass_flow = heat_watts["highTemperatureCoolant"] * ht_flow_margin / (ht_cp * ht_rise)
    ht_volume_flow_lpm = ht_mass_flow / ht_density * 60000
    radiator_ua = ht_design_heat / radiator_approach

    oil = thermal["oilCircuit"]
    oil_cp = require_finite_positive(
        "thermal.oilCircuit.oilSpecificHeatJoulesPerKilogramKelvin",
        oil["oilSpecificHeatJoulesPerKilogramKelvin"],
    )
    oil_density = require_finite_positive(
        "thermal.oilCircuit.oilDensityKilogramsPerCubicMeter",
        oil["oilDensityKilogramsPerCubicMeter"],
    )
    oil_drop = require_finite_positive(
        "thermal.oilCircuit.coolerTemperatureDropKelvin",
        oil["coolerTemperatureDropKelvin"],
    )
    oil_capacity_margin = require_margin(
        "thermal.oilCircuit.installedCapacityMargin", oil["installedCapacityMargin"]
    )
    oil_flow_margin = require_margin(
        "thermal.oilCircuit.flowMargin", oil["flowMargin"]
    )
    oil_design_heat = heat_watts["oil"] * oil_capacity_margin
    oil_mass_flow = heat_watts["oil"] * oil_flow_margin / (oil_cp * oil_drop)
    oil_volume_flow_lpm = oil_mass_flow / oil_density * 60000

    lt = thermal["lowTemperatureCircuit"]
    lt_capacity_margin = require_margin(
        "thermal.lowTemperatureCircuit.installedCapacityMargin",
        lt["installedCapacityMargin"],
    )
    lt_design_heat = max(heat_watts["chargeCooling"], charge_cooler_actual) * lt_capacity_margin

    report = {
        "schemaVersion": "professional-v8.thermal-analysis.v1",
        "claimLevel": "P2-engineering-reference",
        "status": "p2-thermal-screening-passed-with-open-compressor-map-selection",
        "derivedGeometry": {
            "displacementCubicCentimeters": round_value(displacement * 1e6, 6),
            "displacementLiters": round_value(displacement * 1000, 9),
        },
        "performance": {
            "targetPowerKilowatts": target_power / 1000,
            "targetPowerRPM": int(target_power_rpm),
            "targetPointTorqueNewtonMeters": full_power_point["torqueNewtonMeters"],
            "peakTorqueNewtonMeters": max(point["torqueNewtonMeters"] for point in points),
            "peakBMEPBar": round_value(peak_bmep, 6),
            "maximumBMEPBar": maximum_bmep_bar,
            "curvePointCount": len(points),
        },
        "fullPowerAirAndFuel": {
            "fuelEnergyKilowatts": round_value(full_fuel_energy_rate / 1000, 6),
            "fuelMassKilogramsPerHour": round_value(full_fuel_mass_flow * 3600, 6),
            "airMassKilogramsPerSecond": round_value(full_air_mass_flow, 9),
            "exhaustMassKilogramsPerSecond": round_value(full_exhaust_mass_flow, 9),
            "bsfcGramsPerKilowattHour": full_power_point[
                "bsfcGramsPerKilowattHour"
            ],
            "manifoldAbsolutePressureKilopascals": full_power_point[
                "manifoldAbsolutePressureKilopascals"
            ],
            "compressorPressureRatio": full_power_point["compressorPressureRatio"],
            "compressorOutletCelsius": round_value(
                full_power_point["compressorOutletKelvin"] - 273.15, 6
            ),
            "chargeTargetCelsius": round_value(charge_target_temperature - 273.15, 6),
            "perCompressorCorrectedMassFlowPoundsPerMinute": full_power_point[
                "perCompressorCorrectedMassFlowPoundsPerMinute"
            ],
            "compressorMapAssessment": "requires-digitized-vendor-map",
        },
        "fullPowerHeatBalance": {
            "fuelInputKilowatts": round_value(full_fuel_energy_rate / 1000, 6),
            "brakeKilowatts": round_value(heat_watts["brake"] / 1000, 6),
            "exhaustBeforeTurbineKilowatts": round_value(
                heat_watts["exhaustBeforeTurbine"] / 1000, 6
            ),
            "highTemperatureCoolantKilowatts": round_value(
                heat_watts["highTemperatureCoolant"] / 1000, 6
            ),
            "oilKilowatts": round_value(heat_watts["oil"] / 1000, 6),
            "chargeCoolingAllocatedKilowatts": round_value(
                heat_watts["chargeCooling"] / 1000, 6
            ),
            "chargeCoolingCalculatedKilowatts": round_value(
                charge_cooler_actual / 1000, 6
            ),
            "chargeCoolingReserveKilowatts": round_value(charge_reserve / 1000, 6),
            "ambientAndUnmodeledKilowatts": round_value(
                heat_watts["ambientAndUnmodeled"] / 1000, 6
            ),
            "closureErrorWatts": round_value(closure_error, 9),
        },
        "turboThermalEnvelope": {
            "estimatedTurbineInletCelsius": round_value(
                estimated_turbine_inlet_temperature - 273.15, 6
            ),
            "continuousLimitCelsius": round_value(continuous_turbine_limit - 273.15, 6),
            "transientLimitCelsius": round_value(transient_turbine_limit - 273.15, 6),
            "estimatedTurbineOutletCelsius": round_value(
                estimated_turbine_outlet_temperature - 273.15, 6
            ),
            "temperatureMethod": "steady-sensible-enthalpy-screening-only",
        },
        "installedCircuitRequirements": {
            "highTemperatureCircuit": {
                "continuousEngineHeatKilowatts": round_value(
                    heat_watts["highTemperatureCoolant"] / 1000, 6
                ),
                "installedRejectionKilowatts": round_value(ht_design_heat / 1000, 6),
                "minimumCoolantMassFlowKilogramsPerSecond": round_value(ht_mass_flow, 6),
                "minimumCoolantVolumeFlowLitersPerMinute": round_value(
                    ht_volume_flow_lpm, 6
                ),
                "minimumRadiatorUAKilowattsPerKelvin": round_value(
                    radiator_ua / 1000, 6
                ),
            },
            "oilCircuit": {
                "continuousOilHeatKilowatts": round_value(heat_watts["oil"] / 1000, 6),
                "installedRejectionKilowatts": round_value(oil_design_heat / 1000, 6),
                "minimumOilMassFlowKilogramsPerSecond": round_value(oil_mass_flow, 6),
                "minimumOilVolumeFlowLitersPerMinute": round_value(
                    oil_volume_flow_lpm, 6
                ),
            },
            "lowTemperatureCircuit": {
                "installedRejectionKilowatts": round_value(lt_design_heat / 1000, 6),
                "sourceLoad": "maximum-of-allocated-and-calculated-charge-cooling",
            },
        },
        "openReleaseGates": [
            "digitized compressor maps with surge, choke, speed, and efficiency margins",
            "1D gas-exchange model with turbine A/R and backpressure",
            "combustion and knock model with cylinder pressure traces",
            "vehicle radiator, duct, fan, pump, and altitude validation",
            "dyno heat-balance and SAE J1349 measurement",
        ],
    }
    return report, points


def render_csv(fieldnames: list[str], rows: list[dict[str, Any]]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def generated_outputs(
    requirements_bytes: bytes, source_bytes: bytes
) -> dict[str, bytes]:
    requirements = json.loads(requirements_bytes)
    report, points = analyze(requirements)
    report["provenance"] = {
        "requirementsSHA256": sha256_bytes(requirements_bytes),
        "calculationSourceSHA256": sha256_bytes(source_bytes),
    }
    power_fields = [
        "rpm",
        "torqueNewtonMeters",
        "powerKilowatts",
        "bmepBar",
        "brakeThermalEfficiency",
        "bsfcGramsPerKilowattHour",
        "fuelMassFlowKilogramsPerSecond",
        "airMassFlowKilogramsPerSecond",
    ]
    compressor_fields = [
        "rpm",
        "compressorActive",
        "manifoldAbsolutePressureKilopascals",
        "compressorPressureRatio",
        "compressorOutletKelvin",
        "chargeCoolerHeatKilowatts",
        "compressorShaftPowerKilowatts",
        "turbineExtractedPowerKilowatts",
        "perCompressorMassFlowKilogramsPerSecond",
        "perCompressorCorrectedMassFlowPoundsPerMinute",
        "compressorMapAssessment",
    ]
    heat_balance = report["fullPowerHeatBalance"]
    thermal_rows = [
        {"path": key, "kilowatts": value}
        for key, value in heat_balance.items()
        if key.endswith("Kilowatts") and key != "chargeCoolingReserveKilowatts"
    ]
    thermal_rows.extend(
        {
            "path": f"installed.{circuit}.{key}",
            "kilowatts": value,
        }
        for circuit, values in report["installedCircuitRequirements"].items()
        for key, value in values.items()
        if key.endswith("Kilowatts")
    )
    return {
        "analysis-thermal.json": (
            json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + "\n"
        ).encode("utf-8"),
        "power-curve.csv": render_csv(
            power_fields, [{key: point[key] for key in power_fields} for point in points]
        ),
        "compressor-operating-points.csv": render_csv(
            compressor_fields,
            [{key: point[key] for key in compressor_fields} for point in points],
        ),
        "thermal-budget.csv": render_csv(["path", "kilowatts"], thermal_rows),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--requirements",
        type=Path,
        default=Path(__file__).with_name("requirements.json"),
    )
    parser.add_argument(
        "--output-directory", type=Path, default=Path(__file__).parent
    )
    arguments = parser.parse_args()
    requirements_bytes = arguments.requirements.read_bytes()
    source_bytes = Path(__file__).read_bytes()
    outputs = generated_outputs(requirements_bytes, source_bytes)
    arguments.output_directory.mkdir(parents=True, exist_ok=True)
    for filename, content in outputs.items():
        (arguments.output_directory / filename).write_bytes(content)


if __name__ == "__main__":
    main()
