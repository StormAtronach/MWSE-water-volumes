"""Works out where the water of each tier of the Palace of Vivec ends, for make_palace_water.py.

Input: the height maps that the harness scenario `palacescan` writes (tests/harness/water.lua):
for each tier, the height of the first solid below a point, every 8 units, against the height
of the vanilla water of that tier.

A tier is a channel between the sloped wall of the tier above and a parapet. The water is
raised to a level at which a person swims. Its edge is put in the middle of the parapet, so
that it is hidden in the stone all the way round. On three tiers the parapet has two openings,
through which the waterfalls leave; there the edge goes straight across, between the two
pillars of the opening.

Output: palace_outlines.json, in world units against the place of the water static.
"""
import json
import sys

import contourpy
import numpy as np
from scipy import ndimage
from shapely.geometry import LineString, Point, Polygon

SCAN = sys.argv[1] if len(sys.argv) > 1 else "C:/tmp/pondwater/palace"
STEP = 8
# The water static Ex_Vivec_P_water_01, as the game places it. It is turned half a circle.
ORIGIN = (32832.0, -106880.0, 512.0)
# How deep the water is over the floor of a channel. A person swims in water deeper than 0.9
# of their height, and the tallest are near 146 tall.
DEPTH = 135
# For each tier: the size of its map and where the map starts, the height of the vanilla
# water, and the waterfalls that leave it (where their references are, against the static).
TIERS = [
    {"columns": 729, "lines": 871, "west": 29920.0, "south": -110360.0, "surface": 498.4, "falls": []},
    {"columns": 611, "lines": 755, "west": 30392.0, "south": -109896.0, "surface": 883.0, "falls": [(-1120.3, 1449.2), (1183.9, 1449.2)]},
    {"columns": 507, "lines": 661, "west": 30808.0, "south": -109520.0, "surface": 1255.2, "falls": [(-861.6, 932.3), (929.5, 932.3)]},
    {"columns": 407, "lines": 561, "west": 31208.0, "south": -109120.0, "surface": 1639.3, "falls": [(-605.9, 429.3), (675.0, 428.0)]},
]
VOID = -100


def outline_of(index, tier):
    a = np.fromfile("%s/tier%d.bin" % (SCAN, index), dtype="<u2").reshape(tier["lines"], tier["columns"]).astype(np.int32) - 1000
    floor = int(np.bincount(a[(a > -40) & (a < 0)] + 40).argmax() - 40)
    level = floor + DEPTH

    def cell(x, y):
        return int(round((ORIGIN[0] + x - tier["west"]) / STEP)), int(round((ORIGIN[1] + y - tier["south"]) / STEP))

    # An opening is closed along the middle of its two pillars, which stand higher than the parapet.
    wall = np.zeros(a.shape, dtype=bool)
    gates = []
    for x, y in tier["falls"]:
        i, j = cell(x, y)
        near = a[j - 8:j + 20, i - 18:i + 19]
        rows = np.nonzero((near >= level + 30).any(axis=1))[0]
        middle = j - 8 + int(round((rows.min() + rows.max()) / 2))
        wall[middle - 1:middle + 1, i - 15:i + 16] = True
        gates.append((tier["south"] + (middle - 0.5) * STEP - ORIGIN[1], x))

    wet = (a > VOID) & (a < level) & ~wall
    labels, _ = ndimage.label(wet)
    counts = np.bincount(labels[(a >= floor - 1) & (a <= floor + 1) & wet])
    counts[0] = 0
    channel = labels == counts.argmax()
    filled = ndimage.binary_fill_holes(channel)
    outside = ~filled & (a < level) & ~wall
    assert not (ndimage.binary_dilation(filled, structure=np.ones((3, 3))) & outside).any(), "tier %d: the water has a way out at level %d" % (index, level)

    # The edge: as far from the water as from the open air.
    phi = ndimage.distance_transform_edt(~filled) - ndimage.distance_transform_edt(~outside)
    lines = contourpy.contour_generator(z=phi).lines(0.0)
    ring = max(lines, key=len)
    polygon = Polygon([(tier["west"] + p[0] * STEP - ORIGIN[0], tier["south"] + p[1] * STEP - ORIGIN[1]) for p in ring]).simplify(3.0)
    if not polygon.exterior.is_ccw:
        polygon = Polygon(list(polygon.exterior.coords)[::-1])
    points = [(round(x, 1), round(y, 1)) for x, y in polygon.exterior.coords[:-1]]

    # Checks. Along the edge the stone stands above the water, but for the openings.
    def height(x, y):
        i, j = (ORIGIN[0] + x - tier["west"]) / STEP, (ORIGIN[1] + y - tier["south"]) / STEP
        return ndimage.map_coordinates(a.astype(float), [[j], [i]], order=1)[0]

    open_edges, lowest = [], 9999.0
    count = len(points)
    for k in range(count):
        p, q = points[k], points[(k + 1) % count]
        samples = [height(p[0] + (q[0] - p[0]) * s / 8, p[1] + (q[1] - p[1]) * s / 8) for s in range(9)]
        at_gate = any(abs((p[1] + q[1]) / 2 - gate[0]) < 12 and min(p[0], q[0]) < gate[1] + 130 and max(p[0], q[0]) > gate[1] - 130 for gate in gates)
        if at_gate and min(samples) < level:
            open_edges.append(k)
        else:
            lowest = min(lowest, min(samples))
    ys, xs = np.nonzero(channel)
    wet_points = np.column_stack([tier["west"] + xs * STEP - ORIGIN[0], tier["south"] + ys * STEP - ORIGIN[1]])
    sample = wet_points[:: max(1, len(wet_points) // 4000)]
    margin = min(polygon.exterior.distance(Point(p)) for p in sample)
    inside = all(polygon.contains(Point(p)) for p in sample)
    print("tier %d: floor %d, water %d above the vanilla water; %d corners, %d open edges at %d openings; stone at the edge at least %.0f above the water;"
          " every wet point is inside: %s, nearest %.0f from the edge; area %.0f" % (index, floor, level, count, len(open_edges), len(gates), lowest - level, inside, margin, polygon.area))
    return {"tier": index, "vanillaSurface": tier["surface"], "raise": level, "floor": floor, "outline": points, "openEdges": open_edges}


result = {"origin": ORIGIN, "depth": DEPTH, "tiers": [outline_of(i + 1, t) for i, t in enumerate(TIERS)]}
target = __file__.replace("palace_outlines_from_scan.py", "palace_outlines.json")
with open(target, "w", encoding="ascii", newline="\n") as f:
    json.dump(result, f, indent=1)
print("written", target)
