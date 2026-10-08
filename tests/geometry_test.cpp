// Tests of the geometry of the water, without the game.
//
// Build the target wv_geometry_test and run it; it prints one line per check and returns
// nonzero if any check fails.

#include "Geometry.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <random>

using wv::geometry::Shape;
using wv::geometry::Vec3;
using wv::geometry::CarriedStep;

namespace {
    int failures = 0;

    void check(bool ok, const char* what, const char* detail = "") {
        std::printf("%s %s%s%s\n", ok ? "PASS" : "FAIL", what, *detail ? ": " : "", detail);
        if (!ok) {
            failures++;
        }
    }

    // A turn about the three axes in order, and a shift.
    struct Placement {
        float m[3][3];
        Vec3 shift;

        Placement(float rx, float ry, float rz, Vec3 shift) : shift(shift) {
            const float cx = std::cos(rx), sx = std::sin(rx), cy = std::cos(ry), sy = std::sin(ry), cz = std::cos(rz), sz = std::sin(rz);
            const float values[3][3] = {
                { cy * cz, sx * sy * cz - cx * sz, cx * sy * cz + sx * sz },
                { cy * sz, sx * sy * sz + cx * cz, cx * sy * sz - sx * cz },
                { -sy, sx * cy, cx * cy },
            };
            for (auto i = 0; i < 3; ++i) {
                for (auto j = 0; j < 3; ++j) {
                    m[i][j] = values[i][j];
                }
            }
        }

        Vec3 toWorld(const Vec3& p) const {
            return {
                m[0][0] * p.x + m[0][1] * p.y + m[0][2] * p.z + shift.x,
                m[1][0] * p.x + m[1][1] * p.y + m[1][2] * p.z + shift.y,
                m[2][0] * p.x + m[2][1] * p.y + m[2][2] * p.z + shift.z,
            };
        }

        Vec3 toLocal(const Vec3& p) const {
            const Vec3 d = { p.x - shift.x, p.y - shift.y, p.z - shift.z };
            return {
                m[0][0] * d.x + m[1][0] * d.y + m[2][0] * d.z,
                m[0][1] * d.x + m[1][1] * d.y + m[2][1] * d.z,
                m[0][2] * d.x + m[1][2] * d.y + m[2][2] * d.z,
            };
        }
    };

    void addQuad(Shape& shape, const Placement& at, Vec3 a, Vec3 b, Vec3 c, Vec3 d) {
        shape.addTriangle(at.toWorld(a), at.toWorld(b), at.toWorld(c));
        shape.addTriangle(at.toWorld(a), at.toWorld(c), at.toWorld(d));
    }

    // The top and the bottom of the box between two corners. Its sides are seen edge-on from
    // above and never count.
    void addBox(Shape& shape, Vec3 corner, Vec3 opposite) {
        const auto x0 = std::min(corner.x, opposite.x), x1 = std::max(corner.x, opposite.x);
        const auto y0 = std::min(corner.y, opposite.y), y1 = std::max(corner.y, opposite.y);
        for (const auto z : { std::max(corner.z, opposite.z), std::min(corner.z, opposite.z) }) {
            shape.addTriangle({ x0, y0, z }, { x1, y0, z }, { x1, y1, z });
            shape.addTriangle({ x0, y0, z }, { x1, y1, z }, { x0, y1, z });
        }
    }

    constexpr float HALF = 512.0f, DEPTH = 512.0f;

    bool near(float a, float b) {
        return std::abs(a - b) < 0.01f;
    }

    // A box of water as a kit square has it: a surface, a bottom and four sides.
    Shape closedBox(const Placement& at) {
        Shape shape;
        const float h = HALF, d = DEPTH;
        addQuad(shape, at, { -h, -h, 0 }, { h, -h, 0 }, { h, h, 0 }, { -h, h, 0 });
        addQuad(shape, at, { -h, -h, -d }, { h, -h, -d }, { h, h, -d }, { -h, h, -d });
        addQuad(shape, at, { -h, -h, 0 }, { h, -h, 0 }, { h, -h, -d }, { -h, -h, -d });
        addQuad(shape, at, { h, -h, 0 }, { h, h, 0 }, { h, h, -d }, { h, -h, -d });
        addQuad(shape, at, { h, h, 0 }, { -h, h, 0 }, { -h, h, -d }, { h, h, -d });
        addQuad(shape, at, { -h, h, 0 }, { -h, -h, 0 }, { -h, -h, -d }, { -h, h, -d });
        shape.finish();
        return shape;
    }

    bool inWater(const Shape& shape, const Vec3& p) {
        float surface = 0.0f, floor = 0.0f;
        return shape.waterAt(p, false, surface, floor) && p.z <= surface && p.z >= floor;
    }

    void testClosedBoxAtAnyTilt() {
        std::mt19937 random(2025);
        std::uniform_real_distribution<float> angle(-3.14159f, 3.14159f), offset(-900.0f, 900.0f);
        auto wrong = 0, checked = 0, inside = 0;
        for (auto placement = 0; placement < 40; ++placement) {
            const Placement at(placement == 0 ? 0.0f : angle(random), placement == 0 ? 0.0f : angle(random), angle(random),
                { 12345.0f + offset(random), -67890.0f + offset(random), 1500.0f });
            const auto shape = closedBox(at);
            for (auto i = 0; i < 5000; ++i) {
                const Vec3 p = { at.shift.x + offset(random), at.shift.y + offset(random), at.shift.z + offset(random) };
                const auto l = at.toLocal(p);
                const auto nearFace = std::abs(std::abs(l.x) - HALF) < 1.0f || std::abs(std::abs(l.y) - HALF) < 1.0f || std::abs(l.z) < 1.0f || std::abs(l.z + DEPTH) < 1.0f;
                if (nearFace) {
                    continue;
                }
                const auto expected = std::abs(l.x) < HALF && std::abs(l.y) < HALF && l.z < 0.0f && l.z > -DEPTH;
                checked++;
                inside += expected;
                wrong += inWater(shape, p) != expected;
            }
        }
        char detail[128];
        std::snprintf(detail, sizeof(detail), "%d of %d points wrong over 40 placements, %d of them inside", wrong, checked, inside);
        check(wrong == 0 && inside > 1000, "a closed box holds exactly the water inside it at any tilt", detail);
    }

    void testPointsOnSharedEdges() {
        // The surface and the bottom of a level box are each two triangles that share a diagonal.
        const Placement level(0.0f, 0.0f, 0.0f, { 0.0f, 0.0f, 0.0f });
        const auto box = closedBox(level);
        auto wrong = 0, checked = 0;
        for (auto k = -500; k <= 500; k += 25) {
            checked++;
            wrong += !inWater(box, { static_cast<float>(k), static_cast<float>(k), -100.0f });
        }
        // The same for a tilted box: points under the diagonal of its surface.
        const Placement tilted(0.5f, 0.3f, 0.9f, { 2000.0f, -3000.0f, 800.0f });
        const auto tiltedBox = closedBox(tilted);
        for (auto k = -480; k <= 480; k += 20) {
            // A point 20 straight below a point on the diagonal of the surface.
            const auto onSurface = tilted.toWorld({ static_cast<float>(k), static_cast<float>(k), 0.0f });
            checked++;
            wrong += !inWater(tiltedBox, { onSurface.x, onSurface.y, onSurface.z - 20.0f });
        }
        char detail[96];
        std::snprintf(detail, sizeof(detail), "%d of %d points wrong", wrong, checked);
        check(wrong == 0, "a point under an edge that two triangles share is counted once", detail);
    }

    void testSheetClosedBelow() {
        Shape sheet;
        const Placement level(0.0f, 0.0f, 0.0f, { 0.0f, 0.0f, 100.0f });
        addQuad(sheet, level, { -200, -200, 0 }, { 200, -200, 0 }, { 200, 200, 0 }, { -200, 200, 0 });
        sheet.closeBelow(50.0f);
        sheet.finish();
        float surface = 0.0f, floor = 0.0f;
        const auto under = sheet.waterAt({ 0, 0, 80 }, false, surface, floor) && near(surface, 100.0f) && near(floor, 50.0f);
        const auto tooDeep = !sheet.waterAt({ 0, 0, 40 }, false, surface, floor);
        const auto above = sheet.waterAt({ 0, 0, 150 }, false, surface, floor) && near(surface, 100.0f);
        const auto beside = !sheet.waterAt({ 300, 0, 80 }, false, surface, floor);
        check(under && tooDeep && above && beside, "a sheet closed below: water from the sheet down to the depth, none below it or beside it");
    }

    void testTwoSidedSheet() {
        // Every face two times, the second time wound the other way: a surface for both sides.
        Shape sheet;
        const Placement level(0.0f, 0.0f, 0.0f, { 0.0f, 0.0f, 100.0f });
        addQuad(sheet, level, { -200, -200, 0 }, { 200, -200, 0 }, { 200, 200, 0 }, { -200, 200, 0 });
        addQuad(sheet, level, { -200, -200, 0 }, { -200, 200, 0 }, { 200, 200, 0 }, { 200, -200, 0 });
        sheet.closeBelow(50.0f);
        sheet.finish();
        float surface = 0.0f, floor = 0.0f;
        const auto under = sheet.waterAt({ 0, 0, 80 }, false, surface, floor) && near(surface, 100.0f) && near(floor, 50.0f);
        const auto tooDeep = !sheet.waterAt({ 0, 0, 40 }, false, surface, floor);
        check(under && tooDeep, "a sheet with every face two times is one sheet");
    }

    void testSlopedSheet() {
        Shape sheet;
        const Placement tilted(0.2f, 0.0f, 0.0f, { 500.0f, 500.0f, 1000.0f });
        addQuad(sheet, tilted, { -400, -400, 0 }, { 400, -400, 0 }, { 400, 400, 0 }, { -400, 400, 0 });
        sheet.closeBelow(300.0f);
        sheet.finish();
        auto worst = 0.0f;
        for (auto y = -300; y <= 300; y += 60) {
            const auto onSurface = tilted.toWorld({ 37.0f, static_cast<float>(y), 0.0f });
            float surface = 0.0f, floor = 0.0f;
            if (!sheet.waterAt({ onSurface.x, onSurface.y, onSurface.z - 50.0f }, false, surface, floor)) {
                worst = 1e9f;
                break;
            }
            worst = std::max(worst, std::abs(surface - onSurface.z) + std::abs(floor - (onSurface.z - 300.0f)));
        }
        char detail[64];
        std::snprintf(detail, sizeof(detail), "largest error %.4f", worst);
        check(worst < 0.01f, "a sloped sheet closed below: the surface over a point is the height of the sheet there, the floor the depth under it", detail);
    }

    void testMeshNotClosed() {
        // A sheet with nothing under it, and a box without its bottom.
        Shape sheet;
        const Placement level(0.0f, 0.0f, 0.0f, { 0.0f, 0.0f, 100.0f });
        addQuad(sheet, level, { -200, -200, 0 }, { 200, -200, 0 }, { 200, 200, 0 }, { -200, 200, 0 });
        sheet.finish();
        float surface = 0.0f, floor = 0.0f;
        const auto none = !sheet.waterAt({ 0, 0, 80 }, false, surface, floor) && !sheet.waterAt({ 0, 0, 150 }, false, surface, floor)
            && !sheet.waterAt({ 0, 0, 0 }, true, surface, floor);
        check(none, "a mesh that is not closed holds no water");
    }

    void testBodiesOverOneAnother() {
        // Two boxes in one mesh, one over the other with air between.
        Shape shape;
        addBox(shape, { -200, -200, 0 }, { 200, 200, 100 });
        addBox(shape, { -200, -200, 300 }, { 200, 200, 400 });
        shape.finish();
        float surface = 0.0f, floor = 0.0f;
        const auto upper = shape.waterAt({ 0, 0, 350 }, false, surface, floor) && near(surface, 400.0f) && near(floor, 300.0f);
        const auto between = shape.waterAt({ 0, 0, 200 }, false, surface, floor) && near(surface, 100.0f) && near(floor, 0.0f);
        const auto lower = shape.waterAt({ 0, 0, 50 }, false, surface, floor) && near(surface, 100.0f) && near(floor, 0.0f);
        const auto under = !shape.waterAt({ 0, 0, -50 }, false, surface, floor);
        const auto above = shape.waterAt({ 0, 0, 900 }, false, surface, floor) && near(surface, 400.0f);
        const auto anyHeight = shape.waterAt({ 0, 0, -5000 }, true, surface, floor) && near(surface, 400.0f);
        check(upper && between && lower && under && above && anyHeight, "bodies over one another: each holds its own water, and the air between them gets the water under it");
    }

    void testBox() {
        Shape box;
        addBox(box, { 10, 20, 30 }, { -10, -20, -30 });
        const auto made = box.finish();
        float surface = 0.0f, floor = 0.0f;
        const auto inside = box.waterAt({ 0, 0, 0 }, false, surface, floor) && surface == 30.0f && floor == -30.0f;
        const auto bounds = box.min.x == -10.0f && box.max.y == 20.0f && box.min.z == -30.0f;
        const auto under = !box.waterAt({ 0, 0, -40 }, false, surface, floor);
        const auto beside = !box.waterAt({ 15, 0, 0 }, false, surface, floor);
        Shape flat;
        addBox(flat, { 5, 0, 0 }, { 5, 10, 10 });
        check(made && inside && bounds && under && beside && !flat.finish(),
            "a box: the surface is its top and the floor its bottom, whatever the order of the corners; a box with no area is no water");
    }

    void testGridAgainstNoGrid() {
        // A wavy sheet of many triangles, once with the grid and once with a single cell.
        std::mt19937 random(7);
        std::uniform_real_distribution<float> where(-1100.0f, 1100.0f), height(-200.0f, 400.0f);
        Shape gridded, plain;
        const Placement level(0.0f, 0.0f, 0.0f, { 0.0f, 0.0f, 0.0f });
        for (auto ix = 0; ix < 40; ++ix) {
            for (auto iy = 0; iy < 25; ++iy) {
                const auto z = [](int x, int y) { return 60.0f * std::sin(x * 0.4f) * std::cos(y * 0.3f); };
                const float x0 = -1000.0f + ix * 50.0f, y0 = -625.0f + iy * 50.0f;
                for (auto* shape : { &gridded, &plain }) {
                    addQuad(*shape, level, { x0, y0, z(ix, iy) }, { x0 + 50, y0, z(ix + 1, iy) }, { x0 + 50, y0 + 50, z(ix + 1, iy + 1) }, { x0, y0 + 50, z(ix, iy + 1) });
                }
            }
        }
        gridded.closeBelow(150.0f);
        plain.closeBelow(150.0f);
        gridded.finish();
        plain.finish(1);
        auto different = 0, hits = 0;
        for (auto i = 0; i < 20000; ++i) {
            const Vec3 p = { where(random), where(random), height(random) };
            float s1 = 0.0f, f1 = 0.0f, s2 = 0.0f, f2 = 0.0f;
            const auto a = gridded.waterAt(p, false, s1, f1), b = plain.waterAt(p, false, s2, f2);
            hits += a;
            different += a != b || (a && (s1 != s2 || f1 != f2));
        }
        char detail[128];
        std::snprintf(detail, sizeof(detail), "%u by %u cells against 1; %d of 20000 answers differ, %d found water", gridded.gridSize, gridded.gridSize, different, hits);
        check(different == 0 && hits > 1000 && gridded.gridSize > 1, "the grid gives the same answers as looking at every triangle", detail);
    }
}

    void testFanVertex() {
        // A pyramid: four sides that meet in one vertex over the middle of a square base. A
        // point under that vertex, and points under the edges of the sides, are covered once.
        Shape pyramid;
        const Vec3 top = { 0, 0, 100 };
        const Vec3 base[4] = { { -100, -100, 0 }, { 100, -100, 0 }, { 100, 100, 0 }, { -100, 100, 0 } };
        for (auto i = 0; i < 4; ++i) {
            pyramid.addTriangle(base[i], base[(i + 1) % 4], top);
        }
        pyramid.addTriangle(base[0], base[1], base[2]);
        pyramid.addTriangle(base[0], base[2], base[3]);
        const auto made = pyramid.finish();
        float surface = 0.0f, floor = 0.0f;
        const auto underTop = pyramid.waterAt({ 0, 0, 50 }, false, surface, floor) && near(surface, 100.0f) && near(floor, 0.0f);
        auto wrong = 0;
        for (auto i = 1; i < 100; ++i) {
            // Along the two diagonals, under the edges where two sides meet
            const auto d = static_cast<float>(i);
            for (const auto& point : { Vec3{ d, d, 0.5f }, Vec3{ -d, d, 0.5f }, Vec3{ d, -d, 0.5f }, Vec3{ -d, -d, 0.5f } }) {
                if (!pyramid.waterAt(point, false, surface, floor) || !near(surface, 100.0f - d) || !near(floor, 0.0f)) {
                    wrong++;
                }
            }
        }
        char detail[64];
        std::snprintf(detail, sizeof(detail), "%d of 396 points wrong", wrong);
        check(made && underTop && wrong == 0, "a point under a vertex that many triangles share, or under their edges, is counted once", detail);
    }

    void testTooManyCrossings() {
        // More sheets over one another than the test keeps heights for: there inside and
        // outside cannot be told apart, and the answer is no water. Beside the stack it is
        // as always.
        Shape stack;
        for (auto i = 0; i < 20; ++i) {
            const auto z = static_cast<float>(i) * 100.0f;
            addBox(stack, { -50, -50, z }, { 50, 50, z + 50.0f });
        }
        addBox(stack, { 200, -50, 0 }, { 300, 50, 50 });
        stack.finish();
        float surface = 0.0f, floor = 0.0f;
        const auto inStack = stack.waterAt({ 0, 0, 25 }, false, surface, floor);
        const auto beside = stack.waterAt({ 250, 0, 25 }, false, surface, floor) && near(surface, 50.0f);
        check(!inStack && beside, "more crossings than are kept: no water there, and water as always beside it");
    }

    void testDrySpace() {
        // The dry space of a boat: a closed shape. A point is in it between its floor and its
        // top, and not over it, under it or beside it. Water that reaches higher does not count.
        Shape mask;
        addBox(mask, { -100, -40, -140 }, { 100, 40, 45 });
        mask.finish();
        // The floor face itself is not in the space: a point must be over it.
        const auto inside = mask.holds({ 0, 0, -100 }) && mask.holds({ 99, 39, 44 }) && mask.holds({ 0, 0, -139.5f });
        const auto outside = !mask.holds({ 0, 0, 60 }) && !mask.holds({ 0, 0, -150 }) && !mask.holds({ 120, 0, -100 }) && !mask.holds({ 0, 50, 0 });
        // Two dry spaces over one another in one mesh: the air between them is not dry.
        Shape two;
        addBox(two, { -50, -50, 0 }, { 50, 50, 100 });
        addBox(two, { -50, -50, 300 }, { 50, 50, 400 });
        two.finish();
        const auto between = !two.holds({ 0, 0, 200 }) && two.holds({ 0, 0, 50 }) && two.holds({ 0, 0, 350 });
        Shape open;
        const Placement level(0.0f, 0.0f, 0.0f, { 0.0f, 0.0f, 0.0f });
        addQuad(open, level, { -50, -50, 0 }, { 50, -50, 0 }, { 50, 50, 0 }, { -50, 50, 0 });
        open.finish();
        check(inside && outside && between && !open.holds({ 0, 0, -10 }), "a dry space: inside the closed shape and nowhere else; a shape that is not closed has none");
    }

    void testCarriedStep() {
        const auto same = [](const Vec3& v, float x, float y, float z) { return near(v.x, x) && near(v.y, y) && near(v.z, z); };
        // A boat that goes down 2 in a frame of a fiftieth of a second: 100 a second for who is in it.
        CarriedStep step;
        step.startLook();
        step.moved({ 0, 0, -2 }, 64.0f);
        const auto first = same(step.velocity(0.02f), 0, 0, -100);
        // Two actors in the boat get the same in one frame.
        const auto second = same(step.velocity(0.02f), 0, 0, -100);
        // At the next look the step is done with.
        step.startLook();
        const auto done = same(step.velocity(0.02f), 0, 0, 0);

        // A menu opens after a move: no actor moves in that frame, the boat stands still in
        // the next looks, and the step is still there when the game goes on.
        CarriedStep paused;
        paused.startLook();
        paused.moved({ 3, 0, -2 }, 64.0f);
        paused.startLook();
        paused.startLook();
        const auto kept = same(paused.velocity(0.02f), 150, 0, -100);
        // Steps add up while nobody was moved, and a frame of no time uses nothing.
        CarriedStep sum;
        sum.moved({ 1, 0, 0 }, 64.0f);
        sum.startLook();
        sum.moved({ 1, 0, 0 }, 64.0f);
        const auto noTime = same(sum.velocity(0.0f), 0, 0, 0);
        const auto both = same(sum.velocity(0.5f), 4, 0, 0);
        // A jump is a new place and carries nobody, and takes what was pending with it.
        CarriedStep jump;
        jump.moved({ 1, 0, 0 }, 64.0f);
        jump.moved({ 0, 500, 0 }, 64.0f);
        const auto none = same(jump.velocity(0.02f), 0, 0, 0);
        check(first && second && done && kept && noTime && both && none,
            "a step that carries: the same velocity for all in one frame, used once, kept over frames in which nobody moves, lost on a jump");
    }

int main() {
    testBox();
    testSheetClosedBelow();
    testTwoSidedSheet();
    testSlopedSheet();
    testMeshNotClosed();
    testBodiesOverOneAnother();
    testClosedBoxAtAnyTilt();
    testPointsOnSharedEdges();
    testGridAgainstNoGrid();
    testFanVertex();
    testTooManyCrossings();
    testDrySpace();
    testCarriedStep();
    std::printf("%d failed\n", failures);
    return failures == 0 ? 0 : 1;
}
