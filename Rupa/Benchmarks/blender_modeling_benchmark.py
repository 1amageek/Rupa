import argparse
import json
import math
import sys
import time

import bpy


def parse_arguments():
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--body-count", type=int, default=100)
    parser.add_argument("--iterations", type=int, default=7)
    parser.add_argument("--warmups", type=int, default=2)
    options = parser.parse_args(arguments)
    if options.body_count <= 0 or options.iterations <= 0 or options.warmups < 0:
        parser.error("benchmark counts must be positive")
    return options


def clear_scene():
    for object_value in list(bpy.data.objects):
        bpy.data.objects.remove(object_value, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def cube_geometry():
    vertices = [
        (-0.01, -0.005, 0.0),
        (0.01, -0.005, 0.0),
        (0.01, 0.005, 0.0),
        (-0.01, 0.005, 0.0),
        (-0.01, -0.005, 0.01),
        (0.01, -0.005, 0.01),
        (0.01, 0.005, 0.01),
        (-0.01, 0.005, 0.01),
    ]
    faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    return vertices, faces


def create_boxes(body_count):
    vertices, faces = cube_geometry()
    objects = []
    collection = bpy.context.scene.collection
    for index in range(body_count):
        mesh = bpy.data.meshes.new(f"Body {index} Mesh")
        mesh.from_pydata(vertices, [], faces)
        mesh.update(calc_edges=True)
        object_value = bpy.data.objects.new(f"Body {index}", mesh)
        collection.objects.link(object_value)
        objects.append(object_value)
    bpy.context.view_layer.update()
    return objects


def measure_create(body_count):
    clear_scene()
    start = time.perf_counter()
    objects = create_boxes(body_count)
    elapsed = time.perf_counter() - start
    if len(objects) != body_count:
        raise RuntimeError("unexpected Blender object count")
    return elapsed


def measure_edit(body_count):
    clear_scene()
    objects = create_boxes(body_count)
    mesh = objects[-1].data
    start = time.perf_counter()
    for vertex in mesh.vertices:
        if vertex.co.z > 0.0:
            vertex.co.z = 0.012
    mesh.update(calc_edges=True)
    bpy.context.view_layer.update()
    return time.perf_counter() - start


def percentile(values, fraction):
    ordered = sorted(values)
    rank = max(0, min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1))
    return ordered[rank]


def statistics_for(samples):
    return {
        "minimum": min(samples),
        "median": percentile(samples, 0.5),
        "p95": percentile(samples, 0.95),
        "maximum": max(samples),
        "samples": samples,
    }


def main():
    options = parse_arguments()
    for _ in range(options.warmups):
        measure_create(options.body_count)
        measure_edit(options.body_count)

    create_samples = [measure_create(options.body_count) for _ in range(options.iterations)]
    edit_samples = [measure_edit(options.body_count) for _ in range(options.iterations)]
    report = {
        "schemaVersion": 1,
        "engine": "blender",
        "unit": "seconds",
        "bodyCount": options.body_count,
        "iterationCount": options.iterations,
        "workloads": [
            {"name": "create_bodies", "statistics": statistics_for(create_samples)},
            {"name": "edit_one_body", "statistics": statistics_for(edit_samples)},
        ],
    }
    print("RUPA_BENCHMARK_JSON_BEGIN")
    print(json.dumps(report, indent=2, sort_keys=True))
    print("RUPA_BENCHMARK_JSON_END")


if __name__ == "__main__":
    main()
