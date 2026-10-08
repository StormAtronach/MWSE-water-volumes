#pragma once

#include <vector>

// The water of one closed mesh, as plain geometry. Nothing in here knows the game, so that it
// can be tested without the game: see tests/geometry_test.cpp.
namespace wv::geometry {
    struct Vec3 {
        float x;
        float y;
        float z;
    };

    // An edge of a triangle seen from above: a point on it, its direction, and which side of it
    // the triangle lies on.
    struct Edge {
        float x;
        float y;
        float dx;
        float dy;
        bool inside;
    };

    struct Triangle {
        Vec3 a;
        Vec3 b;
        Vec3 c;
        float denominator;
        Edge edges[3];
    };

    // The most places at which a mesh may cross the vertical through one point. A point where
    // it crosses more often has no water.
    constexpr auto MAX_HEIGHTS = 32u;

    // A closed mesh. The water is what is inside it: a point is in the water when the mesh
    // crosses the vertical through the point an odd number of times above it.
    struct Shape {
        Vec3 min = {};
        Vec3 max = {};
        // The triangles of the mesh, in world space.
        std::vector<Triangle> footprint;
        // A grid over the bounds. The triangles that touch cell n are
        // gridItems[gridStart[n]] up to, not including, gridItems[gridStart[n + 1]].
        std::vector<unsigned int> gridStart;
        std::vector<unsigned int> gridItems;
        unsigned int gridSize = 0;
        float gridScaleX = 0.0f;
        float gridScaleY = 0.0f;

        // Adds a triangle of the mesh. A triangle seen edge-on from above covers no area and is
        // left out: it never crosses a vertical.
        void addTriangle(const Vec3& a, const Vec3& b, const Vec3& c);

        // Closes a mesh that is only the surface of the water: adds every triangle again, this
        // much lower, as the bottom. The surface must be one sheet, with no part of it over
        // another.
        void closeBelow(float depth);

        // Works out the bounds and the grid once every triangle is added. A triangle that is
        // there two times, as in a surface with two sides, counts one time. Returns false if
        // there is no triangle. maxGridSize is for the tests; the game uses the default.
        bool finish(unsigned int maxGridSize = 64);

        // The surface and the floor of the water at a position, if there is any. A position
        // above the water gets the water under it. With ignoreHeight only where the position is
        // on the map counts, and the answer is the top surface there.
        bool waterAt(const Vec3& position, bool ignoreHeight, float& out_surface, float& out_floor) const;

        // True for a point inside the closed shape: in its bounds, and between a top and a
        // bottom of it. This is the test for a dry space.
        bool holds(const Vec3& point) const {
            if (point.x < min.x || point.x > max.x || point.y < min.y || point.y > max.y || point.z < min.z || point.z > max.z) {
                return false;
            }
            float top = 0.0f, bottom = 0.0f;
            return waterAt(point, false, top, bottom) && point.z <= top && point.z >= bottom;
        }
    };
    // How far a thing that carries what stands in it has moved, and nobody was yet moved for.
    // The thing is looked at once a frame; the movement of the actors asks for the step as a
    // velocity. The step is kept until it was asked for, so that a frame in which no actor
    // moves, a frame of a menu, does not lose it.
    struct CarriedStep {
        Vec3 pending = { 0.0f, 0.0f, 0.0f };
        bool used = false;

        // At each look, before the new step is known: a step that was used is done with.
        void startLook() {
            if (used) {
                pending = { 0.0f, 0.0f, 0.0f };
                used = false;
            }
        }

        // The thing moved by this much since the last look. A step longer than the limit is
        // a new place, not a move, and carries nobody.
        void moved(const Vec3& step, float longest) {
            if (step.x * step.x + step.y * step.y + step.z * step.z < longest * longest) {
                pending = { pending.x + step.x, pending.y + step.y, pending.z + step.z };
            } else {
                pending = { 0.0f, 0.0f, 0.0f };
            }
        }

        void clear() {
            pending = { 0.0f, 0.0f, 0.0f };
            used = false;
        }

        // The step as a velocity for a frame of this many seconds. Nothing for a frame of no
        // time, and the step is kept then.
        Vec3 velocity(float seconds) {
            if (seconds <= 0.0f) {
                return { 0.0f, 0.0f, 0.0f };
            }
            used = true;
            return { pending.x / seconds, pending.y / seconds, pending.z / seconds };
        }
    };
}
