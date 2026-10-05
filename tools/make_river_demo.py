#!/usr/bin/env python3
"""Writes a demo plugin: a gently sloping river of kit pieces along a stretch of Foyada Mamaea.

The script reads the land of the cells from the master files, finds the floor of the foyada
between two points, lays 512 wide kit pieces along it on the grid of the kit (256 level, 64
down), chooses for each piece how much it falls so that the water stays a sensible depth over
the floor, and writes the references into a plugin. The pieces, their ends and their falls are
read from the list that make_kit.py writes.

Usage:
    python make_river_demo.py <Data Files folder> <output.esp> [--land <plugin> ...]

The land is read from Morrowind.esm in the Data Files folder, then from each plugin given with
--land, in that order; the last one that has a cell wins. The output plugin depends on
Morrowind.esm and on "Water Volumes Kit.esp". The kit plugin is looked for beside the output,
in the "Water Volumes" folder of this repository, and in the Data Files folder.
"""
import heapq
import json
import math
import os
import struct
import sys

CELL = 8192
LAND_STEP = 128
KIT = "Water Volumes Kit.esp"

# The stretch: from the floor of the foyada in the cell south-west of Ghostgate (2, 4), through
# (1, 3), to the low ground where (1, 3) meets (1, 2). The floor falls by about 370 on the way.
TOP_NEAR = (17536.0, 33792.0)
BOTTOM_NEAR = (9728.0, 24320.0)
CELLS = [(x, y) for x in range(0, 4) for y in range(1, 6)]
# The three cells the river lies in.
ALLOWED = {(2, 4), (1, 3), (1, 2)}

WIDTH = 512
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Water Volumes", "MWSE", "mods", "waterVolumes", "kit.json")


# --- plugin files ---------------------------------------------------------------------------

def sub(name, data):
    return name.encode("ascii") + struct.pack("<I", len(data)) + data


def record(name, subrecords):
    data = b"".join(subrecords)
    return name.encode("ascii") + struct.pack("<III", len(data), 0, 0) + data


def zstr(text):
    return text.encode("cp1252") + b"\0"


def records(path, wanted):
    with open(path, "rb") as handle:
        blob = handle.read()
    pos = 0
    while pos < len(blob):
        tag = blob[pos:pos + 4]
        size = struct.unpack_from("<I", blob, pos + 4)[0]
        if tag in wanted:
            yield tag, blob[pos + 16:pos + 16 + size]
        pos += 16 + size


def subrecords(body):
    at = 0
    while at < len(body):
        tag = body[at:at + 4]
        size = struct.unpack_from("<I", body, at + 4)[0]
        yield tag, body[at + 8:at + 8 + size]
        at += 8 + size


# --- land -------------------------------------------------------------------------------------

def decode_heights(vhgt):
    """65 rows of 65 heights in game units, row 0 at the south edge, column 0 at the west edge."""
    offset = struct.unpack_from("<f", vhgt, 0)[0]
    deltas = struct.unpack_from("<4225b", vhgt, 4)
    rows = []
    for y in range(65):
        offset += deltas[y * 65]
        value = offset
        row = [value]
        for x in range(1, 65):
            value += deltas[y * 65 + x]
            row.append(value)
        rows.append([h * 8.0 for h in row])
    return rows


class Terrain:
    def __init__(self, files, cells):
        wanted = set(cells)
        self.land = {}
        self.cells = {}
        for path in files:
            for tag, body in records(path, {b"LAND", b"CELL"}):
                if tag == b"LAND":
                    cell, vhgt = None, None
                    for stag, sdata in subrecords(body):
                        if stag == b"INTV":
                            cell = struct.unpack("<ii", sdata)
                            if cell not in wanted:
                                break
                        elif stag == b"VHGT":
                            vhgt = sdata
                    if cell in wanted and vhgt:
                        self.land[cell] = (decode_heights(vhgt), os.path.basename(path))
                else:
                    name, region, data = b"\0", None, None
                    for stag, sdata in subrecords(body):
                        if stag == b"NAME" and data is None:
                            name = sdata
                        elif stag == b"DATA" and data is None:
                            data = struct.unpack("<Iii", sdata)
                        elif stag == b"RGNN":
                            region = sdata
                        elif stag == b"FRMR":
                            break
                    if data and not data[0] & 1 and (data[1], data[2]) in wanted:
                        self.cells[(data[1], data[2])] = (name, region, data[0])

    def height(self, x, y):
        """Height of the land at a world position, between the four land points around it."""
        gx, gy = int(x // CELL), int(y // CELL)
        entry = self.land.get((gx, gy))
        if not entry:
            return None
        rows = entry[0]
        fx, fy = (x - gx * CELL) / LAND_STEP, (y - gy * CELL) / LAND_STEP
        ix, iy = min(int(fx), 63), min(int(fy), 63)
        tx, ty = fx - ix, fy - iy
        a, b = rows[iy][ix], rows[iy][ix + 1]
        c, d = rows[iy + 1][ix], rows[iy + 1][ix + 1]
        return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty

    def lowest_near(self, x, y, reach):
        best = None
        for dx in range(-reach, reach + 1, LAND_STEP):
            for dy in range(-reach, reach + 1, LAND_STEP):
                h = self.height(x + dx, y + dy)
                if h is not None and (best is None or h < best[0]):
                    best = (h, x + dx, y + dy)
        return best


def trace_floor(terrain, a, b):
    """The floor of the valley from a to b: the cheapest way over the land points, where high
    ground is dear. Returns [(x, y, height)]."""
    g = LAND_STEP

    def h(node):
        return terrain.height(node[0] * g + 0.01, node[1] * g + 0.01)

    start, goal = (int(a[0] // g), int(a[1] // g)), (int(b[0] // g), int(b[1] // g))
    base = min(h(start), h(goal)) - 300
    dist, prev, heap = {start: 0.0}, {}, [(0.0, start)]
    while heap:
        d, node = heapq.heappop(heap)
        if node == goal:
            break
        if d > dist.get(node, 1e30):
            continue
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                nxt = (node[0] + dx, node[1] + dy)
                hh = h(nxt)
                if hh is None:
                    continue
                nd = d + math.hypot(dx, dy) * (1.0 + (max(hh - base, 0) / 100.0) ** 3)
                if nd < dist.get(nxt, 1e30):
                    dist[nxt] = nd
                    prev[nxt] = node
                    heapq.heappush(heap, (nd, nxt))
    path = [goal]
    while path[-1] != start:
        path.append(prev[path[-1]])
    path.reverse()
    return [(n[0] * g, n[1] * g, h(n)) for n in path]


# --- the pieces of the kit ----------------------------------------------------------------------
#
# A piece runs from its origin towards "its south". A reference turned by t degrees (the game
# turns clockwise seen from above) flows along flow(t), and its own east is left(t): the bank
# on the left hand of someone who goes with the water.

def flow(turn):
    r = math.radians(turn)
    return (-round(math.sin(r)), -round(math.cos(r)))


def left(turn):
    r = math.radians(turn)
    return (round(math.cos(r)), -round(math.sin(r)))


def to_world(origin, turn, lx, ly):
    f, l = flow(turn), left(turn)
    return (origin[0] + lx * l[0] - ly * f[0], origin[1] + lx * l[1] - ly * f[1])


class Move:
    """One kind of piece: where it ends, how it turns the stream, the line down its middle,
    and the piece for each fall it is made with."""

    def __init__(self, end, turn, line, pieces):
        self.end, self.turn, self.line, self.pieces = end, turn, line, pieces
        self.falls = tuple(sorted(pieces))

    def piece(self, fall):
        return self.pieces[fall]


def load_kit(width):
    """The river pieces of one width from the list the kit script wrote: the moves, the piece
    that ends a stream, and how deep the pieces are."""
    with open(MANIFEST, encoding="ascii") as handle:
        manifest = json.load(handle)
    turns = {(0, -1): 0, (1, 0): -90, (-1, 0): 90}
    moves, end_piece, depth = {}, None, None
    for piece in manifest["pieces"]:
        joint = piece.get("joint")
        if not joint or joint.get("widthIn") != width:
            continue
        if "x" not in joint:
            end_piece = piece["name"]
            continue
        if joint["width"] != width:
            continue
        depth = piece["depth"]
        rows, points = piece["rows"], piece["points"]
        line = [((points[i][0] + points[rows + i][0]) / 2, (points[i][1] + points[rows + i][1]) / 2) for i in range(rows)]
        if rows == 2:
            # A straight stretch has only its two ends; the land is looked at in between as well.
            (ax, ay), (bx, by) = line
            line = [(ax + (bx - ax) * k / 8, ay + (by - ay) * k / 8) for k in range(9)]
        key = (joint["x"], joint["y"], joint["dx"], joint["dy"])
        if key not in moves:
            moves[key] = Move((joint["x"], joint["y"]), turns[(joint["dx"], joint["dy"])], line, {})
        moves[key].pieces[-joint["z"]] = piece["name"]
    for move in moves.values():
        move.falls = tuple(sorted(move.pieces))
    if not moves or end_piece is None:
        raise SystemExit("the kit has no river pieces %d wide; run make_kit.py first" % width)
    return list(moves.values()), end_piece, depth


MOVES, END_PIECE, DEPTH = load_kit(WIDTH)


# --- the way of the river -------------------------------------------------------------------------

class Floor:
    """The traced floor, with the distance along it, for asking how far a point is from it."""

    def __init__(self, points):
        self.points = points
        self.along = [0.0]
        for i in range(1, len(points)):
            self.along.append(self.along[-1] + math.hypot(points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]))

    def nearest(self, x, y):
        best = (1e30, 0.0)
        for i, (px, py, _) in enumerate(self.points):
            d = (px - x) ** 2 + (py - y) ** 2
            if d < best[0]:
                best = (d, self.along[i])
        return math.sqrt(best[0]), best[1]

    def height_at(self, along):
        """The height of the floor at a distance along it."""
        lo, hi = 0, len(self.along) - 1
        while lo < hi:
            mid = (lo + hi) // 2
            if self.along[mid] < along:
                lo = mid + 1
            else:
                hi = mid
        return self.points[lo][2]


def plan_way(terrain, floor, allowed):
    """The pieces from the top of the stretch to its bottom that stay on the lowest ground.
    Every piece has its origin in one of the allowed cells. Returns [(move, origin, turn)]."""
    top, bottom = floor.points[0], floor.points[-1]
    total = floor.along[-1]

    def in_allowed(point):
        return (int(point[0] // CELL), int(point[1] // CELL)) in allowed

    def rise(x, y, at):
        """How much higher the land at a point is than the floor of the valley beside it."""
        ground = terrain.height(x, y)
        return 1e6 if ground is None else max(ground - floor.height_at(at), 0.0)

    def snap(v):
        return int(round(v / 256.0)) * 256

    starts = []
    for dx in (-256, 0, 256):
        for dy in (-256, 0, 256):
            for turn in (0, 90, 180, 270):
                origin = (snap(top[0]) + dx, snap(top[1]) + dy)
                if not in_allowed(origin):
                    continue
                off, at = floor.nearest(*origin)
                starts.append(((off / 100.0) ** 2 * 4, (origin, turn)))
    dist, prev, heap = {}, {}, []
    for cost, state in starts:
        dist[state] = cost
        heapq.heappush(heap, (cost, state))
    goal = None
    while heap:
        d, state = heapq.heappop(heap)
        if d > dist.get(state, 1e30):
            continue
        origin, turn = state
        off, at = floor.nearest(*origin)
        if total - at < 500 and off < 400:
            goal = state
            break
        for move in MOVES:
            end = to_world(origin, turn, *move.end)
            if not in_allowed(end):
                continue
            cost, ok = 0.0, True
            for i in range(1, len(move.line)):
                lx, ly = move.line[i]
                x, y = to_world(origin, turn, lx, ly)
                o, a = floor.nearest(x, y)
                if o > 700 or a < at - 300:
                    ok = False
                    break
                # The land under the middle of the stream and under both of its sides.
                px, py = move.line[i - 1]
                length = math.hypot(lx - px, ly - py) or 1.0
                nx, ny = -(ly - py) / length, (lx - px) / length
                cost += (rise(x, y, a) / 30.0) ** 2
                for side in (-200, 200):
                    ex, ey = to_world(origin, turn, lx + nx * side, ly + ny * side)
                    cost += (rise(ex, ey, a) / 60.0) ** 2
            if not ok:
                continue
            nxt = ((int(round(end[0])), int(round(end[1]))), (turn + move.turn) % 360)
            # A little for every piece, so that the way does not wander.
            nd = d + cost + 2.0
            if nd < dist.get(nxt, 1e30):
                dist[nxt] = nd
                prev[nxt] = (state, move)
                heapq.heappush(heap, (nd, nxt))
    if goal is None:
        raise SystemExit("no way for the river was found")
    way, state = [], goal
    while state in prev:
        before, move = prev[state]
        way.append((move, before[0], before[1]))
        state = before
    way.reverse()
    return way, goal


def plan_heights(terrain, way, target=150.0):
    """The fall of every piece and the height of the first one, so that the water is close to
    the target depth over the land under its middle and never climbs. Returns (z0, [fall])."""
    grounds = []
    for move, origin, turn in way:
        grounds.append([terrain.height(*to_world(origin, turn, lx, ly)) for lx, ly in move.line])

    def penalty(depth):
        p = ((depth - target) / 60.0) ** 2
        if depth < 60:
            p += ((60 - depth) / 10.0) ** 2
        if depth > DEPTH - 20:
            p += ((depth - (DEPTH - 20)) / 10.0) ** 2
        return p

    def cost(i, z, fall):
        n = len(grounds[i]) - 1
        return sum(penalty(z - fall * k / n - g) for k, g in enumerate(grounds[i]))

    first = grounds[0][0]
    levels = [64 * k for k in range(int(first // 64) - 2, int(first // 64) + 8)]
    best = None
    for z0 in levels:
        # table[z] = (cost so far, falls so far) with the water at z where the next piece starts
        table = {z0: (0.0, [])}
        for i, (move, _, _) in enumerate(way):
            nxt = {}
            for z, (c, falls) in table.items():
                for fall in move.falls:
                    total = c + cost(i, z, fall)
                    if z - fall not in nxt or total < nxt[z - fall][0]:
                        nxt[z - fall] = (total, falls + [fall])
            table = nxt
        c, falls = min(table.values(), key=lambda v: v[0])
        if best is None or c < best[0]:
            best = (c, z0, falls)
    return best[1], best[2], grounds


def main():
    argv = sys.argv[1:]
    extra, args = [], []
    i = 0
    while i < len(argv):
        if argv[i] == "--land" and i + 1 < len(argv):
            extra.append(argv[i + 1])
            i += 2
        else:
            args.append(argv[i])
            i += 1
    if len(args) != 2:
        raise SystemExit(__doc__)
    data_files, output = args
    master = os.path.join(data_files, "Morrowind.esm")
    # The kit plugin: beside the output, in the mod folder of this repository, or installed.
    here = os.path.dirname(os.path.abspath(__file__))
    places = [os.path.dirname(os.path.abspath(output)), os.path.join(here, "..", "Water Volumes"), data_files]
    kit = next((os.path.join(place, KIT) for place in places if os.path.exists(os.path.join(place, KIT))), None)
    if kit is None:
        raise SystemExit("%s was not found beside the output, in the mod folder or in %s" % (KIT, data_files))

    terrain = Terrain([master] + extra, CELLS)
    top = terrain.lowest_near(TOP_NEAR[0], TOP_NEAR[1], 768)
    bottom = terrain.lowest_near(BOTTOM_NEAR[0], BOTTOM_NEAR[1], 768)
    floor = Floor(trace_floor(terrain, (top[1], top[2]), (bottom[1], bottom[2])))
    print("floor of the foyada: %.0f long, from height %.0f at %.0f, %.0f to height %.0f at %.0f, %.0f"
          % (floor.along[-1], top[0], top[1], top[2], bottom[0], bottom[1], bottom[2]))

    way, _ = plan_way(terrain, floor, ALLOWED)
    z0, falls, grounds = plan_heights(terrain, way)

    # (static, x, y, z, turn in degrees)
    placements = []
    z = z0
    first_origin, first_turn = way[0][1], way[0][2]
    placements.append((END_PIECE, first_origin[0], first_origin[1], z, (first_turn + 180) % 360))
    report = []
    for (move, origin, turn), fall, ground in zip(way, falls, grounds):
        name = move.piece(fall)
        placements.append((name, origin[0], origin[1], z, turn))
        n = len(ground) - 1
        depths = [z - fall * k / n - g for k, g in enumerate(ground)]
        report.append((name, origin, z, turn, min(depths), max(depths)))
        z -= fall
    last_move, last_origin, last_turn = way[-1]
    end = to_world(last_origin, last_turn, *last_move.end)
    placements.append((END_PIECE, int(round(end[0])), int(round(end[1])), z, (last_turn + last_move.turn) % 360))

    for name, origin, pz, turn, low, high in report:
        print("%-24s at %6d %6d %5d turned %3d  cell %d,%d  water %3.0f to %3.0f deep over the land"
              % (name, origin[0], origin[1], pz, turn, origin[0] // CELL, origin[1] // CELL, low, high))
    print("%d pieces and 2 ends; the water falls from %d to %d" % (len(way), z0, z))

    by_cell = {}
    for p in placements:
        by_cell.setdefault((int(p[1] // CELL), int(p[2] // CELL)), []).append(p)
    cell_records, index = [], 0
    for (gx, gy), refs in sorted(by_cell.items()):
        if (gx, gy) not in terrain.cells:
            raise SystemExit("exterior cell %d,%d not found" % (gx, gy))
        name, region, flags = terrain.cells[(gx, gy)]
        subs = [sub("NAME", name), sub("DATA", struct.pack("<Iii", flags, gx, gy))]
        if region:
            subs.append(sub("RGNN", region))
        subs.append(sub("NAM0", struct.pack("<I", len(refs))))
        for static, x, y, pz, turn in refs:
            index += 1
            subs.append(sub("FRMR", struct.pack("<I", index)))
            subs.append(sub("NAME", zstr(static)))
            subs.append(sub("DATA", struct.pack("<6f", x, y, pz, 0.0, 0.0, math.radians(turn))))
        cell_records.append(record("CELL", subs))
        print("cell %d,%d: %d pieces" % (gx, gy, len(refs)))

    description = b"Water Volumes demo: a river of kit pieces in Foyada Mamaea, south-west of Ghostgate."
    header = struct.pack("<fI32s256sI", 1.3, 0, b"Water Volumes", description, len(cell_records))
    tes3 = record("TES3", [
        sub("HEDR", header),
        sub("MAST", zstr("Morrowind.esm")), sub("DATA", struct.pack("<Q", os.path.getsize(master))),
        sub("MAST", zstr(KIT)), sub("DATA", struct.pack("<Q", os.path.getsize(kit))),
    ])
    with open(output, "wb") as handle:
        handle.write(tes3 + b"".join(cell_records))
    plan = os.path.splitext(output)[0] + ".json"
    with open(plan, "w", encoding="ascii") as handle:
        json.dump({"pieces": [{"id": p[0], "x": p[1], "y": p[2], "z": p[3], "turn": p[4]} for p in placements]}, handle, indent=1)
    print("wrote %s and %s" % (output, plan))


if __name__ == "__main__":
    main()
