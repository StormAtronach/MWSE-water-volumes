// TES3 engine accessors. The NI:: methods the plugin calls are compiled from
// the SharedSE sources (globbed in CMakeLists.txt). SharedSE has no TES3
// layer, so the few TES3 accessors the hooks need are defined here, each a
// one-liner onto a fixed Morrowind.exe address.

#include "stdafx.h"

#include "TES3DataHandler.h"
#include "TES3MobilePlayer.h"
#include "TES3WorldController.h"

namespace TES3 {

DataHandler* DataHandler::get() {
    return *reinterpret_cast<TES3::DataHandler**>(0x7C67E0);
}

WorldController* WorldController::get() {
    return *reinterpret_cast<TES3::WorldController**>(0x7C67DC);
}

MobilePlayer* WorldController::getMobilePlayer() {
    const auto TES3_WorldController_getMobilePlayer = reinterpret_cast<MobilePlayer*(__thiscall*)(WorldController*)>(0x40FF20);
    return TES3_WorldController_getMobilePlayer(this);
}

}  // namespace TES3
