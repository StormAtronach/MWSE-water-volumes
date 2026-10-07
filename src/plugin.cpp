// Water Volumes plugin - luaopen_watervolumes entry point. Loaded by MWSE's
// include("watervolumes"); what this returns becomes the Lua-side table.
//
// The Lua mod finds the water references and hands them over by address.
// Everything the engine then asks about water goes through the hooks in
// WaterVolumes.cpp.

#include "WaterVolumes.h"

#include <cstring>

extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

namespace {

void setStringField(lua_State* L, const char* key, const char* value) {
    lua_pushstring(L, key);
    lua_pushstring(L, value);
    lua_settable(L, -3);
}

void setCFunctionField(lua_State* L, const char* key, lua_CFunction fn) {
    lua_pushstring(L, key);
    lua_pushcfunction(L, fn);
    lua_settable(L, -3);
}

// watervolumes.install() -> true, or false and a message. Installs the engine
// hooks. Changes nothing and returns false if the executable is not the one
// the hooks were written for, or if something else has already patched the
// same places. Idempotent.
int install_lua(lua_State* L) {
    std::string message;
    if (wv::install(message)) {
        lua_pushboolean(L, 1);
        return 1;
    }
    lua_pushboolean(L, 0);
    lua_pushstring(L, message.c_str());
    return 2;
}

// The point given by three number arguments, the first of them at index.
NI::Point3 checkPoint(lua_State* L, int index) {
    return NI::Point3(
        static_cast<float>(luaL_checknumber(L, index)),
        static_cast<float>(luaL_checknumber(L, index + 1)),
        static_cast<float>(luaL_checknumber(L, index + 2)));
}

// watervolumes.addReference(address, depth, holdsWater) -> id, or 0. The address
// is that of a reference, as mwse.memory.convertFrom.tes3object gives it. The
// volume follows the reference from then on; see update. Remove it before the
// reference is freed. With holdsWater false the reference is followed for its
// mesh alone.
int addReference_lua(lua_State* L) {
    const auto address = static_cast<uintptr_t>(luaL_checknumber(L, 1));
    const auto depth = static_cast<float>(luaL_optnumber(L, 2, 512.0));
    const auto holdsWater = lua_isnoneornil(L, 3) || lua_toboolean(L, 3) != 0;
    lua_pushnumber(L, wv::add(reinterpret_cast<const TES3::Reference*>(address), depth, holdsWater));
    return 1;
}

// watervolumes.update() -> nil, or a list of ids. Brings the volumes of
// references in line with their references; call it once per frame. The ids
// are those of the volumes whose reference has another mesh than at the last
// call.
int update_lua(lua_State* L) {
    const auto& renewed = wv::update();
    if (renewed.empty()) {
        lua_pushnil(L);
        return 1;
    }
    lua_createtable(L, static_cast<int>(renewed.size()), 0);
    for (auto i = 0u; i < renewed.size(); ++i) {
        lua_pushnumber(L, renewed[i]);
        lua_rawseti(L, -2, static_cast<int>(i) + 1);
    }
    return 1;
}

// watervolumes.remove(id) -> bool.
int remove_lua(lua_State* L) {
    lua_pushboolean(L, wv::remove(static_cast<int>(luaL_checknumber(L, 1))) ? 1 : 0);
    return 1;
}

// watervolumes.setColor(id, red, green, blue) -> bool. The colour of the water
// of a volume, each part from 0 to 1, for the view from under its surface.
// Black takes the colour away.
int setColor_lua(lua_State* L) {
    const auto id = static_cast<int>(luaL_checknumber(L, 1));
    const auto color = checkPoint(L, 2);
    lua_pushboolean(L, wv::setColor(id, color.x, color.y, color.z) ? 1 : 0);
    return 1;
}

// A number field of the table at the top of the stack, or the default.
float numberField(lua_State* L, const char* key, float fallback) {
    lua_getfield(L, -1, key);
    const auto value = lua_isnumber(L, -1) ? static_cast<float>(lua_tonumber(L, -1)) : fallback;
    lua_pop(L, 1);
    return value;
}

// Up to count numbers from the array in the field, into out.
void numbersField(lua_State* L, const char* key, float* out, int count) {
    lua_getfield(L, -1, key);
    if (lua_istable(L, -1)) {
        for (int i = 0; i < count; ++i) {
            lua_rawgeti(L, -1, i + 1);
            if (lua_isnumber(L, -1)) {
                out[i] = static_cast<float>(lua_tonumber(L, -1));
            }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
}

// watervolumes.setFlow(id, x, y, carry, byDepth) -> true, or false for an
// unknown id. The current of the water: x and y in the axes of the mesh, in
// units per second, and how much of it carries an actor (0 to 1). With
// byDepth the carry grows with the depth of the actor, from nothing at the
// surface to all of it where the actor swims.
int setFlow_lua(lua_State* L) {
    const auto id = static_cast<int>(luaL_checknumber(L, 1));
    const auto x = static_cast<float>(luaL_checknumber(L, 2));
    const auto y = static_cast<float>(luaL_checknumber(L, 3));
    const auto carry = static_cast<float>(luaL_optnumber(L, 4, 1.0));
    const auto byDepth = lua_toboolean(L, 5) != 0;
    lua_pushboolean(L, wv::setFlow(id, x, y, carry, byDepth) ? 1 : 0);
    return 1;
}

// watervolumes.hasLooks() -> true when the renderer takes looks.
int hasLooks_lua(lua_State* L) {
    lua_pushboolean(L, wv::rendererHasLooks() ? 1 : 0);
    return 1;
}

// watervolumes.setLook(slot, look) -> true, or false when the renderer takes
// no looks. The look is a table: reflectsScene (default true), tintFromVertex,
// opacityFromVertex, flow {x, y}, speed, scale, glow, opacity, shader,
// params { {..}, {..}, {..}, {..} }, sky { red, green, blue }.
// A field that is missing has its standard value.
int setLook_lua(lua_State* L) {
    const auto slot = static_cast<unsigned int>(luaL_checknumber(L, 1));
    luaL_checktype(L, 2, LUA_TTABLE);
    lua_settop(L, 2);

    wv::Look look = {};
    look.size = sizeof(wv::Look);
    lua_getfield(L, 2, "reflectsScene");
    look.flags = (lua_isnil(L, -1) || lua_toboolean(L, -1)) ? 1u : 0u;
    lua_pop(L, 1);
    lua_getfield(L, 2, "tintFromVertex");
    look.flags |= lua_toboolean(L, -1) ? 2u : 0u;
    lua_pop(L, 1);
    lua_getfield(L, 2, "opacityFromVertex");
    look.flags |= lua_toboolean(L, -1) ? 4u : 0u;
    lua_pop(L, 1);
    numbersField(L, "flow", look.flow, 2);
    look.speed = numberField(L, "speed", 1.0f);
    look.scale = numberField(L, "scale", 1.0f);
    look.glow = numberField(L, "glow", 0.0f);
    look.opacity = numberField(L, "opacity", 1.0f);
    lua_getfield(L, 2, "params");
    if (lua_istable(L, -1)) {
        for (int i = 0; i < 4; ++i) {
            lua_rawgeti(L, -1, i + 1);
            if (lua_istable(L, -1)) {
                for (int j = 0; j < 4; ++j) {
                    lua_rawgeti(L, -1, j + 1);
                    if (lua_isnumber(L, -1)) {
                        look.params[i][j] = static_cast<float>(lua_tonumber(L, -1));
                    }
                    lua_pop(L, 1);
                }
            }
            lua_pop(L, 1);
        }
    }
    lua_pop(L, 1);
    lua_getfield(L, 2, "sky");
    if (lua_istable(L, -1)) {
        lua_pop(L, 1);
        lua_pushvalue(L, 2);
        numbersField(L, "sky", look.sky, 3);
        lua_pop(L, 1);
        look.flags |= 8;
    } else {
        lua_pop(L, 1);
    }
    lua_getfield(L, 2, "shader");
    if (lua_isstring(L, -1)) {
        strncpy_s(look.shader, lua_tostring(L, -1), _TRUNCATE);
    }
    lua_pop(L, 1);

    lua_pushboolean(L, wv::setRendererLook(slot, look) ? 1 : 0);
    return 1;
}

// watervolumes.surfaceAt(x, y, z) -> height of the surface of the water the
// point is in or over, or nil.
int surfaceAt_lua(lua_State* L) {
    const auto surface = wv::getSurfaceAt(checkPoint(L, 1));
    if (surface) {
        lua_pushnumber(L, *surface);
    } else {
        lua_pushnil(L);
    }
    return 1;
}

// watervolumes.waterAt(x, y, z) -> id, surface, floor of the water the point
// is in, or nil.
int waterAt_lua(lua_State* L) {
    const auto water = wv::getWaterAt(checkPoint(L, 1));
    if (!water) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushnumber(L, water->id);
    lua_pushnumber(L, water->surface);
    lua_pushnumber(L, water->floor);
    return 3;
}

// watervolumes.count() -> number of volumes that hold water now.
int count_lua(lua_State* L) {
    lua_pushnumber(L, static_cast<lua_Number>(wv::count()));
    return 1;
}

// watervolumes.hookStatus() -> intact, total. How many of the patched places
// still lead to the plugin.
int hookStatus_lua(lua_State* L) {
    int intact = 0, total = 0;
    wv::hookStatus(intact, total);
    lua_pushnumber(L, intact);
    lua_pushnumber(L, total);
    return 2;
}

}  // namespace

extern "C" __declspec(dllexport) int luaopen_watervolumes(lua_State* L) {
    lua_newtable(L);

    setStringField(L, "version", "0.1.1");
    setCFunctionField(L, "install", &install_lua);
    setCFunctionField(L, "addReference", &addReference_lua);
    setCFunctionField(L, "update", &update_lua);
    setCFunctionField(L, "remove", &remove_lua);
    setCFunctionField(L, "setColor", &setColor_lua);
    setCFunctionField(L, "setFlow", &setFlow_lua);
    setCFunctionField(L, "hasLooks", &hasLooks_lua);
    setCFunctionField(L, "setLook", &setLook_lua);
    setCFunctionField(L, "surfaceAt", &surfaceAt_lua);
    setCFunctionField(L, "waterAt", &waterAt_lua);
    setCFunctionField(L, "count", &count_lua);
    setCFunctionField(L, "hookStatus", &hookStatus_lua);

    return 1;
}
