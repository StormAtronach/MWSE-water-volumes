#include "WaterVolumes.h"

#include "Geometry.h"
#include "MemoryUtil.h"

#include "TES3ActorAnimationController.h"
#include "TES3Cell.h"
#include "TES3CombatSession.h"
#include "TES3DataHandler.h"
#include "TES3MobileActor.h"
#include "TES3MobilePlayer.h"
#include "TES3Reference.h"
#include "TES3WaterController.h"
#include "TES3WeatherController.h"
#include "TES3WorldController.h"

#include "NICamera.h"
#include "NINode.h"
#include "NIRTTI.h"
#include "NITriShape.h"
#include "NITriShapeData.h"

#include <algorithm>
#include <cstdint>
#include <functional>
#include <memory>

namespace wv {

    //
    // Registry.
    //

    // The water of one reference: the closed mesh it has now, and what it was made from.
    struct Volume : geometry::Shape {
        int id = 0;
        // The reference whose mesh this is. The volume is kept in line with it.
        const TES3::Reference* reference = nullptr;
        // False for a mesh that only looks like water. It is followed for its mesh alone.
        bool holdsWater = true;
        // How far the water of a mesh without a body reaches below its surface, at scale 1.
        float depth = 0.0f;

        // The scene graph branch of the reference when it was last looked at. Compared, never
        // followed.
        const NI::AVObject* node = nullptr;
        // Its water counts: it is in the squares of the world.
        bool linked = false;
        // The dry space of the mesh: a closed shape named WaterMask. Inside it there is no
        // water, of this volume, of another one, or of the cell: the hold of a boat, a cellar
        // under a lake, a bubble of air under the sea.
        geometry::Shape mask;
        // The mask counts: it is in the list of the masks.
        bool masked = false;
        // The triangles, or their absence, are those of the placement below.
        bool current = false;
        NI::Matrix33 rotation;
        NI::Point3 translation;
        float scale = 0.0f;

        // The colour of the water, for the view from under its surface. Black is the game's own.
        NI::Point3 color = { 0.0f, 0.0f, 0.0f };
        bool colored = false;

        // The current of the water, in the axes of the mesh, in units per second, and how
        // much of it carries an actor. Zero carries nobody. With carryByDepth the carry grows
        // from nothing at the surface to all of it at the depth where the actor swims.
        NI::Point3 flow = { 0.0f, 0.0f, 0.0f };
        float carry = 0.0f;
        bool carryByDepth = false;
    };

    static std::unordered_map<int, std::unique_ptr<Volume>> volumes;
    static int nextVolumeId = 1;
    static bool installed = false;
    static DWORD mainThreadId = 0;

    // Read from assembly. True while at least one volume holds water or has a mask.
    static bool anyVolumes = false;
    static size_t linkedCount = 0;
    // The volumes that have a dry space. There are few, and every one is tested.
    static std::vector<const Volume*> masks;

    // The volumes by the squares of the world their bounds touch, so that a lookup tests only
    // the ones near the point. A volume that touches too many squares is tested every time.
    constexpr auto BUCKET_SIZE = 1024.0f;
    constexpr auto MAX_BUCKETS_PER_VOLUME = 256;
    static std::unordered_map<std::uint64_t, std::vector<const Volume*>> buckets;
    static std::vector<const Volume*> wideVolumes;

    // The scene graph branches of the volumes.
    static std::unordered_multiset<const NI::AVObject*> volumeNodes;

    // Creatures that can only swim, with where each was last seen in the water of a volume.
    struct KeptSwimmer {
        NI::Point3 position;
        DWORD seen;
    };
    static std::unordered_map<const TES3::MobileActor*, KeptSwimmer> keptSwimmers;

    // The mobile that came by last. Several hooked functions run for one mobile in a row, and
    // one look at it is enough; the next mobile, if only the player, makes it due again.
    static const TES3::MobileObject* lastLookedAt = nullptr;

    static int bucketOf(float value) {
        return static_cast<int>(std::clamp(std::floor(value / BUCKET_SIZE), -2e6f, 2e6f));
    }

    static std::uint64_t bucketKey(int x, int y) {
        return (static_cast<std::uint64_t>(static_cast<std::uint32_t>(x)) << 32) | static_cast<std::uint32_t>(y);
    }

    // The squares a volume touches. None if it touches too many.
    static std::vector<std::uint64_t> bucketKeys(const Volume& volume) {
        const auto x0 = bucketOf(volume.min.x), x1 = bucketOf(volume.max.x);
        const auto y0 = bucketOf(volume.min.y), y1 = bucketOf(volume.max.y);
        std::vector<std::uint64_t> keys;
        if (static_cast<std::int64_t>(x1 - x0 + 1) * (y1 - y0 + 1) > MAX_BUCKETS_PER_VOLUME) {
            return keys;
        }
        for (auto y = y0; y <= y1; ++y) {
            for (auto x = x0; x <= x1; ++x) {
                keys.push_back(bucketKey(x, y));
            }
        }
        return keys;
    }

    static void link(Volume& volume) {
        const auto keys = bucketKeys(volume);
        if (keys.empty()) {
            wideVolumes.push_back(&volume);
        }
        for (const auto key : keys) {
            buckets[key].push_back(&volume);
        }
        if (volume.node != nullptr) {
            volumeNodes.insert(volume.node);
        }
        volume.linked = true;
        linkedCount++;
        anyVolumes = true;
    }

    // Gives the renderer the triangles of all dry spaces, so that it does not draw water in
    // them.
    static void sendMasksToRenderer() {
        using Setter = void(__cdecl*)(const float*, unsigned int);
        static const auto setter = []() -> Setter {
            const auto renderer = GetModuleHandleA("d3d8.dll");
            return renderer == NULL ? nullptr : reinterpret_cast<Setter>(GetProcAddress(renderer, "MGE_WaterMasksSet"));
        }();
        if (setter == nullptr) {
            return;
        }
        std::vector<float> corners;
        for (const auto volume : masks) {
            for (const auto& triangle : volume->mask.footprint) {
                for (const auto& corner : { triangle.a, triangle.b, triangle.c }) {
                    corners.push_back(corner.x);
                    corners.push_back(corner.y);
                    corners.push_back(corner.z);
                }
            }
        }
        setter(corners.empty() ? nullptr : corners.data(), static_cast<unsigned int>(corners.size() / 9));
    }

    static void addMask(Volume& volume) {
        masks.push_back(&volume);
        volume.masked = true;
        anyVolumes = true;
        sendMasksToRenderer();
    }

    static void removeMask(Volume& volume) {
        if (volume.masked) {
            std::erase(masks, &volume);
            volume.masked = false;
            anyVolumes = linkedCount != 0 || !masks.empty();
            sendMasksToRenderer();
        }
    }

    // True for a point in the dry space of a mask.
    static bool isDry(const NI::Point3* position) {
        const geometry::Vec3 point = { position->x, position->y, position->z };
        for (const auto volume : masks) {
            const auto& mask = volume->mask;
            if (point.x < mask.min.x || point.x > mask.max.x || point.y < mask.min.y || point.y > mask.max.y
                || point.z < mask.min.z || point.z > mask.max.z) {
                continue;
            }
            float top = 0.0f, bottom = 0.0f;
            if (mask.waterAt(point, false, top, bottom) && point.z <= top && point.z >= bottom) {
                return true;
            }
        }
        return false;
    }

    static void unlink(Volume& volume) {
        removeMask(volume);
        if (!volume.linked) {
            return;
        }
        const auto keys = bucketKeys(volume);
        if (keys.empty()) {
            std::erase(wideVolumes, &volume);
        }
        for (const auto key : keys) {
            const auto bucket = buckets.find(key);
            if (bucket != buckets.end() && std::erase(bucket->second, &volume) > 0 && bucket->second.empty()) {
                buckets.erase(bucket);
            }
        }
        const auto node = volumeNodes.find(volume.node);
        if (node != volumeNodes.end()) {
            volumeNodes.erase(node);
        }
        volume.linked = false;
        linkedCount--;
        anyVolumes = linkedCount != 0 || !masks.empty();
    }

    // Layout shared with the renderer's exported setter.
    struct ExportedVolume {
        float min[3];
        float max[3];
    };

    // The renderer is told about one volume at most: the one the camera is in, as a box whose
    // top is the surface at the camera.
    static int rendererVolumeId = 0;
    static float rendererSurface = 0.0f;

    using RendererSetter = void(__cdecl*)(const ExportedVolume*, unsigned int);

    static RendererSetter findRendererSetter() {
        const auto renderer = GetModuleHandleA("d3d8.dll");
        if (renderer == NULL) {
            return nullptr;
        }
        return reinterpret_cast<RendererSetter>(GetProcAddress(renderer, "MGE_WaterVolumesSet"));
    }

    static void setRendererVolume(const Volume* volume, float surface, float floor) {
        const auto id = volume ? volume->id : 0;
        if (id == rendererVolumeId && (id == 0 || std::abs(surface - rendererSurface) < 0.5f)) {
            return;
        }
        rendererVolumeId = id;
        rendererSurface = surface;

        static const auto setter = findRendererSetter();
        if (setter == nullptr) {
            return;
        }

        if (volume) {
            const ExportedVolume exported = { { volume->min.x, volume->min.y, floor }, { volume->max.x, volume->max.y, surface } };
            setter(&exported, 1);
        }
        else {
            setter(nullptr, 0);
        }
    }

    // Tells the renderer that the camera is in a dry space, where it is not under water.
    static void setRendererDry(bool dry) {
        static bool told = false;
        if (dry == told) {
            return;
        }
        told = dry;
        using Setter = void(__cdecl*)(int);
        static const auto setter = []() -> Setter {
            const auto renderer = GetModuleHandleA("d3d8.dll");
            return renderer == NULL ? nullptr : reinterpret_cast<Setter>(GetProcAddress(renderer, "MGE_WaterDrySet"));
        }();
        if (setter != nullptr) {
            setter(dry ? 1 : 0);
        }
    }

    using RendererLookSetter = void(__cdecl*)(unsigned int, const Look*);

    static RendererLookSetter findRendererLookSetter() {
        const auto renderer = GetModuleHandleA("d3d8.dll");
        if (renderer == NULL) {
            return nullptr;
        }
        return reinterpret_cast<RendererLookSetter>(GetProcAddress(renderer, "MGE_WaterLookSet"));
    }

    bool rendererHasLooks() {
        static const auto setter = findRendererLookSetter();
        return setter != nullptr;
    }

    bool setRendererLook(unsigned int slot, const Look& look) {
        static const auto setter = findRendererLookSetter();
        if (setter == nullptr || slot == 0) {
            return false;
        }
        Look sent = look;
        sent.size = sizeof(Look);
        sent.shader[sizeof(sent.shader) - 1] = '\0';
        setter(slot, &sent);
        return true;
    }

    // A shape named WaterBody gives the sides and the bottom of the water. It is hidden in the
    // game and counts all the same. With the surface it closes the mesh.
    static bool isWaterBody(const NI::AVObject* object) {
        const auto name = object->getName();
        return name != nullptr && _strnicmp(name, "WaterBody", 9) == 0;
    }

    static bool isWaterMask(const NI::AVObject* object) {
        const auto name = object->getName();
        return name != nullptr && _strnicmp(name, "WaterMask", 9) == 0;
    }

    static bool isWaterSurface(const NI::AVObject* object) {
        const auto name = object->getName();
        return name != nullptr && _strnicmp(name, "WaterVolume", 11) == 0;
    }

    // True if something in the branch is named as the surface of the water, or as a mask: the
    // mesh then says itself what in it is water, and a mesh with a mask alone has none.
    static bool hasNamedSurface(NI::AVObject* object) {
        if (object == nullptr) {
            return false;
        }
        if (isWaterSurface(object) || isWaterMask(object)) {
            return true;
        }
        if (object->isInstanceOfType(NI::RTTIStaticPtr::NiNode)) {
            for (const auto& child : static_cast<NI::Node*>(object)->children) {
                if (hasNamedSurface(child.get())) {
                    return true;
                }
            }
        }
        return false;
    }

    // Everything under a WaterBody is body: an exporter may write one object as a group of
    // shapes, one per material. The same holds for an object named as the surface.
    // With namedOnly the mesh names its water, and its other shapes are no water: a well has
    // posts and a roof. Without a name in it the whole mesh is water.
    // Everything under a WaterMask is the dry space of the mesh, and no water.
    static void collectFootprint(NI::AVObject* object, Volume& volume, bool& out_hasBody, bool namedOnly, bool inBody = false, bool inSurface = false,
                                 bool inMask = false) {
        if (object == nullptr) {
            return;
        }
        const auto body = inBody || isWaterBody(object);
        const auto surface = inSurface || isWaterSurface(object);
        const auto masking = inMask || isWaterMask(object);
        if (object->getAppCulled() && !body && !masking) {
            return;
        }

        if (object->isInstanceOfType(NI::RTTIStaticPtr::NiTriShape)) {
            if (namedOnly && !body && !surface && !masking) {
                return;
            }
            const auto shape = static_cast<NI::TriShape*>(object);
            const auto data = shape->getModelData();
            if (data == nullptr || data->vertex == nullptr || data->triangleList == nullptr) {
                return;
            }
            if (body && !masking) {
                out_hasBody = true;
            }
            geometry::Shape& target = masking ? volume.mask : static_cast<geometry::Shape&>(volume);

            const auto corner = [&](unsigned short index) {
                const auto world = shape->worldTransform * data->vertex[index];
                return geometry::Vec3{ world.x, world.y, world.z };
            };
            const auto triangleCount = data->getActiveTriangleCount();
            for (auto i = 0u; i < triangleCount; ++i) {
                const auto& indices = data->triangleList[i].vertices;
                target.addTriangle(corner(indices[0]), corner(indices[1]), corner(indices[2]));
            }
        }
        else if (object->isInstanceOfType(NI::RTTIStaticPtr::NiNode)) {
            for (const auto& child : static_cast<NI::Node*>(object)->children) {
                collectFootprint(child.get(), volume, out_hasBody, namedOnly, body, surface, masking);
            }
        }
    }

    // Takes the triangles of a branch as the water of a volume, and those of its mask as its
    // dry space. False if they hold no water; out_dry says if there is a dry space.
    static bool build(Volume& volume, NI::AVObject* node, float depth, bool& out_dry) {
        static_cast<geometry::Shape&>(volume) = {};
        volume.mask = {};
        auto hasBody = false;
        collectFootprint(node, volume, hasBody, hasNamedSurface(node));
        // A mesh without a body is the surface alone, and gets its bottom from the depth.
        if (!hasBody && depth > 0.0f) {
            volume.closeBelow(depth);
        }
        out_dry = volume.mask.finish();
        return volume.finish();
    }

    static bool samePlacement(const Volume& volume, const NI::AVObject* node) {
        return node->localRotation != nullptr
            && volume.scale == node->localScale
            && memcmp(&volume.translation, &node->localTranslate, sizeof(NI::Point3)) == 0
            && memcmp(&volume.rotation, node->localRotation, sizeof(NI::Matrix33)) == 0;
    }

    // Brings the water of a reference in line with the reference: where it is, how it is
    // turned and scaled, whether it is disabled or deleted, and which mesh it has. Returns
    // true if the reference has another mesh than when it was last looked at.
    static bool refresh(Volume& volume) {
        const auto reference = volume.reference;
        const auto node = reference->sceneNode.get();
        const auto renewed = node != nullptr && node != volume.node;
        const auto gone = (reference->objectFlags & (TES3::ObjectFlag::Disabled | TES3::ObjectFlag::Delete)) != 0;
        const auto wanted = volume.holdsWater && node != nullptr && !gone;
        if (wanted && volume.current && !renewed && samePlacement(volume, node)) {
            return false;
        }

        unlink(volume);
        volume.node = node;
        volume.current = false;
        if (wanted && node->localRotation != nullptr) {
            node->update();
            volume.rotation = *node->localRotation;
            volume.translation = node->localTranslate;
            volume.scale = node->localScale;
            volume.current = true;
            // The depth is given for the mesh as modelled, so it scales with the reference.
            auto dry = false;
            if (build(volume, node, volume.depth * node->localScale, dry)) {
                link(volume);
            }
            if (dry) {
                addMask(volume);
            }
        }
        return renewed;
    }

    int add(const TES3::Reference* reference, float depth, bool holdsWater) {
        if (!installed || reference == nullptr) {
            return 0;
        }

        if (GetCurrentThreadId() != mainThreadId) {
            OutputDebugStringA("Water Volumes: a reference was not taken: it came from a thread other than the one the hooks answer on.\n");
            return 0;
        }

        auto volume = std::make_unique<Volume>();
        volume->id = nextVolumeId++;
        volume->reference = reference;
        volume->depth = std::max(depth, 0.0f);
        volume->holdsWater = holdsWater;
        refresh(*volume);
        const auto id = volume->id;
        volumes.emplace(id, std::move(volume));
        return id;
    }

    const std::vector<int>& update() {
        static std::vector<int> renewed;
        renewed.clear();
        if (GetCurrentThreadId() != mainThreadId) {
            return renewed;
        }
        for (const auto& [id, volume] : volumes) {
            if (refresh(*volume)) {
                renewed.push_back(id);
            }
        }
        return renewed;
    }

    bool remove(int id) {
        const auto itt = volumes.find(id);
        if (itt == volumes.end()) {
            return false;
        }
        unlink(*itt->second);
        volumes.erase(itt);
        if (id == rendererVolumeId) {
            setRendererVolume(nullptr, 0.0f, 0.0f);
        }
        return true;
    }

    bool setColor(int id, float red, float green, float blue) {
        const auto itt = volumes.find(id);
        if (itt == volumes.end()) {
            return false;
        }
        auto& volume = *itt->second;
        volume.color = { std::clamp(red, 0.0f, 1.0f), std::clamp(green, 0.0f, 1.0f), std::clamp(blue, 0.0f, 1.0f) };
        volume.colored = volume.color.x > 0.0f || volume.color.y > 0.0f || volume.color.z > 0.0f;
        return true;
    }

    bool setFlow(int id, float x, float y, float carry, bool byDepth) {
        const auto itt = volumes.find(id);
        if (itt == volumes.end()) {
            return false;
        }
        auto& volume = *itt->second;
        volume.flow = { x, y, 0.0f };
        volume.carry = std::clamp(carry, 0.0f, 1.0f);
        volume.carryByDepth = byDepth;
        return true;
    }

    size_t count() {
        return linkedCount;
    }

    static const Volume* findVolume(const NI::Point3* position, bool ignoreHeight, float& out_surface, float& out_floor) {
        if (!ignoreHeight && !masks.empty() && isDry(position)) {
            return nullptr;
        }
        const Volume* found = nullptr;
        const geometry::Vec3 point = { position->x, position->y, position->z };
        const auto test = [&](const Volume* volume) {
            if (point.x < volume->min.x || point.x > volume->max.x) return;
            if (point.y < volume->min.y || point.y > volume->max.y) return;
            if (!ignoreHeight && point.z < volume->min.z) return;

            float surface = 0.0f, floor = 0.0f;
            if (!volume->waterAt(point, ignoreHeight, surface, floor)) return;
            if (found != nullptr && surface <= out_surface) return;

            found = volume;
            out_surface = surface;
            out_floor = floor;
        };

        const auto bucket = buckets.find(bucketKey(bucketOf(position->x), bucketOf(position->y)));
        if (bucket != buckets.end()) {
            for (const auto volume : bucket->second) {
                test(volume);
            }
        }
        for (const auto volume : wideVolumes) {
            test(volume);
        }
        return found;
    }

    static bool findSurface(const NI::Point3* position, bool ignoreHeight, float& out_surface) {
        float floor = 0.0f;
        return findVolume(position, ignoreHeight, out_surface, floor) != nullptr;
    }

    std::optional<float> getSurfaceAt(const NI::Point3& position) {
        float surface = 0.0f;
        if (findSurface(&position, false, surface)) {
            return surface;
        }
        return {};
    }

    bool isDryAt(const NI::Point3& position) {
        return !masks.empty() && isDry(&position);
    }

    std::optional<WaterAt> getWaterAt(const NI::Point3& position) {
        float surface = 0.0f, floor = 0.0f;
        const auto volume = findVolume(&position, false, surface, floor);
        if (volume == nullptr || position.z > surface) {
            return {};
        }
        return WaterAt{ volume->id, surface, floor };
    }

    //
    // Subject tracking. Each hooked function names the point its water queries are about.
    //

    struct Subject {
        const NI::Point3* position;
        bool ignoreHeight;
    };

    enum class SubjectKind : DWORD {
        ThisMobile,
        Arg0Mobile,
        Arg0Position,
        Arg1Position,
        AnimationController,
        CombatSession,
        Camera,
        Player,
        Arg0Arg1XY,
    };

    struct Frame {
        DWORD returnAddress;
        DWORD stackPointer;
        Subject previous;
        NI::Point3 storage;
    };

    struct SavedRegisters {
        DWORD edi, esi, ebp, esp, ebx, edx, ecx, eax;
    };

    constexpr auto MAX_FRAMES = 64u;
    static Frame frames[MAX_FRAMES];
    static unsigned int frameCount = 0;
    static Subject subject = { nullptr, false };
    static DWORD exitStub = 0;

    static Subject subjectFromMobile(const TES3::MobileObject* mobile) {
        if (mobile == nullptr || mobile->reference == nullptr) {
            return { nullptr, false };
        }
        return { &mobile->reference->position, false };
    }

    const auto TES3_getWaterMinLevel = reinterpret_cast<float(__cdecl*)()>(0x51D760);
    const auto TES3_MobileActor_canOnlySwim = reinterpret_cast<bool(__thiscall*)(const TES3::MobileActor*)>(0x521800);

    //
    // Creatures that can only swim.
    //
    // The game keeps such a creature in the water by two things: the land around the water,
    // and the surface over it. A volume can end in the open, where neither is there. A creature
    // that swims out of a volume there is put back where it last was in the water, and is given
    // that place as the one it is making for, so that it chooses again.
    //

    // A mobile that was not seen for this long may be another one at the same address.
    constexpr DWORD KEPT_FOR_MILLISECONDS = 500;

    // How far a creature can be from where it last was in a volume and still have swum there.
    constexpr auto SWUM_ACROSS = 128.0f;

    static void keepSwimmerInWater(TES3::MobileObject* object) {
        // Only creatures can be unable to walk. Projectiles come this way too.
        if (object == nullptr || object == lastLookedAt) {
            return;
        }
        lastLookedAt = object;
        if (object->objectType != TES3::ObjectType::MobileCreature) {
            return;
        }
        const auto mobile = static_cast<TES3::MobileActor*>(object);
        if (mobile->reference == nullptr || !TES3_MobileActor_canOnlySwim(mobile)) {
            return;
        }

        auto& position = mobile->reference->position;
        const auto now = GetTickCount();
        float surface = 0.0f, floor = 0.0f;
        if (findVolume(&position, false, surface, floor) != nullptr && position.z <= surface) {
            if (keptSwimmers.size() > 256) {
                keptSwimmers.clear();
            }
            keptSwimmers[mobile] = { position, now };
            return;
        }

        const auto kept = keptSwimmers.find(mobile);
        if (kept == keptSwimmers.end()) {
            return;
        }
        if (now - kept->second.seen > KEPT_FOR_MILLISECONDS) {
            keptSwimmers.erase(kept);
            return;
        }
        // Other water, the sea or the water of an interior, is as good as the volume it left,
        // if the creature swam into it. A creature that left through an open side high over
        // the sea is set down at the level of the sea in the same step; that is no swim.
        const auto dx = position.x - kept->second.position.x;
        const auto dy = position.y - kept->second.position.y;
        const auto dz = position.z - kept->second.position.z;
        if (position.z < TES3_getWaterMinLevel() && dx * dx + dy * dy + dz * dz < SWUM_ACROSS * SWUM_ACROSS) {
            keptSwimmers.erase(kept);
            return;
        }

        position = kept->second.position;
        mobile->actionData.walkDestination = kept->second.position;
        mobile->velocity = NI::Point3(0.0f, 0.0f, 0.0f);
        mobile->impulseVelocity = NI::Point3(0.0f, 0.0f, 0.0f);
        kept->second.seen = now;
    }

    static Subject resolveSubject(SubjectKind kind, DWORD ecx, const DWORD* stack, Frame& frame) {
        switch (kind) {
        case SubjectKind::ThisMobile:
            // A creature far from the player is moved without the full simulation, so the
            // look after swimmers is taken at every function that runs for a mobile.
            keepSwimmerInWater(reinterpret_cast<TES3::MobileObject*>(ecx));
            return subjectFromMobile(reinterpret_cast<const TES3::MobileObject*>(ecx));
        case SubjectKind::Arg0Mobile:
            return subjectFromMobile(reinterpret_cast<const TES3::MobileObject*>(stack[1]));
        case SubjectKind::Arg0Position:
            return { reinterpret_cast<const NI::Point3*>(stack[1]), false };
        case SubjectKind::Arg1Position:
            return { reinterpret_cast<const NI::Point3*>(stack[2]), false };
        case SubjectKind::AnimationController:
            return subjectFromMobile(reinterpret_cast<const TES3::ActorAnimationController*>(ecx)->mobileActor);
        case SubjectKind::CombatSession:
            return subjectFromMobile(reinterpret_cast<const TES3::CombatSession*>(ecx)->parentActor);
        case SubjectKind::Camera: {
            const auto worldController = TES3::WorldController::get();
            const auto camera = worldController ? worldController->worldCamera.cameraData.camera.get() : nullptr;
            if (camera == nullptr) {
                return { nullptr, false };
            }
            return { &camera->worldTransform.translation, false };
        }
        case SubjectKind::Player: {
            const auto worldController = TES3::WorldController::get();
            return subjectFromMobile(worldController ? worldController->getMobilePlayer() : nullptr);
        }
        case SubjectKind::Arg0Arg1XY:
            memcpy(&frame.storage.x, &stack[1], sizeof(float));
            memcpy(&frame.storage.y, &stack[2], sizeof(float));
            return { &frame.storage, true };
        }
        return { nullptr, false };
    }

    static void __stdcall onEnter(SubjectKind kind, SavedRegisters* registers) {
        if (!anyVolumes || GetCurrentThreadId() != mainThreadId) {
            return;
        }

        const auto stack = reinterpret_cast<DWORD*>(registers->esp);
        const auto dropFrame = [] {
            frameCount--;
            subject = frames[frameCount].previous;
        };

        // Frames below this stack position never returned through the exit stub.
        while (frameCount > 0 && frames[frameCount - 1].stackPointer < registers->esp) {
            dropFrame();
        }
        if (frameCount > 0 && frames[frameCount - 1].stackPointer == registers->esp) {
            // Entered by a jump out of a hooked function, whose frame stands for this one too.
            if (stack[0] == exitStub) {
                subject = resolveSubject(kind, registers->ecx, stack, frames[frameCount - 1]);
                return;
            }
            dropFrame();
        }
        if (frameCount == MAX_FRAMES || stack[0] == exitStub) {
            return;
        }

        auto& frame = frames[frameCount++];
        frame.returnAddress = stack[0];
        frame.stackPointer = registers->esp;
        frame.previous = subject;
        subject = resolveSubject(kind, registers->ecx, stack, frame);
        stack[0] = exitStub;
    }

    static DWORD __stdcall onLeave(DWORD stackPointer) {
        if (frameCount == 0) {
            // No return address is known. Stop here, where the cause can still be seen.
            OutputDebugStringA("Water Volumes: a hooked function returned with no frame on record.\n");
            RaiseFailFastException(nullptr, nullptr, 0);
        }
        // The returning frame is the outermost one below the current stack position.
        while (frameCount > 1 && frames[frameCount - 2].stackPointer < stackPointer) {
            frameCount--;
        }
        frameCount--;
        subject = frames[frameCount].previous;
        return frames[frameCount].returnAddress;
    }

    static float adjustLevel(float base) {
        if (!anyVolumes || subject.position == nullptr || GetCurrentThreadId() != mainThreadId) {
            return base;
        }
        // In a dry space there is no water at all, that of the cell included: its level is
        // given as far under the one who asks.
        if (!subject.ignoreHeight && !masks.empty() && isDry(subject.position)) {
            return std::min(base, subject.position->z - 100000.0f);
        }
        float surface = 0.0f;
        if (findSurface(subject.position, subject.ignoreHeight, surface) && surface > base) {
            return surface;
        }
        return base;
    }

    //
    // Replacement functions.
    //

    // Stands in for the interior cell at call sites that skip the level query in exteriors.
    alignas(4) static BYTE proxyCell[sizeof(TES3::Cell)] = {};

    const auto TES3_Cell_getWaterLevel = reinterpret_cast<float(__thiscall*)(const void*)>(0x4E28B0);

    static float __cdecl getWaterMinLevel() {
        return adjustLevel(TES3_getWaterMinLevel());
    }

    static float __fastcall cellGetWaterLevel(const void* cell) {
        const auto base = (cell == proxyCell) ? 0.0f : TES3_Cell_getWaterLevel(cell);
        return adjustLevel(base);
    }

    const auto TES3_lineOfSightRayVsReferenceNode = reinterpret_cast<bool(__cdecl*)(NI::Node*, const NI::Point3*, const NI::Point3*, float)>(0x53AF90);

    // Line of sight passes through the surface mesh of a water volume. The game is asked first:
    // it is called for every reference of a cell and turns most of them away at once, so the
    // look at the volumes is left for the few that stand in the way.
    static bool __cdecl lineOfSightRayVsReferenceNode(NI::Node* node, const NI::Point3* origin, const NI::Point3* direction, float maxDistance) {
        if (!TES3_lineOfSightRayVsReferenceNode(node, origin, direction, maxDistance)) {
            return false;
        }
        return !(anyVolumes && GetCurrentThreadId() == mainThreadId && volumeNodes.contains(node));
    }

    const auto TES3_WeatherController_updateUnderwaterState = reinterpret_cast<void(__thiscall*)(void*, float, float)>(0x440AF0);

    // While the camera is under the surface of a volume that has a colour, that colour is the
    // game's underwater colour, made as dark as the game's own is: a colour whose brightest
    // part is one half comes out as bright as the game's. The game's own is put back when the
    // camera leaves.
    static void setUnderwaterColor(TES3::WeatherController* weatherController, const Volume* volume) {
        static bool changed = false;
        static NI::Point3 gameColor;
        if (volume != nullptr && volume->colored) {
            if (!changed) {
                gameColor = weatherController->underwaterCol;
                changed = true;
            }
            const auto darkness = std::max({ gameColor.x, gameColor.y, gameColor.z }) / 0.5f;
            weatherController->underwaterCol = {
                std::min(volume->color.x * darkness, 1.0f),
                std::min(volume->color.y * darkness, 1.0f),
                std::min(volume->color.z * darkness, 1.0f),
            };
        }
        else if (changed) {
            weatherController->underwaterCol = gameColor;
            changed = false;
        }
    }

    // The underwater state is decided against the height of the water plane node, so a camera
    // inside a volume is reported relative to that node.
    static void __fastcall updateUnderwaterState(void* weatherController, DWORD _UNUSED_, float cameraZ, float waterLevel) {
        float surface = 0.0f, floor = 0.0f;
        const auto volume = (anyVolumes && subject.position != nullptr) ? findVolume(subject.position, false, surface, floor) : nullptr;
        // A camera in a dry space is not under water, however deep under the sea it is.
        const auto dry = anyVolumes && subject.position != nullptr && !masks.empty() && isDry(subject.position);
        setRendererDry(dry);
        setRendererVolume(volume, surface, floor);
        setUnderwaterColor(static_cast<TES3::WeatherController*>(weatherController), (volume != nullptr && subject.position->z < surface) ? volume : nullptr);
        if (volume != nullptr || dry) {
            const auto dataHandler = TES3::DataHandler::get();
            const auto plane = dataHandler && dataHandler->waterController ? dataHandler->waterController->waterPlane : nullptr;
            if (plane != nullptr) {
                cameraZ = plane->worldTransform.translation.z + ((volume != nullptr && subject.position->z < surface) ? -1.0f : 1.0f);
            }
        }
        TES3_WeatherController_updateUnderwaterState(weatherController, cameraZ, waterLevel);
    }

    const auto TES3_MobileObject_updateInstantVelocity = reinterpret_cast<void(__thiscall*)(TES3::MobileObject*, const NI::Point3*)>(0x55EA90);

    // The movement physics of an actor ends with its velocity for the frame. An actor in
    // water with a current gets the current added, turned and scaled with the reference of
    // the water, so the engine moves it as it moves an actor in the wind. The function is
    // only called for actors. An actor swims where the water is deeper than three quarters
    // of its height, the rule of mustActorSwimAtDestination.
    static void __fastcall updateInstantVelocityWithCurrent(TES3::MobileObject* mobile, DWORD _UNUSED_, NI::Point3* velocity) {
        const auto reference = mobile->reference;
        if (anyVolumes && reference != nullptr && GetCurrentThreadId() == mainThreadId) {
            float surface = 0.0f, floor = 0.0f;
            const auto volume = findVolume(&reference->position, false, surface, floor);
            if (volume != nullptr && volume->carry > 0.0f && reference->position.z < surface) {
                auto carry = volume->carry;
                if (volume->carryByDepth) {
                    const auto swimDepth = static_cast<TES3::MobileActor*>(mobile)->height * 0.75f;
                    carry *= std::clamp((surface - reference->position.z) / std::max(swimDepth, 1.0f), 0.0f, 1.0f);
                }
                const auto current = (volume->rotation * volume->flow) * (volume->scale * carry);
                velocity->x += current.x;
                velocity->y += current.y;
            }
        }
        TES3_MobileObject_updateInstantVelocity(mobile, velocity);
    }

    static bool __cdecl isPointUnderwater(const NI::Point3* position) {
        if (!masks.empty() && GetCurrentThreadId() == mainThreadId && isDry(position)) {
            return false;
        }
        auto level = TES3_getWaterMinLevel();
        float surface = 0.0f;
        if (anyVolumes && GetCurrentThreadId() == mainThreadId && findSurface(position, false, surface) && surface > level) {
            level = surface;
        }
        return level > position->z;
    }

    // How far a position is under water, by the game's own rules: under the water of an interior
    // that has water, or, outdoors, as deep as the land there lies under the level of the sea.
    static float depthOfGameWater(const NI::Point3* position) {
        const auto dataHandler = TES3::DataHandler::get();
        const auto interior = dataHandler->currentInteriorCell;
        if (interior != nullptr) {
            if ((interior->cellFlags & TES3::CellFlag::HasWater) != 0) {
                const auto level = TES3_getWaterMinLevel();
                if (level > position->z) {
                    return level - position->z;
                }
            }
            return 0.0f;
        }
        float land = 0.0f;
        dataHandler->getLandHeightAtPosition(*position, &land);
        return land < 0.0f ? -land : 0.0f;
    }

    // How far a position is under water: under the surface of a volume, or else by the game's
    // own rules. The game's two functions for this do not ask for the water level outdoors, so
    // hooks on the level cannot reach them; these two take their place whole.
    static float __cdecl getAbsDistanceBelowWater(const NI::Point3* position) {
        if (!masks.empty() && GetCurrentThreadId() == mainThreadId && isDry(position)) {
            return 0.0f;
        }
        float surface = 0.0f;
        if (anyVolumes && GetCurrentThreadId() == mainThreadId && findSurface(position, false, surface) && surface > position->z) {
            return surface - position->z;
        }
        return depthOfGameWater(position);
    }

    // True where the water is too deep for the actor to stand in.
    static bool __cdecl mustActorSwimAtDestination(const TES3::MobileActor* mobile, const NI::Point3* position) {
        return mobile->height * 0.75f < getAbsDistanceBelowWater(position);
    }

    static __declspec(naked) void getInteriorCellOrProxy() {
        __asm {
            mov ecx, [eax + 0xAC]
            test ecx, ecx
            jnz done
            cmp byte ptr [anyVolumes], 0
            je done
            mov ecx, offset proxyCell
        done:
            ret
        }
    }

    //
    // Hook tables.
    //

    // Call sites of the global water level query (0x51D760).
    static const DWORD globalLevelCallSites[] = {
        0x466AAA, 0x466B96,                                // waterwalk check
        0x523EEA, 0x523F0D,                                // actor scene graph update
        0x5243F3, 0x52451B, 0x52462D, 0x524799,            // actor simulation
        0x52535D, 0x5254B8, 0x52567C, 0x5257BA, 0x5258A7,  // collision resolution
        0x525D36,                                          // movement collision
        0x526CD1, 0x527464,                                // swim/fly movement, surfacing for air
        0x5287DA, 0x528935, 0x528BC0, 0x528EA9,            // destination checks
        0x528FAA,                                          // voiceover
        0x5293F8, 0x5294F6, 0x5295B0,                      // distance to surface, foot point
        0x529A42, 0x529AB6,                                // breathing
        0x52D502, 0x52D511,                                // standing position check
        0x53771A,                                          // combat weighting
        0x53E973, 0x53E9A7,                                // movement physics
        0x560C1B,                                          // projectile water collision
        // 0x507986: script instruction, left alone.
        // 0x53B4A0: the whole function is replaced by isPointUnderwater.
        // 0x53B553, 0x53B5D7: inside the two functions that are replaced whole.
    };

    // Call sites of the cell water level query (0x4E28B0).
    static const DWORD cellLevelCallSites[] = {
        0x410394, 0x410527,            // environment update, camera
        0x441473,                      // weather particles
        0x48A598,                      // ambient water sound
        0x51C205, 0x51C386,            // ripples
        0x522C82, 0x525B29, 0x53B4E8,  // actor collision, waterwalking
        0x5523A2, 0x5523E3, 0x5524C4,  // walking
        0x552B67, 0x552BA6,            // falling
        0x552E5B,                      // swimming
        // 0x5079BF, 0x507A0F: script instructions, left alone.
        // 0x51BA97: water plane placement, left alone.
        // 0x51D77E: inside the global query, already covered by its call sites.
    };

    // Call sites of the underwater state update (0x440AF0).
    static const DWORD underwaterStateCallSites[] = {
        0x4103A4, 0x410537,
    };

    // Loads of DataHandler::currentInteriorCell that precede a null check and a level query.
    static const DWORD interiorCellLoadSites[] = {
        0x51C373, 0x522C6A, 0x552E43,
    };

    struct EntryHook {
        DWORD address;
        BYTE length;
        BYTE expected[9];
        SubjectKind kind;
    };

    static const EntryHook entryHooks[] = {
        { 0x4100D0, 6, { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x2C }, SubjectKind::Camera },
        { 0x466A60, 6, { 0x64, 0xA1, 0x00, 0x00, 0x00, 0x00 }, SubjectKind::Arg0Mobile },
        { 0x48A560, 5, { 0x83, 0xEC, 0x50, 0x53, 0x56 }, SubjectKind::Player },
        { 0x51C1E0, 5, { 0x83, 0xEC, 0x18, 0x53, 0x55 }, SubjectKind::Arg0Arg1XY },
        { 0x523DA0, 5, { 0x83, 0xEC, 0x1C, 0x53, 0x56 }, SubjectKind::ThisMobile },
        { 0x524070, 6, { 0x55, 0x8B, 0xEC, 0x83, 0xE4, 0xF8 }, SubjectKind::ThisMobile },
        { 0x525230, 6, { 0x83, 0xEC, 0x10, 0x56, 0x8B, 0xF1 }, SubjectKind::ThisMobile },
        { 0x5259F0, 5, { 0xA1, 0xE0, 0x67, 0x7C, 0x00 }, SubjectKind::ThisMobile },
        { 0x526BB0, 6, { 0x83, 0xEC, 0x28, 0x56, 0x8B, 0xF1 }, SubjectKind::ThisMobile },
        { 0x527410, 6, { 0x83, 0xEC, 0x18, 0x56, 0x33, 0xC0 }, SubjectKind::ThisMobile },
        { 0x5287D0, 5, { 0x83, 0xEC, 0x08, 0x53, 0x56 }, SubjectKind::Arg0Position },
        { 0x528870, 6, { 0x83, 0xEC, 0x1C, 0x56, 0x8B, 0xF1 }, SubjectKind::ThisMobile },
        { 0x5289D0, 7, { 0x83, 0xEC, 0x28, 0x8B, 0x44, 0x24, 0x2C }, SubjectKind::Arg0Position },
        { 0x528D30, 6, { 0x83, 0xEC, 0x1C, 0x53, 0x8B, 0xD9 }, SubjectKind::ThisMobile },
        { 0x528F80, 7, { 0x8B, 0x44, 0x24, 0x04, 0x83, 0xEC, 0x0C }, SubjectKind::ThisMobile },
        { 0x5293B0, 6, { 0x83, 0xEC, 0x0C, 0x56, 0x8B, 0xF1 }, SubjectKind::ThisMobile },
        { 0x529540, 6, { 0x57, 0x8B, 0xF9, 0x8B, 0x4F, 0x14 }, SubjectKind::ThisMobile },
        { 0x5299F0, 7, { 0x51, 0x56, 0x8B, 0xF1, 0x8B, 0x4E, 0x14 }, SubjectKind::ThisMobile },
        { 0x52D420, 6, { 0x83, 0xEC, 0x08, 0x55, 0x8B, 0xE9 }, SubjectKind::ThisMobile },
        { 0x5375A0, 5, { 0x83, 0xEC, 0x44, 0x53, 0x55 }, SubjectKind::CombatSession },
        { 0x53B4C0, 6, { 0x53, 0x56, 0x8B, 0x74, 0x24, 0x0C }, SubjectKind::Arg0Mobile },
        { 0x53E270, 6, { 0x83, 0xEC, 0x70, 0x56, 0x8B, 0xF1 }, SubjectKind::AnimationController },
        { 0x560BE0, 5, { 0x55, 0x8B, 0xEC, 0x6A, 0xFF }, SubjectKind::ThisMobile },
        { 0x5679E0, 6, { 0x83, 0xEC, 0x28, 0x56, 0x8B, 0xF1 }, SubjectKind::ThisMobile },
        { 0x573790, 5, { 0x56, 0x8B, 0x74, 0x24, 0x08 }, SubjectKind::ThisMobile },
        { 0x574DA0, 6, { 0x56, 0x8B, 0xF1, 0x8B, 0x46, 0x10 }, SubjectKind::ThisMobile },
    };

    static const BYTE interiorCellLoadBytes[] = { 0x8B, 0x88, 0xAC, 0x00, 0x00, 0x00 };

    // The function that begins with the global water level query and is replaced whole.
    constexpr DWORD POINT_UNDERWATER_FUNCTION = 0x53B4A0;

    // Functions of the game that are replaced whole: where each begins, the bytes it begins
    // with, and what takes its place.
    struct ReplacedFunction {
        DWORD address;
        BYTE expected[9];
        void* replacement;
    };
    static const ReplacedFunction replacedFunctions[] = {
        { 0x53B500, { 0x83, 0xEC, 0x08, 0x8B, 0x0D, 0xE0, 0x67, 0x7C, 0x00 }, &getAbsDistanceBelowWater },
        { 0x53B580, { 0x83, 0xEC, 0x08, 0x8B, 0x0D, 0xE0, 0x67, 0x7C, 0x00 }, &mustActorSwimAtDestination },
    };

    // The call that tests a line of sight against the mesh of one reference.
    constexpr DWORD LINE_OF_SIGHT_CALL_SITE = 0x53B1DD;
    // The end of the actor movement physics, where the velocity of the frame is set.
    constexpr DWORD INSTANT_VELOCITY_CALL_SITE = 0x53EC4D;

    // Where each entry hook's stub is, once installed.
    static DWORD entryStubs[std::size(entryHooks)] = {};

    //
    // Installation.
    //

    static bool isRelativeTo(DWORD address, BYTE opcode, DWORD target) {
        if (*reinterpret_cast<const BYTE*>(address) != opcode) {
            return false;
        }
        return *reinterpret_cast<const DWORD*>(address + 1) + address + 5 == target;
    }

    constexpr BYTE CALL = 0xE8;
    constexpr BYTE JUMP = 0xE9;

    // One place in the code of the game that the plugin changes.
    struct Patch {
        DWORD address;
        // What is there in the unchanged game: a call to this function, or else these bytes.
        DWORD callsBefore;
        const BYTE* bytesBefore;
        BYTE bytesBeforeLength;
        // What the plugin puts there: a call or a jump to the target, over this many bytes.
        BYTE opcode;
        DWORD target;
        BYTE length;

        bool unchanged() const {
            if (bytesBefore != nullptr) {
                return memcmp(reinterpret_cast<const void*>(address), bytesBefore, bytesBeforeLength) == 0;
            }
            return isRelativeTo(address, CALL, callsBefore);
        }

        bool intact() const {
            return isRelativeTo(address, opcode, target);
        }

        void apply() const {
            if (opcode == CALL) {
                se::memory::genCallUnprotected(address, target, length);
            }
            else {
                se::memory::genJumpUnprotected(address, target, length);
            }
        }
    };

    // Every patch. The check, the installation and the status all go by this list.
    static std::vector<Patch> listPatches() {
        std::vector<Patch> patches;
        const auto call = [&](DWORD site, DWORD before, void* target) {
            patches.push_back({ site, before, nullptr, 0, CALL, reinterpret_cast<DWORD>(target), 5 });
        };
        const auto overBytes = [&](DWORD address, const BYTE* before, BYTE beforeLength, BYTE opcode, DWORD target, BYTE length) {
            patches.push_back({ address, 0, before, beforeLength, opcode, target, length });
        };

        for (const auto site : globalLevelCallSites) {
            call(site, 0x51D760, &getWaterMinLevel);
        }
        patches.push_back({ POINT_UNDERWATER_FUNCTION, 0x51D760, nullptr, 0, JUMP, reinterpret_cast<DWORD>(&isPointUnderwater), 5 });
        for (const auto site : cellLevelCallSites) {
            call(site, 0x4E28B0, &cellGetWaterLevel);
        }
        for (const auto site : underwaterStateCallSites) {
            call(site, 0x440AF0, &updateUnderwaterState);
        }
        call(LINE_OF_SIGHT_CALL_SITE, 0x53AF90, &lineOfSightRayVsReferenceNode);
        call(INSTANT_VELOCITY_CALL_SITE, 0x55EA90, &updateInstantVelocityWithCurrent);
        for (const auto site : interiorCellLoadSites) {
            overBytes(site, interiorCellLoadBytes, sizeof(interiorCellLoadBytes), CALL, reinterpret_cast<DWORD>(&getInteriorCellOrProxy), sizeof(interiorCellLoadBytes));
        }
        for (auto i = 0u; i < std::size(entryHooks); ++i) {
            const auto& hook = entryHooks[i];
            overBytes(hook.address, hook.expected, hook.length, JUMP, entryStubs[i], hook.length);
        }
        for (const auto& function : replacedFunctions) {
            overBytes(function.address, function.expected, sizeof(function.expected), JUMP, reinterpret_cast<DWORD>(function.replacement), 5);
        }
        return patches;
    }

    // Lists the places that do not hold what the unchanged game has there. True if there is none.
    static bool verify(std::string& out_message) {
        std::ostringstream changed;
        auto count = 0;
        for (const auto& patch : listPatches()) {
            if (!patch.unchanged()) {
                changed << (count++ == 0 ? "" : ", ") << "0x" << std::hex << patch.address;
            }
        }
        if (count == 0) {
            return true;
        }
        out_message = "This is not the executable the plugin knows, or something else has changed the same code first. Is the same patch built into this MWSE.dll? Unexpected code at " + changed.str() + ".";
        return false;
    }

    static BYTE* emitByte(BYTE* at, BYTE value) {
        *at = value;
        return at + 1;
    }

    static BYTE* emitDword(BYTE* at, DWORD value) {
        memcpy(at, &value, sizeof(value));
        return at + sizeof(value);
    }

    static BYTE* emitRelative(BYTE* at, BYTE opcode, DWORD target) {
        at = emitByte(at, opcode);
        return emitDword(at, target - (reinterpret_cast<DWORD>(at) + 4));
    }

    void hookStatus(int& out_intact, int& out_total) {
        out_intact = 0;
        out_total = 0;
        for (const auto& patch : listPatches()) {
            out_total++;
            if (patch.intact()) {
                out_intact++;
            }
        }
    }

    bool install(std::string& out_message) {
        if (installed) {
            return true;
        }
        if (!verify(out_message)) {
            return false;
        }

        constexpr auto STUB_PAGE_SIZE = 0x1000u;
        const auto stubPage = static_cast<BYTE*>(VirtualAlloc(nullptr, STUB_PAGE_SIZE, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
        if (stubPage == nullptr) {
            out_message = "No memory for the hook stubs.";
            return false;
        }
        auto code = stubPage;

        // HasWater | IsInterior, so the proxy passes the flag checks ahead of the level query.
        proxyCell[offsetof(TES3::Cell, cellFlags)] = 0x3;

        // Exit stub: restores the subject and returns to the original caller.
        exitStub = reinterpret_cast<DWORD>(code);
        code = emitByte(code, 0x50);                             // push eax
        code = emitByte(code, 0x60);                             // pushad
        code = emitDword(code, 0x2424448D);                      // lea eax, [esp+0x24]
        code = emitByte(code, 0x50);                             // push eax
        code = emitRelative(code, 0xE8, reinterpret_cast<DWORD>(&onLeave));
        code = emitDword(code, 0x20244489);                      // mov [esp+0x20], eax
        code = emitByte(code, 0x61);                             // popad
        code = emitByte(code, 0xC3);                             // ret

        // Entry stubs: set the subject, run the displaced instructions, continue in the function.
        for (auto i = 0u; i < std::size(entryHooks); ++i) {
            const auto& hook = entryHooks[i];
            entryStubs[i] = reinterpret_cast<DWORD>(code);
            code = emitByte(code, 0x60);                         // pushad
            code = emitByte(code, 0x54);                         // push esp
            code = emitByte(code, 0x68);                         // push kind
            code = emitDword(code, static_cast<DWORD>(hook.kind));
            code = emitRelative(code, 0xE8, reinterpret_cast<DWORD>(&onEnter));
            code = emitByte(code, 0x61);                         // popad
            memcpy(code, hook.expected, hook.length);
            code += hook.length;
            code = emitRelative(code, 0xE9, hook.address + hook.length);
        }

        // The stubs are complete: from here on the page is only run.
        DWORD previousProtection = 0;
        if (!VirtualProtect(stubPage, STUB_PAGE_SIZE, PAGE_EXECUTE_READ, &previousProtection)) {
            out_message = "The hook stubs could not be made runnable.";
            VirtualFree(stubPage, 0, MEM_RELEASE);
            return false;
        }

        for (const auto& patch : listPatches()) {
            patch.apply();
        }

        // The hooks answer on the thread that installs them: the game's main thread, which is
        // the one that runs Lua.
        mainThreadId = GetCurrentThreadId();
        installed = true;
        return true;
    }
}
