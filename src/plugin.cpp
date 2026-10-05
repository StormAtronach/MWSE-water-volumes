// Water Volumes plugin - luaopen_watervolumes entry point. Loaded by MWSE's
// include("watervolumes"); what this returns becomes the Lua-side table.
//
// The Lua mod finds the water references and hands them over by address.
// Everything the engine then asks about water goes through the hooks in
// WaterVolumes.cpp.

#include "WaterVolumes.h"

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

    setStringField(L, "version", "0.1.0");
    setCFunctionField(L, "install", &install_lua);
    setCFunctionField(L, "addReference", &addReference_lua);
    setCFunctionField(L, "update", &update_lua);
    setCFunctionField(L, "remove", &remove_lua);
    setCFunctionField(L, "surfaceAt", &surfaceAt_lua);
    setCFunctionField(L, "count", &count_lua);
    setCFunctionField(L, "hookStatus", &hookStatus_lua);

    return 1;
}
