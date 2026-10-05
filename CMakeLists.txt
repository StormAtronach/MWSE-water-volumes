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
# with the engine headers at ${MWSE_ROOT}/MWSE and ${MWSE_ROOT}/SharedSE. The
# default is the submodule at deps/mwse-upstream, pinned to a known-good MWSE
# commit. Override with -DMWSE_ROOT=... to build against another checkout.
set(MWSE_ROOT "${CMAKE_SOURCE_DIR}/deps/mwse-upstream"
    CACHE PATH "Path to MWSE source root (outer dir, containing deps/ and MWSE/)")

if(NOT EXISTS "${MWSE_ROOT}/SharedSE/NIAVObject.h")
    message(FATAL_ERROR
        "Couldn't find MWSE engine headers at ${MWSE_ROOT}/SharedSE/. "
        "Run: git submodule update --init --recursive")
endif()

# LuaJIT, for the C API headers and the import library of lua51.dll, which
# MWSE loads. MWSE carries it as a nested submodule that ships source only:
# deps/rubic0n today, deps/luajit2 in older checkouts.
if(EXISTS "${MWSE_ROOT}/deps/rubic0n/src/lua.h")
    set(LUAJIT_SRC "${MWSE_ROOT}/deps/rubic0n/src")
else()
    set(LUAJIT_SRC "${MWSE_ROOT}/deps/luajit2/src")
endif()
if(NOT EXISTS "${LUAJIT_SRC}/lua51.lib")
    message(FATAL_ERROR
        "Couldn't find lua51.lib at ${LUAJIT_SRC}. Initialise the submodules "
        "(git submodule update --init --recursive), then build LuaJIT there the way MWSE "
        "does: from a Visual Studio x86 developer prompt, in that directory, run "
        "`msvcbuild.bat lua52compat`.")
endif()

# The SharedSE engine sources the plugin uses. They build with the PCH, whose
# SharedSE prelude selects the Morrowind addresses. If the linker reports an
# unresolved NI:: or mwse:: symbol after an MWSE update, add its file here.
set(SHAREDSE_NAMES
    MemoryUtil
    NIAVObject
    NIBinaryStream
    NIBound
    NICamera
    NICollisionSwitch
    NIDynamicEffect
    NIGeometry
    NIGeometryData
    NIMatrix33
    NIMatrix44
    NINode
    NIObject
    NIObjectNET
    NIPoint3
    NIPoint4
    NIProperty
    NIQuaternion
    NIRTTI
    NISkinInstance
    NIStream
    NISwitchNode
    NITransform
    NITriBasedGeometry
    NITriBasedGeometryData
    NITriShape
    NITriShapeData
)
set(SHAREDSE_SOURCES "")
foreach(name IN LISTS SHAREDSE_NAMES)
    list(APPEND SHAREDSE_SOURCES "${MWSE_ROOT}/SharedSE/${name}.cpp")
endforeach()

add_library(watervolumes SHARED
    src/plugin.cpp
    # The water volumes themselves: registry and the engine hooks.
    src/WaterVolumes.cpp
    # The geometry of the water. It knows nothing of the game.
    src/Geometry.cpp
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
    "${LUAJIT_SRC}"
)

target_link_libraries(watervolumes PRIVATE
    "${LUAJIT_SRC}/lua51.lib"
)

# Full debug info in every config; the PDB stays in the build tree.
target_compile_options(watervolumes PRIVATE /Zi)
# The DLL names its PDB by file name only, not by the path on the build machine.
target_link_options(watervolumes PRIVATE /DEBUG /OPT:REF /OPT:ICF /PDBALTPATH:watervolumes.pdb)

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
    RUNTIME_OUTPUT_DIRECTORY_DEBUG   "${CMAKE_BINARY_DIR}/debug-lib"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/Water Volumes/MWSE/lib"
    PDB_OUTPUT_DIRECTORY_DEBUG       "${CMAKE_BINARY_DIR}/debug-lib"
    PDB_OUTPUT_DIRECTORY_RELEASE     "${CMAKE_BINARY_DIR}/pdb"
    OUTPUT_NAME "watervolumes"
)

# The geometry of the water, tested without the game:
#   build the target wv_geometry_test, then run ctest -C Release in the build folder.
add_executable(wv_geometry_test tests/geometry_test.cpp src/Geometry.cpp)
target_include_directories(wv_geometry_test PRIVATE src)
set_property(TARGET wv_geometry_test PROPERTY
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
enable_testing()
add_test(NAME geometry COMMAND wv_geometry_test)
