#!/usr/bin/env python3
"""Writes the plugin that makes the Water Volumes kit available in the Construction Set.

The plugin holds one Static per kit mesh and places nothing. Load it in the Construction Set
together with your own plugin, and the pieces are in the Object Window under Static, with ids
that start with wv_.

Usage:
    python make_kit_plugin.py <Morrowind.esm> <meshes/wv folder> <output.esp>
"""
import os
import struct
import sys

DESCRIPTION = b"Water Volumes kit: water pieces to place in the world. Needs the Water Volumes mod."


def sub(name, data):
    return name.encode("ascii") + struct.pack("<I", len(data)) + data


def record(name, subrecords):
    data = b"".join(subrecords)
    return name.encode("ascii") + struct.pack("<III", len(data), 0, 0) + data


def zstr(text):
    return text.encode("cp1252") + b"\0"


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    master, meshes, output = sys.argv[1:]
    names = sorted(os.path.splitext(f)[0] for f in os.listdir(meshes) if f.lower().endswith(".nif"))
    if not names:
        raise SystemExit("no meshes in %s" % meshes)

    # The game keeps a model path in 32 bytes, the closing zero included.
    too_long = [n for n in names if len("wv/" + n + ".nif") > 31]
    if too_long:
        raise SystemExit("mesh names too long for a model path: %s" % ", ".join(too_long))

    records = []
    for name in names:
        # Paths in a plugin are relative to the Meshes folder and use backslashes.
        records.append(record("STAT", [sub("NAME", zstr(name)), sub("MODL", zstr("wv" + chr(92) + name + ".nif"))]))
        print("static %s" % name)

    header = struct.pack("<fI32s256sI", 1.3, 0, b"Water Volumes", DESCRIPTION, len(records))
    tes3 = record("TES3", [
        sub("HEDR", header),
        sub("MAST", zstr(os.path.basename(master))),
        sub("DATA", struct.pack("<Q", os.path.getsize(master))),
    ])
    with open(output, "wb") as handle:
        handle.write(tes3 + b"".join(records))
    print("wrote %s with %d statics" % (output, len(records)))


if __name__ == "__main__":
    main()
