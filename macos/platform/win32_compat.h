/**
 * win32_compat.h
 *
 * Stubs for Windows types and APIs used throughout the MilkDrop3 codebase.
 * On macOS we replace the Windows Platform SDK surface with this header.
 * Every file that previously included <windows.h> should now include this
 * file instead (via the compiler flag or a forced include).
 *
 * Rule: if you see a new compile error about a missing Windows symbol, add
 * the stub here rather than touching the original source.
 */

#pragma once

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <sys/types.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>

// ── Basic integer typedefs ────────────────────────────────────────────────────
typedef unsigned char       BYTE;
typedef unsigned short      WORD;
typedef unsigned int        DWORD;
typedef unsigned long long  QWORD;
typedef int                 BOOL;
typedef long                LONG;
typedef unsigned long       ULONG;
typedef long long           LONGLONG;
typedef unsigned long long  ULONGLONG;
typedef intptr_t            INT_PTR;
typedef uintptr_t           UINT_PTR;
typedef void*               HANDLE;
typedef void*               HINSTANCE;
typedef void*               HMODULE;
typedef void*               HWND;
typedef void*               HDC;
typedef void*               HFONT;
typedef void*               HICON;
typedef void*               HMENU;
typedef void*               HBITMAP;
typedef void*               HBRUSH;
typedef void*               HPALETTE;
typedef void*               HPEN;
typedef void*               HRGN;
typedef void*               HRSRC;
typedef unsigned int        UINT;
typedef UINT                WPARAM;
typedef LONG                LPARAM;
typedef LONG                LRESULT;
typedef char*               LPSTR;
typedef const char*         LPCSTR;
typedef wchar_t*            LPWSTR;
typedef const wchar_t*      LPCWSTR;
typedef void*               LPVOID;
typedef const void*         LPCVOID;
typedef unsigned int        UINT32;
typedef int                 INT32;
typedef float               FLOAT;
typedef double              DOUBLE;

#define TRUE  1
#define FALSE 0

#define MAX_PATH 260

// ── RECT / POINT / SIZE ───────────────────────────────────────────────────────
typedef struct tagRECT {
    LONG left, top, right, bottom;
} RECT, *LPRECT;

typedef struct tagPOINT {
    LONG x, y;
} POINT, *LPPOINT;

typedef struct tagSIZE {
    LONG cx, cy;
} SIZE, *LPSIZE;

// ── GUID ──────────────────────────────────────────────────────────────────────
typedef struct _GUID {
    uint32_t  Data1;
    uint16_t  Data2;
    uint16_t  Data3;
    uint8_t   Data4[8];
} GUID;
typedef GUID IID;
typedef GUID CLSID;

// ── LARGE_INTEGER ─────────────────────────────────────────────────────────────
typedef union _LARGE_INTEGER {
    struct { DWORD LowPart; LONG HighPart; };
    LONGLONG QuadPart;
} LARGE_INTEGER;

// ── Common macros ─────────────────────────────────────────────────────────────
#define WINAPI
#define CALLBACK
#define STDMETHODCALLTYPE
#define STDMETHOD(name)   virtual HRESULT name
#define STDMETHOD_(t,name) virtual t name
#define PURE              = 0
#define THIS_
#define THIS              void
#define DECLARE_INTERFACE(x) struct x
#define DECLARE_INTERFACE_(x,y) struct x : public y

#ifndef SUCCEEDED
#define SUCCEEDED(hr)  (((HRESULT)(hr)) >= 0)
#define FAILED(hr)     (((HRESULT)(hr)) < 0)
#endif

typedef LONG HRESULT;
#define S_OK      ((HRESULT)0L)
#define S_FALSE   ((HRESULT)1L)
#define E_FAIL    ((HRESULT)0x80004005L)
#define E_NOTIMPL ((HRESULT)0x80004001L)
#define E_POINTER ((HRESULT)0x80004003L)

// ── Win32 string helpers ──────────────────────────────────────────────────────
// MilkDrop uses GetPrivateProfileInt/String for reading INI files.
// These are implemented in ini_parser.cpp.
#ifdef __cplusplus
extern "C" {
#endif

UINT GetPrivateProfileIntW(const wchar_t* section, const wchar_t* key,
                            INT def, const wchar_t* file);
DWORD GetPrivateProfileStringW(const wchar_t* section, const wchar_t* key,
                                const wchar_t* def, wchar_t* buf, DWORD size,
                                const wchar_t* file);
BOOL WritePrivateProfileStringW(const wchar_t* section, const wchar_t* key,
                                 const wchar_t* value, const wchar_t* file);

UINT GetPrivateProfileIntA(const char* section, const char* key,
                            INT def, const char* file);
DWORD GetPrivateProfileStringA(const char* section, const char* key,
                                const char* def, char* buf, DWORD size,
                                const char* file);
BOOL WritePrivateProfileStringA(const char* section, const char* key,
                                 const char* value, const char* file);

#ifdef __cplusplus
} // extern "C"
#endif

// ── High-performance timer (replaces QueryPerformanceCounter) ────────────────
static inline BOOL QueryPerformanceCounter(LARGE_INTEGER* out) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
    out->QuadPart = (LONGLONG)ts.tv_sec * 1000000000LL + ts.tv_nsec;
    return TRUE;
}
static inline BOOL QueryPerformanceFrequency(LARGE_INTEGER* out) {
    out->QuadPart = 1000000000LL; // nanoseconds
    return TRUE;
}

// ── Thread helpers ────────────────────────────────────────────────────────────
#define INFINITE  0xFFFFFFFF
static inline DWORD WaitForSingleObject(HANDLE h, DWORD ms) { return 0; }
static inline HANDLE CreateEvent(void*, BOOL, BOOL, const char*) { return nullptr; }
static inline BOOL   SetEvent(HANDLE)   { return TRUE; }
static inline BOOL   ResetEvent(HANDLE) { return TRUE; }
static inline BOOL   CloseHandle(HANDLE){ return TRUE; }

// ── Message box stub ─────────────────────────────────────────────────────────
#define MB_OK 0
#define MB_ICONERROR 0
#define MB_ICONWARNING 0
#define MB_YESNO 4
#define IDYES 6
#define IDNO  7
static inline int MessageBoxW(HWND, const wchar_t* text, const wchar_t* cap, UINT) {
    // In a real port: show an NSAlert
    wprintf(L"[MessageBox] %ls: %ls\n", cap, text);
    return IDNO;
}
static inline int MessageBoxA(HWND, const char* text, const char* cap, UINT) {
    fprintf(stderr, "[MessageBox] %s: %s\n", cap, text);
    return IDNO;
}
#define MessageBox MessageBoxA

// ── OutputDebugString ─────────────────────────────────────────────────────────
static inline void OutputDebugStringA(const char* s)  { fprintf(stderr, "[DBG] %s", s); }
static inline void OutputDebugStringW(const wchar_t* s){ fwprintf(stderr, L"[DBG] %ls", s); }
#define OutputDebugString OutputDebugStringA

// ── File paths: forward-slash on macOS ────────────────────────────────────────
// The codebase uses backslashes in paths sometimes.
// convert_path() is called at load time; see ini_parser.cpp
#ifdef __cplusplus
#include <string>
inline std::string win_path_to_posix(const std::string& p) {
    std::string r = p;
    for (char& c : r) if (c == '\\') c = '/';
    return r;
}
inline std::wstring win_path_to_posix(const std::wstring& p) {
    std::wstring r = p;
    for (wchar_t& c : r) if (c == L'\\') c = L'/';
    return r;
}
#endif

// ── Suppress Windows-only pragmas ────────────────────────────────────────────
#define __pragma(x)

// ── wcslen / wcs* are in <wchar.h> on macOS – nothing to add ─────────────────

// ── sprintf_s / swprintf_s compat ────────────────────────────────────────────
#define sprintf_s(buf, size, fmt, ...) snprintf(buf, size, fmt, ##__VA_ARGS__)
#define swprintf_s(buf, size, fmt, ...) swprintf(buf, size, fmt, ##__VA_ARGS__)
#define sscanf_s  sscanf
#define _snwprintf swprintf
#define _snprintf  snprintf
#define _stricmp  strcasecmp
#define _wcsicmp  wcscasecmp
#define _strdup   strdup
#define strtok_s  strtok_r
#define wcstok_s(a,b,c) wcstok(a,b,c)

// ── Math extras ───────────────────────────────────────────────────────────────
#ifndef _USE_MATH_DEFINES
#define M_PI 3.14159265358979323846
#endif
