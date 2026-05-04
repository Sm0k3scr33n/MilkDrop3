// macOS-specific DXContext wrapper
#ifdef MILKDROP_MACOS

#include "DXContext.h"
#include "render/MetalDevice.h"
#include "shell_defines.h"

// This implementation reuses the existing DXContext interface but forwards
// device operations to the Metal-backed IDirect3DDevice9 implementation.

DXContext::DXContext(LPDIRECT3DDEVICE9 device, D3DPRESENT_PARAMETERS* d3dpp, HWND hwnd, wchar_t* szIniFile)
{
    // Keep minimal state and reuse the Metal device pointer.
    m_szWindowCaption[0] = 0;
    m_hwnd = hwnd;
    m_lpDevice = device;
    m_d3dpp = d3dpp;
    m_hmod_d3d9 = NULL;
    m_hmod_d3dx9 = NULL;
    m_zFormat = D3DFMT_UNKNOWN;
    m_ordinal_adapter = 0;
    m_winamp_minimized = 0;
    m_truly_exiting = 0;
    m_bpp = 0;
    m_frame_delay = 0;
    if (szIniFile) {
        StringCbCopyW(m_szIniFile, sizeof(m_szIniFile), szIniFile);
    } else {
        m_szIniFile[0] = 0;
    }
    m_szDriver[0] = 0;
    m_szDesc[0] = 0;
    m_lastErr = S_OK;
    m_ready = FALSE;
}

DXContext::~DXContext()
{
    Internal_CleanUp();
}

void DXContext::Internal_CleanUp()
{
    m_ready = FALSE;
}

BOOL DXContext::Internal_Init(DXCONTEXT_PARAMS *pParams, BOOL bFirstInit)
{
    memcpy(&m_current_mode, pParams, sizeof(DXCONTEXT_PARAMS));

    // Query device caps from MetalDevice if available
    if (m_lpDevice) {
        m_lpDevice->GetDeviceCaps(&m_caps);
        m_bpp = 32;
    } else {
        memset(&m_caps, 0, sizeof(m_caps));
        m_bpp = 32;
    }

    m_ready = TRUE;
    return TRUE;
}

BOOL DXContext::StartOrRestartDevice(DXCONTEXT_PARAMS *pParams)
{
    if (!m_ready)
    {
        return Internal_Init(pParams, TRUE);
    }
    else
    {
        m_ready = FALSE;
        return Internal_Init(pParams, FALSE);
    }
}

HWND DXContext::GetHwnd() { return m_hwnd; }
bool DXContext::TempIgnoreDestroyMessages() { return false; }
void DXContext::SaveWindow() { }

void DXContext::WriteSafeWindowPos()
{
    WritePrivateProfileIntW(64, L"nMainWndTop", m_szIniFile, L"settings");
    WritePrivateProfileIntW(64, L"nMainWndLeft", m_szIniFile, L"settings");
}

bool DXContext::OnUserResizeWindow(RECT *new_window_rect, RECT *new_client_rect)
{
    if (!m_ready)
        return FALSE;

    if ((m_client_width == new_client_rect->right - new_client_rect->left) &&
        (m_client_height == new_client_rect->bottom - new_client_rect->top) &&
        (m_window_width == new_window_rect->right - new_window_rect->left) &&
        (m_window_height == new_window_rect->bottom - new_window_rect->top))
    {
        return TRUE;
    }

    m_ready = FALSE;

    m_window_width = new_window_rect->right - new_window_rect->left;
    m_window_height = new_window_rect->bottom - new_window_rect->top;
    m_client_width = m_REAL_client_width = new_client_rect->right - new_client_rect->left;
    m_client_height = m_REAL_client_height = new_client_rect->bottom - new_client_rect->top;

    if (m_lpDevice) {
        // On MetalDevice, Reset will reconfigure internal viewport/backbuffer size
        if (m_lpDevice->Reset(m_d3dpp) != D3D_OK) {
            WriteSafeWindowPos();
            m_lastErr = DXC_ERR_RESIZEFAILED;
            return FALSE;
        }
    }

    // SetViewport will be implemented by device; call it if available
    SetViewport();
    m_ready = TRUE;
    return TRUE;
}

void DXContext::SetViewport()
{
    D3DVIEWPORT9 v;
    v.X = 0;
    v.Y = 0;
    v.Width = m_client_width;
    v.Height = m_client_height;
    v.MinZ = 0.0f;
    v.MaxZ = 1.0f;
    if (m_lpDevice) m_lpDevice->SetViewport(&v);
}

#endif // MILKDROP_MACOS
