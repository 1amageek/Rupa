#!/usr/bin/env python3

import json
import math
import uuid
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


OUTPUT_DIRECTORY = Path(__file__).resolve().parent
TOOTH_COUNT = 24
MODULE_MILLIMETERS = 2.0
PRESSURE_ANGLE_DEGREES = 20.0
FACE_WIDTH_MILLIMETERS = 12.0
BORE_DIAMETER_MILLIMETERS = 8.0
ADDENDUM_COEFFICIENT = 1.0
DEDENDUM_COEFFICIENT = 1.25
INVOLUTE_START_PARAMETER = 0.05
INVOLUTE_SEGMENT_COUNT = 3
PROFILE_SAMPLE_COUNT_PER_CURVE = 32


def involute_function(value):
    return value - math.atan(value)


def rotate(point, angle):
    cosine = math.cos(angle)
    sine = math.sin(angle)
    return (
        point[0] * cosine - point[1] * sine,
        point[0] * sine + point[1] * cosine,
    )


def involute_point(base_radius, parameter, rotation):
    cosine = math.cos(parameter)
    sine = math.sin(parameter)
    point = (
        base_radius * (cosine + parameter * sine),
        base_radius * (sine - parameter * cosine),
    )
    return rotate(point, rotation)


def involute_derivative(base_radius, parameter, rotation):
    derivative = (
        base_radius * parameter * math.cos(parameter),
        base_radius * parameter * math.sin(parameter),
    )
    return rotate(derivative, rotation)


def add(left, right):
    return (left[0] + right[0], left[1] + right[1])


def subtract(left, right):
    return (left[0] - right[0], left[1] - right[1])


def scale(point, factor):
    return (point[0] * factor, point[1] * factor)


def cubic_bezier(point0, point1, point2, point3, parameter):
    inverse = 1.0 - parameter
    return (
        inverse**3 * point0[0]
        + 3.0 * inverse**2 * parameter * point1[0]
        + 3.0 * inverse * parameter**2 * point2[0]
        + parameter**3 * point3[0],
        inverse**3 * point0[1]
        + 3.0 * inverse**2 * parameter * point1[1]
        + 3.0 * inverse * parameter**2 * point2[1]
        + parameter**3 * point3[1],
    )


def cubic_involute_controls(base_radius, start, end, rotation):
    point0 = involute_point(base_radius, start, rotation)
    point3 = involute_point(base_radius, end, rotation)
    derivative0 = involute_derivative(base_radius, start, rotation)
    derivative1 = involute_derivative(base_radius, end, rotation)
    interval = end - start
    return (
        point0,
        add(point0, scale(derivative0, interval / 3.0)),
        subtract(point3, scale(derivative1, interval / 3.0)),
        point3,
    )


def involute_control_chain(base_radius, start, end, rotation):
    controls = []
    for index in range(INVOLUTE_SEGMENT_COUNT):
        segment_start = start + (end - start) * index / INVOLUTE_SEGMENT_COUNT
        segment_end = start + (end - start) * (index + 1) / INVOLUTE_SEGMENT_COUNT
        segment = cubic_involute_controls(
            base_radius,
            segment_start,
            segment_end,
            rotation,
        )
        if controls:
            controls.extend(segment[1:])
        else:
            controls.extend(segment)
    return controls


def polar(radius, angle):
    return (radius * math.cos(angle), radius * math.sin(angle))


def transformed(points, angle):
    return [rotate(point, angle) for point in points]


def length_expression(millimeters):
    return {
        "kind": "constant",
        "quantity": {
            "value": millimeters / 1000.0,
            "kind": "length",
        },
    }


def angle_expression(radians):
    return {
        "kind": "constant",
        "quantity": {
            "value": radians,
            "kind": "angle",
        },
    }


def sketch_point(point):
    return {
        "x": length_expression(point[0]),
        "y": length_expression(point[1]),
    }


def identifier(index):
    return str(uuid.UUID(int=0x1000 + index)).upper()


def build_profile():
    pitch_radius = MODULE_MILLIMETERS * TOOTH_COUNT / 2.0
    pressure_angle = math.radians(PRESSURE_ANGLE_DEGREES)
    base_radius = pitch_radius * math.cos(pressure_angle)
    addendum_radius = pitch_radius + ADDENDUM_COEFFICIENT * MODULE_MILLIMETERS
    dedendum_radius = pitch_radius - DEDENDUM_COEFFICIENT * MODULE_MILLIMETERS
    pitch_parameter = math.sqrt((pitch_radius / base_radius) ** 2 - 1.0)
    addendum_parameter = math.sqrt((addendum_radius / base_radius) ** 2 - 1.0)
    half_tooth_angle = math.pi / (2.0 * TOOTH_COUNT)
    flank_rotation = half_tooth_angle + involute_function(pitch_parameter)
    base_half_angle = flank_rotation - involute_function(INVOLUTE_START_PARAMETER)
    tip_half_angle = flank_rotation - involute_function(addendum_parameter)
    tooth_pitch_angle = 2.0 * math.pi / TOOTH_COUNT

    right_controls = involute_control_chain(
        base_radius,
        INVOLUTE_START_PARAMETER,
        addendum_parameter,
        -flank_rotation,
    )
    left_controls_forward = [(point[0], -point[1]) for point in right_controls]
    left_controls_reverse = list(reversed(left_controls_forward))

    entities = {}
    entity_order = []
    entity_index = 1

    def append_entity(entity):
        nonlocal entity_index
        entity_id = identifier(entity_index)
        entity_index += 1
        entities[entity_id] = entity
        entity_order.append(entity_id)

    for tooth_index in range(TOOTH_COUNT):
        center_angle = tooth_index * tooth_pitch_angle
        next_center_angle = (tooth_index + 1) * tooth_pitch_angle
        root_right = polar(dedendum_radius, center_angle - base_half_angle)
        root_left = polar(dedendum_radius, center_angle + base_half_angle)
        rotated_right_controls = transformed(right_controls, center_angle)
        rotated_left_controls = transformed(left_controls_reverse, center_angle)

        append_entity({
            "kind": "line",
            "line": {
                "start": sketch_point(root_right),
                "end": sketch_point(rotated_right_controls[0]),
            },
        })
        append_entity({
            "kind": "spline",
            "spline": {
                "controlPoints": [sketch_point(point) for point in rotated_right_controls],
                "isClosed": False,
            },
        })
        append_entity({
            "kind": "arc",
            "arc": {
                "center": sketch_point((0.0, 0.0)),
                "radius": length_expression(addendum_radius),
                "startAngle": angle_expression(center_angle - tip_half_angle),
                "endAngle": angle_expression(center_angle + tip_half_angle),
            },
        })
        append_entity({
            "kind": "spline",
            "spline": {
                "controlPoints": [sketch_point(point) for point in rotated_left_controls],
                "isClosed": False,
            },
        })
        append_entity({
            "kind": "line",
            "line": {
                "start": sketch_point(rotated_left_controls[-1]),
                "end": sketch_point(root_left),
            },
        })
        append_entity({
            "kind": "arc",
            "arc": {
                "center": sketch_point((0.0, 0.0)),
                "radius": length_expression(dedendum_radius),
                "startAngle": angle_expression(center_angle + base_half_angle),
                "endAngle": angle_expression(next_center_angle - base_half_angle),
            },
        })

    append_entity({
        "kind": "circle",
        "circle": {
            "center": sketch_point((0.0, 0.0)),
            "radius": length_expression(BORE_DIAMETER_MILLIMETERS / 2.0),
        },
    })

    encoded_entities = []
    for entity_id in entity_order:
        encoded_entities.extend([entity_id, entities[entity_id]])

    sketch = {
        "id": identifier(0),
        "plane": {"kind": "xy"},
        "entities": encoded_entities,
        "entityOrder": entity_order,
        "constraints": [],
        "dimensions": [],
    }
    command = {
        "createSketch": {
            "name": "Agent Involute Spur Gear Profile",
            "sketch": sketch,
            "geometryRole": "sketchProfile",
        },
    }

    maximum_deviation = 0.0
    segment_interval = (
        addendum_parameter - INVOLUTE_START_PARAMETER
    ) / INVOLUTE_SEGMENT_COUNT
    for segment_index in range(INVOLUTE_SEGMENT_COUNT):
        start = INVOLUTE_START_PARAMETER + segment_interval * segment_index
        end = start + segment_interval
        controls = cubic_involute_controls(base_radius, start, end, -flank_rotation)
        for sample_index in range(PROFILE_SAMPLE_COUNT_PER_CURVE + 1):
            local_parameter = sample_index / PROFILE_SAMPLE_COUNT_PER_CURVE
            exact_parameter = start + (end - start) * local_parameter
            exact = involute_point(base_radius, exact_parameter, -flank_rotation)
            approximation = cubic_bezier(*controls, local_parameter)
            maximum_deviation = max(
                maximum_deviation,
                math.hypot(exact[0] - approximation[0], exact[1] - approximation[1]),
            )

    outline = []
    for tooth_index in range(TOOTH_COUNT):
        center_angle = tooth_index * tooth_pitch_angle
        next_center_angle = (tooth_index + 1) * tooth_pitch_angle
        outline.append(polar(dedendum_radius, center_angle - base_half_angle))
        for sample_index in range(PROFILE_SAMPLE_COUNT_PER_CURVE + 1):
            parameter = INVOLUTE_START_PARAMETER + (
                addendum_parameter - INVOLUTE_START_PARAMETER
            ) * sample_index / PROFILE_SAMPLE_COUNT_PER_CURVE
            outline.append(
                rotate(
                    involute_point(base_radius, parameter, -flank_rotation),
                    center_angle,
                )
            )
        for sample_index in range(1, PROFILE_SAMPLE_COUNT_PER_CURVE + 1):
            angle = center_angle - tip_half_angle + 2.0 * tip_half_angle * (
                sample_index / PROFILE_SAMPLE_COUNT_PER_CURVE
            )
            outline.append(polar(addendum_radius, angle))
        for sample_index in range(1, PROFILE_SAMPLE_COUNT_PER_CURVE + 1):
            parameter = addendum_parameter - (
                addendum_parameter - INVOLUTE_START_PARAMETER
            ) * sample_index / PROFILE_SAMPLE_COUNT_PER_CURVE
            point = involute_point(base_radius, parameter, -flank_rotation)
            outline.append(rotate((point[0], -point[1]), center_angle))
        outline.append(polar(dedendum_radius, center_angle + base_half_angle))
        for sample_index in range(1, PROFILE_SAMPLE_COUNT_PER_CURVE + 1):
            angle = center_angle + base_half_angle + (
                next_center_angle - base_half_angle - center_angle - base_half_angle
            ) * sample_index / PROFILE_SAMPLE_COUNT_PER_CURVE
            outline.append(polar(dedendum_radius, angle))

    doubled_area = 0.0
    for index, point in enumerate(outline):
        next_point = outline[(index + 1) % len(outline)]
        doubled_area += point[0] * next_point[1] - point[1] * next_point[0]
    outer_area = abs(doubled_area) / 2.0
    bore_area = math.pi * (BORE_DIAMETER_MILLIMETERS / 2.0) ** 2
    material_area = outer_area - bore_area

    specification = {
        "schema": "rupa.agent.spur-gear.v1",
        "model": "external involute spur gear",
        "units": "millimeter",
        "toothCount": TOOTH_COUNT,
        "module": MODULE_MILLIMETERS,
        "pressureAngleDegrees": PRESSURE_ANGLE_DEGREES,
        "faceWidth": FACE_WIDTH_MILLIMETERS,
        "boreDiameter": BORE_DIAMETER_MILLIMETERS,
        "pitchDiameter": pitch_radius * 2.0,
        "baseDiameter": base_radius * 2.0,
        "outsideDiameter": addendum_radius * 2.0,
        "rootDiameter": dedendum_radius * 2.0,
        "circularPitch": math.pi * MODULE_MILLIMETERS,
        "nominalToothThicknessAtPitch": math.pi * MODULE_MILLIMETERS / 2.0,
        "addendumCoefficient": ADDENDUM_COEFFICIENT,
        "dedendumCoefficient": DEDENDUM_COEFFICIENT,
        "involuteCubicSegmentsPerFlank": INVOLUTE_SEGMENT_COUNT,
        "maximumSampledInvoluteDeviationMillimeters": maximum_deviation,
        "sketchEntityCount": len(entities),
        "outerBoundaryEntityCount": len(entities) - 1,
        "innerLoopCount": 1,
        "approximateMaterialAreaSquareMillimeters": material_area,
        "approximateVolumeCubicMillimeters": material_area * FACE_WIDTH_MILLIMETERS,
        "limitations": [
            "The root transition is radial rather than a generated cutter trochoid.",
            "Backlash, profile shift, crowning, helix, material, and tolerance class are not specified.",
            "The model is a validated CAD demonstration artifact, not a certified manufacturing drawing.",
        ],
    }
    return command, specification, outline, {
        "pitchRadius": pitch_radius,
        "baseRadius": base_radius,
        "addendumRadius": addendum_radius,
        "dedendumRadius": dedendum_radius,
        "baseHalfAngle": base_half_angle,
        "tipHalfAngle": tip_half_angle,
        "toothPitchAngle": tooth_pitch_angle,
        "rightControls": right_controls,
        "leftControlsReverse": left_controls_reverse,
    }


def svg_path(geometry):
    root_radius = geometry["dedendumRadius"]
    tip_radius = geometry["addendumRadius"]
    base_half_angle = geometry["baseHalfAngle"]
    tip_half_angle = geometry["tipHalfAngle"]
    tooth_pitch_angle = geometry["toothPitchAngle"]
    right_controls = geometry["rightControls"]
    left_controls_reverse = geometry["leftControlsReverse"]

    start = polar(root_radius, -base_half_angle)
    commands = [f"M {start[0]:.9f} {-start[1]:.9f}"]
    for tooth_index in range(TOOTH_COUNT):
        center_angle = tooth_index * tooth_pitch_angle
        next_center_angle = (tooth_index + 1) * tooth_pitch_angle
        right = transformed(right_controls, center_angle)
        left = transformed(left_controls_reverse, center_angle)
        commands.append(f"L {right[0][0]:.9f} {-right[0][1]:.9f}")
        for index in range(0, len(right) - 1, 3):
            commands.append(
                "C "
                f"{right[index + 1][0]:.9f} {-right[index + 1][1]:.9f} "
                f"{right[index + 2][0]:.9f} {-right[index + 2][1]:.9f} "
                f"{right[index + 3][0]:.9f} {-right[index + 3][1]:.9f}"
            )
        tip_left = polar(tip_radius, center_angle + tip_half_angle)
        commands.append(
            f"A {tip_radius:.9f} {tip_radius:.9f} 0 0 0 "
            f"{tip_left[0]:.9f} {-tip_left[1]:.9f}"
        )
        for index in range(0, len(left) - 1, 3):
            commands.append(
                "C "
                f"{left[index + 1][0]:.9f} {-left[index + 1][1]:.9f} "
                f"{left[index + 2][0]:.9f} {-left[index + 2][1]:.9f} "
                f"{left[index + 3][0]:.9f} {-left[index + 3][1]:.9f}"
            )
        root_left = polar(root_radius, center_angle + base_half_angle)
        commands.append(f"L {root_left[0]:.9f} {-root_left[1]:.9f}")
        next_root_right = polar(root_radius, next_center_angle - base_half_angle)
        commands.append(
            f"A {root_radius:.9f} {root_radius:.9f} 0 0 0 "
            f"{next_root_right[0]:.9f} {-next_root_right[1]:.9f}"
        )
    commands.append("Z")
    return " ".join(commands)


def render_isometric_preview(outline, geometry):
    width = 1800
    height = 1400
    scale_pixels_per_millimeter = 17.0
    center_x = width / 2.0
    center_y = height / 2.0 + 70.0
    half_width = FACE_WIDTH_MILLIMETERS / 2.0

    def project(point, z):
        x, y = point
        return (
            center_x + (x - y) * math.sqrt(3.0) / 2.0 * scale_pixels_per_millimeter,
            center_y
            + (x + y) * 0.5 * scale_pixels_per_millimeter
            - z * 0.9 * scale_pixels_per_millimeter,
        )

    image = Image.new("RGB", (width, height), "#0b1018")
    draw = ImageDraw.Draw(image)
    top = [project(point, half_width) for point in outline]
    bottom = [project(point, -half_width) for point in outline]

    side_faces = []
    for index, point in enumerate(outline):
        next_index = (index + 1) % len(outline)
        next_point = outline[next_index]
        edge_x = next_point[0] - point[0]
        edge_y = next_point[1] - point[1]
        length = math.hypot(edge_x, edge_y)
        if length == 0.0:
            continue
        normal_x = edge_y / length
        normal_y = -edge_x / length
        lighting = max(0.0, normal_x * -0.55 + normal_y * -0.84)
        shade = int(52 + lighting * 58)
        color = (shade, shade + 21, shade + 42)
        depth = (point[0] + point[1] + next_point[0] + next_point[1]) / 2.0
        side_faces.append((depth, [
            bottom[index],
            bottom[next_index],
            top[next_index],
            top[index],
        ], color))
    for _, polygon, color in sorted(side_faces, key=lambda item: item[0]):
        draw.polygon(polygon, fill=color)

    bore_radius = BORE_DIAMETER_MILLIMETERS / 2.0
    bore = [
        polar(bore_radius, 2.0 * math.pi * index / 160.0)
        for index in range(160)
    ]
    bore_top = [project(point, half_width) for point in bore]
    bore_bottom = [project(point, -half_width) for point in bore]
    bore_faces = []
    for index, point in enumerate(bore):
        next_index = (index + 1) % len(bore)
        next_point = bore[next_index]
        depth = (point[0] + point[1] + next_point[0] + next_point[1]) / 2.0
        bore_faces.append((depth, [
            bore_bottom[index],
            bore_bottom[next_index],
            bore_top[next_index],
            bore_top[index],
        ]))
    for _, polygon in sorted(bore_faces, key=lambda item: item[0]):
        draw.polygon(polygon, fill="#273849")

    top_mask = Image.new("L", (width, height), 0)
    top_mask_draw = ImageDraw.Draw(top_mask)
    top_mask_draw.polygon(top, fill=255)
    top_mask_draw.polygon(bore_top, fill=0)
    top_face = Image.new("RGB", (width, height), "#9fc5ec")
    image.paste(top_face, mask=top_mask)
    draw = ImageDraw.Draw(image)
    draw.line(top + [top[0]], fill="#d7eaff", width=2, joint="curve")
    draw.line(bore_top + [bore_top[0]], fill="#d7eaff", width=2)

    pitch_radius = geometry["pitchRadius"]
    pitch_points = [
        project(polar(pitch_radius, 2.0 * math.pi * index / 192.0), half_width + 0.02)
        for index in range(192)
    ]
    for index in range(0, len(pitch_points), 6):
        draw.line(
            pitch_points[index:index + 4],
            fill="#f0a84a",
            width=2,
        )

    try:
        title_font = ImageFont.truetype(
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            42,
        )
        body_font = ImageFont.truetype(
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            27,
        )
    except OSError:
        title_font = ImageFont.load_default()
        body_font = ImageFont.load_default()

    draw.text(
        (70, 60),
        "Agent Involute Spur Gear",
        fill="#f3f7fb",
        font=title_font,
    )
    details = [
        "24 teeth  |  module 2 mm  |  pressure angle 20 deg",
        "pitch diameter 48 mm  |  outside diameter 52 mm",
        "face width 12 mm  |  bore diameter 8 mm",
        "Orange dashed line: pitch circle",
    ]
    for index, detail in enumerate(details):
        draw.text(
            (72, 125 + index * 38),
            detail,
            fill="#b8c6d8" if index < 3 else "#f0a84a",
            font=body_font,
        )
    draw.text(
        (70, height - 82),
        "Preview projected from the same parametric profile used by the Rupa CAD source.",
        fill="#8495aa",
        font=body_font,
    )
    image.save(OUTPUT_DIRECTORY / "gear-isometric-preview.png", optimize=True)


def write_outputs():
    command, specification, outline, geometry = build_profile()
    command_path = OUTPUT_DIRECTORY / "create-gear-sketch.json"
    specification_path = OUTPUT_DIRECTORY / "gear-specification.json"
    preview_path = OUTPUT_DIRECTORY / "gear-profile.svg"

    command_path.write_text(
        json.dumps(command, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    specification_path.write_text(
        json.dumps(specification, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    path = svg_path(geometry)
    preview_path.write_text(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"-29 -29 58 58\" width=\"1200\" height=\"1200\">\n"
        "  <rect x=\"-29\" y=\"-29\" width=\"58\" height=\"58\" fill=\"#101722\"/>\n"
        f"  <path d=\"{path}\" fill=\"#d7e3f4\" stroke=\"#4a76a8\" stroke-width=\"0.12\" fill-rule=\"evenodd\"/>\n"
        f"  <circle cx=\"0\" cy=\"0\" r=\"{BORE_DIAMETER_MILLIMETERS / 2.0:.9f}\" fill=\"#101722\" stroke=\"#4a76a8\" stroke-width=\"0.12\"/>\n"
        f"  <circle cx=\"0\" cy=\"0\" r=\"{geometry['pitchRadius']:.9f}\" fill=\"none\" stroke=\"#e49f38\" stroke-width=\"0.08\" stroke-dasharray=\"0.5 0.5\"/>\n"
        "</svg>\n",
        encoding="utf-8",
    )
    render_isometric_preview(outline, geometry)


if __name__ == "__main__":
    write_outputs()
