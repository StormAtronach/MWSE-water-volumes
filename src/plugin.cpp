// Water Volumes plugin - luaopen_watervolumes entry point. Loaded by MWSE's
// include("watervolumes"); what this returns becomes the Lua-side table.
//
// The Lua mod finds the water meshes and hands their scene nodes over by
// address. Everything the engine then asks about water goes through the
// hooks in WaterVolumes.cpp.

#include "Log.h"
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

// watervolumes.install() -> bool. Installs the engine hooks. Changes nothing
// and returns false if the executable is not the one the hooks were written
// for, or if something else has already patched the same places. Idempotent.
int install_lua(lua_State* L) {
    lua_pushboolean(L, wv::install() ? 1 : 0);
    return 1;
}

// The point given by three number arguments, the first of them at index.
NI::Point3 checkPoint(lua_State* L, int index) {
    return NI::Point3(
        static_cast<float>(luaL_checknumber(L, index)),
        static_cast<float>(luaL_checknumber(L, index + 1)),
        static_cast<float>(luaL_checknumber(L, index + 2)));
}

// watervolumes.addBox(minX, minY, minZ, maxX, maxY, maxZ) -> id, or 0.
int addBox_lua(lua_State* L) {
    lua_pushnumber(L, wv::add(checkPoint(L, 1), checkPoint(L, 4)));
    return 1;
}

// watervolumes.addNode(address, depth) -> id, or 0. The address is that of a
// scene graph branch, as mwse.memory.convertFrom.niObject gives it. The
// triangles are read at once; the node is afterwards only compared against.
int addNode_lua(lua_State* L) {
    const auto address = static_cast<uintptr_t>(luaL_checknumber(L, 1));
    const auto depth = static_cast<float>(luaL_optnumber(L, 2, 512.0));
    lua_pushnumber(L, wv::addFromNode(reinterpret_cast<NI::AVObject*>(address), depth));
    return 1;
}

// watervolumes.remove(id) -> bool.
int remove_lua(lua_State* L) {
    lua_pushboolean(L, wv::remove(static_cast<int>(luaL_checknumber(L, 1))) ? 1 : 0);
    return 1;
}

// watervolumes.clear().
int clear_lua(lua_State*) {
    wv::clear();
    return 0;
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

// watervolumes.count() -> number of registered volumes.
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

// watervolumes.flushLog() - force WaterVolumes.log to disk.
int flushLog_lua(lua_State*) {
    wv::log::flush();
    return 0;
}

}  // namespace

extern "C" __declspec(dllexport) int luaopen_watervolumes(lua_State* L) {
    lua_newtable(L);

    setStringField(L, "version", "0.1.0");
    setCFunctionField(L, "install", &install_lua);
    setCFunctionField(L, "addBox", &addBox_lua);
    setCFunctionField(L, "addNode", &addNode_lua);
    setCFunctionField(L, "remove", &remove_lua);
    setCFunctionField(L, "clear", &clear_lua);
    setCFunctionField(L, "surfaceAt", &surfaceAt_lua);
    setCFunctionField(L, "count", &count_lua);
    setCFunctionField(L, "hookStatus", &hookStatus_lua);
    setCFunctionField(L, "flushLog", &flushLog_lua);

#ifdef NDEBUG
    constexpr const char* kBuildConfig = "release";
#else
    constexpr const char* kBuildConfig = "DEBUG";
#endif
    wv::log::getLog() << "Water Volumes: loaded, awaiting install() from main.lua. build=" << kBuildConfig << std::endl;
    wv::log::flush();
    return 1;
}
