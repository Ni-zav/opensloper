# OpenSloper - parametric sewing pattern drafting
# Copyright (C) 2026 The OpenSloper authors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

"""Drapes an OpenSloper drape export in Blender's cloth simulation.

opensloper-cli drape writes this script beside the scene file it reads
(NAME.blender.py beside NAME.blender.json). Run it with Blender:

    blender --background --python NAME.blender.py

It imports the pieces and the body, joins each pattern's pieces into one cloth
object with a loose edge between every pair of vertices a seam sews, holds the
vertices of attached edges on the body (or where they are placed, without
one), sets up the cloth and collisions, runs the simulation and saves
NAME.blend, at its last frame. Options go after "--":

    blender --background --python NAME.blender.py -- --frames 80 --output dress.blend

Written for Blender 5.2; other versions may differ.
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Vector

BLENDER_VERSION = (5, 2)
SCENE_FORMAT = "blender"
SCENE_VERSION = 1
SCRIPT_SUFFIX = ".blender.py"
SCENE_SUFFIX = ".blender.json"
# The export is in mm; Blender works in metres
METRES_PER_MM = 0.001
DEFAULT_FRAMES = 120
# The seams close with no gravity first, so the pieces do not fall before they
# are sewn round the body
SEWING_FRAMES = 40
# Blender's mass is per vertex, in kg; its stiffnesses are tuned for its default
DEFAULT_MASS = 0.3
# How close cloth comes to the body and to itself, in metres
COLLISION_DISTANCE = 0.003
SELF_COLLISION_DISTANCE = 0.002
BODY_THICKNESS = 0.004
BODY_FRICTION = 5
CLOTH_QUALITY = 5
COLLISION_QUALITY = 3
# Stiffness of the fabric's stretch, shear and bending, as Blender's cotton
TENSION_STIFFNESS = 15
SHEAR_STIFFNESS = 5
BENDING_STIFFNESS = 0.5
# The most force a sewing edge pulls with; 0 has no limit
SEWING_FORCE = 5
BODY_COLOR = (0.89, 0.84, 0.77, 1)
# The vertex group of the vertices held to the body, or where they are placed
# when there is no body: the cloth's pin group
ATTACHED_GROUP = "Attached"
# How far off the body's surface the attached vertices are held, in metres
ATTACHED_OFFSET = COLLISION_DISTANCE + BODY_THICKNESS
PROGRESS_PREFIX = "OpenSloper:"


def report(text):
    """A line the drape app and the command line show as progress."""
    print(PROGRESS_PREFIX, text, flush=True)


def arguments():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    script = os.path.abspath(__file__)
    scene = script[: -len(SCRIPT_SUFFIX)] + SCENE_SUFFIX if script.endswith(SCRIPT_SUFFIX) else None
    parser = argparse.ArgumentParser(prog="blender --background --python " + os.path.basename(script) + " --")
    parser.add_argument("--scene", default=scene, help="the scene file (default: the one named like this script)")
    parser.add_argument("--frames", type=int, default=DEFAULT_FRAMES, help="frames to simulate")
    parser.add_argument("--mass", type=float, default=DEFAULT_MASS, help="kg per vertex")
    parser.add_argument("--sewing-frames", type=int, default=SEWING_FRAMES, help="frames sewn before gravity comes on")
    parser.add_argument("--quality", type=int, default=CLOTH_QUALITY, help="cloth steps per frame")
    parser.add_argument("--sewing-force", type=float, default=SEWING_FORCE, help="the most a sewing edge pulls with; 0 for no limit")
    parser.add_argument("--output", help="the .blend file to save (default: beside the scene file)")
    parser.add_argument("--no-simulate", action="store_true", help="set up the scene only")
    options = parser.parse_args(argv)
    if not options.scene:
        parser.error("give --scene")
    if not options.output:
        base = options.scene[: -len(SCENE_SUFFIX)] if options.scene.endswith(SCENE_SUFFIX) else os.path.splitext(options.scene)[0]
        options.output = base + ".blend"
    return options


def read_scene(path):
    with open(path, encoding="utf-8") as file:
        scene = json.load(file)
    if scene.get("format") != SCENE_FORMAT:
        raise SystemExit(f"{path} is not an OpenSloper Blender scene")
    if scene.get("version", 0) > SCENE_VERSION:
        raise SystemExit(f"{path} is a newer version than this script reads; export the drape again")
    return scene


def import_obj(path):
    """The objects the OBJ file holds, by name, in mm with the drape's axes."""
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=path, forward_axis="Y", up_axis="Z", use_split_objects=True)
    return {item.name: item for item in bpy.data.objects if item not in before}


def find_imported(imported, name):
    # Blender keeps names to 63 bytes
    found = imported.get(name)
    if found is None:
        short = name.encode("utf-8")[:63].decode("utf-8", "ignore")
        found = imported.get(short)
    if found is None:
        raise SystemExit(f"The pieces' OBJ file has no object {name}")
    return found


def material_for(name, color, cache):
    key = (name, color)
    if key not in cache:
        material = bpy.data.materials.new(name or "Fabric")
        rgb = [int(color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
        linear = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4 for channel in rgb]
        material.diffuse_color = (*linear, 1)
        if material.node_tree is not None:
            shader = material.node_tree.nodes.get("Principled BSDF")
            if shader is not None:
                shader.inputs["Base Color"].default_value = (*linear, 1)
                shader.inputs["Roughness"].default_value = 0.9
        cache[key] = material
    return cache[key]


def build_garment(name, indexes, scene, imported, materials):
    """One mesh of the pattern's pieces, as placed, with its seams' sewing edges."""
    vertices, faces, face_uvs, face_materials = [], [], [], []
    starts = {}
    groups = []
    attached = []
    slots = []
    for index in indexes:
        entry = scene["objects"][index]
        piece = find_imported(imported, entry["name"]).data
        if len(piece.vertices) != entry["vertices"]:
            raise SystemExit(f"{entry['name']} has {len(piece.vertices)} vertices, not {entry['vertices']}: export the drape again")
        turn = Euler([math.radians(angle) for angle in entry["rotation"]], "XYZ").to_matrix()
        position = Vector(entry["position"])
        starts[index] = len(vertices)
        groups.append((entry["name"], range(len(vertices), len(vertices) + len(piece.vertices))))
        attached.extend(len(vertices) + vertex for vertex in entry.get("attached", []))
        vertices.extend((turn @ vertex.co + position) * METRES_PER_MM for vertex in piece.vertices)
        material = material_for(entry.get("material", ""), entry["color"], materials)
        if material not in slots:
            slots.append(material)
        uv_layer = piece.uv_layers.active
        for polygon in piece.polygons:
            faces.append([starts[index] + vertex for vertex in polygon.vertices])
            face_uvs.append([uv_layer.data[loop].uv.copy() for loop in polygon.loop_indices] if uv_layer else None)
            face_materials.append(slots.index(material))
    edges = []
    for seam in scene["seams"]:
        for pair in seam["pairs"]:
            if pair["first"] in starts and pair["second"] in starts:
                edges.append((starts[pair["first"]] + pair["firstVertex"], starts[pair["second"]] + pair["secondVertex"]))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, edges, faces)
    uv_layer = mesh.uv_layers.new(name="Fabric")
    for polygon, uvs in zip(mesh.polygons, face_uvs):
        polygon.use_smooth = True
        if uvs:
            for loop, uv in zip(polygon.loop_indices, uvs):
                uv_layer.data[loop].uv = uv
    for material in slots:
        mesh.materials.append(material)
    mesh.polygons.foreach_set("material_index", face_materials)
    mesh.update()
    garment = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(garment)
    for group_name, members in groups:
        group = garment.vertex_groups.new(name=group_name)
        group.add(list(members), 1.0, "REPLACE")
    if attached:
        garment.vertex_groups.new(name=ATTACHED_GROUP).add(attached, 1.0, "REPLACE")
    return garment, len(edges), len(attached)


def add_cloth(garment, options, others, body):
    attached = ATTACHED_GROUP in garment.vertex_groups
    # Attached vertices start on the body, where the shrinkwrap puts them, and
    # stay there: the cloth pins what the modifiers before it give
    if attached and body is not None:
        wrap = garment.modifiers.new("Attach", "SHRINKWRAP")
        wrap.target = body
        wrap.vertex_group = ATTACHED_GROUP
        wrap.wrap_method = "NEAREST_SURFACEPOINT"
        wrap.wrap_mode = "OUTSIDE_SURFACE"
        wrap.offset = ATTACHED_OFFSET
    cloth = garment.modifiers.new("Cloth", "CLOTH")
    settings = cloth.settings
    if attached:
        settings.vertex_group_mass = ATTACHED_GROUP
    settings.mass = options.mass
    settings.quality = options.quality
    settings.tension_stiffness = TENSION_STIFFNESS
    settings.compression_stiffness = TENSION_STIFFNESS
    settings.shear_stiffness = SHEAR_STIFFNESS
    settings.bending_stiffness = BENDING_STIFFNESS
    settings.use_sewing_springs = True
    settings.sewing_force_max = options.sewing_force
    collisions = cloth.collision_settings
    collisions.use_collision = True
    collisions.collision_quality = COLLISION_QUALITY
    collisions.distance_min = COLLISION_DISTANCE
    collisions.use_self_collision = True
    collisions.self_distance_min = SELF_COLLISION_DISTANCE
    weights = settings.effector_weights
    weights.gravity = 0
    weights.keyframe_insert("gravity", frame=1)
    weights.keyframe_insert("gravity", frame=max(1, options.sewing_frames))
    weights.gravity = 1
    weights.keyframe_insert("gravity", frame=options.sewing_frames + 1)
    cloth.point_cache.frame_start = 1
    cloth.point_cache.frame_end = options.frames
    # Several patterns, a top over a skirt, push each other away
    if others:
        garment.modifiers.new("Collision", "COLLISION")


def add_body(path):
    imported = import_obj(path)
    body = next(iter(imported.values()))
    body.name = "Body"
    body.data.transform(Matrix.Scale(METRES_PER_MM, 4))
    for polygon in body.data.polygons:
        polygon.use_smooth = True
    material = bpy.data.materials.new("Body")
    material.diffuse_color = BODY_COLOR
    body.data.materials.append(material)
    body.modifiers.new("Collision", "COLLISION")
    body.collision.thickness_outer = BODY_THICKNESS
    body.collision.cloth_friction = BODY_FRICTION
    return body


def add_view():
    """A light and a camera in front, so the file opens on something to see."""
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.rotation_euler = Euler((math.radians(50), 0, math.radians(-30)), "XYZ")
    bpy.context.scene.collection.objects.link(sun)
    camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    camera.location = (0, -4.5, 1.1)
    camera.rotation_euler = Euler((math.radians(90), 0, 0), "XYZ")
    camera.data.lens = 50
    bpy.context.scene.collection.objects.link(camera)
    bpy.context.scene.camera = camera


def main():
    if bpy.app.version[:2] != BLENDER_VERSION:
        report(f"written for Blender {BLENDER_VERSION[0]}.{BLENDER_VERSION[1]}; this is {bpy.app.version_string}, so it may not work")
    options = arguments()
    scene = read_scene(options.scene)
    folder = os.path.dirname(os.path.abspath(options.scene))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.length_unit = "MILLIMETERS"
    report("importing the pieces")
    imported = import_obj(os.path.join(folder, scene["pieces"]))
    body = add_body(os.path.join(folder, scene["body"])) if "body" in scene else None
    by_source = {}
    for index, entry in enumerate(scene["objects"]):
        by_source.setdefault(entry["source"], []).append(index)
    materials = {}
    garments = []
    for indexes in by_source.values():
        name = scene["objects"][indexes[0]]["name"].rsplit(" ", 2)[0] if len(by_source) > 1 else scene.get("name") or "Garment"
        garment, sewn, held = build_garment(name, indexes, scene, imported, materials)
        report(f"{name}: {len(garment.data.vertices)} vertices, {sewn} sewing edges, {held} attached")
        garments.append(garment)
    for item in imported.values():
        bpy.data.objects.remove(item)
    for garment in garments:
        add_cloth(garment, options, len(garments) > 1, body)
    add_view()
    target = bpy.context.scene
    target.frame_start = 1
    target.frame_end = options.frames
    if not options.no_simulate:
        for frame in range(1, options.frames + 1):
            target.frame_set(frame)
            report(f"frame {frame} of {options.frames}")
        bake_from_memory(garments)
    output = os.path.abspath(options.output)
    bpy.ops.wm.save_as_mainfile(filepath=output)
    report(f"saved {output}")


def bake_from_memory(garments):
    """Keeps the frames simulated, so the saved file shows them without simulating again."""
    for garment in garments:
        cache = garment.modifiers["Cloth"].point_cache
        with bpy.context.temp_override(point_cache=cache):
            bpy.ops.ptcache.bake_from_cache()


if __name__ == "__main__":
    main()
