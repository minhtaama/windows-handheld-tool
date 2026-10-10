#include "dxgi_hook.h"
#include "minhook/MinHook.h"

#include <string>
#include <vector>
#include <algorithm>
#include <mutex>
#include <shlwapi.h>

#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3d11.lib")

namespace {

// Handle DLL instance
HINSTANCE g_hInstance = nullptr;

// Shared data segment giữa Flutter Process và Injected Game Process
#pragma data_seg(".shared")
HHOOK g_hHook = nullptr;
BOOL g_isOverlayActive = FALSE;
int g_hookMode = 0; // 0: Borderless, 1: Shared Texture
HANDLE g_hSharedTexture = nullptr;
HANDLE g_hSharedTextureBGRA = nullptr;
HANDLE g_hSharedTextureRGBA = nullptr;
#pragma data_seg()
#pragma comment(linker, "/SECTION:.shared,RWS")

// Module handle của dxgi.dll gốc từ System32 (khi chạy ở chế độ Proxy)
HMODULE g_hRealDxgi = nullptr;

// Mutex bảo vệ danh sách hook
std::mutex g_hookMutex;
bool g_isInitialized = false;
bool g_isExcludedProcess = false;

// Typedefs cho các hàm DXGI, D3D11 & XInput
typedef HRESULT(WINAPI* PFN_CreateDXGIFactory)(REFIID riid, void** ppFactory);
typedef HRESULT(WINAPI* PFN_CreateDXGIFactory1)(REFIID riid, void** ppFactory);
typedef HRESULT(WINAPI* PFN_CreateDXGIFactory2)(UINT Flags, REFIID riid, void** ppFactory);
typedef HRESULT(WINAPI* PFN_D3D11CreateDeviceAndSwapChain)(
    IDXGIAdapter* pAdapter,
    D3D_DRIVER_TYPE DriverType,
    HMODULE Software,
    UINT Flags,
    const D3D_FEATURE_LEVEL* pFeatureLevels,
    UINT FeatureLevels,
    UINT SDKVersion,
    const DXGI_SWAP_CHAIN_DESC* pSwapChainDesc,
    IDXGISwapChain** ppSwapChain,
    ID3D11Device** ppDevice,
    D3D_FEATURE_LEVEL* pFeatureLevel,
    ID3D11DeviceContext** ppImmediateContext);

typedef HRESULT(STDMETHODCALLTYPE* PFN_CreateSwapChain)(
    IDXGIFactory* pThis,
    IUnknown* pDevice,
    DXGI_SWAP_CHAIN_DESC* pDesc,
    IDXGISwapChain** ppSwapChain);

typedef HRESULT(STDMETHODCALLTYPE* PFN_CreateSwapChainForHwnd)(
    IDXGIFactory2* pThis,
    IUnknown* pDevice,
    HWND hWnd,
    const DXGI_SWAP_CHAIN_DESC1* pDesc,
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC* pFullscreenDesc,
    IDXGIOutput* pRestrictToOutput,
    IDXGISwapChain1** ppSwapChain);

typedef HRESULT(STDMETHODCALLTYPE* PFN_SetFullscreenState)(
    IDXGISwapChain* pThis,
    BOOL Fullscreen,
    IDXGIOutput* pTarget);

typedef HRESULT(STDMETHODCALLTYPE* PFN_ResizeTarget)(
    IDXGISwapChain* pThis,
    const DXGI_MODE_DESC* pNewTargetParameters);

typedef HRESULT(STDMETHODCALLTYPE* PFN_ResizeBuffers)(
    IDXGISwapChain* pThis,
    UINT BufferCount,
    UINT Width,
    UINT Height,
    DXGI_FORMAT NewFormat,
    UINT SwapChainFlags);

typedef HRESULT(STDMETHODCALLTYPE* PFN_MakeWindowAssociation)(
    IDXGIFactory* pThis,
    HWND WindowHandle,
    UINT Flags);

typedef DWORD(WINAPI* PFN_XInputGetState)(DWORD dwUserIndex, XINPUT_STATE* pState);
typedef DWORD(WINAPI* PFN_XInputGetStateEx)(DWORD dwUserIndex, void* pState);

typedef HRESULT(STDMETHODCALLTYPE* PFN_Present)(
    IDXGISwapChain* pThis,
    UINT SyncInterval,
    UINT Flags);

// Con trỏ tới hàm gốc
PFN_CreateDXGIFactory             g_origCreateDXGIFactory = nullptr;
PFN_CreateDXGIFactory1            g_origCreateDXGIFactory1 = nullptr;
PFN_CreateDXGIFactory2            g_origCreateDXGIFactory2 = nullptr;
PFN_D3D11CreateDeviceAndSwapChain g_origD3D11CreateDeviceAndSwapChain = nullptr;
PFN_CreateSwapChain               g_origCreateSwapChain = nullptr;
PFN_CreateSwapChainForHwnd        g_origCreateSwapChainForHwnd = nullptr;
PFN_SetFullscreenState            g_origSetFullscreenState = nullptr;
PFN_ResizeTarget                  g_origResizeTarget = nullptr;
PFN_ResizeBuffers                 g_origResizeBuffers = nullptr;
PFN_MakeWindowAssociation         g_origMakeWindowAssociation = nullptr;
PFN_Present                       g_origPresent = nullptr;

PFN_XInputGetState                g_origXInputGetState = nullptr;
PFN_XInputGetStateEx              g_origXInputGetStateEx = nullptr;

// Tải dxgi.dll thật từ C:\Windows\System32
HMODULE GetRealDxgiModule() {
    if (!g_hRealDxgi) {
        wchar_t sysDir[MAX_PATH];
        GetSystemDirectoryW(sysDir, MAX_PATH);
        std::wstring realPath = std::wstring(sysDir) + L"\\dxgi.dll";
        g_hRealDxgi = LoadLibraryW(realPath.c_str());
    }
    return g_hRealDxgi;
}

// Kiểm tra xem tiến trình hiện tại có nằm trong danh sách loại trừ không
bool CheckIfExcludedProcess() {
    wchar_t exePath[MAX_PATH];
    GetModuleFileNameW(nullptr, exePath, MAX_PATH);
    std::wstring exeName = PathFindFileNameW(exePath);
    std::transform(exeName.begin(), exeName.end(), exeName.begin(), ::towlower);

    const wchar_t* excludedList[] = {
        L"windows_handheld_tool.exe",
        L"flutter.exe",
        L"explorer.exe",
        L"dwm.exe",
        L"csrss.exe",
        L"lsass.exe",
        L"smss.exe",
        L"services.exe",
        L"svchost.exe",
        L"taskmgr.exe",
        L"devenv.exe",
        L"searchhost.exe",
        L"shellexperiencehost.exe",
        L"startmenuexperiencehost.exe",
        L"antigravity ide.exe"
    };

    for (const auto* excluded : excludedList) {
        if (exeName == excluded) {
            return true;
        }
    }
    return false;
}

// Chuyển đổi một con trỏ VTable và bảo toàn quyền ghi
bool PatchVTable(void** vtable, size_t index, void* newFunc, void** ppOldFunc) {
    if (!vtable || !newFunc) return false;
    DWORD oldProtect;
    if (VirtualProtect(&vtable[index], sizeof(void*), PAGE_EXECUTE_READWRITE, &oldProtect)) {
        if (ppOldFunc && !*ppOldFunc) {
            *ppOldFunc = vtable[index];
        }
        vtable[index] = newFunc;
        VirtualProtect(&vtable[index], sizeof(void*), oldProtect, &oldProtect);
        return true;
    }
    return false;
}

} // namespace

// =========================================================================
// Hook Implementation
// =========================================================================

void HookSwapChain(IDXGISwapChain* pSwapChain);
void HookFactoryVTable(IDXGIFactory* pFactory);

// Hook XInputGetState: Chặn (Mute) nút bấm gamepad khi Quick Settings Overlay đang mở
DWORD WINAPI Hooked_XInputGetState(DWORD dwUserIndex, XINPUT_STATE* pState) {
    DWORD res = ERROR_SUCCESS;
    if (g_origXInputGetState) {
        res = g_origXInputGetState(dwUserIndex, pState);
    }
    if (res == ERROR_SUCCESS && pState && g_isOverlayActive) {
        // Overlay đang mở -> Xóa trắng nút bấm gửi đến game để tránh nhận nhầm thao tác
        ZeroMemory(&pState->Gamepad, sizeof(XINPUT_GAMEPAD));
    }
    return res;
}

// Hook XInputGetStateEx (Ordinal 100): Hỗ trợ thêm phím Guide / Touchpad
DWORD WINAPI Hooked_XInputGetStateEx(DWORD dwUserIndex, void* pState) {
    DWORD res = ERROR_SUCCESS;
    if (g_origXInputGetStateEx) {
        res = g_origXInputGetStateEx(dwUserIndex, pState);
    }
    if (res == ERROR_SUCCESS && pState && g_isOverlayActive) {
        auto* pStateEx = reinterpret_cast<XINPUT_STATE*>(pState);
        ZeroMemory(&pStateEx->Gamepad, sizeof(XINPUT_GAMEPAD));
    }
    return res;
}

// Hook hàm Present trên SwapChain (Slot 8)
// Xử lý Phương án 3: Direct3D Shared Texture Injection (OBS / Discord style)
HRESULT STDMETHODCALLTYPE Hooked_Present(
    IDXGISwapChain* pThis,
    UINT SyncInterval,
    UINT Flags)
{
    // Nếu đang chạy chế độ Shared Texture Injection và Overlay đang mở
    if (g_hookMode == OVERLAY_HOOK_MODE_SHARED_TEXTURE && g_isOverlayActive && (g_hSharedTextureBGRA || g_hSharedTextureRGBA || g_hSharedTexture)) {
        ID3D11Device* pDevice = nullptr;
        if (SUCCEEDED(pThis->GetDevice(__uuidof(ID3D11Device), reinterpret_cast<void**>(&pDevice))) && pDevice) {
            ID3D11DeviceContext* pContext = nullptr;
            pDevice->GetImmediateContext(&pContext);
            if (pContext) {
                ID3D11Texture2D* pBackBuffer = nullptr;
                if (SUCCEEDED(pThis->GetBuffer(0, __uuidof(ID3D11Texture2D), reinterpret_cast<void**>(&pBackBuffer))) && pBackBuffer) {
                    D3D11_TEXTURE2D_DESC backDesc{};
                    pBackBuffer->GetDesc(&backDesc);

                    // Chọn Shared Handle có format phù hợp nhất với BackBuffer của game (R8G8B8A8 vs B8G8R8A8)
                    HANDLE hSharedToOpen = g_hSharedTexture;
                    if (backDesc.Format == DXGI_FORMAT_R8G8B8A8_UNORM ||
                        backDesc.Format == DXGI_FORMAT_R8G8B8A8_UNORM_SRGB ||
                        backDesc.Format == DXGI_FORMAT_R8G8B8A8_TYPELESS) {
                        hSharedToOpen = g_hSharedTextureRGBA ? g_hSharedTextureRGBA : (g_hSharedTexture ? g_hSharedTexture : g_hSharedTextureBGRA);
                    } else {
                        hSharedToOpen = g_hSharedTextureBGRA ? g_hSharedTextureBGRA : (g_hSharedTexture ? g_hSharedTexture : g_hSharedTextureRGBA);
                    }

                    if (hSharedToOpen) {
                        ID3D11Texture2D* pSharedTexture = nullptr;
                        HRESULT hrOpen = pDevice->OpenSharedResource(
                            hSharedToOpen,
                            __uuidof(ID3D11Texture2D),
                            reinterpret_cast<void**>(&pSharedTexture)
                        );

                        if (SUCCEEDED(hrOpen) && pSharedTexture) {
                            D3D11_TEXTURE2D_DESC sharedDesc{};
                            pSharedTexture->GetDesc(&sharedDesc);

                            // Chỉ sao chép vùng Side Dock Panel bên mép phải (khoảng 40% bề rộng màn hình)
                            // Giữ nguyên vẹn 60% màn hình bên trái cho thế giới game mà không che khuất
                            UINT panelW = static_cast<UINT>(sharedDesc.Width * 0.40f);
                            if (panelW > sharedDesc.Width) panelW = sharedDesc.Width;

                            D3D11_BOX box{};
                            box.left = sharedDesc.Width - panelW;
                            box.right = sharedDesc.Width;
                            box.top = 0;
                            box.bottom = sharedDesc.Height;
                            box.front = 0;
                            box.back = 1;

                            UINT destX = backDesc.Width > panelW ? (backDesc.Width - panelW) : 0;

                            // Chép trực tiếp kết cấu Side Panel vào BackBuffer trước khi GPU xuất hình
                            pContext->CopySubresourceRegion(
                                pBackBuffer, 0, destX, 0, 0,
                                pSharedTexture, 0, &box
                            );
                            pSharedTexture->Release();
                        }
                    }
                    pBackBuffer->Release();
                }
                pContext->Release();
            }
            pDevice->Release();
        }
    }

    if (g_origPresent) {
        return g_origPresent(pThis, SyncInterval, Flags);
    }
    return S_OK;
}

// Hook hàm SetFullscreenState trên SwapChain
HRESULT STDMETHODCALLTYPE Hooked_SetFullscreenState(
    IDXGISwapChain* pThis,
    BOOL Fullscreen,
    IDXGIOutput* pTarget)
{
    OutputDebugStringA("[DXGI-Hook] SetFullscreenState called\n");

    if (g_hookMode == OVERLAY_HOOK_MODE_BORDERLESS) {
        if (Fullscreen) {
            // Trò chơi cố gắng bật Fullscreen Exclusive -> Cưỡng bức đưa cửa sổ về Borderless Fullscreen
            DXGI_SWAP_CHAIN_DESC desc{};
            if (SUCCEEDED(pThis->GetDesc(&desc)) && desc.OutputWindow) {
                MakeWindowBorderless(desc.OutputWindow);
            }

            // Gọi hàm gốc với Fullscreen = FALSE để DirectX không chuyển đổi phần cứng màn hình
            if (g_origSetFullscreenState) {
                g_origSetFullscreenState(pThis, FALSE, nullptr);
            }

            // Trả về S_OK để Game tin rằng đã chuyển sang Fullscreen thành công
            return S_OK;
        }

        if (g_origSetFullscreenState) {
            return g_origSetFullscreenState(pThis, FALSE, pTarget);
        }
        return S_OK;
    }

    // Chế độ Shared Texture Injection:
    // Nếu đã có GPU Shared Texture, cho phép game chạy Fullscreen Exclusive thật sự.
    // Nếu chưa có kết cấu dùng chung (fallback bảo vệ an toàn), cưỡng bức Borderless để tránh làm biến mất Panel!
    if (g_hookMode == OVERLAY_HOOK_MODE_SHARED_TEXTURE) {
        if (!g_hSharedTexture && Fullscreen) {
            DXGI_SWAP_CHAIN_DESC desc{};
            if (SUCCEEDED(pThis->GetDesc(&desc)) && desc.OutputWindow) {
                MakeWindowBorderless(desc.OutputWindow);
            }
            if (g_origSetFullscreenState) {
                g_origSetFullscreenState(pThis, FALSE, nullptr);
            }
            return S_OK;
        }

        if (g_origSetFullscreenState) {
            return g_origSetFullscreenState(pThis, Fullscreen, pTarget);
        }
        return S_OK;
    }

    if (g_origSetFullscreenState) {
        return g_origSetFullscreenState(pThis, Fullscreen, pTarget);
    }
    return S_OK;
}

// Hook hàm ResizeTarget trên SwapChain (Slot 14)
// Tự động kéo dãn (Dynamic Upscaling) bất kỳ độ phân giải nào (720p, 800p, 1080p, 2K, 4K)
HRESULT STDMETHODCALLTYPE Hooked_ResizeTarget(
    IDXGISwapChain* pThis,
    const DXGI_MODE_DESC* pNewTargetParameters)
{
    OutputDebugStringA("[DXGI-Hook] ResizeTarget called (Handling Dynamic Resolution scaling)\n");

    if (g_hookMode == OVERLAY_HOOK_MODE_BORDERLESS) {
        HWND hWnd = nullptr;
        DXGI_SWAP_CHAIN_DESC desc{};
        if (SUCCEEDED(pThis->GetDesc(&desc))) {
            hWnd = desc.OutputWindow;
        }

        // Lấy kích thước vật lý thực tế động của màn hình hiện tại
        HMONITOR hMon = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
        MONITORINFO mi = { sizeof(MONITORINFO) };
        UINT screenW = static_cast<UINT>(GetSystemMetrics(SM_CXSCREEN));
        UINT screenH = static_cast<UINT>(GetSystemMetrics(SM_CYSCREEN));
        if (GetMonitorInfo(hMon, &mi)) {
            screenW = static_cast<UINT>(mi.rcMonitor.right - mi.rcMonitor.left);
            screenH = static_cast<UINT>(mi.rcMonitor.bottom - mi.rcMonitor.top);
        }

        // Ghi đè tham số modeDesc sang độ phân giải thực tế của màn hình để cửa sổ không bị thu nhỏ
        DXGI_MODE_DESC modifiedMode{};
        const DXGI_MODE_DESC* pActualMode = pNewTargetParameters;
        if (pNewTargetParameters) {
            modifiedMode = *pNewTargetParameters;
            modifiedMode.Width = screenW;
            modifiedMode.Height = screenH;
            pActualMode = &modifiedMode;
        }

        HRESULT hr = S_OK;
        if (g_origResizeTarget) {
            hr = g_origResizeTarget(pThis, pActualMode);
        }

        if (hWnd) {
            MakeWindowBorderless(hWnd);
        }

        return hr;
    }

    // Chế độ Shared Texture: Không can thiệp kích thước cửa sổ game
    if (g_origResizeTarget) {
        return g_origResizeTarget(pThis, pNewTargetParameters);
    }
    return S_OK;
}

// Hook hàm ResizeBuffers trên SwapChain (Slot 13)
HRESULT STDMETHODCALLTYPE Hooked_ResizeBuffers(
    IDXGISwapChain* pThis,
    UINT BufferCount,
    UINT Width,
    UINT Height,
    DXGI_FORMAT NewFormat,
    UINT SwapChainFlags)
{
    OutputDebugStringA("[DXGI-Hook] ResizeBuffers called\n");

    if (g_hookMode == OVERLAY_HOOK_MODE_BORDERLESS) {
        // Loại bỏ cờ Mode Switch độc quyền khi game đổi kích thước bộ đệm
        UINT modifiedFlags = SwapChainFlags & ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;

        HRESULT hr = S_OK;
        if (g_origResizeBuffers) {
            hr = g_origResizeBuffers(pThis, BufferCount, Width, Height, NewFormat, modifiedFlags);
        }

        DXGI_SWAP_CHAIN_DESC desc{};
        if (SUCCEEDED(pThis->GetDesc(&desc)) && desc.OutputWindow) {
            MakeWindowBorderless(desc.OutputWindow);
        }

        return hr;
    }

    // Chế độ Shared Texture: Bảo toàn nguyên vẹn tham số hoán đổi bộ đệm
    if (g_origResizeBuffers) {
        return g_origResizeBuffers(pThis, BufferCount, Width, Height, NewFormat, SwapChainFlags);
    }
    return S_OK;
}

// Hook hàm MakeWindowAssociation trên IDXGIFactory (Slot 8)
HRESULT STDMETHODCALLTYPE Hooked_MakeWindowAssociation(
    IDXGIFactory* pThis,
    HWND WindowHandle,
    UINT Flags)
{
    OutputDebugStringA("[DXGI-Hook] MakeWindowAssociation called\n");

    if (g_hookMode == OVERLAY_HOOK_MODE_BORDERLESS) {
        // Thêm cờ cấm DirectX runtime tự ý thay đổi style hoặc kích thước cửa sổ
        UINT modifiedFlags = Flags | DXGI_MWA_NO_WINDOW_CHANGES | DXGI_MWA_NO_ALT_ENTER;

        if (g_origMakeWindowAssociation) {
            return g_origMakeWindowAssociation(pThis, WindowHandle, modifiedFlags);
        }
        return S_OK;
    }

    if (g_origMakeWindowAssociation) {
        return g_origMakeWindowAssociation(pThis, WindowHandle, Flags);
    }
    return S_OK;
}

void HookSwapChain(IDXGISwapChain* pSwapChain) {
    if (!pSwapChain) return;
    std::lock_guard<std::mutex> lock(g_hookMutex);

    void** vtable = *reinterpret_cast<void***>(pSwapChain);
    if (!vtable) return;

    // 0. Hook Present (Slot 8) - Direct3D Shared Texture Injection
    if (vtable[8] != Hooked_Present) {
        PatchVTable(vtable, 8, reinterpret_cast<void*>(Hooked_Present),
                    reinterpret_cast<void**>(&g_origPresent));
        OutputDebugStringA("[DXGI-Hook] IDXGISwapChain::Present VTable hooked!\n");
    }

    // 1. Hook SetFullscreenState (Slot 10)
    if (vtable[10] != Hooked_SetFullscreenState) {
        PatchVTable(vtable, 10, reinterpret_cast<void*>(Hooked_SetFullscreenState),
                    reinterpret_cast<void**>(&g_origSetFullscreenState));
        OutputDebugStringA("[DXGI-Hook] IDXGISwapChain::SetFullscreenState VTable hooked!\n");
    }

    // 2. Hook ResizeBuffers (Slot 13)
    if (vtable[13] != Hooked_ResizeBuffers) {
        PatchVTable(vtable, 13, reinterpret_cast<void*>(Hooked_ResizeBuffers),
                    reinterpret_cast<void**>(&g_origResizeBuffers));
        OutputDebugStringA("[DXGI-Hook] IDXGISwapChain::ResizeBuffers VTable hooked!\n");
    }

    // 3. Hook ResizeTarget (Slot 14) - Tự động mở rộng toàn màn hình
    if (vtable[14] != Hooked_ResizeTarget) {
        PatchVTable(vtable, 14, reinterpret_cast<void*>(Hooked_ResizeTarget),
                    reinterpret_cast<void**>(&g_origResizeTarget));
        OutputDebugStringA("[DXGI-Hook] IDXGISwapChain::ResizeTarget VTable hooked!\n");
    }
}

// Hook hàm CreateSwapChain của IDXGIFactory
HRESULT STDMETHODCALLTYPE Hooked_CreateSwapChain(
    IDXGIFactory* pThis,
    IUnknown* pDevice,
    DXGI_SWAP_CHAIN_DESC* pDesc,
    IDXGISwapChain** ppSwapChain)
{
    OutputDebugStringA("[DXGI-Hook] CreateSwapChain intercepted\n");

    if (pDesc && g_hookMode == OVERLAY_HOOK_MODE_BORDERLESS) {
        // 1. Ép Windowed = TRUE (Cưỡng bức chạy chế độ Cửa sổ DWM)
        pDesc->Windowed = TRUE;

        // 2. Loại bỏ cờ Mode Switch độc quyền
        pDesc->Flags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;

        // 3. Xóa viền cửa sổ game thành Borderless Fullscreen
        if (pDesc->OutputWindow) {
            MakeWindowBorderless(pDesc->OutputWindow);
        }
    }

    HRESULT hr = S_OK;
    if (g_origCreateSwapChain) {
        hr = g_origCreateSwapChain(pThis, pDevice, pDesc, ppSwapChain);
    }

    // 4. Hook SetFullscreenState, ResizeTarget, ResizeBuffers trên SwapChain mới tạo
    if (SUCCEEDED(hr) && ppSwapChain && *ppSwapChain) {
        HookSwapChain(*ppSwapChain);
    }

    return hr;
}

// Hook hàm CreateSwapChainForHwnd của IDXGIFactory2
HRESULT STDMETHODCALLTYPE Hooked_CreateSwapChainForHwnd(
    IDXGIFactory2* pThis,
    IUnknown* pDevice,
    HWND hWnd,
    const DXGI_SWAP_CHAIN_DESC1* pDesc,
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC* pFullscreenDesc,
    IDXGIOutput* pRestrictToOutput,
    IDXGISwapChain1** ppSwapChain)
{
    OutputDebugStringA("[DXGI-Hook] CreateSwapChainForHwnd intercepted\n");

    DXGI_SWAP_CHAIN_DESC1 descCopy;
    const DXGI_SWAP_CHAIN_DESC1* pActualDesc = pDesc;

    DXGI_SWAP_CHAIN_FULLSCREEN_DESC fsDescCopy;
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC* pActualFsDesc = pFullscreenDesc;

    if (g_hookMode == OVERLAY_HOOK_MODE_BORDERLESS) {
        if (pDesc) {
            descCopy = *pDesc;

            // Cưỡng bức chế độ Scaling = DXGI_SCALING_STRETCH (0) để tự động Upscale
            if (descCopy.Scaling == DXGI_SCALING_NONE) {
                descCopy.Scaling = DXGI_SCALING_STRETCH;
            }

            // Loại bỏ cờ Mode Switch độc quyền
            descCopy.Flags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
            pActualDesc = &descCopy;
        }

        if (pFullscreenDesc) {
            fsDescCopy = *pFullscreenDesc;
            // Ép Windowed = TRUE
            fsDescCopy.Windowed = TRUE;
            pActualFsDesc = &fsDescCopy;
        }

        if (hWnd) {
            MakeWindowBorderless(hWnd);
        }
    }

    HRESULT hr = S_OK;
    if (g_origCreateSwapChainForHwnd) {
        hr = g_origCreateSwapChainForHwnd(pThis, pDevice, hWnd, pActualDesc, pActualFsDesc, pRestrictToOutput, ppSwapChain);
    }

    if (SUCCEEDED(hr) && ppSwapChain && *ppSwapChain) {
        HookSwapChain(*ppSwapChain);
    }

    return hr;
}

// Gắn Hook vào IDXGIFactory / IDXGIFactory2 VTable
void HookFactoryVTable(IDXGIFactory* pFactory) {
    if (!pFactory) return;
    std::lock_guard<std::mutex> lock(g_hookMutex);

    void** vtable = *reinterpret_cast<void***>(pFactory);
    if (vtable) {
        // Hook MakeWindowAssociation (Slot 8)
        if (vtable[8] != Hooked_MakeWindowAssociation) {
            PatchVTable(vtable, 8, reinterpret_cast<void*>(Hooked_MakeWindowAssociation),
                        reinterpret_cast<void**>(&g_origMakeWindowAssociation));
        }

        // Hook CreateSwapChain (Slot 10)
        if (vtable[10] != Hooked_CreateSwapChain) {
            PatchVTable(vtable, 10, reinterpret_cast<void*>(Hooked_CreateSwapChain),
                        reinterpret_cast<void**>(&g_origCreateSwapChain));
            OutputDebugStringA("[DXGI-Hook] IDXGIFactory::CreateSwapChain VTable hooked!\n");
        }

        // Thử Query IDXGIFactory2 để hook CreateSwapChainForHwnd (Slot 15)
        IDXGIFactory2* pFactory2 = nullptr;
        if (SUCCEEDED(pFactory->QueryInterface(__uuidof(IDXGIFactory2), reinterpret_cast<void**>(&pFactory2))) && pFactory2) {
            void** vtable2 = *reinterpret_cast<void***>(pFactory2);
            if (vtable2 && vtable2[15] != Hooked_CreateSwapChainForHwnd) {
                PatchVTable(vtable2, 15, reinterpret_cast<void*>(Hooked_CreateSwapChainForHwnd),
                            reinterpret_cast<void**>(&g_origCreateSwapChainForHwnd));
                OutputDebugStringA("[DXGI-Hook] IDXGIFactory2::CreateSwapChainForHwnd VTable hooked!\n");
            }
            pFactory2->Release();
        }
    }
}

// Hook CreateDXGIFactory
HRESULT WINAPI Hooked_CreateDXGIFactory(REFIID riid, void **ppFactory) {
    OutputDebugStringA("[DXGI-Hook] CreateDXGIFactory called\n");
    HRESULT hr = E_FAIL;
    if (g_origCreateDXGIFactory) {
        hr = g_origCreateDXGIFactory(riid, ppFactory);
    } else {
        HMODULE hReal = GetRealDxgiModule();
        if (hReal) {
            auto pFunc = reinterpret_cast<PFN_CreateDXGIFactory>(GetProcAddress(hReal, "CreateDXGIFactory"));
            if (pFunc) hr = pFunc(riid, ppFactory);
        }
    }
    if (SUCCEEDED(hr) && ppFactory && *ppFactory) {
        HookFactoryVTable(reinterpret_cast<IDXGIFactory*>(*ppFactory));
    }
    return hr;
}

// Hook CreateDXGIFactory1
HRESULT WINAPI Hooked_CreateDXGIFactory1(REFIID riid, void **ppFactory) {
    OutputDebugStringA("[DXGI-Hook] CreateDXGIFactory1 called\n");
    HRESULT hr = E_FAIL;
    if (g_origCreateDXGIFactory1) {
        hr = g_origCreateDXGIFactory1(riid, ppFactory);
    } else {
        HMODULE hReal = GetRealDxgiModule();
        if (hReal) {
            auto pFunc = reinterpret_cast<PFN_CreateDXGIFactory1>(GetProcAddress(hReal, "CreateDXGIFactory1"));
            if (pFunc) hr = pFunc(riid, ppFactory);
        }
    }
    if (SUCCEEDED(hr) && ppFactory && *ppFactory) {
        HookFactoryVTable(reinterpret_cast<IDXGIFactory*>(*ppFactory));
    }
    return hr;
}

// Hook CreateDXGIFactory2
HRESULT WINAPI Hooked_CreateDXGIFactory2(UINT Flags, REFIID riid, void **ppFactory) {
    OutputDebugStringA("[DXGI-Hook] CreateDXGIFactory2 called\n");
    HRESULT hr = E_FAIL;
    if (g_origCreateDXGIFactory2) {
        hr = g_origCreateDXGIFactory2(Flags, riid, ppFactory);
    } else {
        HMODULE hReal = GetRealDxgiModule();
        if (hReal) {
            auto pFunc = reinterpret_cast<PFN_CreateDXGIFactory2>(GetProcAddress(hReal, "CreateDXGIFactory2"));
            if (pFunc) hr = pFunc(Flags, riid, ppFactory);
        }
    }
    if (SUCCEEDED(hr) && ppFactory && *ppFactory) {
        HookFactoryVTable(reinterpret_cast<IDXGIFactory*>(*ppFactory));
    }
    return hr;
}

// Hook D3D11CreateDeviceAndSwapChain từ d3d11.dll
HRESULT WINAPI Hooked_D3D11CreateDeviceAndSwapChain(
    IDXGIAdapter* pAdapter,
    D3D_DRIVER_TYPE DriverType,
    HMODULE Software,
    UINT Flags,
    const D3D_FEATURE_LEVEL* pFeatureLevels,
    UINT FeatureLevels,
    UINT SDKVersion,
    const DXGI_SWAP_CHAIN_DESC* pSwapChainDesc,
    IDXGISwapChain** ppSwapChain,
    ID3D11Device** ppDevice,
    D3D_FEATURE_LEVEL* pFeatureLevel,
    ID3D11DeviceContext** ppImmediateContext)
{
    OutputDebugStringA("[DXGI-Hook] D3D11CreateDeviceAndSwapChain intercepted\n");

    DXGI_SWAP_CHAIN_DESC modifiedDesc;
    const DXGI_SWAP_CHAIN_DESC* pActualDesc = pSwapChainDesc;

    if (pSwapChainDesc) {
        modifiedDesc = *pSwapChainDesc;
        modifiedDesc.Windowed = TRUE;
        modifiedDesc.Flags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
        if (modifiedDesc.OutputWindow) {
            MakeWindowBorderless(modifiedDesc.OutputWindow);
        }
        pActualDesc = &modifiedDesc;
    }

    HRESULT hr = S_OK;
    if (g_origD3D11CreateDeviceAndSwapChain) {
        hr = g_origD3D11CreateDeviceAndSwapChain(
            pAdapter, DriverType, Software, Flags, pFeatureLevels, FeatureLevels,
            SDKVersion, pActualDesc, ppSwapChain, ppDevice, pFeatureLevel, ppImmediateContext);
    }

    if (SUCCEEDED(hr) && ppSwapChain && *ppSwapChain) {
        HookSwapChain(*ppSwapChain);
    }

    return hr;
}

// Khởi tạo các hook trong không gian tiến trình game
void InitializeDxgiHooks() {
    if (g_isInitialized || g_isExcludedProcess) return;
    std::lock_guard<std::mutex> lock(g_hookMutex);
    if (g_isInitialized) return;

    MH_STATUS status = MH_Initialize();
    if (status != MH_OK && status != MH_ERROR_ALREADY_INITIALIZED) {
        OutputDebugStringA("[DXGI-Hook] MH_Initialize failed\n");
        return;
    }

    // 1. Hook CreateDXGIFactory, CreateDXGIFactory1, CreateDXGIFactory2 từ dxgi.dll
    MH_CreateHookApi(L"dxgi.dll", "CreateDXGIFactory",
                     reinterpret_cast<LPVOID>(Hooked_CreateDXGIFactory),
                     reinterpret_cast<LPVOID*>(&g_origCreateDXGIFactory));

    MH_CreateHookApi(L"dxgi.dll", "CreateDXGIFactory1",
                     reinterpret_cast<LPVOID>(Hooked_CreateDXGIFactory1),
                     reinterpret_cast<LPVOID*>(&g_origCreateDXGIFactory1));

    MH_CreateHookApi(L"dxgi.dll", "CreateDXGIFactory2",
                     reinterpret_cast<LPVOID>(Hooked_CreateDXGIFactory2),
                     reinterpret_cast<LPVOID*>(&g_origCreateDXGIFactory2));

    // 2. Hook D3D11CreateDeviceAndSwapChain từ d3d11.dll
    MH_CreateHookApi(L"d3d11.dll", "D3D11CreateDeviceAndSwapChain",
                     reinterpret_cast<LPVOID>(Hooked_D3D11CreateDeviceAndSwapChain),
                     reinterpret_cast<LPVOID*>(&g_origD3D11CreateDeviceAndSwapChain));

    // 3. Hook XInputGetState & XInputGetStateEx để ngắt gamepad vào game khi mở Overlay
    const wchar_t* xinputModules[] = {
        L"xinput1_4.dll", L"xinput1_3.dll", L"xinput9_1_0.dll", L"xinput1_2.dll", L"xinput1_1.dll"
    };
    for (const auto* mod : xinputModules) {
        HMODULE hXInput = GetModuleHandleW(mod);
        if (!hXInput) hXInput = LoadLibraryW(mod);
        if (hXInput) {
            FARPROC pGetState = GetProcAddress(hXInput, "XInputGetState");
            if (pGetState && !g_origXInputGetState) {
                MH_CreateHook(reinterpret_cast<LPVOID>(pGetState),
                              reinterpret_cast<LPVOID>(Hooked_XInputGetState),
                              reinterpret_cast<LPVOID*>(&g_origXInputGetState));
                OutputDebugStringA("[DXGI-Hook] XInputGetState hooked successfully!\n");
            }

            FARPROC pGetStateEx = GetProcAddress(hXInput, MAKEINTRESOURCEA(100));
            if (pGetStateEx && !g_origXInputGetStateEx) {
                MH_CreateHook(reinterpret_cast<LPVOID>(pGetStateEx),
                              reinterpret_cast<LPVOID>(Hooked_XInputGetStateEx),
                              reinterpret_cast<LPVOID*>(&g_origXInputGetStateEx));
                OutputDebugStringA("[DXGI-Hook] XInputGetStateEx hooked successfully!\n");
            }
        }
    }

    MH_EnableHook(MH_ALL_HOOKS);

    // 4. Thử tạo một Factory giả lập để hook VTable dùng chung toàn tiến trình ngay lập tức
    IDXGIFactory* pDummyFactory = nullptr;
    HMODULE hDxgi = GetModuleHandleW(L"dxgi.dll");
    if (hDxgi) {
        auto pCreateFactory = reinterpret_cast<PFN_CreateDXGIFactory>(GetProcAddress(hDxgi, "CreateDXGIFactory"));
        if (pCreateFactory && SUCCEEDED(pCreateFactory(__uuidof(IDXGIFactory), reinterpret_cast<void**>(&pDummyFactory)))) {
            HookFactoryVTable(pDummyFactory);
            pDummyFactory->Release();
        }
    }

    g_isInitialized = true;
    OutputDebugStringA("[DXGI-Hook] DXGI Borderless & XInput Hook initialized successfully!\n");
}

// =========================================================================
// Exported Functions & Global Hook Management
// =========================================================================

// CBT Hook Procedure (được Windows tự động gọi trong mọi tiến trình GUI 64-bit)
LRESULT CALLBACK CBTProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode >= 0) {
        if (!g_isInitialized && !g_isExcludedProcess) {
            InitializeDxgiHooks();
        }
    }
    return CallNextHookEx(g_hHook, nCode, wParam, lParam);
}

extern "C" {

DXGI_HOOK_API BOOL WINAPI InstallGlobalDxgiHook(void) {
    if (g_hHook) return TRUE;

    // Cài đặt CBT Hook toàn hệ thống (Thread ID 0)
    g_hHook = SetWindowsHookExW(WH_CBT, CBTProc, g_hInstance, 0);
    if (!g_hHook) {
        // Fallback sang WH_GETMESSAGE nếu CBT gặp hạn chế
        g_hHook = SetWindowsHookExW(WH_GETMESSAGE, reinterpret_cast<HOOKPROC>(CBTProc), g_hInstance, 0);
    }

    return g_hHook != nullptr;
}

DXGI_HOOK_API BOOL WINAPI UninstallGlobalDxgiHook(void) {
    if (!g_hHook) return TRUE;

    BOOL res = UnhookWindowsHookEx(g_hHook);
    if (res) {
        g_hHook = nullptr;
    }
    return res;
}

DXGI_HOOK_API BOOL WINAPI IsGlobalDxgiHookActive(void) {
    return g_hHook != nullptr;
}

DXGI_HOOK_API void WINAPI SetOverlayActive(BOOL active) {
    g_isOverlayActive = active;
    if (active) {
        OutputDebugStringA("[DXGI-Hook] SetOverlayActive(TRUE): Gamepad input muted in game\n");
    } else {
        OutputDebugStringA("[DXGI-Hook] SetOverlayActive(FALSE): Gamepad input restored in game\n");
    }
}

DXGI_HOOK_API BOOL WINAPI IsOverlayActive(void) {
    return g_isOverlayActive;
}

DXGI_HOOK_API void WINAPI SetOverlayHookMode(int mode) {
    g_hookMode = mode;
    if (mode == OVERLAY_HOOK_MODE_SHARED_TEXTURE) {
        OutputDebugStringA("[DXGI-Hook] Switch to Direct3D Shared Texture Injection Mode\n");
    } else {
        OutputDebugStringA("[DXGI-Hook] Switch to DXGI Borderless Hook Mode\n");
    }
}

DXGI_HOOK_API int WINAPI GetOverlayHookMode(void) {
    return g_hookMode;
}

DXGI_HOOK_API void WINAPI SetSharedTextureHandle(HANDLE hSharedTexture) {
    g_hSharedTexture = hSharedTexture;
    OutputDebugStringA("[DXGI-Hook] SetSharedTextureHandle updated\n");
}

DXGI_HOOK_API HANDLE WINAPI GetSharedTextureHandle(void) {
    return g_hSharedTexture;
}

// =========================================================================
// Host Direct3D 11 Texture Capture Pipeline (Dành cho Ứng dụng Flutter)
// =========================================================================

namespace {
ID3D11Device*        g_pHostDevice = nullptr;
ID3D11DeviceContext* g_pHostContext = nullptr;
ID3D11Texture2D*     g_pHostTexture = nullptr;      // Format B8G8R8A8_UNORM
ID3D11Texture2D*     g_pHostTextureRGBA = nullptr;  // Format R8G8B8A8_UNORM
HDC                  g_hHostMemDC = nullptr;
HBITMAP              g_hHostBitmap = nullptr;
void*                g_pHostBits = nullptr;
void*                g_pHostBitsRGBA = nullptr;
UINT                 g_hostWidth = 0;
UINT                 g_hostHeight = 0;
} // namespace

DXGI_HOOK_API void WINAPI ReleaseOverlaySharedTexture(void) {
    if (g_hHostBitmap) {
        DeleteObject(g_hHostBitmap);
        g_hHostBitmap = nullptr;
        g_pHostBits = nullptr;
    }
    if (g_pHostBitsRGBA) {
        free(g_pHostBitsRGBA);
        g_pHostBitsRGBA = nullptr;
    }
    if (g_hHostMemDC) {
        DeleteDC(g_hHostMemDC);
        g_hHostMemDC = nullptr;
    }
    if (g_pHostTextureRGBA) {
        g_pHostTextureRGBA->Release();
        g_pHostTextureRGBA = nullptr;
    }
    if (g_pHostTexture) {
        g_pHostTexture->Release();
        g_pHostTexture = nullptr;
    }
    if (g_pHostContext) {
        g_pHostContext->Release();
        g_pHostContext = nullptr;
    }
    if (g_pHostDevice) {
        g_pHostDevice->Release();
        g_pHostDevice = nullptr;
    }
    g_hSharedTexture = nullptr;
    g_hSharedTextureBGRA = nullptr;
    g_hSharedTextureRGBA = nullptr;
    g_hostWidth = 0;
    g_hostHeight = 0;
    OutputDebugStringA("[DXGI-Hook] ReleaseOverlaySharedTexture: Released host resources\n");
}

DXGI_HOOK_API BOOL WINAPI CreateOverlaySharedTexture(UINT width, UINT height) {
    if (width == 0 || height == 0) return FALSE;

    ReleaseOverlaySharedTexture();

    D3D_FEATURE_LEVEL featureLevels[] = {
        D3D_FEATURE_LEVEL_11_0,
        D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0
    };
    D3D_FEATURE_LEVEL actualLevel;

    HRESULT hr = D3D11CreateDevice(
        nullptr,
        D3D_DRIVER_TYPE_HARDWARE,
        nullptr,
        D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        featureLevels,
        ARRAYSIZE(featureLevels),
        D3D11_SDK_VERSION,
        &g_pHostDevice,
        &actualLevel,
        &g_pHostContext
    );

    if (FAILED(hr) || !g_pHostDevice) {
        OutputDebugStringA("[DXGI-Hook] CreateOverlaySharedTexture: D3D11CreateDevice failed\n");
        return FALSE;
    }

    // 1. Tạo GPU Shared Texture chuẩn B8G8R8A8_UNORM
    D3D11_TEXTURE2D_DESC descBGRA{};
    descBGRA.Width = width;
    descBGRA.Height = height;
    descBGRA.MipLevels = 1;
    descBGRA.ArraySize = 1;
    descBGRA.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    descBGRA.SampleDesc.Count = 1;
    descBGRA.SampleDesc.Quality = 0;
    descBGRA.Usage = D3D11_USAGE_DEFAULT;
    descBGRA.BindFlags = D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET;
    descBGRA.CPUAccessFlags = 0;
    descBGRA.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

    hr = g_pHostDevice->CreateTexture2D(&descBGRA, nullptr, &g_pHostTexture);
    if (FAILED(hr) || !g_pHostTexture) {
        OutputDebugStringA("[DXGI-Hook] CreateOverlaySharedTexture: CreateTexture2D (BGRA) failed\n");
        ReleaseOverlaySharedTexture();
        return FALSE;
    }

    IDXGIResource* pResourceBGRA = nullptr;
    hr = g_pHostTexture->QueryInterface(__uuidof(IDXGIResource), reinterpret_cast<void**>(&pResourceBGRA));
    if (SUCCEEDED(hr) && pResourceBGRA) {
        HANDLE hShared = nullptr;
        if (SUCCEEDED(pResourceBGRA->GetSharedHandle(&hShared))) {
            g_hSharedTextureBGRA = hShared;
            g_hSharedTexture = hShared;
            OutputDebugStringA("[DXGI-Hook] CreateOverlaySharedTexture: SharedHandle (BGRA) created successfully\n");
        }
        pResourceBGRA->Release();
    }

    // 2. Tạo GPU Shared Texture chuẩn R8G8B8A8_UNORM dành cho các tựa game DirectX chuẩn RGBA
    D3D11_TEXTURE2D_DESC descRGBA = descBGRA;
    descRGBA.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    hr = g_pHostDevice->CreateTexture2D(&descRGBA, nullptr, &g_pHostTextureRGBA);
    if (SUCCEEDED(hr) && g_pHostTextureRGBA) {
        IDXGIResource* pResourceRGBA = nullptr;
        hr = g_pHostTextureRGBA->QueryInterface(__uuidof(IDXGIResource), reinterpret_cast<void**>(&pResourceRGBA));
        if (SUCCEEDED(hr) && pResourceRGBA) {
            HANDLE hSharedRGBA = nullptr;
            if (SUCCEEDED(pResourceRGBA->GetSharedHandle(&hSharedRGBA))) {
                g_hSharedTextureRGBA = hSharedRGBA;
                OutputDebugStringA("[DXGI-Hook] CreateOverlaySharedTexture: SharedHandle (RGBA) created successfully\n");
            }
            pResourceRGBA->Release();
        }
    }

    // Tạo GDI Memory DC & 32-bit DIB Bitmap để capture cửa sổ Flutter
    HDC screenDC = GetDC(nullptr);
    g_hHostMemDC = CreateCompatibleDC(screenDC);

    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = width;
    bmi.bmiHeader.biHeight = -static_cast<LONG>(height); // Top-down DIB
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;

    g_hHostBitmap = CreateDIBSection(g_hHostMemDC, &bmi, DIB_RGB_COLORS, &g_pHostBits, nullptr, 0);
    if (g_hHostBitmap) {
        SelectObject(g_hHostMemDC, g_hHostBitmap);
    }
    ReleaseDC(nullptr, screenDC);

    // Cấp phát bộ đệm CPU RGBA để chuyển đổi pixel màu nhanh cho texture RGBA
    g_pHostBitsRGBA = malloc(static_cast<size_t>(width) * height * 4);

    g_hostWidth = width;
    g_hostHeight = height;
    return (g_hSharedTextureBGRA != nullptr || g_hSharedTextureRGBA != nullptr);
}

DXGI_HOOK_API BOOL WINAPI UpdateOverlaySharedTextureFromHwnd(HWND hWnd) {
    if (!hWnd || !IsWindow(hWnd)) {
        return FALSE;
    }

    // Tự động phục hồi hoặc khởi tạo kết cấu nếu chưa có
    if (!g_pHostTexture || !g_pHostContext || !g_pHostBits || !g_hHostMemDC) {
        RECT rc{};
        GetClientRect(hWnd, &rc);
        UINT w = rc.right - rc.left;
        UINT h = rc.bottom - rc.top;
        if (w == 0 || h == 0) {
            w = static_cast<UINT>(GetSystemMetrics(SM_CXSCREEN));
            h = static_cast<UINT>(GetSystemMetrics(SM_CYSCREEN));
        }
        if (!CreateOverlaySharedTexture(w, h)) {
            return FALSE;
        }
    }

    // Chụp trực tiếp bề mặt Render của cửa sổ Flutter vào DIB Section
    BOOL printed = PrintWindow(hWnd, g_hHostMemDC, 2 /* PW_RENDERFULLCONTENT */);
    if (!printed) {
        HDC wndDC = GetDC(hWnd);
        if (wndDC) {
            BitBlt(g_hHostMemDC, 0, 0, g_hostWidth, g_hostHeight, wndDC, 0, 0, SRCCOPY);
            ReleaseDC(hWnd, wndDC);
        }
    }

    // 1. Nạp dữ liệu BGRA vào GPU VRAM Direct3D 11 Texture BGRA
    UINT rowPitch = g_hostWidth * 4;
    g_pHostContext->UpdateSubresource(g_pHostTexture, 0, nullptr, g_pHostBits, rowPitch, 0);

    // 2. Swizzle nhanh kênh màu B và R sang RGBA và nạp vào Texture RGBA
    if (g_pHostTextureRGBA && g_pHostBitsRGBA && g_pHostBits) {
        const uint32_t* src = static_cast<const uint32_t*>(g_pHostBits);
        uint32_t* dst = static_cast<uint32_t*>(g_pHostBitsRGBA);
        size_t totalPixels = static_cast<size_t>(g_hostWidth) * g_hostHeight;
        for (size_t i = 0; i < totalPixels; ++i) {
            uint32_t p = src[i];
            dst[i] = (p & 0xFF00FF00) | ((p & 0x00FF0000) >> 16) | ((p & 0x000000FF) << 16);
        }
        g_pHostContext->UpdateSubresource(g_pHostTextureRGBA, 0, nullptr, g_pHostBitsRGBA, rowPitch, 0);
    }

    return TRUE;
}

DXGI_HOOK_API BOOL WINAPI InjectDxgiHook(DWORD dwProcessId) {
    if (dwProcessId == 0 || dwProcessId == GetCurrentProcessId()) return FALSE;

    HANDLE hProcess = OpenProcess(PROCESS_CREATE_THREAD | PROCESS_QUERY_INFORMATION |
                                  PROCESS_VM_OPERATION | PROCESS_VM_WRITE | PROCESS_VM_READ,
                                  FALSE, dwProcessId);
    if (!hProcess) return FALSE;

    wchar_t dllPath[MAX_PATH];
    GetModuleFileNameW(g_hInstance, dllPath, MAX_PATH);

    size_t pathSize = (wcslen(dllPath) + 1) * sizeof(wchar_t);
    LPVOID remoteMem = VirtualAllocEx(hProcess, nullptr, pathSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remoteMem) {
        CloseHandle(hProcess);
        return FALSE;
    }

    if (!WriteProcessMemory(hProcess, remoteMem, dllPath, pathSize, nullptr)) {
        VirtualFreeEx(hProcess, remoteMem, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        return FALSE;
    }

    LPTHREAD_START_ROUTINE pLoadLibraryW = reinterpret_cast<LPTHREAD_START_ROUTINE>(
        GetProcAddress(GetModuleHandleW(L"kernel32.dll"), "LoadLibraryW"));

    HANDLE hThread = CreateRemoteThread(hProcess, nullptr, 0, pLoadLibraryW, remoteMem, 0, nullptr);
    if (!hThread) {
        VirtualFreeEx(hProcess, remoteMem, 0, MEM_RELEASE);
        CloseHandle(hProcess);
        return FALSE;
    }

    WaitForSingleObject(hThread, 5000);
    VirtualFreeEx(hProcess, remoteMem, 0, MEM_RELEASE);
    CloseHandle(hThread);
    CloseHandle(hProcess);
    return TRUE;
}

DXGI_HOOK_API BOOL WINAPI EjectDxgiHook(DWORD dwProcessId) {
    return TRUE;
}

DXGI_HOOK_API BOOL WINAPI MakeWindowBorderless(HWND hWnd) {
    if (!hWnd || !IsWindow(hWnd)) return FALSE;

    // Lấy thông tin Monitor chứa cửa sổ game
    HMONITOR hMon = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = { sizeof(MONITORINFO) };
    int screenX = 0, screenY = 0;
    int screenW = GetSystemMetrics(SM_CXSCREEN);
    int screenH = GetSystemMetrics(SM_CYSCREEN);

    if (GetMonitorInfo(hMon, &mi)) {
        screenX = mi.rcMonitor.left;
        screenY = mi.rcMonitor.top;
        screenW = mi.rcMonitor.right - mi.rcMonitor.left;
        screenH = mi.rcMonitor.bottom - mi.rcMonitor.top;
    }

    // 1. Xóa bỏ hoàn toàn thanh tiêu đề, khung kéo kích thước, viền cửa sổ
    LONG_PTR style = GetWindowLongPtr(hWnd, GWL_STYLE);
    style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU | WS_BORDER | WS_DLGFRAME);
    style |= WS_POPUP | WS_VISIBLE;
    SetWindowLongPtr(hWnd, GWL_STYLE, style);

    LONG_PTR exStyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE);
    exStyle &= ~(WS_EX_DLGMODALFRAME | WS_EX_CLIENTEDGE | WS_EX_STATICEDGE | WS_EX_WINDOWEDGE | WS_EX_OVERLAPPEDWINDOW);
    SetWindowLongPtr(hWnd, GWL_EXSTYLE, exStyle);

    // 2. Đặt vị trí bao phủ trọn vẹn màn hình với cờ SWP_FRAMECHANGED
    SetWindowPos(hWnd, HWND_TOP, screenX, screenY, screenW, screenH,
                 SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_SHOWWINDOW);

    OutputDebugStringA("[DXGI-Hook] Window converted to Borderless Fullscreen successfully!\n");
    return TRUE;
}

// =========================================================================
// Proxy DXGI Export Functions
// =========================================================================

HRESULT WINAPI CreateDXGIFactory(REFIID riid, void **ppFactory) {
    return Hooked_CreateDXGIFactory(riid, ppFactory);
}

HRESULT WINAPI CreateDXGIFactory1(REFIID riid, void **ppFactory) {
    return Hooked_CreateDXGIFactory1(riid, ppFactory);
}

HRESULT WINAPI CreateDXGIFactory2(UINT Flags, REFIID riid, void **ppFactory) {
    return Hooked_CreateDXGIFactory2(Flags, riid, ppFactory);
}

HRESULT WINAPI DXGID3D10CreateDevice(HMODULE hModule, IDXGIFactory *pFactory, IDXGIAdapter *pAdapter, UINT Flags, void *pUnknown, void **ppDevice) {
    HMODULE hReal = GetRealDxgiModule();
    if (!hReal) return E_FAIL;
    typedef HRESULT(WINAPI* fnDXGID3D10CreateDevice)(HMODULE, IDXGIFactory*, IDXGIAdapter*, UINT, void*, void**);
    auto pFunc = reinterpret_cast<fnDXGID3D10CreateDevice>(GetProcAddress(hReal, "DXGID3D10CreateDevice"));
    return pFunc ? pFunc(hModule, pFactory, pAdapter, Flags, pUnknown, ppDevice) : E_FAIL;
}

HRESULT WINAPI DXGID3D10CreateLayeredDevice(void *pUnknown1, void *pUnknown2, void *pUnknown3, void *pUnknown4, void *pUnknown5) {
    HMODULE hReal = GetRealDxgiModule();
    if (!hReal) return E_FAIL;
    typedef HRESULT(WINAPI* fnDXGID3D10CreateLayeredDevice)(void*, void*, void*, void*, void*);
    auto pFunc = reinterpret_cast<fnDXGID3D10CreateLayeredDevice>(GetProcAddress(hReal, "DXGID3D10CreateLayeredDevice"));
    return pFunc ? pFunc(pUnknown1, pUnknown2, pUnknown3, pUnknown4, pUnknown5) : E_FAIL;
}

size_t WINAPI DXGID3D10GetProviderFactoryAddress(void) {
    HMODULE hReal = GetRealDxgiModule();
    if (!hReal) return 0;
    typedef size_t(WINAPI* fnDXGID3D10GetProviderFactoryAddress)(void);
    auto pFunc = reinterpret_cast<fnDXGID3D10GetProviderFactoryAddress>(GetProcAddress(hReal, "DXGID3D10GetProviderFactoryAddress"));
    return pFunc ? pFunc() : 0;
}

HRESULT WINAPI DXGID3D10RegisterLayers(const void *pLayers, UINT NumLayers) {
    HMODULE hReal = GetRealDxgiModule();
    if (!hReal) return E_FAIL;
    typedef HRESULT(WINAPI* fnDXGID3D10RegisterLayers)(const void*, UINT);
    auto pFunc = reinterpret_cast<fnDXGID3D10RegisterLayers>(GetProcAddress(hReal, "DXGID3D10RegisterLayers"));
    return pFunc ? pFunc(pLayers, NumLayers) : E_FAIL;
}

} // extern "C"

// =========================================================================
// DllMain Entry Point
// =========================================================================

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    switch (fdwReason) {
        case DLL_PROCESS_ATTACH:
            DisableThreadLibraryCalls(hinstDLL);
            g_hInstance = hinstDLL;
            g_isExcludedProcess = CheckIfExcludedProcess();

            // Nếu không phải tiến trình bị loại trừ, tự động khởi tạo hook
            if (!g_isExcludedProcess) {
                InitializeDxgiHooks();
            }
            break;

        case DLL_PROCESS_DETACH:
            if (g_isInitialized) {
                MH_DisableHook(MH_ALL_HOOKS);
                MH_Uninitialize();
            }
            if (g_hRealDxgi) {
                FreeLibrary(g_hRealDxgi);
                g_hRealDxgi = nullptr;
            }
            break;
    }
    return TRUE;
}
