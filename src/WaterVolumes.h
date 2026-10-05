#pragma once

#include "NIPoint3.h"

namespace TES3 {
    struct Reference;
}

namespace wv {
    // Installs the hooks. Returns false and changes nothing if the executable does not match;
    // the message then says why.
    bool install(std::string& out_message);

    // How many of the patched places still lead to this plugin, and how many there are.
    // Something that patches the same places later takes them away.
    void hookStatus(int& out_intact, int& out_total);

    // Adds the water of the mesh of a reference. The water is what is inside the mesh, at any
    // tilt; where the mesh is not closed there is none. A mesh with a shape named WaterBody is
    // taken as it is: the body closes it. A mesh without one is the surface alone, one sheet
    // that may slope, and is closed with a copy of itself depth below, scaled as the reference
    // is; with a depth of 0 it is taken as it is.
    //
    // The volume follows the reference: update() moves it with the reference and takes its
    // water away while the reference is disabled, deleted or without a mesh. Remove the volume
    // before the reference is freed. With holdsWater false there is never any water, and the
    // reference is followed for its mesh alone.
    //
    // Returns the volume id, or 0 on failure.
    int add(const TES3::Reference* reference, float depth, bool holdsWater);

    // Brings the volumes in line with their references. Call it once per frame. Returns the
    // ids of the volumes whose reference has another mesh than at the last call.
    const std::vector<int>& update();

    bool remove(int id);

    // How many volumes hold water now.
    size_t count();

    // The surface height of the water that a position is in or over, if any.
    std::optional<float> getSurfaceAt(const NI::Point3& position);
}
