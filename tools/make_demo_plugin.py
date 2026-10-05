#!/usr/bin/env python3
"""Writes a small plugin that places Water Volumes kit meshes, the way the Construction Set would.

The plugin holds Statics that use a kit mesh and references to them in exterior cells. It
exists to test the path a modder's plugin takes: the game loads the references from the plugin,
the Water Volumes mod turns them into water, and MGE XE's distant land generator sees them.

Usage:
    python make_demo_plugin.py <Morrowind.esm> <output.esp>            one disc near Vas
    python make_demo_plugin.py <Morrowind.esm> <output.esp> --grid     that disc, and one high in
                                                                       the air over each of the
                                                                       next three cells to the east
    python make_demo_plugin.py <Morrowind.esm> <output.esp> --solids   the four solids of the kit,
                                                                       in a row high over the sea
                                                                       north of Vas

--solids places the Statics of "Water Volumes Kit.esp"; load the output after that plugin.
"""
import os
import struct
import sys

MESH = "wv\\wv_disc_1024.nif"
SITE = (7060.0, 186303.0, 620.0)
CELL_SIZE = 8192.0
# The solids of the kit, 3072 apart in a row that runs east, 2048 over the sea north of Vas.
SOLIDS = ("wv_sphere_1024", "wv_cube_1024", "wv_pyramid_1024", "wv_octa_1024")
SOLIDS_SITE = (2048.0, 200704.0, 2048.0)
SOLIDS_STEP = 3072.0


def sub(name, data):
    return name.encode("ascii") + struct.pack("<I", len(data)) + data


def record(name, subrecords):
    data = b"".join(subrecords)
    return name.encode("ascii") + struct.pack("<III", len(data), 0, 0) + data


def zstr(text):
    return text.encode("cp1252") + b"\0"


def exterior_cells(master):
    """Name, region and flags of every exterior cell of the master file, by grid position."""
    with open(master, "rb") as handle:
        blob = handle.read()
    cells = {}
    pos = 0
    while pos < len(blob):
        tag = blob[pos:pos + 4]
        size = struct.unpack_from("<I", blob, pos + 4)[0]
        body = blob[pos + 16:pos + 16 + size]
        pos += 16 + size
        if tag != b"CELL":
            continue
        name, region, data = b"\0", None, None
        at = 0
        while at < len(body):
            stag = body[at:at + 4]
            ssize = struct.unpack_from("<I", body, at + 4)[0]
            sdata = body[at + 8:at + 8 + ssize]
            at += 8 + ssize
            if stag == b"NAME" and data is None:
                name = sdata
            elif stag == b"DATA" and data is None:
                data = struct.unpack("<Iii", sdata)
            elif stag == b"RGNN":
                region = sdata
            elif stag == b"FRMR":
                break
        if data and not data[0] & 1:
            cells[(data[1], data[2])] = (name, region, data[0])
    return cells


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) < 2:
        raise SystemExit(__doc__)
    master, output = args[0], args[1]
    grid = "--grid" in sys.argv

    solids = "--solids" in sys.argv
    placements = [("wv_demo_disc", SITE)]
    if grid:
        for step in (1, 2, 3):
            placements.append(("wv_demo_disc%d" % step, (SITE[0] + step * CELL_SIZE, SITE[1], 1500.0)))
    if solids:
        placements = [(name, (SOLIDS_SITE[0] + index * SOLIDS_STEP, SOLIDS_SITE[1], SOLIDS_SITE[2]))
                      for index, name in enumerate(SOLIDS)]

    cells = exterior_cells(master)
    records = []
    for static_id, _ in placements:
        # The solids are Statics of the kit plugin already.
        if not solids:
            records.append(record("STAT", [sub("NAME", zstr(static_id)), sub("MODL", zstr(MESH))]))

    by_cell = {}
    for static_id, (x, y, z) in placements:
        by_cell.setdefault((int(x // CELL_SIZE), int(y // CELL_SIZE)), []).append((static_id, x, y, z))
    index = 0
    for (grid_x, grid_y), refs in sorted(by_cell.items()):
        if (grid_x, grid_y) not in cells:
            raise SystemExit("exterior cell %d,%d not found in %s" % (grid_x, grid_y, master))
        name, region, flags = cells[(grid_x, grid_y)]
        subs = [sub("NAME", name), sub("DATA", struct.pack("<Iii", flags, grid_x, grid_y))]
        if region:
            subs.append(sub("RGNN", region))
        # Temporary references: their count, then each reference.
        subs.append(sub("NAM0", struct.pack("<I", len(refs))))
        for static_id, x, y, z in refs:
            index += 1
            subs.append(sub("FRMR", struct.pack("<I", index)))
            subs.append(sub("NAME", zstr(static_id)))
            subs.append(sub("DATA", struct.pack("<6f", x, y, z, 0.0, 0.0, 0.0)))
        records.append(record("CELL", subs))
        print("cell %d,%d (%s): %s" % (grid_x, grid_y, name.rstrip(b"\0").decode("cp1252") or "unnamed",
                                       ", ".join("%s at %.0f, %.0f, %.0f" % r for r in refs)))

    header = struct.pack("<fI32s256sI", 1.3, 0, b"Water Volumes", b"Demo: kit pieces placed near Vas.", len(records))
    masters = [sub("MAST", zstr(os.path.basename(master))), sub("DATA", struct.pack("<Q", os.path.getsize(master)))]
    if solids:
        kit = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Water Volumes", "Water Volumes Kit.esp")
        masters += [sub("MAST", zstr(os.path.basename(kit))), sub("DATA", struct.pack("<Q", os.path.getsize(kit)))]
    tes3 = record("TES3", [sub("HEDR", header)] + masters)
    with open(output, "wb") as handle:
        handle.write(tes3 + b"".join(records))
    print("wrote %s" % output)


if __name__ == "__main__":
    main()
