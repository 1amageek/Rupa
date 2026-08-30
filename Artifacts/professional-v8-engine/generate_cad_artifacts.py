#!/usr/bin/env python3
"""Generate a requirements-bound semantic Rupa CAD batch and preview."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont


class CADGenerationError(ValueError):
    """Raised when semantic or geometric CAD generation cannot close."""


COLORS = {
    "structure": (67, 91, 110),
    "cranktrain": (169, 181, 191),
    "valvetrain": (190, 133, 62),
    "fuel": (150, 75, 57),
    "air": (56, 117, 146),
    "exhaust": (139, 72, 49),
    "coolant-ht": (48, 112, 164),
    "coolant-lt": (47, 145, 160),
    "oil": (157, 126, 47),
    "interface": (112, 97, 134),
}


def add(left: tuple[float, float, float], right: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(left[index] + right[index] for index in range(3))


def subtract(left: tuple[float, float, float], right: tuple[float, float, float]) -> tuple[float, float, float]:
    return tuple(left[index] - right[index] for index in range(3))


def scale(vector: tuple[float, float, float], factor: float) -> tuple[float, float, float]:
    return tuple(value * factor for value in vector)


def dot(left: tuple[float, float, float], right: tuple[float, float, float]) -> float:
    return sum(left[index] * right[index] for index in range(3))


def cross(left: tuple[float, float, float], right: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    )


def magnitude(vector: tuple[float, float, float]) -> float:
    return math.sqrt(dot(vector, vector))


def normalized(vector: tuple[float, float, float]) -> tuple[float, float, float]:
    length = magnitude(vector)
    if length <= 1e-12:
        raise CADGenerationError("a nonzero vector is required")
    return scale(vector, 1 / length)


def rounded(value: float, digits: int = 12) -> float:
    result = round(value, digits)
    return 0.0 if result == -0.0 else result


def vector_json(vector: tuple[float, float, float]) -> dict[str, float]:
    return {"x": rounded(vector[0]), "y": rounded(vector[1]), "z": rounded(vector[2])}


def point_json_meters_from_millimeters(point: tuple[float, float, float]) -> dict[str, float]:
    return vector_json(scale(point, 0.001))


def length_expression(millimeters: float) -> dict[str, Any]:
    return {"kind": "constant", "quantity": {"value": rounded(millimeters * 0.001), "kind": "length"}}


def sketch_plane(center: tuple[float, float, float], normal: tuple[float, float, float]) -> dict[str, Any]:
    return {
        "kind": "sketchPlane",
        "sketchPlane": {
            "kind": "plane",
            "plane": {
                "origin": point_json_meters_from_millimeters(center),
                "normal": vector_json(normalized(normal)),
            },
        },
    }


def component_command(component: dict[str, Any]) -> dict[str, Any]:
    if component["primitive"] == "cylinder":
        return {
            "createExtrudedCircle": {
                "name": component["bodyName"],
                "plane": sketch_plane(tuple(component["centerMillimeters"]), tuple(component["axis"])),
                "center": {"x": length_expression(0), "y": length_expression(0)},
                "radius": length_expression(component["radiusMillimeters"]),
                "depth": length_expression(component["lengthMillimeters"]),
                "direction": {"kind": "symmetric"},
            }
        }
    if component["primitive"] == "box":
        return {
            "createExtrudedRectangle": {
                "name": component["bodyName"],
                "plane": sketch_plane(tuple(component["centerMillimeters"]), tuple(component["normal"])),
                "width": length_expression(component["widthMillimeters"]),
                "height": length_expression(component["heightMillimeters"]),
                "depth": length_expression(component["depthMillimeters"]),
                "direction": {"kind": "symmetric"},
            }
        }
    raise CADGenerationError(f"unsupported primitive: {component['primitive']}")


def build_components(requirements: dict[str, Any], architecture: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, float]]:
    engine = requirements["engine"]
    mechanical = requirements["mechanical"]
    cad = requirements["cad"]
    semantic_parts = {part["partID"]: part for part in architecture["parts"]}
    components: list[dict[str, Any]] = []
    mapped_parts: set[str] = set()
    body_names: set[str] = set()

    def base_component(part_id: str, role: str, category: str, preview_visible: bool) -> dict[str, Any]:
        if part_id not in semantic_parts:
            raise CADGenerationError(f"unknown semantic part: {part_id}")
        body_name = f"{part_id}__{role}"
        if body_name in body_names:
            raise CADGenerationError(f"duplicate CAD body name: {body_name}")
        body_names.add(body_name)
        mapped_parts.add(part_id)
        part = semantic_parts[part_id]
        return {
            "bodyName": body_name,
            "partID": part_id,
            "role": role,
            "category": category,
            "semanticRepresentation": part["cadRepresentation"],
            "calculationDependencies": part["calculationDependencies"],
            "previewVisible": preview_visible,
        }

    def add_cylinder(part_id: str, role: str, category: str, center: tuple[float, float, float], axis: tuple[float, float, float], radius: float, length: float, preview_visible: bool = True) -> None:
        if radius <= 0 or length <= 0:
            raise CADGenerationError("cylinder dimensions must be positive")
        component = base_component(part_id, role, category, preview_visible)
        component.update({
            "primitive": "cylinder",
            "centerMillimeters": list(center),
            "axis": list(normalized(axis)),
            "radiusMillimeters": radius,
            "lengthMillimeters": length,
        })
        components.append(component)

    def add_box(part_id: str, role: str, category: str, center: tuple[float, float, float], normal: tuple[float, float, float], width: float, height: float, depth: float, preview_visible: bool = True) -> None:
        if min(width, height, depth) <= 0:
            raise CADGenerationError("box dimensions must be positive")
        component = base_component(part_id, role, category, preview_visible)
        component.update({
            "primitive": "box",
            "centerMillimeters": list(center),
            "normal": list(normalized(normal)),
            "widthMillimeters": width,
            "heightMillimeters": height,
            "depthMillimeters": depth,
        })
        components.append(component)

    bore = engine["boreMeters"] * 1000
    stroke = engine["strokeMeters"] * 1000
    crank_radius = stroke / 2
    pitch = mechanical["cylinderPitchMeters"] * 1000
    rod_length = mechanical["connectingRodLengthMeters"] * 1000
    deck_height = mechanical["crankAxisToDeckMeters"] * 1000
    compression_height = mechanical["pistonCompressionHeightMeters"] * 1000
    wrist_pin_radius = mechanical["wristPinDiameterMeters"] * 500
    crankpin_radius = mechanical["crankpinDiameterMeters"] * 500
    crankpin_length = mechanical["crankpinJournalWidthMeters"] * 1000
    main_radius = mechanical["mainJournalDiameterMeters"] * 500
    main_length = mechanical["mainJournalWidthMeters"] * 1000
    static_angle = cad["staticCrankAngleDegrees"]
    throw_phases = mechanical["crankpinAnglesDegrees"]
    stations = tuple((index - 1.5) * pitch for index in range(4))
    main_stations = tuple((index - 2) * pitch for index in range(5))
    half_angle = math.radians(mechanical["bankAngleDegrees"] / 2)
    sine = math.sin(half_angle)
    cosine = math.cos(half_angle)
    bank_axes = {"L": (0.0, -sine, cosine), "R": (0.0, sine, cosine)}
    x_axis = (1.0, 0.0, 0.0)
    z_axis = (0.0, 0.0, 1.0)

    add_box("structure.block", "central-crankcase", "structure", (0, 0, 20), z_axis, 410, 160, 150)
    for bank, bank_axis in bank_axes.items():
        visible = bank != cad["previewCutawayBank"]
        add_box("structure.block", f"deck-rail-{bank}", "structure", scale(bank_axis, deck_height - 45), bank_axis, 410, 116, 90, visible)
    add_box("structure.bedplate", "five-main-bedplate", "structure", (0, 0, -72), z_axis, 420, 185, 42)
    add_box("structure.lower-crankcase", "dry-sump-lower-envelope", "oil", (0, 0, -125), z_axis, 420, 170, 58)
    for bank, bank_axis in bank_axes.items():
        visible = bank != cad["previewCutawayBank"]
        add_box(f"head.{bank}", "head-structural-envelope", "structure", scale(bank_axis, deck_height + 46), bank_axis, 410, 132, 92, visible)
        add_box(f"cover.cam.{bank}", "cam-cover-service-envelope", "structure", scale(bank_axis, deck_height + 101), bank_axis, 398, 112, 34, visible)

    for index, station in enumerate(main_stations, start=1):
        add_cylinder("crankshaft", f"main-journal-{index}", "cranktrain", (station, 0, 0), x_axis, main_radius, main_length)
        add_cylinder(f"bearing.main.{index}", "bearing-interface", "interface", (station, 0, 0), x_axis, main_radius + 2, main_length + 2, False)
    for index, station in enumerate(stations):
        phase = math.radians(throw_phases[index] + static_angle)
        offset = (0.0, crank_radius * math.sin(phase), crank_radius * math.cos(phase))
        crankpin_center = (station, offset[1], offset[2])
        add_cylinder("crankshaft", f"crankpin-{index + 1}", "cranktrain", crankpin_center, x_axis, crankpin_radius, crankpin_length)
        radial = normalized(offset)
        for side, x_offset in (("front", -crankpin_length / 2 - 7), ("rear", crankpin_length / 2 + 7)):
            web_center = (station + x_offset, offset[1] / 2, offset[2] / 2)
            add_cylinder("crankshaft", f"web-{index + 1}-{side}", "cranktrain", web_center, radial, 24, crank_radius)
            counter_center = (station + x_offset, -radial[1] * 26, -radial[2] * 26)
            add_cylinder("crankshaft", f"counterweight-{index + 1}-{side}", "cranktrain", counter_center, scale(radial, -1), 34, 52)
    add_cylinder("crankshaft", "front-nose", "cranktrain", (-230, 0, 0), x_axis, 18, 52)
    add_cylinder("crankshaft", "flywheel-flange", "cranktrain", (226, 0, 0), x_axis, 38, 28)
    add_cylinder("flywheel-interface", "flywheel-envelope", "interface", (252, 0, 0), x_axis, 105, 24)
    add_cylinder("torsional-damper", "damper-envelope", "interface", (-262, 0, 0), x_axis, 82, 30)

    maximum_rod_residual = 0.0
    for bank, bank_axis in bank_axes.items():
        tangent = normalized(cross(x_axis, bank_axis))
        visible_exterior = bank != cad["previewCutawayBank"]
        for index, station in enumerate(stations):
            cylinder = f"{bank}{index + 1}"
            prefix = f"cylinder.{cylinder}"
            phase = math.radians(throw_phases[index] + static_angle)
            crank_offset = (0.0, crank_radius * math.sin(phase), crank_radius * math.cos(phase))
            axial_projection = dot(bank_axis, crank_offset)
            perpendicular = subtract(crank_offset, scale(bank_axis, axial_projection))
            radicand = rod_length**2 - dot(perpendicular, perpendicular)
            if radicand <= 0:
                raise CADGenerationError(f"connecting rod cannot close for {cylinder}")
            piston_distance = axial_projection + math.sqrt(radicand)
            piston_pin = (station, bank_axis[1] * piston_distance, bank_axis[2] * piston_distance)
            rod_journal_x = station + (-10.25 if bank == "L" else 10.25)
            crankpin_for_rod = (rod_journal_x, crank_offset[1], crank_offset[2])
            piston_pin = (rod_journal_x, piston_pin[1], piston_pin[2])
            rod_vector = subtract(piston_pin, crankpin_for_rod)
            rod_actual_length = magnitude(rod_vector)
            maximum_rod_residual = max(maximum_rod_residual, abs(rod_actual_length - rod_length))

            liner_center = (rod_journal_x, bank_axis[1] * (deck_height - 65), bank_axis[2] * (deck_height - 65))
            add_cylinder(f"{prefix}.liner", "bore-volume-envelope", "structure", liner_center, bank_axis, bore / 2, 130, visible_exterior)
            add_cylinder(f"coolant.ht-jacket.{bank}", f"cylinder-{index + 1}-coolant-volume-envelope", "coolant-ht", liner_center, bank_axis, bore / 2 + 7, 142, False)
            add_cylinder(f"{prefix}.piston", "piston-envelope", "cranktrain", piston_pin, bank_axis, bore / 2 - 2, compression_height)
            add_cylinder(f"{prefix}.wrist-pin", "pin-envelope", "cranktrain", piston_pin, x_axis, wrist_pin_radius, mechanical["wristPinTotalBearingWidthMeters"] * 1000)
            rod_center = scale(add(crankpin_for_rod, piston_pin), 0.5)
            add_cylinder(f"{prefix}.connecting-rod", "weak-axis-envelope", "cranktrain", rod_center, rod_vector, 8, rod_actual_length)
            add_cylinder(f"{prefix}.big-end-bearing", "projected-bearing-envelope", "interface", crankpin_for_rod, x_axis, crankpin_radius + 2, mechanical["connectingRodBigEndWidthMeters"] * 1000, False)
            jet_center = add(scale(bank_axis, 88), scale(tangent, -18))
            jet_center = (rod_journal_x, jet_center[1], jet_center[2])
            add_cylinder(f"{prefix}.oil-jet", "piston-cooling-nozzle-envelope", "oil", jet_center, bank_axis, 2.5, 32)

            head_center = scale(bank_axis, deck_height + 46)
            valve_distance = deck_height + 42
            valve_positions = {
                "intake-valve": (15, -14, mechanical["intakeValveHeadDiameterMeters"] * 500, mechanical["intakeValveLiftMeters"] * 1000 + 45),
                "exhaust-valve": (-15, 14, mechanical["exhaustValveHeadDiameterMeters"] * 500, mechanical["exhaustValveLiftMeters"] * 1000 + 45),
            }
            for valve_kind, (x_offset, tangent_offset, radius, length) in valve_positions.items():
                for valve_index, sign in enumerate((-1, 1), start=1):
                    base = add(scale(bank_axis, valve_distance), scale(tangent, tangent_offset))
                    center = (rod_journal_x + sign * abs(x_offset), base[1], base[2])
                    add_cylinder(f"{prefix}.{valve_kind}.{valve_index}", "valve-motion-envelope", "valvetrain", center, bank_axis, radius, length, visible_exterior)
            plug_center = scale(bank_axis, deck_height + 58)
            add_cylinder(f"{prefix}.spark-plug", "spark-plug-service-envelope", "fuel", (rod_journal_x, plug_center[1], plug_center[2]), bank_axis, 7, 62, visible_exterior)
            di_center = add(scale(bank_axis, deck_height + 54), scale(tangent, -18))
            add_cylinder(f"{prefix}.di-injector", "direct-injector-service-envelope", "fuel", (rod_journal_x + 8, di_center[1], di_center[2]), bank_axis, 6, 72, visible_exterior)
            pfi_center = add(scale(bank_axis, deck_height + 82), scale(tangent, -38))
            add_cylinder(f"{prefix}.pfi-injector", "port-injector-service-envelope", "fuel", (rod_journal_x, pfi_center[1], pfi_center[2]), bank_axis, 6, 62, visible_exterior)
            coil_center = scale(bank_axis, deck_height + 103)
            add_cylinder(f"{prefix}.ignition-coil", "coil-service-envelope", "fuel", (rod_journal_x, coil_center[1], coil_center[2]), bank_axis, 13, 86, visible_exterior)

        for cam_kind, tangent_offset in (("intake", -28), ("exhaust", 28)):
            center = add(scale(bank_axis, deck_height + 83), scale(tangent, tangent_offset))
            add_cylinder(f"camshaft.{bank}.{cam_kind}", "camshaft-envelope", "valvetrain", (0, center[1], center[2]), x_axis, 18, 408, visible_exterior)

    for bank, sign in (("L", -1), ("R", 1)):
        bank_axis = bank_axes[bank]
        visible_exterior = bank != cad["previewCutawayBank"]
        add_box(f"intake-plenum.{bank}", "plenum-flow-envelope", "air", (0, sign * 130, 335), z_axis, 360, 84, 78, visible_exterior)
        add_cylinder(f"throttle.{bank}", "throttle-interface-envelope", "air", (-208, sign * 130, 335), x_axis, 36, 54, visible_exterior)
        add_box(f"air.filter.{bank}", "filter-service-envelope", "air", (-315, sign * 365, 160), z_axis, 108, 95, 82)
        add_box(f"charge-cooler.{bank}", "charge-cooler-flow-envelope", "coolant-lt", (-285, sign * 235, 155), z_axis, 125, 92, 94)
        add_cylinder(f"turbo.{bank}.compressor", "compressor-housing-envelope", "air", (-42, sign * 365, 72), x_axis, 55, 62)
        add_cylinder(f"turbo.{bank}.core", "bearing-core-service-envelope", "interface", (18, sign * 365, 72), x_axis, 26, 70)
        add_cylinder(f"turbo.{bank}.turbine", "turbine-thermal-envelope", "exhaust", (78, sign * 365, 72), x_axis, 50, 60)
        manifold_start = add(scale(bank_axis, deck_height + 35), (0, sign * 55, -25))
        manifold_end = (35, sign * 330, 82)
        manifold_vector = subtract(manifold_end, manifold_start)
        add_cylinder(f"exhaust-manifold.{bank}", "runner-collector-thermal-envelope", "exhaust", scale(add(manifold_start, manifold_end), 0.5), manifold_vector, 28, magnitude(manifold_vector))
        add_cylinder(f"catalyst-interface.{bank}", "aftertreatment-interface-envelope", "exhaust", (155, sign * 365, 72), x_axis, 58, 80)
        rail_base = add(scale(bank_axis, deck_height + 72), scale(normalized(cross(x_axis, bank_axis)), -35))
        add_cylinder(f"fuel.di-rail.{bank}", "di-rail-envelope", "fuel", (0, rail_base[1], rail_base[2]), x_axis, 10, 390, visible_exterior)
        pfi_rail = add(scale(bank_axis, deck_height + 94), scale(normalized(cross(x_axis, bank_axis)), -52))
        add_cylinder(f"fuel.pfi-rail.{bank}", "pfi-rail-envelope", "fuel", (0, pfi_rail[1], pfi_rail[2]), x_axis, 9, 390, visible_exterior)
        add_cylinder(f"fuel.high-pressure-pump.{bank}", "high-pressure-pump-envelope", "fuel", (-215, sign * 128, 300), x_axis, 30, 58, visible_exterior)
        add_cylinder(f"oil.scavenge-gallery.{bank}", "scavenge-flow-envelope", "oil", (0, sign * 62, -112), x_axis, 8, 385, False)

    add_cylinder("coolant.ht-pump", "ht-pump-service-envelope", "coolant-ht", (-260, 0, 10), x_axis, 52, 62)
    add_cylinder("coolant.ht-thermostat", "thermostat-service-envelope", "coolant-ht", (-215, 0, 285), x_axis, 34, 54)
    add_box("coolant.ht-radiator-interface", "vehicle-radiator-interface-envelope", "coolant-ht", (-360, 0, 20), z_axis, 22, 190, 95)
    add_cylinder("coolant.lt-pump", "lt-pump-service-envelope", "coolant-lt", (-350, 0, 145), x_axis, 36, 48)
    add_box("coolant.lt-front-interface", "lt-front-heat-exchanger-interface-envelope", "coolant-lt", (-390, 0, 155), z_axis, 20, 430, 130)
    add_box("oil.dry-sump-pump", "six-stage-pump-service-envelope", "oil", (-225, -105, -92), z_axis, 95, 52, 62)
    add_cylinder("oil.tank", "deaeration-tank-service-envelope", "oil", (185, -265, -15), z_axis, 72, 210)
    add_box("oil.cooler-interface", "oil-cooler-interface-envelope", "oil", (-330, -145, -35), z_axis, 90, 28, 105)
    add_cylinder("oil.pressure-gallery", "main-pressure-flow-envelope", "oil", (0, -48, -62), x_axis, 7, 395, False)

    missing_parts = set(semantic_parts) - mapped_parts
    if missing_parts:
        raise CADGenerationError(f"semantic parts without CAD representation: {sorted(missing_parts)}")
    if len(semantic_parts) < cad["minimumSemanticParts"]:
        raise CADGenerationError("semantic part inventory is below the CAD minimum")
    if len(components) > cad["maximumBodyCount"]:
        raise CADGenerationError("CAD body count exceeds the configured resource ceiling")
    if maximum_rod_residual > 1e-9:
        raise CADGenerationError("slider-crank CAD geometry does not close")
    return components, {
        "maximumConnectingRodResidualMillimeters": 0.0 if maximum_rod_residual < 1e-9 else maximum_rod_residual,
        "staticCrankAngleDegrees": static_angle,
        "boreMillimeters": bore,
        "strokeMillimeters": stroke,
        "cylinderPitchMillimeters": pitch,
        "deckHeightMillimeters": deck_height,
        "bankAngleDegrees": mechanical["bankAngleDegrees"],
    }


def plane_basis(normal: tuple[float, float, float]) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    normal = normalized(normal)
    helper = (0.0, 0.0, 1.0) if abs(normal[2]) < 0.9 else (0.0, 1.0, 0.0)
    axis_u = normalized(cross(helper, normal))
    return axis_u, cross(normal, axis_u)


def polygons_for_component(component: dict[str, Any], segments: int) -> list[tuple[list[tuple[float, float, float]], tuple[float, float, float]]]:
    center = tuple(component["centerMillimeters"])
    if component["primitive"] == "cylinder":
        axis = tuple(component["axis"])
        half_axis = scale(axis, component["lengthMillimeters"] / 2)
        centers = (subtract(center, half_axis), add(center, half_axis))
        helper = (0.0, 0.0, 1.0) if abs(axis[2]) < 0.9 else (0.0, 1.0, 0.0)
        radial_u = normalized(cross(helper, axis))
        radial_v = cross(axis, radial_u)
        rings = []
        for axial_center in centers:
            ring = []
            for index in range(segments):
                angle = 2 * math.pi * index / segments
                radial = add(scale(radial_u, component["radiusMillimeters"] * math.cos(angle)), scale(radial_v, component["radiusMillimeters"] * math.sin(angle)))
                ring.append(add(axial_center, radial))
            rings.append(ring)
        polygons = []
        for index in range(segments):
            next_index = (index + 1) % segments
            points = [rings[0][index], rings[0][next_index], rings[1][next_index], rings[1][index]]
            polygons.append((points, normalized(cross(subtract(points[1], points[0]), subtract(points[2], points[0])))))
        polygons.append((list(reversed(rings[0])), scale(axis, -1)))
        polygons.append((rings[1], axis))
        return polygons
    normal = tuple(component["normal"])
    axis_u, axis_v = plane_basis(normal)
    axes = (axis_u, axis_v, normal)
    halves = (component["widthMillimeters"] / 2, component["heightMillimeters"] / 2, component["depthMillimeters"] / 2)
    corners = {}
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                point = center
                for axis, half, sign in zip(axes, halves, (sx, sy, sz)):
                    point = add(point, scale(axis, half * sign))
                corners[(sx, sy, sz)] = point
    faces = []
    for axis_index in range(3):
        other = [index for index in range(3) if index != axis_index]
        for sign in (-1, 1):
            points = []
            for first, second in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                signs = [0, 0, 0]
                signs[axis_index] = sign
                signs[other[0]] = first
                signs[other[1]] = second
                points.append(corners[tuple(signs)])
            faces.append((points, scale(axes[axis_index], sign)))
    return faces


def render_preview(components: list[dict[str, Any]], output: Path, segments: int, metrics: dict[str, float]) -> None:
    view_direction = normalized((1.35, -1.8, 1.05))
    screen_right = normalized(cross(view_direction, (0.0, 0.0, 1.0)))
    screen_up = normalized(cross(screen_right, view_direction))
    light = normalized((-0.35, -0.55, 1.0))
    polygons = []
    projected_points = []
    for component in components:
        if not component["previewVisible"]:
            continue
        for points, normal in polygons_for_component(component, segments):
            projected = [(dot(point, screen_right), dot(point, screen_up)) for point in points]
            depth = sum(dot(point, view_direction) for point in points) / len(points)
            polygons.append((depth, projected, normal, component["category"]))
            projected_points.extend(projected)
    minimum_x = min(point[0] for point in projected_points)
    maximum_x = max(point[0] for point in projected_points)
    minimum_y = min(point[1] for point in projected_points)
    maximum_y = max(point[1] for point in projected_points)
    width, height, supersampling = 1800, 1200, 2
    margin_x, title_height, bottom_margin = 90, 155, 95
    scale_factor = min((width - 2 * margin_x) / (maximum_x - minimum_x), (height - title_height - bottom_margin) / (maximum_y - minimum_y))
    image = Image.new("RGB", (width * supersampling, height * supersampling), (10, 16, 22))
    draw = ImageDraw.Draw(image)

    def screen(point: tuple[float, float]) -> tuple[int, int]:
        return (
            round((margin_x + (point[0] - minimum_x) * scale_factor) * supersampling),
            round((title_height + (maximum_y - point[1]) * scale_factor) * supersampling),
        )

    for _, points, normal, category in sorted(polygons, key=lambda value: value[0]):
        base = COLORS[category]
        brightness = 0.48 + 0.52 * max(0, dot(normalized(normal), light))
        fill = tuple(max(0, min(255, round(channel * brightness))) for channel in base)
        draw.polygon([screen(point) for point in points], fill=fill, outline=(17, 24, 30))
    try:
        title_font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 42 * supersampling)
        subtitle_font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 22 * supersampling)
        label_font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 18 * supersampling)
    except OSError:
        title_font = subtitle_font = label_font = ImageFont.load_default()
    draw.text((margin_x * supersampling, 24 * supersampling), "Professional V8 P2 Engineering Reference", fill=(238, 244, 248), font=title_font)
    draw.text((margin_x * supersampling, 82 * supersampling), "450 kW · 750 N·m · thermal/load-bound semantic CAD · left presentation cutaway", fill=(154, 178, 192), font=subtitle_font)
    draw.text((margin_x * supersampling, 116 * supersampling), f"86 × 86 mm · 3.996 L · {len(components)} source bodies · maximum rod residual {metrics['maximumConnectingRodResidualMillimeters']:.3g} mm", fill=(132, 155, 169), font=subtitle_font)
    legend = [("Structure", "structure"), ("Cranktrain", "cranktrain"), ("Valvetrain", "valvetrain"), ("Air / coolant", "coolant-lt"), ("Fuel / oil", "oil"), ("Exhaust", "exhaust")]
    legend_x = margin_x
    for label, category in legend:
        y = height - 55
        draw.rounded_rectangle((legend_x * supersampling, y * supersampling, (legend_x + 24) * supersampling, (y + 18) * supersampling), radius=4 * supersampling, fill=COLORS[category])
        draw.text(((legend_x + 33) * supersampling, (y - 3) * supersampling), label, fill=(195, 207, 215), font=label_font)
        legend_x += 255
    image.resize((width, height), Image.Resampling.LANCZOS).save(output)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--requirements", type=Path, default=Path(__file__).with_name("requirements.json"))
    parser.add_argument("--thermal-analysis", type=Path, default=Path(__file__).with_name("analysis-thermal.json"))
    parser.add_argument("--mechanical-analysis", type=Path, default=Path(__file__).with_name("analysis-mechanical.json"))
    parser.add_argument("--architecture", type=Path, default=Path(__file__).with_name("semantic-architecture.json"))
    parser.add_argument("--output-directory", type=Path, default=Path(__file__).parent)
    arguments = parser.parse_args()
    sources = {
        "requirements": arguments.requirements.read_bytes(),
        "thermalAnalysis": arguments.thermal_analysis.read_bytes(),
        "mechanicalAnalysis": arguments.mechanical_analysis.read_bytes(),
        "semanticArchitecture": arguments.architecture.read_bytes(),
        "generator": Path(__file__).read_bytes(),
    }
    requirements = json.loads(sources["requirements"])
    thermal = json.loads(sources["thermalAnalysis"])
    mechanical = json.loads(sources["mechanicalAnalysis"])
    architecture = json.loads(sources["semanticArchitecture"])
    requirement_hash = sha256_bytes(sources["requirements"])
    thermal_hash = sha256_bytes(sources["thermalAnalysis"])
    if thermal["provenance"]["requirementsSHA256"] != requirement_hash:
        raise CADGenerationError("thermal analysis is stale")
    if mechanical["provenance"]["requirementsSHA256"] != requirement_hash or mechanical["provenance"]["thermalAnalysisSHA256"] != thermal_hash:
        raise CADGenerationError("mechanical analysis is stale")
    if architecture["provenance"] != mechanical["provenance"]:
        raise CADGenerationError("semantic architecture is stale")
    components, metrics = build_components(requirements, architecture)
    commands = [component_command(component) for component in components]
    commands.append({"validateDocument": {}})
    provenance = {f"{name}SHA256": sha256_bytes(value) for name, value in sources.items()}
    manifest = {
        "schemaVersion": "professional-v8.cad-source-manifest.v1",
        "claimLevel": "P2-engineering-reference",
        "authority": "native-rupa-cad-source-after-successful-public-cli-publication",
        "primitiveContract": ["symmetric-extruded-circle", "symmetric-extruded-rectangle"],
        "bodyCount": len(components),
        "semanticPartCount": len(architecture["parts"]),
        "coveredSemanticPartCount": len({component["partID"] for component in components}),
        "representationCounts": dict(sorted(Counter(component["semanticRepresentation"] for component in components).items())),
        "categoryCounts": dict(sorted(Counter(component["category"] for component in components).items())),
        "geometryChecks": metrics,
        "components": components,
        "provenance": provenance,
        "unsupportedManufacturingDetails": [
            "hollow coolant jackets and galleries",
            "combustion chambers and gas-exchange ports",
            "bearing oil films, clearances, and surface finishes",
            "cast and forged wall sections, fillets, fasteners, and tolerances",
            "seals, rings, valve seats, springs, timing drive, and accessory drive",
        ],
    }
    arguments.output_directory.mkdir(parents=True, exist_ok=True)
    (arguments.output_directory / "create-professional-v8-batch.json").write_text(json.dumps({"commands": commands}, indent=2, sort_keys=True) + "\n")
    (arguments.output_directory / "cad-source-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True, allow_nan=False) + "\n")
    render_preview(components, arguments.output_directory / "professional-v8-preview.png", requirements["cad"]["previewCylinderSegments"], metrics)
    print(json.dumps({"bodyCount": len(components), "semanticPartCount": len(architecture["parts"]), "commandCount": len(commands), "geometryChecks": metrics}, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
