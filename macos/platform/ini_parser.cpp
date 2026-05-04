/**
 * ini_parser.cpp
 *
 * Cross-platform INI file reader/writer (replaces GetPrivateProfile* Win32 API).
 *
 * Implementation notes:
 *   - Files are parsed lazily and cached in memory.
 *   - Writes go to the in-memory cache immediately; flushed on FlushAll() or
 *     when the cache entry is evicted.
 *   - All paths are normalised to POSIX (forward-slash) before use.
 *   - wchar_t ↔ UTF-8 conversion uses standard C locale; MilkDrop preset
 *     names are ASCII-safe so this is fine for the initial port.
 */

#include "ini_parser.h"
#include "win32_compat.h"

#include <fstream>
#include <sstream>
#include <algorithm>
#include <cstring>
#include <cstdio>
#include <cassert>
#include <codecvt>
#include <locale>

// ── Internal types ────────────────────────────────────────────────────────────
namespace {

using SectionMap = std::unordered_map<std::wstring, std::wstring>;   // key → value
using IniData    = std::unordered_map<std::wstring, SectionMap>;     // section → keys

struct CachedFile {
    IniData  data;
    bool     dirty = false;
};

std::unordered_map<std::wstring, CachedFile> g_cache;
std::mutex                                    g_mutex;

// ── helpers ──────────────────────────────────────────────────────────────────

static std::wstring to_wide(const std::string& s) {
    std::wstring out;
    out.reserve(s.size());
    for (unsigned char c : s) out += static_cast<wchar_t>(c);
    return out;
}

static std::string to_narrow(const std::wstring& w) {
    std::string out;
    out.reserve(w.size());
    for (wchar_t c : w) out += (c < 0x80) ? static_cast<char>(c) : '?';
    return out;
}

static std::wstring normalise_path(const std::wstring& p) {
    std::wstring r = p;
    for (wchar_t& c : r) if (c == L'\\') c = L'/';
    return r;
}

static std::wstring trim(const std::wstring& s) {
    size_t b = s.find_first_not_of(L" \t\r\n");
    if (b == std::wstring::npos) return {};
    size_t e = s.find_last_not_of(L" \t\r\n");
    return s.substr(b, e - b + 1);
}

static std::wstring to_lower(std::wstring s) {
    for (wchar_t& c : s) if (c >= L'A' && c <= L'Z') c += 32;
    return s;
}

// ── parse a file into IniData ─────────────────────────────────────────────────
static IniData parse_file(const std::wstring& path) {
    IniData data;
    std::ifstream f(to_narrow(path));
    if (!f.is_open()) return data;

    std::string line_raw;
    std::wstring current_section;

    while (std::getline(f, line_raw)) {
        std::wstring line = trim(to_wide(line_raw));
        if (line.empty() || line[0] == L';' || line[0] == L'#') continue;

        if (line[0] == L'[') {
            size_t close = line.find(L']');
            if (close != std::wstring::npos)
                current_section = to_lower(trim(line.substr(1, close - 1)));
        } else {
            size_t eq = line.find(L'=');
            if (eq != std::wstring::npos) {
                std::wstring key = to_lower(trim(line.substr(0, eq)));
                std::wstring val = trim(line.substr(eq + 1));
                data[current_section][key] = val;
            }
        }
    }
    return data;
}

// ── write IniData to disk ─────────────────────────────────────────────────────
static bool write_file(const std::wstring& path, const IniData& data) {
    std::ofstream f(to_narrow(path), std::ios::trunc);
    if (!f.is_open()) return false;
    for (auto& [sec, kvs] : data) {
        f << "[" << to_narrow(sec) << "]\n";
        for (auto& [k, v] : kvs)
            f << to_narrow(k) << "=" << to_narrow(v) << "\n";
        f << "\n";
    }
    return true;
}

// ── get or load a CachedFile ──────────────────────────────────────────────────
static CachedFile& get_cached(const std::wstring& raw_path) {
    // called with g_mutex held
    std::wstring path = normalise_path(raw_path);
    auto it = g_cache.find(path);
    if (it == g_cache.end()) {
        CachedFile cf;
        cf.data = parse_file(path);
        g_cache[path] = std::move(cf);
        return g_cache[path];
    }
    return it->second;
}

} // anonymous namespace

// ── Public API ────────────────────────────────────────────────────────────────

namespace IniParser {

int GetInt(const std::wstring& file, const std::wstring& section,
           const std::wstring& key, int defaultVal)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto& cf  = get_cached(file);
    auto  sit = cf.data.find(to_lower(section));
    if (sit == cf.data.end()) return defaultVal;
    auto  kit = sit->second.find(to_lower(key));
    if (kit == sit->second.end()) return defaultVal;
    try { return std::stoi(to_narrow(kit->second)); }
    catch (...) { return defaultVal; }
}

float GetFloat(const std::wstring& file, const std::wstring& section,
               const std::wstring& key, float defaultVal)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto& cf  = get_cached(file);
    auto  sit = cf.data.find(to_lower(section));
    if (sit == cf.data.end()) return defaultVal;
    auto  kit = sit->second.find(to_lower(key));
    if (kit == sit->second.end()) return defaultVal;
    try { return std::stof(to_narrow(kit->second)); }
    catch (...) { return defaultVal; }
}

void GetString(const std::wstring& file, const std::wstring& section,
               const std::wstring& key, const std::wstring& defaultVal,
               wchar_t* buf, size_t bufSize)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto& cf  = get_cached(file);
    auto  sit = cf.data.find(to_lower(section));
    const std::wstring* val = &defaultVal;
    if (sit != cf.data.end()) {
        auto kit = sit->second.find(to_lower(key));
        if (kit != sit->second.end()) val = &kit->second;
    }
    wcsncpy(buf, val->c_str(), bufSize - 1);
    buf[bufSize - 1] = L'\0';
}

bool WriteInt(const std::wstring& file, const std::wstring& section,
              const std::wstring& key, int value)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto& cf = get_cached(file);
    cf.data[to_lower(section)][to_lower(key)] = to_wide(std::to_string(value));
    cf.dirty = true;
    write_file(normalise_path(file), cf.data);
    return true;
}

bool WriteFloat(const std::wstring& file, const std::wstring& section,
                const std::wstring& key, float value)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto& cf = get_cached(file);
    char tmp[64]; snprintf(tmp, sizeof(tmp), "%.8g", value);
    cf.data[to_lower(section)][to_lower(key)] = to_wide(tmp);
    cf.dirty = true;
    write_file(normalise_path(file), cf.data);
    return true;
}

bool WriteString(const std::wstring& file, const std::wstring& section,
                 const std::wstring& key, const std::wstring& value)
{
    std::lock_guard<std::mutex> lk(g_mutex);
    auto& cf = get_cached(file);
    cf.data[to_lower(section)][to_lower(key)] = value;
    cf.dirty = true;
    write_file(normalise_path(file), cf.data);
    return true;
}

void FlushAll() {
    std::lock_guard<std::mutex> lk(g_mutex);
    for (auto& [path, cf] : g_cache) {
        if (cf.dirty) {
            write_file(path, cf.data);
            cf.dirty = false;
        }
    }
}

} // namespace IniParser

// ── Win32 C-API shim (called from win32_compat.h declarations) ───────────────
extern "C" {

UINT GetPrivateProfileIntW(const wchar_t* sec, const wchar_t* key,
                            INT def, const wchar_t* file)
{
    return (UINT)IniParser::GetInt(file ? file : L"", sec ? sec : L"",
                                   key  ? key  : L"", def);
}

DWORD GetPrivateProfileStringW(const wchar_t* sec, const wchar_t* key,
                                const wchar_t* def, wchar_t* buf,
                                DWORD size, const wchar_t* file)
{
    IniParser::GetString(file ? file : L"",
                         sec  ? sec  : L"",
                         key  ? key  : L"",
                         def  ? def  : L"",
                         buf, size);
    return (DWORD)wcslen(buf);
}

BOOL WritePrivateProfileStringW(const wchar_t* sec, const wchar_t* key,
                                 const wchar_t* val, const wchar_t* file)
{
    return IniParser::WriteString(file ? file : L"",
                                  sec  ? sec  : L"",
                                  key  ? key  : L"",
                                  val  ? val  : L"") ? TRUE : FALSE;
}

UINT GetPrivateProfileIntA(const char* sec, const char* key,
                            INT def, const char* file)
{
    auto ws = [](const char* s) -> std::wstring {
        if (!s) return {};
        std::wstring r; for (; *s; ++s) r += (wchar_t)(unsigned char)*s; return r;
    };
    return (UINT)IniParser::GetInt(ws(file), ws(sec), ws(key), def);
}

DWORD GetPrivateProfileStringA(const char* sec, const char* key,
                                const char* def, char* buf,
                                DWORD size, const char* file)
{
    auto ws = [](const char* s) -> std::wstring {
        if (!s) return {};
        std::wstring r; for (; *s; ++s) r += (wchar_t)(unsigned char)*s; return r;
    };
    wchar_t wbuf[4096] = {};
    IniParser::GetString(ws(file), ws(sec), ws(key),
                         def ? ws(def) : L"", wbuf, 4096);
    for (DWORD i = 0; i < size - 1 && wbuf[i]; ++i)
        buf[i] = (char)wbuf[i];
    buf[size - 1] = '\0';
    return (DWORD)strlen(buf);
}

BOOL WritePrivateProfileStringA(const char* sec, const char* key,
                                 const char* val, const char* file)
{
    auto ws = [](const char* s) -> std::wstring {
        if (!s) return {};
        std::wstring r; for (; *s; ++s) r += (wchar_t)(unsigned char)*s; return r;
    };
    return IniParser::WriteString(ws(file), ws(sec), ws(key), ws(val)) ? TRUE : FALSE;
}

} // extern "C"
