#include "Geometry.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <set>

namespace wv::geometry {

    static bool sideOf(const Edge& edge, float x, float y) {
        return edge.dx * (y - edge.y) - edge.dy * (x - edge.x) >= 0.0f;
    }

    // The edge between two corners, seen from above. Its ends are put in a fixed order, so that
    // the two triangles that share an edge get the very same numbers for it and agree on which
    // side of it any point lies. A point on the line itself then belongs to exactly one of two
    // triangles that lie on opposite sides, and to both or neither of two that fold over.
    static Edge makeEdge(const Vec3& p, const Vec3& q, const Vec3& opposite) {
        const auto swapped = q.x < p.x || (q.x == p.x && q.y < p.y);
        const auto& from = swapped ? q : p;
        const auto& to = swapped ? p : q;
        Edge edge = { from.x, from.y, to.x - from.x, to.y - from.y, false };
        edge.inside = sideOf(edge, opposite.x, opposite.y);
        return edge;
    }

    static bool covers(const Triangle& t, float x, float y) {
        return sideOf(t.edges[0], x, y) == t.edges[0].inside
            && sideOf(t.edges[1], x, y) == t.edges[1].inside
            && sideOf(t.edges[2], x, y) == t.edges[2].inside;
    }

    void Shape::addTriangle(const Vec3& a, const Vec3& b, const Vec3& c) {
        Triangle triangle = {};
        triangle.a = a;
        triangle.b = b;
        triangle.c = c;
        triangle.denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
        if (std::abs(triangle.denominator) < 1e-6f) {
            return;
        }
        triangle.edges[0] = makeEdge(a, b, c);
        triangle.edges[1] = makeEdge(b, c, a);
        triangle.edges[2] = makeEdge(c, a, b);
        footprint.push_back(triangle);
    }

    void Shape::closeBelow(float depth) {
        const auto count = footprint.size();
        footprint.reserve(count * 2);
        for (auto i = 0u; i < count; ++i) {
            auto bottom = footprint[i];
            bottom.a.z -= depth;
            bottom.b.z -= depth;
            bottom.c.z -= depth;
            footprint.push_back(bottom);
        }
    }

    // The corners of a triangle in a fixed order, to an eighth of a unit: the same for two
    // triangles with the same corners, whichever way each is wound.
    static std::array<int, 9> cornersOf(const Triangle& triangle) {
        std::array<std::array<int, 3>, 3> corners;
        const Vec3* points[3] = { &triangle.a, &triangle.b, &triangle.c };
        for (auto i = 0; i < 3; ++i) {
            corners[i] = { static_cast<int>(std::lround(points[i]->x * 8.0f)), static_cast<int>(std::lround(points[i]->y * 8.0f)),
                           static_cast<int>(std::lround(points[i]->z * 8.0f)) };
        }
        std::sort(corners.begin(), corners.end());
        return { corners[0][0], corners[0][1], corners[0][2], corners[1][0], corners[1][1], corners[1][2], corners[2][0], corners[2][1], corners[2][2] };
    }

    bool Shape::finish(unsigned int maxGridSize) {
        if (footprint.empty()) {
            return false;
        }

        // A surface that is to be seen from both sides can have every face two times, one for
        // each side. The two are one face of the water: counted two times, they would cross
        // every vertical two times and there would be no water.
        {
            std::set<std::array<int, 9>> seen;
            footprint.erase(std::remove_if(footprint.begin(), footprint.end(), [&](const Triangle& triangle) {
                return !seen.insert(cornersOf(triangle)).second;
            }), footprint.end());
        }

        min = footprint[0].a;
        max = footprint[0].a;
        for (const auto& t : footprint) {
            for (const auto& corner : { t.a, t.b, t.c }) {
                min.x = std::min(min.x, corner.x);
                min.y = std::min(min.y, corner.y);
                min.z = std::min(min.z, corner.z);
                max.x = std::max(max.x, corner.x);
                max.y = std::max(max.y, corner.y);
                max.z = std::max(max.z, corner.z);
            }
        }

        // Spread the triangles over a grid, so that a lookup tests only the few near the point.
        const auto count = footprint.size();
        gridSize = std::clamp(static_cast<unsigned int>(std::ceil(std::sqrt(static_cast<float>(count)))), 1u, std::max(maxGridSize, 1u));
        const auto cellCount = gridSize * gridSize;
        gridScaleX = gridSize / std::max(max.x - min.x, 1.0f);
        gridScaleY = gridSize / std::max(max.y - min.y, 1.0f);

        const auto cellOf = [&](float value, float origin, float scale) {
            return std::clamp(static_cast<int>((value - origin) * scale), 0, static_cast<int>(gridSize) - 1);
        };
        const auto forEachCell = [&](const Triangle& t, const auto& visit) {
            const auto x0 = cellOf(std::min({ t.a.x, t.b.x, t.c.x }), min.x, gridScaleX);
            const auto x1 = cellOf(std::max({ t.a.x, t.b.x, t.c.x }), min.x, gridScaleX);
            const auto y0 = cellOf(std::min({ t.a.y, t.b.y, t.c.y }), min.y, gridScaleY);
            const auto y1 = cellOf(std::max({ t.a.y, t.b.y, t.c.y }), min.y, gridScaleY);
            for (auto y = y0; y <= y1; ++y) {
                for (auto x = x0; x <= x1; ++x) {
                    visit(y * gridSize + x);
                }
            }
        };

        // Count the triangles of each cell, turn the counts into where each cell starts, then
        // put the triangles in.
        gridStart.assign(cellCount + 1, 0);
        for (const auto& t : footprint) {
            forEachCell(t, [&](unsigned int cell) { gridStart[cell + 1]++; });
        }
        for (auto cell = 0u; cell < cellCount; ++cell) {
            gridStart[cell + 1] += gridStart[cell];
        }
        gridItems.resize(gridStart[cellCount]);
        std::vector<unsigned int> next(gridStart.begin(), gridStart.end() - 1);
        for (auto i = 0u; i < count; ++i) {
            forEachCell(footprint[i], [&](unsigned int cell) { gridItems[next[cell]++] = i; });
        }
        return true;
    }

    // The water at a position, from the heights at which the mesh crosses the vertical through
    // it. The position is inside the mesh, and so in the water, when the mesh crosses an odd
    // number of times above it. The water then reaches from the crossing above down to the
    // crossing below. A position above the water gets the water under it.
    static bool waterInside(float* heights, unsigned int crossings, const Vec3& position, bool ignoreHeight, float& out_surface, float& out_floor) {
        std::sort(heights, heights + crossings, std::greater<float>());

        auto above = 0u;
        if (!ignoreHeight) {
            while (above < crossings && heights[above] >= position.z) {
                above++;
            }
        }
        // Inside: the top is the crossing above. Outside: the top is the next crossing below.
        const auto top = (above % 2 == 1) ? above - 1 : above;
        // Where the mesh is not closed there is a top with no bottom, and no water.
        if (top + 1 >= crossings) {
            return false;
        }
        out_surface = heights[top];
        out_floor = heights[top + 1];
        return true;
    }

    bool Shape::waterAt(const Vec3& position, bool ignoreHeight, float& out_surface, float& out_floor) const {
        const auto x = position.x;
        const auto y = position.y;
        const auto cellX = std::clamp(static_cast<int>((x - min.x) * gridScaleX), 0, static_cast<int>(gridSize) - 1);
        const auto cellY = std::clamp(static_cast<int>((y - min.y) * gridScaleY), 0, static_cast<int>(gridSize) - 1);

        float heights[MAX_HEIGHTS];
        auto count = 0u;
        const auto cell = cellY * gridSize + cellX;
        for (auto item = gridStart[cell]; item < gridStart[cell + 1]; ++item) {
            const auto& t = footprint[gridItems[item]];
            if (!covers(t, x, y)) {
                continue;
            }
            const auto w1 = ((t.b.y - t.c.y) * (x - t.c.x) + (t.c.x - t.b.x) * (y - t.c.y)) / t.denominator;
            const auto w2 = ((t.c.y - t.a.y) * (x - t.c.x) + (t.a.x - t.c.x) * (y - t.c.y)) / t.denominator;
            const auto w3 = 1.0f - w1 - w2;
            heights[count++] = w1 * t.a.z + w2 * t.b.z + w3 * t.c.z;
            if (count == MAX_HEIGHTS) {
                break;
            }
        }
        // With more crossings than are kept, inside and outside cannot be told apart.
        if (count == MAX_HEIGHTS) {
            return false;
        }
        return waterInside(heights, count, position, ignoreHeight, out_surface, out_floor);
    }
}
