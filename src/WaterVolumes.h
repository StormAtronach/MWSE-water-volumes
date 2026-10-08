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

    // Gives the water of a volume a colour: red, green and blue from 0 to 1. While the camera
    // is under the surface of that volume, the colour, made as dark as the game's own
    // underwater colour, is the game's underwater colour. Black takes the colour away. The colour of the surface is not set here: it is in the material
    // of the mesh, where the renderer reads it.
    bool setColor(int id, float red, float green, float blue);

    // How many volumes hold water now.
    size_t count();

    // The look of a surface beyond its colour, as the renderer takes it: the same flat layout
    // as MGE XE's WaterLook. A surface names its slot in the specular power of its material,
    // 100000 + slot.
    struct Look {
        unsigned int size;
        // 1: the surface reflects what is on screen; otherwise the sky only. 2: the vertex
        // colour tints the water. 4: the vertex alpha is the opacity. 8: sky holds the colour
        // that the surface reflects in place of the sky.
        unsigned int flags;
        // Drift of the ripples in the axes of the mesh, in units per second
        float flow[2];
        float speed;
        float scale;
        float glow;
        float opacity;
        float params[4][4];
        char shader[32];
        float sky[3];
        // Over how many units of water what is under the surface fades into the colour of
        // deep water; 800 is the standard
        float clarity;
    };

    // Gives the water of a volume a current: x and y in the axes of the mesh, in units per
    // second, and how much of it carries an actor in the water (0 to 1). With byDepth the
    // carry grows with the depth of the actor: nothing at the surface, all of it from the
    // depth at which the actor swims. The engine's own physics moves the actor by it, as it
    // does by the wind on the surface.
    bool setFlow(int id, float x, float y, float carry, bool byDepth);

    // True when the renderer takes looks.
    bool rendererHasLooks();

    // Tells the renderer the look of a slot, from 1 up. False when the renderer takes none.
    bool setRendererLook(unsigned int slot, const Look& look);

    // The surface height of the water that a position is in or over, if any.
    std::optional<float> getSurfaceAt(const NI::Point3& position);

    // The water that a position is in: the id of the volume, with the heights of its surface
    // and its bottom there.
    struct WaterAt {
        int id;
        float surface;
        float floor;
    };
    std::optional<WaterAt> getWaterAt(const NI::Point3& position);

    // True for a position in the dry space of a mask: a closed shape named WaterMask.
    bool isDryAt(const NI::Point3& position);
}
