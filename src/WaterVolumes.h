#pragma once

#include "NIAVObject.h"
#include "NIPoint3.h"

namespace wv {
    // An edge of a triangle seen from above: a point on it, its direction, and which side of it
    // the triangle lies on.
    struct FootprintEdge {
        float x;
        float y;
        float dx;
        float dy;
        bool inside;
    };

    struct FootprintTriangle {
        NI::Point3 a;
        NI::Point3 b;
        NI::Point3 c;
        float denominator;
        FootprintEdge edges[3];
    };

    struct Volume {
        int id;
        // Bounds. For a box, max.z is the surface and min.z the floor.
        NI::Point3 min;
        NI::Point3 max;
        // How far the water reaches below a single layer of triangles. Unused for a box.
        float depth;
        // The scene graph branch the triangles came from. Compared, never followed.
        const NI::AVObject* node;
        // Empty for a box. Otherwise the triangles of the mesh, in world space.
        std::vector<FootprintTriangle> footprint;
        // The mesh has a WaterBody and so is closed: the water is what is inside it. Otherwise
        // the triangles are the surface: where they lie in one layer over a point the volume
        // reaches depth below them; where they lie in several, the lowest is the floor.
        bool closed;
        // A grid over the bounds. The triangles that touch cell n are
        // gridItems[gridStart[n]] up to, not including, gridItems[gridStart[n + 1]].
        std::vector<unsigned int> gridStart;
        std::vector<unsigned int> gridItems;
        unsigned int gridSize;
        float gridScaleX;
        float gridScaleY;
    };

    // Installs the hooks. Returns false and changes nothing if the executable does not match.
    bool install();

    // How many of the patched places still lead to this plugin, and how many there are.
    // Something that patches the same places later takes them away.
    void hookStatus(int& out_intact, int& out_total);

    // Adds a box of water. The surface is at max.z and the floor at min.z. Returns the volume id, or 0 on failure.
    int add(const NI::Point3& min, const NI::Point3& max);

    // Adds the water of a scene graph branch, using the current world positions of its triangles.
    // If the branch has a shape named WaterBody, the mesh is taken to be closed and the water is
    // what is inside it, at any tilt. Otherwise the triangles are the surface, which may slope,
    // and the volume reaches depth below them; where triangles lie over one another, the lowest
    // is the floor instead, and the water under each of the others reaches down to the one below.
    // Returns the volume id, or 0 on failure.
    int addFromNode(NI::AVObject* node, float depth);

    bool remove(int id);
    void clear();
    size_t count();

    // The surface height of the volume that contains the position, if any.
    std::optional<float> getSurfaceAt(const NI::Point3& position);
}
