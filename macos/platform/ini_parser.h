/**
 * ini_parser.h
 *
 * Cross-platform replacement for the Win32 GetPrivateProfile* /
 * WritePrivateProfile* family of functions used throughout MilkDrop.
 *
 * The file format is standard Windows INI:
 *   [Section]
 *   Key=Value
 *
 * Thread-safety: basic – last-write-wins on concurrent writes.
 */

#pragma once

#include <string>
#include <unordered_map>
#include <mutex>

// ── C++ API (used internally by the platform layer) ──────────────────────────
namespace IniParser {

    // Returns int value, or defaultVal if not found.
    int   GetInt   (const std::wstring& file, const std::wstring& section,
                    const std::wstring& key,  int defaultVal);
    // Returns float value, or defaultVal if not found.
    float GetFloat (const std::wstring& file, const std::wstring& section,
                    const std::wstring& key,  float defaultVal);
    // Returns string value into buf (max bufSize wchar_ts incl null), or defaultVal.
    void  GetString(const std::wstring& file, const std::wstring& section,
                    const std::wstring& key,  const std::wstring& defaultVal,
                    wchar_t* buf, size_t bufSize);

    bool  WriteInt   (const std::wstring& file, const std::wstring& section,
                      const std::wstring& key,  int value);
    bool  WriteFloat (const std::wstring& file, const std::wstring& section,
                      const std::wstring& key,  float value);
    bool  WriteString(const std::wstring& file, const std::wstring& section,
                      const std::wstring& key,  const std::wstring& value);

    // Flush all dirty files to disk (call on shutdown).
    void  FlushAll();

} // namespace IniParser
