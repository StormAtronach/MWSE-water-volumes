#pragma once

// Plugin-local logger. Output goes to WaterVolumes.log next to Morrowind.exe.
// Call sites read `log::getLog() << ...`, matching MWSE's own Log.h.
//
// getLog() opens the file lazily on first use and an atexit handler flushes
// it. std::endl does not force a flush, so call flush() at a point after
// which the process may not exit cleanly.

#include <iosfwd>

namespace wv::log {
std::ostream& getLog();

void flush();
}  // namespace wv::log
