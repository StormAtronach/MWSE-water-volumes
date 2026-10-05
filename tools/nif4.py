"""Reads and writes Morrowind mesh files (NetImmerse 4.0.0.2), for the block types that the
game's water meshes use.

A file is a list of blocks. A block is a dict with its fields and its "type". A field that
names another block holds the place of that block in the list, or -1 for none. Before a file
is written, such a field may hold the other block itself: write() puts the place in.
"""
import math
import struct

HEADER = b"NetImmerse File Format, Version 4.0.0.2\n"
VERSION = 0x04000002


class Reader:
    def __init__(self, data):
        self.d, self.p = data, 0

    def take(self, fmt):
        values = struct.unpack_from("<" + fmt, self.d, self.p)
        self.p += struct.calcsize("<" + fmt)
        return values[0] if len(values) == 1 else list(values)

    def u8(self): return self.take("B")
    def u16(self): return self.take("H")
    def s16(self): return self.take("h")
    def u32(self): return self.take("I")
    def i32(self): return self.take("i")
    def f(self, n=1): return self.take("%df" % n)

    def s(self):
        n = self.u32()
        v = self.d[self.p:self.p + n].decode("cp1252")
        self.p += n
        return v


def _read_object_net(r):
    return {"name": r.s(), "extra": r.i32(), "controller": r.i32()}


def _read_av_object(r):
    o = _read_object_net(r)
    o["flags"] = r.u16()
    o["translation"], o["rotation"], o["scale"], o["velocity"] = r.f(3), r.f(9), r.f(), r.f(3)
    o["properties"] = [r.i32() for _ in range(r.u32())]
    assert r.u32() == 0, "a bounding box is not handled"
    return o


def _read_block(r, kind):
    if kind in ("NiNode", "NiBSAnimationNode"):
        o = _read_av_object(r)
        o["children"] = [r.i32() for _ in range(r.u32())]
        o["effects"] = [r.i32() for _ in range(r.u32())]
    elif kind == "NiTriShape":
        o = _read_av_object(r)
        o["data"], o["skin"] = r.i32(), r.i32()
    elif kind == "NiTriShapeData":
        o = {}
        n = r.u16()
        o["vertices"] = [r.f(3) for _ in range(n)] if r.u32() else []
        o["normals"] = [r.f(3) for _ in range(n)] if r.u32() else []
        o["center"], o["radius"] = r.f(3), r.f()
        o["colors"] = [r.f(4) for _ in range(n)] if r.u32() else []
        sets = r.u16()
        o["uv"] = [[r.f(2) for _ in range(n)] for _ in range(sets)] if r.u32() else []
        t = r.u16()
        assert r.u32() == t * 3
        o["triangles"] = [r.take("3H") for _ in range(t)]
        o["matchGroups"] = [[r.u16() for _ in range(r.u16())] for _ in range(r.u16())]
    elif kind == "NiStringExtraData":
        o = {"next": r.i32()}
        r.u32()
        o["string"] = r.s()
    elif kind == "NiTexturingProperty":
        o = _read_object_net(r)
        o["flags"], o["applyMode"] = r.u16(), r.u32()
        o["slots"] = []
        for slot in range(r.u32()):
            entry = None
            if r.u32():
                entry = {"source": r.i32(), "clamp": r.u32(), "filter": r.u32(), "uvSet": r.u32(), "ps2L": r.s16(), "ps2K": r.s16(), "unknown": r.u16()}
                if slot == 5:
                    entry["bump"] = r.f(6)
            o["slots"].append(entry)
    elif kind == "NiSourceTexture":
        o = _read_object_net(r)
        assert r.u8() == 1, "a texture inside the file is not handled"
        o["file"] = r.s()
        o["pixelLayout"], o["mipmaps"], o["alphaFormat"], o["static"] = r.u32(), r.u32(), r.u32(), r.u8()
    elif kind == "NiAlphaProperty":
        o = _read_object_net(r)
        o["flags"], o["threshold"] = r.u16(), r.u8()
    elif kind == "NiZBufferProperty":
        o = _read_object_net(r)
        o["flags"] = r.u16()
    elif kind == "NiMaterialProperty":
        o = _read_object_net(r)
        o["flags"] = r.u16()
        o["ambient"], o["diffuse"], o["specular"], o["emissive"] = r.f(3), r.f(3), r.f(3), r.f(3)
        o["glossiness"], o["alpha"] = r.f(), r.f()
    elif kind == "NiStencilProperty":
        o = _read_object_net(r)
        o["flags"], o["enabled"] = r.u16(), r.u8()
        o["function"], o["ref"], o["mask"], o["fail"], o["zFail"], o["pass"], o["drawMode"] = [r.u32() for _ in range(7)]
    elif kind == "NiUVController":
        o = {"next": r.i32(), "flags": r.u16(), "frequency": r.f(), "phase": r.f(), "start": r.f(), "stop": r.f(), "target": r.i32(),
             "textureSet": r.u16(), "data": r.i32()}
    elif kind == "NiUVData":
        o = {"groups": []}
        for _ in range(4):
            n = r.u32()
            group = {"keys": []}
            if n:
                group["interpolation"] = r.u32()
                per = {1: 2, 2: 4, 3: 5}[group["interpolation"]]
                group["keys"] = [r.f(per) for _ in range(n)]
            o["groups"].append(group)
    else:
        raise ValueError("block type %r is not handled" % kind)
    o["type"] = kind
    return o


def read(path):
    """The blocks of a file. The first block is the root."""
    data = open(path, "rb").read()
    assert data.startswith(HEADER), "not a 4.0.0.2 mesh file"
    r = Reader(data)
    r.p = len(HEADER)
    assert r.u32() == VERSION
    blocks = [_read_block(r, r.s()) for _ in range(r.u32())]
    roots = [r.i32() for _ in range(r.u32())]
    assert r.p == len(data) and roots == [0]
    return blocks


def _string(text):
    data = text.encode("cp1252")
    return struct.pack("<I", len(data)) + data


def _floats(values):
    return struct.pack("<%df" % len(values), *values)


def bounds(vertices):
    """The centre and the radius that the game's exporter writes: the middle of the box."""
    lows = [min(v[i] for v in vertices) for i in range(3)]
    highs = [max(v[i] for v in vertices) for i in range(3)]
    center = [(lows[i] + highs[i]) / 2 for i in range(3)]
    return center, max(math.dist(v, center) for v in vertices)


def write(path, blocks):
    place = {id(b): i for i, b in enumerate(blocks)}

    def link(value):
        if value is None:
            return struct.pack("<i", -1)
        return struct.pack("<i", value if isinstance(value, int) else place[id(value)])

    def links(values):
        return struct.pack("<I", len(values)) + b"".join(link(v) for v in values)

    def object_net(o):
        return _string(o["name"]) + link(o["extra"]) + link(o["controller"])

    def av_object(o):
        return (object_net(o) + struct.pack("<H", o["flags"]) + _floats(o["translation"]) + _floats(o["rotation"]) + _floats([o["scale"]])
                + _floats(o["velocity"]) + links(o["properties"]) + struct.pack("<I", 0))

    out = [HEADER, struct.pack("<II", VERSION, len(blocks))]
    for o in blocks:
        kind = o["type"]
        if kind in ("NiNode", "NiBSAnimationNode"):
            body = av_object(o) + links(o["children"]) + links(o["effects"])
        elif kind == "NiTriShape":
            body = av_object(o) + link(o["data"]) + link(o["skin"])
        elif kind == "NiTriShapeData":
            n = len(o["vertices"])
            body = struct.pack("<HI", n, 1 if n else 0) + b"".join(_floats(v) for v in o["vertices"])
            body += struct.pack("<I", 1 if o["normals"] else 0) + b"".join(_floats(v) for v in o["normals"])
            body += _floats(o["center"]) + _floats([o["radius"]])
            body += struct.pack("<I", 1 if o["colors"] else 0) + b"".join(_floats(v) for v in o["colors"])
            body += struct.pack("<HI", len(o["uv"]), 1 if o["uv"] else 0) + b"".join(_floats(v) for uv in o["uv"] for v in uv)
            body += struct.pack("<HI", len(o["triangles"]), len(o["triangles"]) * 3) + b"".join(struct.pack("<3H", *t) for t in o["triangles"])
            body += struct.pack("<H", len(o["matchGroups"])) + b"".join(struct.pack("<H", len(g)) + struct.pack("<%dH" % len(g), *g) for g in o["matchGroups"])
        elif kind == "NiStringExtraData":
            body = link(o["next"]) + struct.pack("<I", len(o["string"].encode("cp1252")) + 4) + _string(o["string"])
        elif kind == "NiTexturingProperty":
            body = object_net(o) + struct.pack("<HII", o["flags"], o["applyMode"], len(o["slots"]))
            for entry in o["slots"]:
                if entry is None:
                    body += struct.pack("<I", 0)
                else:
                    body += struct.pack("<I", 1) + link(entry["source"]) + struct.pack("<IIIhhH", entry["clamp"], entry["filter"], entry["uvSet"], entry["ps2L"], entry["ps2K"], entry["unknown"])
                    if "bump" in entry:
                        body += _floats(entry["bump"])
        elif kind == "NiSourceTexture":
            body = object_net(o) + struct.pack("<B", 1) + _string(o["file"]) + struct.pack("<IIIB", o["pixelLayout"], o["mipmaps"], o["alphaFormat"], o["static"])
        elif kind == "NiAlphaProperty":
            body = object_net(o) + struct.pack("<HB", o["flags"], o["threshold"])
        elif kind == "NiZBufferProperty":
            body = object_net(o) + struct.pack("<H", o["flags"])
        elif kind == "NiMaterialProperty":
            body = (object_net(o) + struct.pack("<H", o["flags"]) + _floats(o["ambient"]) + _floats(o["diffuse"]) + _floats(o["specular"]) + _floats(o["emissive"])
                    + _floats([o["glossiness"], o["alpha"]]))
        elif kind == "NiStencilProperty":
            body = object_net(o) + struct.pack("<HB7I", o["flags"], o["enabled"], o["function"], o["ref"], o["mask"], o["fail"], o["zFail"], o["pass"], o["drawMode"])
        elif kind == "NiUVController":
            body = (link(o["next"]) + struct.pack("<H", o["flags"]) + _floats([o["frequency"], o["phase"], o["start"], o["stop"]]) + link(o["target"])
                    + struct.pack("<H", o["textureSet"]) + link(o["data"]))
        elif kind == "NiUVData":
            body = b""
            for group in o["groups"]:
                body += struct.pack("<I", len(group["keys"]))
                if group["keys"]:
                    body += struct.pack("<I", group["interpolation"]) + b"".join(_floats(k) for k in group["keys"])
        else:
            raise ValueError("block type %r is not handled" % kind)
        out.append(_string(kind) + body)
    out.append(struct.pack("<Ii", 1, 0))
    data = b"".join(out)
    if path:
        open(path, "wb").write(data)
    return data


if __name__ == "__main__":
    # Reads each file and writes it again in memory. Apart from the flags that say that a list
    # is there, which the game's exporter left as any number but zero, the bytes are the same.
    import sys
    for name in sys.argv[1:]:
        original = open(name, "rb").read()
        again = write(None, read(name))
        same = len(original) == len(again) and sum(1 for a, b in zip(original, again) if a != b)
        print(name, "length", len(original), len(again), "bytes that differ:", same)
