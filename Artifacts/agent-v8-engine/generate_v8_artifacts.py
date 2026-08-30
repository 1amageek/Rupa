#!/usr/bin/env python3

import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OUTPUT_DIRECTORY = Path(__file__).resolve().parent

BORE_MILLIMETERS = 86.0
STROKE_MILLIMETERS = 86.0
CONNECTING_ROD_LENGTH_MILLIMETERS = 150.0
CYLINDER_PITCH_MILLIMETERS = 94.0
BANK_ANGLE_DEGREES = 90.0
STATIC_CRANK_ANGLE_DEGREES = 30.0
THROW_PHASES_DEGREES = [0.0, 90.0, 270.0, 180.0]
THROW_STATIONS_MILLIMETERS = [-141.0, -47.0, 47.0, 141.0]
MAIN_JOURNAL_STATIONS_MILLIMETERS = [-188.0, -94.0, 0.0, 94.0, 188.0]
BANK_AXIAL_OFFSET_MILLIMETERS = 9.0

CRANK_RADIUS_MILLIMETERS = STROKE_MILLIMETERS / 2.0
SQRT_HALF = math.sqrt(0.5)

CATEGORY_COLORS = {
    "piston": (199, 209, 218),
    "wrist_pin": (116, 137, 151),
    "connecting_rod": (196, 139, 70),
    "crankpin": (75, 94, 108),
    "main_journal": (55, 73, 86),
    "crank_web": (70, 91, 107),
    "counterweight": (47, 66, 80),
    "flywheel": (73, 86, 96),
    "timing_wheel": (89, 106, 117),
    "cylinder_deck": (58, 97, 126),
    "cylinder_bank_rail": (47, 84, 111),
    "valve_cover": (35, 67, 91),
    "crankcase_rail": (42, 77, 101),
}


def add(left, right):
    return tuple(left[index] + right[index] for index in range(3))


def subtract(left, right):
    return tuple(left[index] - right[index] for index in range(3))


def scale(vector, factor):
    return tuple(value * factor for value in vector)


def dot(left, right):
    return sum(left[index] * right[index] for index in range(3))


def cross(left, right):
    return (
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    )


def magnitude(vector):
    return math.sqrt(dot(vector, vector))


def normalized(vector):
    length = magnitude(vector)
    if length <= 1.0e-12:
        raise ValueError("A non-zero vector is required.")
    return scale(vector, 1.0 / length)


def rounded(value):
    result = round(value, 12)
    return 0.0 if result == -0.0 else result


def vector_json(vector):
    return {
        "x": rounded(vector[0]),
        "y": rounded(vector[1]),
        "z": rounded(vector[2]),
    }


def point_json_millimeters(point):
    return {
        "x": rounded(point[0] / 1000.0),
        "y": rounded(point[1] / 1000.0),
        "z": rounded(point[2] / 1000.0),
    }


def length_expression(millimeters):
    return {
        "kind": "constant",
        "quantity": {
            "value": rounded(millimeters / 1000.0),
            "kind": "length",
        },
    }


def sketch_point_zero():
    return {
        "x": length_expression(0.0),
        "y": length_expression(0.0),
    }


def sketch_plane_reference(center, normal):
    return {
        "kind": "sketchPlane",
        "sketchPlane": {
            "kind": "plane",
            "plane": {
                "origin": point_json_millimeters(center),
                "normal": vector_json(normalized(normal)),
            },
        },
    }


def symmetric_direction():
    return {"kind": "symmetric"}


def cylinder_command(component):
    return {
        "createExtrudedCircle": {
            "name": component["name"],
            "plane": sketch_plane_reference(component["center"], component["axis"]),
            "center": sketch_point_zero(),
            "radius": length_expression(component["radius"]),
            "depth": length_expression(component["length"]),
            "direction": symmetric_direction(),
        }
    }


def box_command(component):
    return {
        "createExtrudedRectangle": {
            "name": component["name"],
            "plane": sketch_plane_reference(component["center"], component["normal"]),
            "width": length_expression(component["width"]),
            "height": length_expression(component["height"]),
            "depth": length_expression(component["depth"]),
            "direction": symmetric_direction(),
        }
    }


def slider_crank_piston_pin(bank_axis, crankpin_point):
    axial_projection = dot(bank_axis, crankpin_point)
    perpendicular = subtract(crankpin_point, scale(bank_axis, axial_projection))
    radicand = CONNECTING_ROD_LENGTH_MILLIMETERS**2 - dot(perpendicular, perpendicular)
    if radicand <= 0.0:
        raise ValueError("The connecting rod cannot reach the cylinder axis.")
    piston_distance = axial_projection + math.sqrt(radicand)
    return scale(bank_axis, piston_distance)


def plane_basis(normal):
    normal = normalized(normal)
    helper = (0.0, 0.0, 1.0) if abs(normal[2]) < 0.9 else (0.0, 1.0, 0.0)
    axis_u = normalized(cross(helper, normal))
    axis_v = cross(normal, axis_u)
    return axis_u, axis_v


def build_assembly():
    components = []
    cylinders = []

    def append_cylinder(name, category, center, axis, radius, length, metadata=None):
        component = {
            "kind": "cylinder",
            "name": name,
            "category": category,
            "center": tuple(center),
            "axis": normalized(axis),
            "radius": radius,
            "length": length,
        }
        if metadata is not None:
            component["metadata"] = metadata
        components.append(component)
        return component

    def append_box(name, category, center, normal, width, height, depth):
        normal = normalized(normal)
        axis_u, axis_v = plane_basis(normal)
        component = {
            "kind": "box",
            "name": name,
            "category": category,
            "center": tuple(center),
            "normal": normal,
            "axisU": axis_u,
            "axisV": axis_v,
            "width": width,
            "height": height,
            "depth": depth,
        }
        components.append(component)
        return component

    bank_definitions = [
        ("L", (0.0, -SQRT_HALF, SQRT_HALF), -BANK_AXIAL_OFFSET_MILLIMETERS),
        ("R", (0.0, SQRT_HALF, SQRT_HALF), BANK_AXIAL_OFFSET_MILLIMETERS),
    ]

    for throw_index, station in enumerate(THROW_STATIONS_MILLIMETERS):
        phase_degrees = THROW_PHASES_DEGREES[throw_index] + STATIC_CRANK_ANGLE_DEGREES
        phase_radians = math.radians(phase_degrees)
        crank_offset = (
            0.0,
            CRANK_RADIUS_MILLIMETERS * math.sin(phase_radians),
            CRANK_RADIUS_MILLIMETERS * math.cos(phase_radians),
        )

        append_cylinder(
            f"Crankpin {throw_index + 1}",
            "crankpin",
            (station, crank_offset[1], crank_offset[2]),
            (1.0, 0.0, 0.0),
            11.0,
            70.0,
            {"throw": throw_index + 1, "phaseDegrees": phase_degrees % 360.0},
        )

        radial_axis = normalized(crank_offset)
        counterweight_length = CRANK_RADIUS_MILLIMETERS * 0.72
        for side_index, web_x in enumerate((station - 31.0, station + 31.0), start=1):
            append_cylinder(
                f"Crank Web {throw_index + 1}.{side_index}",
                "crank_web",
                (web_x, crank_offset[1] / 2.0, crank_offset[2] / 2.0),
                radial_axis,
                14.0,
                CRANK_RADIUS_MILLIMETERS,
            )
            append_cylinder(
                f"Counterweight {throw_index + 1}.{side_index}",
                "counterweight",
                (
                    web_x,
                    -radial_axis[1] * counterweight_length / 2.0,
                    -radial_axis[2] * counterweight_length / 2.0,
                ),
                scale(radial_axis, -1.0),
                20.0,
                counterweight_length,
            )

        for bank_name, bank_axis, bank_offset in bank_definitions:
            cylinder_number = throw_index + 1
            crankpin_for_rod = (
                station + bank_offset,
                crank_offset[1],
                crank_offset[2],
            )
            piston_pin_local = slider_crank_piston_pin(bank_axis, crank_offset)
            piston_pin = (
                station + bank_offset,
                piston_pin_local[1],
                piston_pin_local[2],
            )
            rod_vector = subtract(piston_pin, crankpin_for_rod)
            rod_length = magnitude(rod_vector)

            append_cylinder(
                f"Piston {bank_name}{cylinder_number}",
                "piston",
                piston_pin,
                bank_axis,
                40.5,
                28.0,
                {"bank": bank_name, "cylinder": cylinder_number},
            )
            append_cylinder(
                f"Wrist Pin {bank_name}{cylinder_number}",
                "wrist_pin",
                piston_pin,
                (1.0, 0.0, 0.0),
                6.0,
                52.0,
            )
            append_cylinder(
                f"Connecting Rod {bank_name}{cylinder_number}",
                "connecting_rod",
                scale(add(crankpin_for_rod, piston_pin), 0.5),
                rod_vector,
                7.5,
                rod_length,
            )

            cylinders.append({
                "bank": bank_name,
                "cylinder": cylinder_number,
                "throw": throw_index + 1,
                "phaseDegrees": rounded(phase_degrees % 360.0),
                "bankAxis": vector_json(bank_axis),
                "crankpinCenterMillimeters": vector_json(crankpin_for_rod),
                "pistonPinCenterMillimeters": vector_json(piston_pin),
                "connectingRodLengthMillimeters": rounded(rod_length),
                "connectingRodLengthResidualMillimeters": rounded(
                    abs(rod_length - CONNECTING_ROD_LENGTH_MILLIMETERS)
                ),
            })

    for journal_index, station in enumerate(MAIN_JOURNAL_STATIONS_MILLIMETERS, start=1):
        append_cylinder(
            f"Main Journal {journal_index}",
            "main_journal",
            (station, 0.0, 0.0),
            (1.0, 0.0, 0.0),
            22.0,
            22.0,
        )

    append_cylinder(
        "Front Crankshaft Nose",
        "main_journal",
        (-206.5, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        15.0,
        15.0,
    )
    append_cylinder(
        "Flywheel Flange",
        "main_journal",
        (205.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        18.0,
        12.0,
    )
    append_cylinder(
        "Timing Wheel",
        "timing_wheel",
        (-221.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        55.0,
        14.0,
    )
    append_cylinder(
        "Flywheel",
        "flywheel",
        (220.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        92.0,
        18.0,
    )

    for bank_name, bank_axis, _ in bank_definitions:
        for support_index, support_x in enumerate((-190.0, 190.0), start=1):
            append_cylinder(
                f"Cutaway Bank Support {bank_name}{support_index}",
                "cylinder_bank_rail",
                (support_x, bank_axis[1] * 155.0, bank_axis[2] * 155.0),
                bank_axis,
                8.0,
                130.0,
            )

    # The near-side left head is intentionally removed so the CAD artifact is
    # a true cutaway rather than an opaque complete exterior.
    for bank_name, bank_axis, _ in bank_definitions:
        if bank_name == "L":
            continue
        append_box(
            f"Cylinder Deck {bank_name}",
            "cylinder_deck",
            scale(bank_axis, 228.0),
            bank_axis,
            410.0,
            94.0,
            16.0,
        )
        append_box(
            f"Valve Cover {bank_name}",
            "valve_cover",
            scale(bank_axis, 256.0),
            bank_axis,
            388.0,
            74.0,
            24.0,
        )

    append_box(
        "Crankcase Rail Left",
        "crankcase_rail",
        (0.0, -73.0, -56.0),
        (0.0, 0.0, 1.0),
        410.0,
        24.0,
        30.0,
    )
    append_box(
        "Crankcase Rail Right",
        "crankcase_rail",
        (0.0, 73.0, -56.0),
        (0.0, 0.0, 1.0),
        410.0,
        24.0,
        30.0,
    )

    return components, cylinders


def command_for_component(component):
    if component["kind"] == "cylinder":
        return cylinder_command(component)
    if component["kind"] == "box":
        return box_command(component)
    raise ValueError(f"Unsupported component kind: {component['kind']}")


def component_json(component):
    result = {
        "kind": component["kind"],
        "name": component["name"],
        "category": component["category"],
        "centerMillimeters": vector_json(component["center"]),
    }
    if component["kind"] == "cylinder":
        result.update({
            "axis": vector_json(component["axis"]),
            "radiusMillimeters": component["radius"],
            "lengthMillimeters": component["length"],
        })
    else:
        result.update({
            "normal": vector_json(component["normal"]),
            "widthMillimeters": component["width"],
            "heightMillimeters": component["height"],
            "depthMillimeters": component["depth"],
        })
    if "metadata" in component:
        result["metadata"] = component["metadata"]
    return result


def polygon_normal(points):
    if len(points) < 3:
        return (0.0, 0.0, 1.0)
    return normalized(cross(subtract(points[1], points[0]), subtract(points[2], points[0])))


def cylinder_polygons(component, segment_count=20):
    axis = component["axis"]
    center = component["center"]
    half_axis = scale(axis, component["length"] / 2.0)
    first_center = subtract(center, half_axis)
    second_center = add(center, half_axis)
    helper = (0.0, 0.0, 1.0) if abs(axis[2]) < 0.9 else (0.0, 1.0, 0.0)
    radial_u = normalized(cross(helper, axis))
    radial_v = cross(axis, radial_u)
    first_ring = []
    second_ring = []
    for index in range(segment_count):
        angle = 2.0 * math.pi * index / segment_count
        radial = add(
            scale(radial_u, component["radius"] * math.cos(angle)),
            scale(radial_v, component["radius"] * math.sin(angle)),
        )
        first_ring.append(add(first_center, radial))
        second_ring.append(add(second_center, radial))

    polygons = []
    for index in range(segment_count):
        next_index = (index + 1) % segment_count
        points = [
            first_ring[index],
            first_ring[next_index],
            second_ring[next_index],
            second_ring[index],
        ]
        polygons.append((points, polygon_normal(points), component["category"]))
    polygons.append((list(reversed(first_ring)), scale(axis, -1.0), component["category"]))
    polygons.append((second_ring, axis, component["category"]))
    return polygons


def box_polygons(component):
    center = component["center"]
    axes = [component["axisU"], component["axisV"], component["normal"]]
    half_lengths = [component["width"] / 2.0, component["height"] / 2.0, component["depth"] / 2.0]
    corners = {}
    for first in (-1, 1):
        for second in (-1, 1):
            for third in (-1, 1):
                signs = (first, second, third)
                point = center
                for axis, half_length, sign in zip(axes, half_lengths, signs):
                    point = add(point, scale(axis, half_length * sign))
                corners[signs] = point

    faces = []
    for axis_index in range(3):
        for sign in (-1, 1):
            other_axes = [index for index in range(3) if index != axis_index]
            sign_patterns = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            points = []
            for first, second in sign_patterns:
                signs = [0, 0, 0]
                signs[axis_index] = sign
                signs[other_axes[0]] = first
                signs[other_axes[1]] = second
                points.append(corners[tuple(signs)])
            normal = scale(axes[axis_index], sign)
            if dot(polygon_normal(points), normal) < 0.0:
                points.reverse()
            faces.append((points, normal, component["category"]))
    return faces


def shade(color, normal):
    light = normalized((-0.35, -0.55, 1.0))
    brightness = 0.52 + 0.48 * max(0.0, dot(normalized(normal), light))
    return tuple(max(0, min(255, round(channel * brightness))) for channel in color)


def render_preview(components):
    view_direction = normalized((1.45, -1.75, 1.15))
    world_up = (0.0, 0.0, 1.0)
    screen_right = normalized(cross(view_direction, world_up))
    screen_up = normalized(cross(screen_right, view_direction))

    polygons = []
    projected_points = []
    for component in components:
        source_polygons = (
            cylinder_polygons(component)
            if component["kind"] == "cylinder"
            else box_polygons(component)
        )
        for points, normal, category in source_polygons:
            projected = [(dot(point, screen_right), dot(point, screen_up)) for point in points]
            depth = sum(dot(point, view_direction) for point in points) / len(points)
            polygons.append((depth, projected, normal, category))
            projected_points.extend(projected)

    minimum_x = min(point[0] for point in projected_points)
    maximum_x = max(point[0] for point in projected_points)
    minimum_y = min(point[1] for point in projected_points)
    maximum_y = max(point[1] for point in projected_points)

    width = 1600
    height = 1120
    supersampling = 2
    margin_x = 90
    title_height = 135
    bottom_margin = 85
    available_width = width - 2 * margin_x
    available_height = height - title_height - bottom_margin
    model_width = maximum_x - minimum_x
    model_height = maximum_y - minimum_y
    scale_factor = min(available_width / model_width, available_height / model_height)

    image = Image.new(
        "RGB",
        (width * supersampling, height * supersampling),
        (12, 18, 24),
    )
    draw = ImageDraw.Draw(image)

    def to_screen(point):
        x = margin_x + (point[0] - minimum_x) * scale_factor
        y = title_height + (maximum_y - point[1]) * scale_factor
        return (round(x * supersampling), round(y * supersampling))

    for _, points, normal, category in sorted(polygons, key=lambda item: item[0]):
        screen_points = [to_screen(point) for point in points]
        fill = shade(CATEGORY_COLORS[category], normal)
        draw.polygon(screen_points, fill=fill, outline=(18, 25, 31))

    try:
        title_font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 40 * supersampling)
        subtitle_font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 21 * supersampling)
        label_font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 18 * supersampling)
    except OSError:
        title_font = ImageFont.load_default()
        subtitle_font = ImageFont.load_default()
        label_font = ImageFont.load_default()

    draw.text(
        (margin_x * supersampling, 28 * supersampling),
        "Rupa Agent V8 — 4.0 L Cross-Plane Cutaway",
        fill=(236, 242, 246),
        font=title_font,
    )
    draw.text(
        (margin_x * supersampling, 80 * supersampling),
        "90° bank · 86 × 86 mm · 8 pistons · exact slider-crank rod geometry",
        fill=(155, 174, 187),
        font=subtitle_font,
    )

    legend = [
        ("Pistons", "piston"),
        ("Connecting rods", "connecting_rod"),
        ("Crankshaft", "crank_web"),
        ("Heads / case", "cylinder_deck"),
    ]
    legend_x = margin_x
    legend_y = height - 52
    for label, category in legend:
        box_x = legend_x * supersampling
        box_y = legend_y * supersampling
        draw.rounded_rectangle(
            (box_x, box_y, box_x + 24 * supersampling, box_y + 18 * supersampling),
            radius=4 * supersampling,
            fill=CATEGORY_COLORS[category],
        )
        draw.text(
            ((legend_x + 34) * supersampling, (legend_y - 3) * supersampling),
            label,
            fill=(193, 205, 214),
            font=label_font,
        )
        legend_x += 225

    image.resize((width, height), Image.Resampling.LANCZOS).save(
        OUTPUT_DIRECTORY / "v8-isometric-preview.png"
    )


def write_json(filename, value):
    with (OUTPUT_DIRECTORY / filename).open("w", encoding="utf-8") as file:
        json.dump(value, file, indent=2, ensure_ascii=False)
        file.write("\n")


def main():
    components, cylinders = build_assembly()
    commands = [command_for_component(component) for component in components]
    commands.append({"validateDocument": {}})

    displacement_cubic_centimeters = (
        math.pi
        * BORE_MILLIMETERS**2
        * STROKE_MILLIMETERS
        * 8.0
        / 4.0
        / 1000.0
    )
    left_axis = (0.0, -SQRT_HALF, SQRT_HALF)
    right_axis = (0.0, SQRT_HALF, SQRT_HALF)
    measured_bank_angle = math.degrees(math.acos(dot(left_axis, right_axis)))
    maximum_rod_residual = max(
        cylinder["connectingRodLengthResidualMillimeters"] for cylinder in cylinders
    )

    specification = {
        "artifact": "Rupa Agent V8 Cross-Plane Cutaway",
        "engineArchitecture": "90-degree cross-plane V8",
        "unit": "millimeter",
        "bore": BORE_MILLIMETERS,
        "stroke": STROKE_MILLIMETERS,
        "displacementCubicCentimeters": rounded(displacement_cubic_centimeters),
        "connectingRodLength": CONNECTING_ROD_LENGTH_MILLIMETERS,
        "cylinderPitch": CYLINDER_PITCH_MILLIMETERS,
        "bankAngleDegrees": BANK_ANGLE_DEGREES,
        "staticCrankAngleDegrees": STATIC_CRANK_ANGLE_DEGREES,
        "crossPlaneThrowPhasesDegrees": [
            rounded((phase + STATIC_CRANK_ANGLE_DEGREES) % 360.0)
            for phase in THROW_PHASES_DEGREES
        ],
        "throwStations": THROW_STATIONS_MILLIMETERS,
        "mainJournalStations": MAIN_JOURNAL_STATIONS_MILLIMETERS,
        "bankAxialOffset": BANK_AXIAL_OFFSET_MILLIMETERS,
        "componentCount": len(components),
        "components": [component_json(component) for component in components],
    }
    kinematics = {
        "method": "Exact vector slider-crank closure on each bank axis",
        "equation": "s = dot(a,q) + sqrt(L^2 - |q - dot(a,q)a|^2)",
        "measuredBankAngleDegrees": rounded(measured_bank_angle),
        "maximumConnectingRodLengthResidualMillimeters": maximum_rod_residual,
        "crossPlaneChecks": {
            "throw1ToThrow4Degrees": 180.0,
            "throw2ToThrow3Degrees": 180.0,
            "orthogonalThrowPlaneSeparationDegrees": 90.0,
        },
        "cylinders": cylinders,
    }

    write_json("create-v8-engine-batch.json", {"commands": commands})
    write_json("v8-engine-specification.json", specification)
    write_json("v8-kinematics-report.json", kinematics)
    render_preview(components)

    print(json.dumps({
        "componentCount": len(components),
        "commandCount": len(commands),
        "displacementCubicCentimeters": rounded(displacement_cubic_centimeters),
        "measuredBankAngleDegrees": rounded(measured_bank_angle),
        "maximumConnectingRodLengthResidualMillimeters": maximum_rod_residual,
    }, indent=2))


if __name__ == "__main__":
    main()
