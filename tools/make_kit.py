#!/usr/bin/env python3
"""Builds the Water Volumes kit: the meshes, the list of pieces, and the plugin.

This script is the one place where the pieces of the kit are defined. It writes

    Water Volumes/meshes/wv/<piece>.nif              one mesh per piece
    Water Volumes/MWSE/mods/waterVolumes/kit.json    the pieces, their sizes and their joints
    Water Volumes/Water Volumes Kit.esp              one Static per piece

Usage:
    python make_kit.py <Morrowind.esm>

A palette is the whole kit again in one colour of water: the meshes in a folder of their own,
Water Volumes/meshes/wv<letter>/, and one Static per piece with the name of the palette in
its id. The palettes are listed in PALETTES below.

Each mesh is a root with the text entry "NCO", a shape named WaterVolume for the surface, and a
shape named WaterBody for the sides and the bottom of the water. The names are what makes the
mesh water.

The solids (sphere, cube, pyramid, octahedron) stand free. Their one shape is closed and is
drawn as water on every side; its name, "WaterVolume depth=0", says that the mesh is taken as
it is, with no bottom added.
"""
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(HERE, "..", "Water Volumes")
MESHES = os.path.join(MOD, "meshes", "wv")
MANIFEST = os.path.join(MOD, "MWSE", "mods", "waterVolumes", "kit.json")
PLUGIN = os.path.join(MOD, "Water Volumes Kit.esp")

UV_SCALE = 512.0
SURFACE_COLOR = (120, 170, 160, 200)
BODY_COLOR = (60, 120, 220, 90)
SURFACE_TEXTURE = "Textures\\water\\water00.dds"
RIVER_DEPTH = 256
SEGMENTS = 12
# The palettes: the name in the ids of the statics, the folder of the meshes beside "wv" (a
# model path has room for 31 characters), and the colour of the water as red, green, blue.
PALETTES = [
    ("swamp", "wvs", (0x4a, 0x6b, 0x3c)),
    ("mud", "wvm", (0x7a, 0x5a, 0x38)),
    ("blood", "wvb", (0x8a, 0x10, 0x10)),
]


# --- the pieces -----------------------------------------------------------------------------------
#
# A piece is its surface: points, triangles that turn left seen from above, and the points
# around its edge in the same sense. The body is made from these and the depth.
#
# River pieces fit together on a grid. The origin of a piece is the middle of the end the water
# comes in at, on the surface, and the water leaves towards the south. The middle of the other
# end lies a whole number of grid steps away: 256 units level, 64 units down. A piece placed
# with its origin on the far end of the piece before it joins it exactly. The joint of a piece
# says where the water leaves, in the piece's own frame, and which way it then flows.

def turn(quarters):
    """Cosine and sine of a number of quarter turns, exact at the quarter turns themselves."""
    exact = {0: (1.0, 0.0), 1: (0.0, 1.0), 2: (-1.0, 0.0), 3: (0.0, -1.0), 4: (1.0, 0.0)}
    if quarters in exact:
        return exact[quarters]
    return math.cos(quarters * math.pi / 2), math.sin(quarters * math.pi / 2)


def kit_pieces():
    pieces = []

    def add(name, points, triangles, outline, depth, **more):
        piece = {"name": name, "points": points, "triangles": triangles, "outline": outline, "depth": depth}
        piece.update(more)
        pieces.append(piece)

    def rectangle(name, size, depth):
        h = size / 2
        add(name, [[-h, -h, 0], [h, -h, 0], [h, h, 0], [-h, h, 0]], [[0, 1, 2], [0, 2, 3]], [0, 1, 2, 3], depth)

    def disc(name, size, depth):
        points, triangles, outline = [[0, 0, 0]], [], []
        for s in range(32):
            a = s / 32 * 2 * math.pi
            points.append([math.cos(a) * size / 2, math.sin(a) * size / 2, 0])
        for s in range(1, 33):
            triangles.append([0, s, s % 32 + 1])
            outline.append(s)
        add(name, points, triangles, outline, depth)

    def strip(name, west, east, joint, mirrored=False):
        """Two rows of points, the west and the east bank going downstream."""
        if mirrored:
            # Seen in a mirror, east and west change places.
            west, east = [[-p[0], p[1], p[2]] for p in east], [[-p[0], p[1], p[2]] for p in west]
            joint = dict(joint, x=-joint["x"], dx=-joint["dx"])
        n = len(west)
        triangles = []
        for i in range(n - 1):
            triangles.append([i, i + 1, n + i + 1])
            triangles.append([i, n + i + 1, n + i])
        outline = list(range(n)) + [n + i for i in range(n - 1, -1, -1)]
        add(name, west + east, triangles, outline, RIVER_DEPTH, joint=joint, rows=n)

    def straight(name, width, length, fall):
        h = width / 2
        strip(name, [[-h, 0, 0], [-h, -length, -fall]], [[h, 0, 0], [h, -length, -fall]],
              {"x": 0, "y": -length, "z": -fall, "dx": 0, "dy": -1, "width": width, "widthIn": width})

    def bend(name, width, radius, fall, mirrored):
        """A quarter turn to the east, the middle of the stream on a circle. Mirrored: west."""
        west, east = [], []
        for i in range(SEGMENTS + 1):
            c, s = turn(i / SEGMENTS)
            z = -fall * i / SEGMENTS
            outer, inner = radius + width / 2, radius - width / 2
            west.append([radius - outer * c, -outer * s, z])
            east.append([radius - inner * c, -inner * s, z])
        strip(name, west, east, {"x": radius, "y": -radius, "z": -fall, "dx": 1, "dy": 0, "width": width, "widthIn": width}, mirrored)

    def sway(name, width, length, shift, mirrored):
        """A stretch that moves the stream sideways to the east and keeps its direction."""
        west, east = [], []
        for i in range(SEGMENTS + 1):
            t = i / SEGMENTS
            c = turn(2 * t)[0]
            x = shift * (1 - c) / 2
            west.append([x - width / 2, -length * t, 0])
            east.append([x + width / 2, -length * t, 0])
        strip(name, west, east, {"x": shift, "y": -length, "z": 0, "dx": 0, "dy": -1, "width": width, "widthIn": width}, mirrored)

    def taper(name, width_in, width_out, length):
        strip(name, [[-width_in / 2, 0, 0], [-width_out / 2, -length, 0]], [[width_in / 2, 0, 0], [width_out / 2, -length, 0]],
              {"x": 0, "y": -length, "z": 0, "dx": 0, "dy": -1, "width": width_out, "widthIn": width_in})

    def sector(name, radius, from_quarter, to_quarter, depth, width_in=None):
        """Part of a disc around the origin: a rounded end for a stream, or a corner for a pond."""
        points, triangles, outline = [[0, 0, 0]], [], []
        steps = SEGMENTS * (to_quarter - from_quarter)
        for i in range(steps + 1):
            c, s = turn(from_quarter + i / SEGMENTS)
            points.append([radius * c, radius * s, 0])
        for i in range(1, steps + 1):
            triangles.append([0, i, i + 1])
        # The corner of a quarter is the origin itself. The straight side of a half passes through it.
        if to_quarter - from_quarter == 1:
            outline.append(0)
        outline += list(range(1, steps + 2))
        more = {"joint": {"widthIn": width_in}} if width_in else {}
        add(name, points, triangles, outline, depth, **more)

    for size in (512, 1024, 2048):
        rectangle("wv_square_%d" % size, size, 512)
        disc("wv_disc_%d" % size, size, 512)
    # Shallow pieces. An actor swims in water deeper than nine tenths of its height: 120 for a
    # height of 133. 64 is for wading; 150 is the least in which the tallest races swim as well.
    rectangle("wv_square_1024_d64", 1024, 64)
    disc("wv_disc_1024_d64", 1024, 64)
    rectangle("wv_square_1024_d150", 1024, 150)
    disc("wv_disc_1024_d150", 1024, 150)

    straight("wv_riv_512x1024", 512, 1024, 0)
    straight("wv_riv_512x1024_f64", 512, 1024, 64)
    straight("wv_riv_512x1024_f128", 512, 1024, 128)
    straight("wv_riv_1024x2048", 1024, 2048, 0)
    straight("wv_riv_1024x2048_f128", 1024, 2048, 128)
    straight("wv_riv_1024x2048_f256", 1024, 2048, 256)
    # Quarter turns and sideways stretches to the east (e) and to the west (w).
    for side, mirrored in (("e", False), ("w", True)):
        bend("wv_riv_512_bend_" + side, 512, 512, 0, mirrored)
        bend("wv_riv_512_bend_%s_f64" % side, 512, 512, 64, mirrored)
        bend("wv_riv_1024_bend_" + side, 1024, 1024, 0, mirrored)
        bend("wv_riv_1024_bend_%s_f128" % side, 1024, 1024, 128, mirrored)
        sway("wv_riv_512_sway_" + side, 512, 1024, 256, mirrored)
        sway("wv_riv_1024_sway_" + side, 1024, 2048, 512, mirrored)
    taper("wv_riv_taper_512_1024", 512, 1024, 1024)
    # Rounded ends for a stream, and rounded corners for a pond made of squares.
    sector("wv_riv_512_end", 256, 2, 4, RIVER_DEPTH, 512)
    sector("wv_riv_1024_end", 512, 2, 4, RIVER_DEPTH, 1024)
    sector("wv_corner_512", 512, 0, 1, 512)
    sector("wv_corner_1024", 1024, 0, 1, 512)
    return pieces


def body_of(piece):
    """The sides and the bottom of a piece: vertices, normals and triangles."""
    points, depth = piece["points"], piece["depth"]
    vertices = [[p[0], p[1], p[2] - depth] for p in points]
    normals = [[0.0, 0.0, -1.0] for _ in points]
    triangles = [[t[0], t[2], t[1]] for t in piece["triangles"]]
    outline = piece["outline"]
    for i in range(len(outline)):
        a, b = points[outline[i]], points[outline[(i + 1) % len(outline)]]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dy)
        normal = [dy / length, -dx / length, 0.0]
        v = len(vertices)
        vertices += [[a[0], a[1], a[2]], [b[0], b[1], b[2]], [b[0], b[1], b[2] - depth], [a[0], a[1], a[2] - depth]]
        normals += [normal] * 4
        triangles += [[v, v + 1, v + 2], [v, v + 2, v + 3]]
    return vertices, normals, triangles


# --- the mesh file ----------------------------------------------------------------------------------
#
# NetImmerse 4.0.0.2, as Morrowind reads it. A file is a list of blocks; a block names another
# by its place in the list, and -1 names none.

def string(text):
    data = text.encode("cp1252")
    return struct.pack("<I", len(data)) + data


def block(kind, body):
    return string(kind) + body


def object_net(name="", extra=-1):
    return string(name) + struct.pack("<ii", extra, -1)


def av_object(name, flags, properties, extra=-1):
    identity = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)
    return (object_net(name, extra) + struct.pack("<H", flags) + struct.pack("<3f", 0, 0, 0) + struct.pack("<9f", *identity)
            + struct.pack("<f", 1.0) + struct.pack("<3f", 0, 0, 0)
            + struct.pack("<I", len(properties)) + b"".join(struct.pack("<i", p) for p in properties) + struct.pack("<I", 0))


def shape_data(vertices, normals, color, uv, triangles):
    lows = [min(v[i] for v in vertices) for i in range(3)]
    highs = [max(v[i] for v in vertices) for i in range(3)]
    centre = [(lows[i] + highs[i]) / 2 for i in range(3)]
    radius = max(math.dist(v, centre) for v in vertices)
    out = struct.pack("<HI", len(vertices), 1) + b"".join(struct.pack("<3f", *v) for v in vertices)
    out += struct.pack("<I", 1) + b"".join(struct.pack("<3f", *n) for n in normals)
    out += struct.pack("<3ff", *centre, radius)
    out += struct.pack("<I", 1) + struct.pack("<4f", *[c / 255.0 for c in color]) * len(vertices)
    if uv:
        out += struct.pack("<HI", 1, 1) + b"".join(struct.pack("<2f", *t) for t in uv)
    else:
        out += struct.pack("<HI", 0, 0)
    out += struct.pack("<HI", len(triangles), len(triangles) * 3) + b"".join(struct.pack("<3H", *t) for t in triangles)
    out += struct.pack("<H", 0)
    return out


def stencil_both_sides():
    return block("NiStencilProperty", object_net() + struct.pack("<HB7I", 0, 0, 4, 0, 0xFFFFFFFF, 0, 0, 3, 3))


def material(emissive, alpha):
    return block("NiMaterialProperty", object_net() + struct.pack("<H", 1) + struct.pack("<3f", 1, 1, 1) + struct.pack("<3f", 1, 1, 1)
                 + struct.pack("<3f", 0, 0, 0) + struct.pack("<3f", *emissive) + struct.pack("<2f", 10.0, alpha))


def vertex_colors():
    # The colours of the vertices stand for ambient and diffuse.
    return block("NiVertexColorProperty", object_net() + struct.pack("<HII", 0, 2, 1))


def depth_test_no_write():
    return block("NiZBufferProperty", object_net() + struct.pack("<H", 1))


def alpha_blend():
    # Blend on, source alpha, inverse source alpha.
    return block("NiAlphaProperty", object_net() + struct.pack("<HB", 0x00ED, 255))


def texturing(source):
    # Seven places for a texture; only the first, the base texture, is used. Wrap, trilinear.
    base = struct.pack("<IiIIIhhH", 1, source, 3, 2, 0, 0, -75, 0)
    return block("NiTexturingProperty", object_net() + struct.pack("<HII", 0, 2, 7) + base + struct.pack("<I", 0) * 6)


def source_texture(path):
    return block("NiSourceTexture", object_net() + struct.pack("<B", 1) + string(path) + struct.pack("<IIIB", 5, 2, 3, 1))


def text_entry(text, following):
    return block("NiStringExtraData", struct.pack("<iI", following, len(text) + 4) + string(text))


def mesh_of(piece, color=(0, 0, 0)):
    """color is the colour of the water, red, green and blue to 255: the emissive colour."""
    points = piece["points"]
    body_vertices, body_normals, body_triangles = body_of(piece)
    # The place of every block in the file, in the order the blocks are written.
    blocks = [
        block("NiNode", av_object(piece["name"], 10, [], extra=1) + struct.pack("<I2i", 2, 2, 11) + struct.pack("<I", 0)),
        text_entry("NCO", -1),
        block("NiTriShape", av_object("WaterVolume", 2, [3, 4, 5, 6, 7, 8]) + struct.pack("<ii", 10, -1)),
        stencil_both_sides(),
        material([c / 255.0 for c in color], 1.0),
        vertex_colors(),
        depth_test_no_write(),
        alpha_blend(),
        texturing(9),
        source_texture(SURFACE_TEXTURE),
        block("NiTriShapeData", shape_data(points, [[0.0, 0.0, 1.0]] * len(points), SURFACE_COLOR,
                                           [[p[0] / UV_SCALE, p[1] / UV_SCALE] for p in points], piece["triangles"])),
        block("NiTriShape", av_object("WaterBody", 2, [12, 13, 14, 15, 16]) + struct.pack("<ii", 17, -1)),
        stencil_both_sides(),
        material((0.3, 0.5, 0.9), 0.35),
        vertex_colors(),
        depth_test_no_write(),
        alpha_blend(),
        block("NiTriShapeData", shape_data(body_vertices, body_normals, BODY_COLOR, None, body_triangles)),
    ]
    header = b"NetImmerse File Format, Version 4.0.0.2\n" + struct.pack("<II", 0x04000002, len(blocks))
    return header + b"".join(blocks) + struct.pack("<Ii", 1, 0)


# --- solids ---------------------------------------------------------------------------------------

def flat_solid(faces):
    """Vertices, normals and triangles of a solid with flat faces. Each face has its own corners."""
    vertices, normals, triangles = [], [], []
    for face in faces:
        a, b, c = face[0], face[1], face[2]
        u = [b[i] - a[i] for i in range(3)]
        v = [c[i] - a[i] for i in range(3)]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        length = math.sqrt(sum(x * x for x in n))
        n = [x / length for x in n]
        first = len(vertices)
        for corner in face:
            vertices.append([float(x) for x in corner])
            normals.append(n)
        for i in range(1, len(face) - 1):
            triangles.append([first, first + i, first + i + 1])
    return vertices, normals, triangles


def kit_solids():
    """Closed bodies of water that stand free. Each is one closed shape."""
    solids = []

    # Sphere, radius 1024, origin at its centre.
    radius, rings, segments = 1024.0, 16, 32
    vertices, normals, triangles = [[0.0, 0.0, radius]], [[0.0, 0.0, 1.0]], []
    for ring in range(1, rings):
        polar = math.pi * ring / rings
        for segment in range(segments):
            around = 2 * math.pi * segment / segments
            n = [math.sin(polar) * math.cos(around), math.sin(polar) * math.sin(around), math.cos(polar)]
            normals.append(n)
            vertices.append([radius * x for x in n])
    vertices.append([0.0, 0.0, -radius])
    normals.append([0.0, 0.0, -1.0])
    last = len(vertices) - 1
    for segment in range(segments):
        following = (segment + 1) % segments
        triangles.append([0, 1 + segment, 1 + following])
        triangles.append([last, last - segments + following, last - segments + segment])
        for ring in range(rings - 2):
            a = 1 + ring * segments + segment
            b = 1 + ring * segments + following
            triangles.append([a, a + segments, b + segments])
            triangles.append([a, b + segments, b])
    solids.append({"name": "wv_sphere_1024", "shape": (vertices, normals, triangles)})

    # Cube, side 1024, origin at the middle of its base.
    h, s = 512.0, 1024.0
    low = [(-h, -h, 0), (h, -h, 0), (h, h, 0), (-h, h, 0)]
    high = [(x, y, s) for x, y, _ in low]
    faces = [list(reversed(low)), high]
    for i in range(4):
        j = (i + 1) % 4
        faces.append([low[i], low[j], high[j], high[i]])
    solids.append({"name": "wv_cube_1024", "shape": flat_solid(faces)})

    # Pyramid, base 1024 by 1024, 1024 high, origin at the middle of its base.
    apex = (0, 0, s)
    faces = [list(reversed(low))] + [[low[i], low[(i + 1) % 4], apex] for i in range(4)]
    solids.append({"name": "wv_pyramid_1024", "shape": flat_solid(faces)})

    # Octahedron, corners 1024 from its centre, origin at its centre.
    r = 1024.0
    ring = [(r, 0, 0), (0, r, 0), (-r, 0, 0), (0, -r, 0)]
    faces = []
    for i in range(4):
        j = (i + 1) % 4
        faces.append([ring[i], ring[j], (0, 0, r)])
        faces.append([ring[j], ring[i], (0, 0, -r)])
    solids.append({"name": "wv_octa_1024", "shape": flat_solid(faces)})

    for solid in solids:
        vertices = solid["shape"][0]
        solid["min"] = [min(v[i] for v in vertices) for i in range(3)]
        solid["max"] = [max(v[i] for v in vertices) for i in range(3)]
    return solids


def solid_mesh(solid, color=(0, 0, 0)):
    vertices, normals, triangles = solid["shape"]
    blocks = [
        block("NiNode", av_object(solid["name"], 10, [], extra=1) + struct.pack("<Ii", 1, 2) + struct.pack("<I", 0)),
        text_entry("NCO", -1),
        block("NiTriShape", av_object("WaterVolume depth=0", 2, [3, 4, 5, 6, 7, 8]) + struct.pack("<ii", 10, -1)),
        stencil_both_sides(),
        material([c / 255.0 for c in color], 1.0),
        vertex_colors(),
        depth_test_no_write(),
        alpha_blend(),
        texturing(9),
        source_texture(SURFACE_TEXTURE),
        block("NiTriShapeData", shape_data(vertices, normals, SURFACE_COLOR,
                                           [[v[0] / UV_SCALE, v[1] / UV_SCALE] for v in vertices], triangles)),
    ]
    header = b"NetImmerse File Format, Version 4.0.0.2\n" + struct.pack("<II", 0x04000002, len(blocks))
    return header + b"".join(blocks) + struct.pack("<Ii", 1, 0)


# --- the plugin ---------------------------------------------------------------------------------------

def sub(name, data):
    return name.encode("ascii") + struct.pack("<I", len(data)) + data


def record(name, subrecords):
    data = b"".join(subrecords)
    return name.encode("ascii") + struct.pack("<III", len(data), 0, 0) + data


def zstr(text):
    return text.encode("cp1252") + b"\0"


def palette_id(name, palette):
    """The id of the static of a piece in a palette: wv_square_1024 is wv_swamp_square_1024."""
    return "wv_" + palette + name[2:]


def write_plugin(master, statics, output):
    """One Static per piece and no references. statics: ids with their paths, relative to Meshes."""
    records = [record("STAT", [sub("NAME", zstr(name)), sub("MODL", zstr(path))]) for name, path in statics]
    description = b"Water Volumes kit: water pieces to place in the world. Needs the Water Volumes mod."
    header = struct.pack("<fI32s256sI", 1.3, 0, b"Water Volumes", description, len(records))
    tes3 = record("TES3", [
        sub("HEDR", header),
        sub("MAST", zstr(os.path.basename(master))),
        sub("DATA", struct.pack("<Q", os.path.getsize(master))),
    ])
    with open(output, "wb") as handle:
        handle.write(tes3 + b"".join(records))
    print("%d statics in %s" % (len(records), os.path.normpath(output)))


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    master = sys.argv[1]
    pieces = kit_pieces()
    solids = kit_solids()
    # The game keeps a model path in 32 bytes, the closing zero included.
    too_long = [p["name"] for p in pieces + solids if len("wv/" + p["name"] + ".nif") > 31]
    if too_long:
        raise SystemExit("mesh names too long for a model path: %s" % ", ".join(too_long))

    os.makedirs(MESHES, exist_ok=True)
    wanted = {p["name"].lower() + ".nif" for p in pieces + solids}
    stale = [f for f in os.listdir(MESHES) if f.lower().endswith(".nif") and f.lower() not in wanted]
    if stale:
        raise SystemExit("meshes in %s that are not pieces of the kit; remove them first: %s" % (MESHES, ", ".join(stale)))
    for piece in pieces:
        with open(os.path.join(MESHES, piece["name"] + ".nif"), "wb") as handle:
            handle.write(mesh_of(piece))
    for solid in solids:
        with open(os.path.join(MESHES, solid["name"] + ".nif"), "wb") as handle:
            handle.write(solid_mesh(solid))

    statics = [(p["name"], "wv\\" + p["name"] + ".nif") for p in pieces + solids]
    for palette, folder, color in PALETTES:
        os.makedirs(os.path.join(MESHES, "..", folder), exist_ok=True)
        for piece in pieces + solids:
            with open(os.path.join(MESHES, "..", folder, piece["name"] + ".nif"), "wb") as handle:
                handle.write(mesh_of(piece, color) if "points" in piece else solid_mesh(piece, color))
            statics.append((palette_id(piece["name"], palette), "%s\\%s.nif" % (folder, piece["name"])))
    too_long = [path for _, path in statics if len(path) > 31]
    if too_long:
        raise SystemExit("model paths too long: %s" % ", ".join(too_long))

    manifest = {"gridLevel": 256, "gridDown": 64, "pieces": [
        {key: piece[key] for key in ("name", "depth", "points", "rows", "joint") if key in piece} for piece in pieces],
        "solids": [{key: solid[key] for key in ("name", "min", "max")} for solid in solids],
        "palettes": [{"name": palette, "folder": folder, "color": "%02x%02x%02x" % color} for palette, folder, color in PALETTES]}
    with open(MANIFEST, "w", encoding="ascii", newline="\n") as handle:
        json.dump(manifest, handle, separators=(",", ":"))
        handle.write("\n")

    write_plugin(master, sorted(statics), PLUGIN)
    print("%d meshes in %s" % (len(statics), os.path.normpath(MESHES)))
    print("list of pieces in %s" % os.path.normpath(MANIFEST))


if __name__ == "__main__":
    main()
