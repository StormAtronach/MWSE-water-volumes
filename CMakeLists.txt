cmake_minimum_required(VERSION 3.21)
project(water-volumes-plugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Morrowind is x86 - the plugin must match. Configure with a preset:
#   cmake --preset win32-release
if(NOT CMAKE_GENERATOR_PLATFORM STREQUAL "Win32")
    message(FATAL_ERROR "Configure with -A Win32. Morrowind is 32-bit; an x64 DLL won't load.")
endif()

# Path to the MWSE source the plugin compiles against: the OUTER repo root,
# with LuaJIT at ${MWSE_ROOT}/deps/luajit2/src and the engine headers at
# ${MWSE_ROOT}/MWSE and ${MWSE_ROOT}/SharedSE.
#
# The default borrows the pinned checkout of the msoc plugin, which sits
# beside this repository and already has LuaJIT built. Give this project a
# submodule of its own at deps/mwse-upstream before it is built anywhere else.
if(EXISTS "${CMAKE_SOURCE_DIR}/deps/mwse-upstream/SharedSE/NIAVObject.h")
    set(MWSE_ROOT_DEFAULT "${CMAKE_SOURCE_DIR}/deps/mwse-upstream")
else()
    set(MWSE_ROOT_DEFAULT "${CMAKE_SOURCE_DIR}/../msoc-plugin/deps/mwse-upstream")
endif()
set(MWSE_ROOT "${MWSE_ROOT_DEFAULT}"
    CACHE PATH "Path to MWSE source root (outer dir, containing deps/ and MWSE/)")

if(NOT EXISTS "${MWSE_ROOT}/deps/luajit2/src/lua51.lib")
    message(FATAL_ERROR
        "Couldn't find lua51.lib at ${MWSE_ROOT}/deps/luajit2/src/. Build LuaJIT there the way "
        "MWSE does: from a Visual Studio x86 developer prompt run `msvcbuild.bat lua52compat`.")
endif()
if(NOT EXISTS "${MWSE_ROOT}/SharedSE/NIAVObject.h")
    message(FATAL_ERROR "Couldn't find MWSE engine headers at ${MWSE_ROOT}/SharedSE/.")
endif()

# SharedSE engine sources, compiled in full, as the msoc plugin does. They
# build with the PCH, whose SharedSE prelude selects the Morrowind addresses.
file(GLOB SHAREDSE_SOURCES CONFIGURE_DEPENDS "${MWSE_ROOT}/SharedSE/*.cpp")
# The crash logger formats through fmtlib, which this project does not carry.
list(FILTER SHAREDSE_SOURCES EXCLUDE REGEX "/CrashLog[^/]*\.cpp$")

add_library(watervolumes SHARED
    src/plugin.cpp
    src/Log.cpp
    # The water volumes themselves: registry, lookup, and the engine hooks.
    src/WaterVolumes.cpp
    # The few TES3 accessors the hooks call. SharedSE has no TES3 layer.
    src/MWSEImports.cpp
    ${SHAREDSE_SOURCES}
)

target_precompile_headers(watervolumes PRIVATE src/stdafx.h)

target_include_directories(watervolumes PRIVATE
    "${MWSE_ROOT}/MWSE"
    "${MWSE_ROOT}/SharedSE"
    "${MWSE_ROOT}/deps/sol/include"
    "${MWSE_ROOT}/deps/DirectX8/include"
    "${MWSE_ROOT}/deps/luajit2/src"
)

target_link_libraries(watervolumes PRIVATE
    "${MWSE_ROOT}/deps/luajit2/src/lua51.lib"
)

# Full debug info in every config; the PDB stays in the build tree.
target_compile_options(watervolumes PRIVATE /Zi)
target_link_options(watervolumes PRIVATE /DEBUG /OPT:REF /OPT:ICF)

target_compile_definitions(watervolumes PRIVATE
    _CRT_SECURE_NO_WARNINGS
    NOMINMAX
    WIN32_LEAN_AND_MEAN
    _SILENCE_CXX17_ITERATOR_BASE_CLASS_DEPRECATION_WARNING
)

# Static CRT, matching MWSE proper: no VC++ redistributable needed.
set_property(TARGET watervolumes PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

# Release drops into the mod folder's lib dir, so include("watervolumes")
# finds it and the folder zips as the archive. Debug goes to the build tree,
# so that a debug build never replaces the release artifact.
set_target_properties(watervolumes PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY         "${CMAKE_SOURCE_DIR}/Water Volumes/MWSE/lib"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_BINARY_DIR}/debug-lib"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/Water Volumes/MWSE/lib"
    PDB_OUTPUT_DIRECTORY             "${CMAKE_BINARY_DIR}/pdb"
    PDB_OUTPUT_DIRECTORY_DEBUG       "${CMAKE_BINARY_DIR}/debug-lib"
    PDB_OUTPUT_DIRECTORY_RELEASE     "${CMAKE_BINARY_DIR}/pdb"
    OUTPUT_NAME "watervolumes"
)
