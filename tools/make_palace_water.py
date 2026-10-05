"""Makes the meshes of the mod "Vivec Palace Water" from the game's own meshes.

The water of the Palace of Vivec is one static, Ex_Vivec_P_water_01: four flat sheets, one
for each tier, each carried twice. The new mesh has, for each tier, one closed body of water
that fills the channel of that tier, deep enough to swim in. Its top, and the sides that show
in the openings of the parapet, are the shape WaterVolume. The rest of its sides and its
bottom are the shape WaterBody, which the game does not draw.

The waterfalls of Vivec get the name that makes them water to look at and not to swim in.

    python make_palace_water.py <Data Files of the game> [<folder of the mod>]

The outlines of the tiers are in palace_outlines.json; palace_outlines_from_scan.py made them.
"""
import copy
import json
import math
import os
import sys

import nif4

HERE = os.path.dirname(os.path.abspath(__file__))
PALACE = "Ex_Vivec_P_water_01"
FALLS = ["Ex_Vivec_waterfall_01", "Ex_Vivec_waterfall_03", "Ex_Vivec_waterfall_05"]
# How far the body reaches below the floor of a channel.
UNDER_FLOOR = 12


def triangulate(points):
    """Cuts a polygon without holes, given counter-clockwise, into triangles."""
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    left = list(range(len(points)))
    triangles = []
    while len(left) > 3:
        for k in range(len(left)):
            i, j, l = left[k - 1], left[k], left[(k + 1) % len(left)]
            a, b, c = points[i], points[j], points[l]
            if cross(a, b, c) <= 1e-9:
                continue
            if any(m not in (i, j, l) and cross(a, b, points[m]) >= 0 and cross(b, c, points[m]) >= 0 and cross(c, a, points[m]) >= 0 for m in left):
                continue
            triangles.append([i, j, l])
            del left[k]
            break
        else:
            raise ValueError("the outline cannot be cut into triangles")
    triangles.append(left)
    return triangles


def wall(p, q, top, bottom):
    """One upright face from p to q of a counter-clockwise outline, seen from outside."""
    length = math.hypot(q[0] - p[0], q[1] - p[1])
    normal = [(q[1] - p[1]) / length, -(q[0] - p[0]) / length, 0.0]
    return [[p[0], p[1], top], [p[0], p[1], bottom], [q[0], q[1], bottom], [q[0], q[1], top]], [normal] * 4


def add_face(target, corners, normals):
    first = len(target["vertices"])
    target["vertices"] += corners
    target["normals"] += normals
    target["triangles"] += [[first, first + 1, first + 2], [first, first + 2, first + 3]]


def palace(source, target):
    blocks = nif4.read(source)
    root = blocks[0]
    sheet = next(b for b in blocks if b["type"] == "NiTriShape" and b["name"] == "Tri " + PALACE)
    data = blocks[sheet["data"]]
    # The heights of the vanilla sheets, lowest first, in the mesh.
    heights = sorted(set(round(v[2] + sheet["translation"][2], 3) for v in data["vertices"]))
    outlines = json.load(open(os.path.join(HERE, "palace_outlines.json")))
    assert len(heights) == len(outlines["tiers"])

    surface = {"vertices": [], "normals": [], "triangles": []}
    body = {"vertices": [], "normals": [], "triangles": []}
    for height, tier in zip(heights, outlines["tiers"]):
        # The static is turned half a circle, so a point against it has both signs changed in the mesh.
        points = [(-x, -y) for x, y in tier["outline"]]
        top = height + tier["raise"]
        bottom = height + tier["floor"] - UNDER_FLOOR
        triangles = triangulate(points)
        first = len(surface["vertices"])
        surface["vertices"] += [[p[0], p[1], top] for p in points]
        surface["normals"] += [[0.0, 0.0, 1.0]] * len(points)
        surface["triangles"] += [[first + a, first + b, first + c] for a, b, c in triangles]
        first = len(body["vertices"])
        body["vertices"] += [[p[0], p[1], bottom] for p in points]
        body["normals"] += [[0.0, 0.0, -1.0]] * len(points)
        body["triangles"] += [[first + a, first + c, first + b] for a, b, c in triangles]
        for k in range(len(points)):
            corners, normals = wall(points[k], points[(k + 1) % len(points)], top, bottom)
            add_face(surface if k in tier["openEdges"] else body, corners, normals)
        print("  tier %d: water at %.1f in the world, %d above the vanilla water, %d deep; %d corners, %d sides that show"
              % (tier["tier"], outlines["origin"][2] + top, tier["raise"], tier["raise"] - tier["floor"], len(points), len(tier["openEdges"])))

    # The texture lies on the new sheets as it lay on the old: flat, from above.
    old = [[v[0] + sheet["translation"][0], v[1] + sheet["translation"][1]] for v in data["vertices"]]
    uv = data["uv"][0]
    a, b = old[0], max(old, key=lambda p: abs(p[0] - old[0][0]))
    c = max(old, key=lambda p: abs(p[1] - old[0][1]))
    u_per_x = (uv[old.index(b)][0] - uv[0][0]) / (b[0] - a[0])
    v_per_y = (uv[old.index(c)][1] - uv[0][1]) / (c[1] - a[1])
    surface_uv = [[uv[0][0] + (v[0] - a[0]) * u_per_x, uv[0][1] + (v[1] - a[1]) * v_per_y] for v in surface["vertices"]]

    def shape_data(part, uv_set):
        center, radius = nif4.bounds(part["vertices"])
        return {"type": "NiTriShapeData", "vertices": part["vertices"], "normals": part["normals"], "center": center, "radius": radius, "colors": [],
                "uv": [uv_set] if uv_set else [], "triangles": part["triangles"], "matchGroups": []}

    def named(kind, **fields):
        block = {"type": kind, "name": "", "extra": None, "controller": None}
        block.update(fields)
        return block

    def shape(name, properties, part, uv_set=None):
        return {"type": "NiTriShape", "name": name, "extra": None, "controller": None, "flags": sheet["flags"], "translation": [0.0, 0.0, 0.0],
                "rotation": [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0], "scale": 1.0, "velocity": [0.0, 0.0, 0.0], "properties": properties,
                "data": shape_data(part, uv_set), "skin": None}

    both_sides = {"flags": 0, "enabled": 0, "function": 4, "ref": 0, "mask": 0xFFFFFFFF, "fail": 0, "zFail": 0, "pass": 3, "drawMode": 3}
    # The sheet keeps the look of the vanilla sheet: its texture, which moves, and its material.
    looks = [copy.deepcopy(blocks[p]) for p in sheet["properties"]]
    texture = None
    for look in looks:
        if look["type"] == "NiTexturingProperty":
            texture = copy.deepcopy(blocks[look["slots"][0]["source"]])
            look["slots"][0]["source"] = texture
    water = shape("WaterVolume", looks + [named("NiStencilProperty", **both_sides)], surface, surface_uv)
    mover = copy.deepcopy(blocks[sheet["controller"]])
    mover_data = copy.deepcopy(blocks[mover["data"]])
    mover["target"], mover["data"] = water, mover_data
    water["controller"] = mover
    # The body shows in the Construction Set only, as clear blue.
    body_looks = [
        named("NiMaterialProperty", flags=1, ambient=[1.0, 1.0, 1.0], diffuse=[1.0, 1.0, 1.0], specular=[0.0, 0.0, 0.0], emissive=[0.3, 0.5, 0.9], glossiness=10.0, alpha=0.35),
        named("NiAlphaProperty", flags=0x00ED, threshold=255),
        named("NiZBufferProperty", flags=1),
        named("NiStencilProperty", **both_sides),
    ]
    hidden = shape("WaterBody", body_looks, body)

    new_root = copy.deepcopy(root)
    note = copy.deepcopy(blocks[root["extra"]])
    new_root["extra"] = note
    new_root["children"] = [water, hidden]
    out = [new_root, note, water, mover, mover_data] + looks + [texture, water["properties"][-1], water["data"], hidden] + body_looks + [hidden["data"]]
    nif4.write(target, out)
    print("  %s: %d triangles of surface, %d of body" % (os.path.basename(target), len(surface["triangles"]), len(body["triangles"])))


def fall(source, target, name):
    """The mesh as it is, with the name that makes it water that holds none."""
    blocks = nif4.read(source)
    front = next(b for b in blocks if b["type"] == "NiTriShape" and b["name"].lower() == ("Tri " + name).lower())
    front["name"] = "WaterVolume noswim"
    nif4.write(target, blocks)
    print("  %s: the shape %r is now %r" % (os.path.basename(target), "Tri " + name, front["name"]))


def main():
    game = sys.argv[1]
    mod = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "..", "demo", "Vivec Palace Water")
    meshes = os.path.join(mod, "meshes", "x")
    os.makedirs(meshes, exist_ok=True)
    palace(os.path.join(game, "meshes", "x", PALACE + ".nif"), os.path.join(meshes, PALACE + ".nif"))
    for name in FALLS:
        fall(os.path.join(game, "meshes", "x", name + ".nif"), os.path.join(meshes, name + ".nif"), name)


if __name__ == "__main__":
    main()
