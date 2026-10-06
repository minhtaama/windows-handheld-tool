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

// Hook hàm SetFullscreenState trên SwapChain
HRESULT STDMETHODCALLTYPE Hooked_SetFullscreenState(
    IDXGISwapChain* pThis,
    BOOL Fullscreen,
    IDXGIOutput* pTarget)
{
    OutputDebugStringA("[DXGI-Hook] SetFullscreenState called\n");

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

// Hook hàm ResizeTarget trên SwapChain (Slot 14)
// Tự động kéo dãn (Dynamic Upscaling) bất kỳ độ phân giải nào (720p, 800p, 1080p, 2K, 4K)
HRESULT STDMETHODCALLTYPE Hooked_ResizeTarget(
    IDXGISwapChain* pThis,
    const DXGI_MODE_DESC* pNewTargetParameters)
{
    OutputDebugStringA("[DXGI-Hook] ResizeTarget called (Handling Dynamic Resolution scaling)\n");

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

// Hook hàm MakeWindowAssociation trên IDXGIFactory (Slot 8)
HRESULT STDMETHODCALLTYPE Hooked_MakeWindowAssociation(
    IDXGIFactory* pThis,
    HWND WindowHandle,
    UINT Flags)
{
    OutputDebugStringA("[DXGI-Hook] MakeWindowAssociation called\n");

    // Thêm cờ cấm DirectX runtime tự ý thay đổi style hoặc kích thước cửa sổ
    UINT modifiedFlags = Flags | DXGI_MWA_NO_WINDOW_CHANGES | DXGI_MWA_NO_ALT_ENTER;

    if (g_origMakeWindowAssociation) {
        return g_origMakeWindowAssociation(pThis, WindowHandle, modifiedFlags);
    }
    return S_OK;
}

void HookSwapChain(IDXGISwapChain* pSwapChain) {
    if (!pSwapChain) return;
    std::lock_guard<std::mutex> lock(g_hookMutex);

    void** vtable = *reinterpret_cast<void***>(pSwapChain);
    if (!vtable) return;

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

    if (pDesc) {
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

    DXGI_SWAP_CHAIN_FULLSCREEN_DESC fsDescCopy;
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC* pActualFsDesc = pFullscreenDesc;

    if (pFullscreenDesc) {
        fsDescCopy = *pFullscreenDesc;
        // Ép Windowed = TRUE
        fsDescCopy.Windowed = TRUE;
        pActualFsDesc = &fsDescCopy;
    }

    if (hWnd) {
        MakeWindowBorderless(hWnd);
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
