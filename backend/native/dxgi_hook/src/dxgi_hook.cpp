#include "dxgi_hook.h"
#include <cstdio>
#include <cmath>
#include <atomic>
#include <windowsx.h>

// Log chẩn đoán ra OutputDebugString
static void LogDebug(const char* format, ...) {
    char buf[512];
    va_list args;
    va_start(args, format);
    vsnprintf(buf, sizeof(buf), format, args);
    va_end(args);
    OutputDebugStringA(buf);
}

// Cờ trạng thái
static std::atomic<bool> g_bInitialized(false);
static std::atomic<bool> g_bGameRequestedFullscreen(false);
static std::atomic<bool> g_bSwapChainHooked(false);
static std::atomic<bool> g_bXInputHooked(false);

// Thông số hình học nội tiến trình của Game phục vụ chuẩn hóa chuột
static std::atomic<HWND> g_hGameWnd(nullptr);
static std::atomic<UINT> g_uBufferWidth(0);
static std::atomic<UINT> g_uBufferHeight(0);

// Con trỏ hàm gốc (Original function pointers)
typedef HRESULT (STDMETHODCALLTYPE* PFN_SetFullscreenState)(IDXGISwapChain* This, BOOL Fullscreen, IDXGIOutput* pTarget);
typedef HRESULT (STDMETHODCALLTYPE* PFN_GetFullscreenState)(IDXGISwapChain* This, BOOL* pFullscreen, IDXGIOutput** ppTarget);
typedef HRESULT (STDMETHODCALLTYPE* PFN_CreateSwapChain)(IDXGIFactory* This, IUnknown* pDevice, DXGI_SWAP_CHAIN_DESC* pDesc, IDXGISwapChain** ppSwapChain);
typedef HRESULT (STDMETHODCALLTYPE* PFN_CreateSwapChainForHwnd)(IDXGIFactory2* This, IUnknown* pDevice, HWND hWnd, const DXGI_SWAP_CHAIN_DESC1* pDesc, const DXGI_SWAP_CHAIN_FULLSCREEN_DESC* pFullscreenDesc, IDXGIOutput* pRestrictToOutput, IDXGISwapChain1** ppSwapChain);

typedef HRESULT (WINAPI* PFN_D3D11CreateDeviceAndSwapChain)(IDXGIAdapter* pAdapter, D3D_DRIVER_TYPE DriverType, HMODULE Software, UINT Flags, const D3D_FEATURE_LEVEL* pFeatureLevels, UINT FeatureLevels, UINT SDKVersion, const DXGI_SWAP_CHAIN_DESC* pSwapChainDesc, IDXGISwapChain** ppSwapChain, ID3D11Device** ppDevice, D3D_FEATURE_LEVEL* pFeatureLevel, ID3D11DeviceContext** ppImmediateContext);
typedef HRESULT (WINAPI* PFN_CreateDXGIFactory)(REFIID riid, void** ppFactory);
typedef HRESULT (WINAPI* PFN_CreateDXGIFactory1)(REFIID riid, void** ppFactory);
typedef HRESULT (WINAPI* PFN_CreateDXGIFactory2)(UINT Flags, REFIID riid, void** ppFactory);

typedef HRESULT (STDMETHODCALLTYPE* PFN_ResizeBuffers)(IDXGISwapChain* This, UINT BufferCount, UINT Width, UINT Height, DXGI_FORMAT NewFormat, UINT SwapChainFlags);
typedef HRESULT (STDMETHODCALLTYPE* PFN_ResizeTarget)(IDXGISwapChain* This, const DXGI_MODE_DESC* pNewTargetParameters);

typedef DWORD (WINAPI* PFN_XInputGetState)(DWORD dwUserIndex, XINPUT_STATE* pState);

static PFN_SetFullscreenState g_pOrigSetFullscreenState = nullptr;
static PFN_GetFullscreenState g_pOrigGetFullscreenState = nullptr;
static PFN_CreateSwapChain g_pOrigCreateSwapChain = nullptr;
static PFN_CreateSwapChainForHwnd g_pOrigCreateSwapChainForHwnd = nullptr;
static PFN_D3D11CreateDeviceAndSwapChain g_pOrigD3D11CreateDeviceAndSwapChain = nullptr;
static PFN_CreateDXGIFactory g_pOrigCreateDXGIFactory = nullptr;
static PFN_CreateDXGIFactory1 g_pOrigCreateDXGIFactory1 = nullptr;
static PFN_CreateDXGIFactory2 g_pOrigCreateDXGIFactory2 = nullptr;

static PFN_ResizeBuffers g_pOrigResizeBuffers = nullptr;
static PFN_ResizeTarget g_pOrigResizeTarget = nullptr;
static PFN_XInputGetState g_pOrigXInputGetState = nullptr;
static HANDLE g_hPanelActiveEvent = nullptr;

// Ép nhận thức Per-Monitor V2 DPI cho tiến trình Game để triệt tiêu việc Windows ảo hóa tọa độ chuột
static int g_dpiSetResult = -1; // 1 = OK, >1 = mã lỗi Win32 (5 = đã bị khóa DPI), -1 = chưa gọi

static void InitDpiAwareness() {
    HMODULE hUser32 = GetModuleHandleW(L"user32.dll");
    if (hUser32) {
        typedef BOOL (WINAPI* PFN_SetProcessDpiAwarenessContext)(void*);
        PFN_SetProcessDpiAwarenessContext pfnSetDpiContext = 
            (PFN_SetProcessDpiAwarenessContext)GetProcAddress(hUser32, "SetProcessDpiAwarenessContext");
        if (pfnSetDpiContext) {
            // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = -4
            BOOL dpiOk = pfnSetDpiContext((void*)-4);
            DWORD dpiErr = dpiOk ? 0 : GetLastError();
            g_dpiSetResult = dpiOk ? 1 : (int)dpiErr;
            LogDebug("[DXGI_HOOK] SetProcessDpiAwarenessContext(PMv2) ok=%d, err=%lu\n", dpiOk, dpiErr);
            LogDebug("[DXGI_HOOK] Đã kích hoạt Per-Monitor V2 DPI Awareness cho tiến trình Game\n");
            return;
        }
    }
    HMODULE hShcore = LoadLibraryW(L"shcore.dll");
    if (hShcore) {
        typedef HRESULT (WINAPI* PFN_SetProcessDpiAwareness)(int);
        PFN_SetProcessDpiAwareness pfnSetDpi = (PFN_SetProcessDpiAwareness)GetProcAddress(hShcore, "SetProcessDpiAwareness");
        if (pfnSetDpi) {
            // PROCESS_PER_MONITOR_DPI_AWARE = 2
            pfnSetDpi(2);
            LogDebug("[DXGI_HOOK] Đã kích hoạt Per-Monitor DPI Awareness qua Shcore\n");
        }
    }
}

// Kiểm tra xem Quick Panel có đang mở hay không thông qua Named Event toàn cục
static bool IsPanelActive() {
    if (!g_hPanelActiveEvent) {
        g_hPanelActiveEvent = OpenEventW(SYNCHRONIZE, FALSE, L"Global\\HandheldTool_PanelActive");
        if (!g_hPanelActiveEvent) {
            g_hPanelActiveEvent = OpenEventW(SYNCHRONIZE, FALSE, L"HandheldTool_PanelActive");
        }
    }
    if (g_hPanelActiveEvent) {
        DWORD waitRes = WaitForSingleObject(g_hPanelActiveEvent, 0);
        return (waitRes == WAIT_OBJECT_0);
    }
    return false;
}

// Cưỡng bức chuyển cửa sổ sang Borderless Fullscreen triệt để (Chuẩn hóa cả Style, ExStyle và Scaling)
void ForceBorderlessWindow(HWND hWnd) {
    if (!hWnd || !IsWindow(hWnd)) return;

    HMONITOR hMon = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = { sizeof(mi) };
    if (!GetMonitorInfo(hMon, &mi)) return;

    int screen_w = mi.rcMonitor.right - mi.rcMonitor.left;
    int screen_h = mi.rcMonitor.bottom - mi.rcMonitor.top;

    RECT curRect;
    GetWindowRect(hWnd, &curRect);
    LONG_PTR curStyle = GetWindowLongPtr(hWnd, GWL_STYLE);
    LONG_PTR borderMask = WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU | WS_BORDER | 0x00400000L /*WS_DLGFRAME*/;

    LONG_PTR curExStyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE);
    LONG_PTR exMask = 0x00000100L /*WS_EX_WINDOWEDGE*/ | 0x00000200L /*WS_EX_CLIENTEDGE*/ | 0x00020000L /*WS_EX_STATICEDGE*/;

    bool needsGeoUpdate = (curRect.left != mi.rcMonitor.left ||
                           curRect.top != mi.rcMonitor.top ||
                           (curRect.right - curRect.left) != screen_w ||
                           (curRect.bottom - curRect.top) != screen_h);
    bool needsStyleUpdate = ((curStyle & borderMask) != 0) || ((curExStyle & exMask) != 0);

    // Nếu cửa sổ game đã đúng kích thước và không còn viền, TUYỆT ĐỐI KHÔNG gọi lại SetWindowPos
    // Tránh gửi thông điệp WM_WINDOWPOSCHANGED thừa làm Unreal Engine desync ma trận tọa độ chuột
    if (!needsGeoUpdate && !needsStyleUpdate) {
        return;
    }

    LONG_PTR newStyle = (curStyle & ~borderMask) | WS_POPUP | WS_VISIBLE;
    if (newStyle != curStyle) {
        SetWindowLongPtr(hWnd, GWL_STYLE, newStyle);
    }

    LONG_PTR newExStyle = curExStyle & ~exMask;
    if (newExStyle != curExStyle) {
        SetWindowLongPtr(hWnd, GWL_EXSTYLE, newExStyle);
    }

    SetWindowPos(
        hWnd,
        HWND_NOTOPMOST,
        mi.rcMonitor.left,
        mi.rcMonitor.top,
        screen_w,
        screen_h,
        SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOZORDER | SWP_SHOWWINDOW
    );

    LogDebug("[DXGI_HOOK] ForceBorderlessWindow applied to HWND=0x%p: (%d, %d, %dx%d)\n", hWnd, mi.rcMonitor.left, mi.rcMonitor.top, screen_w, screen_h);
}

// Hook ResizeBuffers để bảo toàn hình học Borderless khi game đổi kích thước buffer
HRESULT STDMETHODCALLTYPE Hooked_ResizeBuffers(
    IDXGISwapChain* This,
    UINT BufferCount,
    UINT Width,
    UINT Height,
    DXGI_FORMAT NewFormat,
    UINT SwapChainFlags
) {
    LogDebug("[DXGI_HOOK] ResizeBuffers intercepted: Count=%u, %ux%u, Format=%d, Flags=0x%X\n",
        BufferCount, Width, Height, NewFormat, SwapChainFlags);

    // Xóa cờ cho phép mode switch
    SwapChainFlags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;

    if (Width > 0 && Height > 0) {
        g_uBufferWidth.store(Width);
        g_uBufferHeight.store(Height);
    }

    HRESULT hr = g_pOrigResizeBuffers ?
        g_pOrigResizeBuffers(This, BufferCount, Width, Height, NewFormat, SwapChainFlags) : E_FAIL;

    DXGI_SWAP_CHAIN_DESC desc;
    if (SUCCEEDED(This->GetDesc(&desc)) && desc.OutputWindow) {
        g_hGameWnd.store(desc.OutputWindow);
        ForceBorderlessWindow(desc.OutputWindow);
    }

    return hr;
}

// Hook ResizeTarget: Chặn game engine co rút cửa sổ Win32 khi render ở độ phân giải nhỏ hơn màn hình
HRESULT STDMETHODCALLTYPE Hooked_ResizeTarget(
    IDXGISwapChain* This,
    const DXGI_MODE_DESC* pNewTargetParameters
) {
    if (pNewTargetParameters) {
        LogDebug("[DXGI_HOOK] ResizeTarget intercepted: Game requested (%ux%u) -> Trả về S_OK bảo toàn ma trận chuột\n",
            pNewTargetParameters->Width, pNewTargetParameters->Height);
    }

    DXGI_SWAP_CHAIN_DESC desc;
    if (SUCCEEDED(This->GetDesc(&desc)) && desc.OutputWindow) {
        ForceBorderlessWindow(desc.OutputWindow);
    }

    // Tuyệt đối KHÔNG gọi g_pOrigResizeTarget với kích thước màn hình giả, vì việc thay đổi Target Parameters
    // sẽ khiến Unreal Engine tính toán lại Viewport Scale và làm lệch tọa độ chuột so với render buffer!
    // Trả về S_OK để game engine tin rằng đã resize thành công mà cửa sổ Win32 và tọa độ chuột không bị xáo trộn.
    return S_OK;
}

// 1. Hook SetFullscreenState
HRESULT STDMETHODCALLTYPE Hooked_SetFullscreenState(
    IDXGISwapChain* This,
    BOOL Fullscreen,
    IDXGIOutput* pTarget
) {
    LogDebug("[DXGI_HOOK] IDXGISwapChain::SetFullscreenState called with Fullscreen=%d\n", Fullscreen);

    if (Fullscreen) {
        g_bGameRequestedFullscreen = true;

        // Ép trạng thái cửa sổ về FALSE
        if (g_pOrigSetFullscreenState) {
            g_pOrigSetFullscreenState(This, FALSE, NULL);
        }

        // Tự động căn chỉnh cửa sổ game bao phủ toàn bộ màn hình
        DXGI_SWAP_CHAIN_DESC desc;
        if (SUCCEEDED(This->GetDesc(&desc)) && desc.OutputWindow) {
            ForceBorderlessWindow(desc.OutputWindow);
        }

        // Báo cho game biết lệnh chuyển Fullscreen đã thành công
        return S_OK;
    }

    return g_pOrigSetFullscreenState ? g_pOrigSetFullscreenState(This, Fullscreen, pTarget) : S_OK;
}

// 2. Hook GetFullscreenState: Bảo đảm trả về FALSE (Windowed) để game engine
// sử dụng chuẩn xác ma trận ánh xạ chuột Client Rect (tránh áp dụng Exclusive Fullscreen Matrix làm lệch chuột)
HRESULT STDMETHODCALLTYPE Hooked_GetFullscreenState(
    IDXGISwapChain* This,
    BOOL* pFullscreen,
    IDXGIOutput** ppTarget
) {
    HRESULT hr = S_OK;
    if (g_pOrigGetFullscreenState) {
        hr = g_pOrigGetFullscreenState(This, pFullscreen, ppTarget);
    }

    // Cưỡng bức trạng thái hiển thị là Windowed để Unreal Engine / Unity sử dụng đúng nhánh Windowed Mouse
    if (pFullscreen) {
        *pFullscreen = FALSE;
    }
    if (ppTarget) {
        *ppTarget = NULL;
    }

    return hr;
}

// 3. Hook XInputGetState để cô lập điều khiển tay cầm khi Quick Panel mở
DWORD WINAPI Hooked_XInputGetState(DWORD dwUserIndex, XINPUT_STATE* pState) {
    if (!g_pOrigXInputGetState) return ERROR_DEVICE_NOT_CONNECTED;

    DWORD res = g_pOrigXInputGetState(dwUserIndex, pState);
    if (res == ERROR_SUCCESS && pState && IsPanelActive()) {
        // Khi Quick Panel đang mở: Xóa sạch dữ liệu nút bấm và cần gạt để game không nhận diện
        pState->Gamepad.wButtons = 0;
        pState->Gamepad.bLeftTrigger = 0;
        pState->Gamepad.bRightTrigger = 0;
        pState->Gamepad.sThumbLX = 0;
        pState->Gamepad.sThumbLY = 0;
        pState->Gamepad.sThumbRX = 0;
        pState->Gamepad.sThumbRY = 0;
    }
    return res;
}

// Đăng ký hook cho instance SwapChain
void HookSwapChainInstance(IDXGISwapChain* pSwapChain) {
    if (!pSwapChain) return;
    void** vtbl = *(void***)pSwapChain;
    if (!vtbl) return;

    DXGI_SWAP_CHAIN_DESC scDesc;
    if (SUCCEEDED(pSwapChain->GetDesc(&scDesc))) {
        if (scDesc.BufferDesc.Width > 0) g_uBufferWidth.store(scDesc.BufferDesc.Width);
        if (scDesc.BufferDesc.Height > 0) g_uBufferHeight.store(scDesc.BufferDesc.Height);
        if (scDesc.OutputWindow) g_hGameWnd.store(scDesc.OutputWindow);
    }

    if (!g_bSwapChainHooked.exchange(true)) {
        MH_CreateHook(vtbl[10], (LPVOID)&Hooked_SetFullscreenState, (LPVOID*)&g_pOrigSetFullscreenState);
        MH_EnableHook(vtbl[10]);

        MH_CreateHook(vtbl[11], (LPVOID)&Hooked_GetFullscreenState, (LPVOID*)&g_pOrigGetFullscreenState);
        MH_EnableHook(vtbl[11]);

        MH_CreateHook(vtbl[13], (LPVOID)&Hooked_ResizeBuffers, (LPVOID*)&g_pOrigResizeBuffers);
        MH_EnableHook(vtbl[13]);

        MH_CreateHook(vtbl[14], (LPVOID)&Hooked_ResizeTarget, (LPVOID*)&g_pOrigResizeTarget);
        MH_EnableHook(vtbl[14]);

        LogDebug("[DXGI_HOOK] Đã móc thành công IDXGISwapChain VMT: SetFullscreenState=0x%p, GetFullscreenState=0x%p, ResizeBuffers=0x%p, ResizeTarget=0x%p\n",
            vtbl[10], vtbl[11], vtbl[13], vtbl[14]);
    }
}

// 4. Hook CreateSwapChain
HRESULT STDMETHODCALLTYPE Hooked_CreateSwapChain(
    IDXGIFactory* This,
    IUnknown* pDevice,
    DXGI_SWAP_CHAIN_DESC* pDesc,
    IDXGISwapChain** ppSwapChain
) {
    LogDebug("[DXGI_HOOK] IDXGIFactory::CreateSwapChain intercepted\n");

    if (pDesc) {
        if (!pDesc->Windowed) {
            g_bGameRequestedFullscreen = true;
            LogDebug("[DXGI_HOOK] Game yêu cầu tạo SwapChain ở chế độ Fullscreen -> Ép Windowed=TRUE\n");
        }
        pDesc->Windowed = TRUE;
        pDesc->Flags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
        if (pDesc->BufferDesc.Scaling == DXGI_MODE_SCALING_UNSPECIFIED || pDesc->BufferDesc.Scaling == DXGI_MODE_SCALING_CENTERED) {
            pDesc->BufferDesc.Scaling = DXGI_MODE_SCALING_STRETCHED;
        }
    }

    HRESULT hr = g_pOrigCreateSwapChain ? g_pOrigCreateSwapChain(This, pDevice, pDesc, ppSwapChain) : E_FAIL;

    if (SUCCEEDED(hr) && ppSwapChain && *ppSwapChain) {
        if (pDesc) {
            if (pDesc->BufferDesc.Width > 0) g_uBufferWidth.store(pDesc->BufferDesc.Width);
            if (pDesc->BufferDesc.Height > 0) g_uBufferHeight.store(pDesc->BufferDesc.Height);
            if (pDesc->OutputWindow) g_hGameWnd.store(pDesc->OutputWindow);
        }
        HookSwapChainInstance(*ppSwapChain);
        if (pDesc && pDesc->OutputWindow) {
            ForceBorderlessWindow(pDesc->OutputWindow);
        }
    }

    return hr;
}

// 5. Hook CreateSwapChainForHwnd
HRESULT STDMETHODCALLTYPE Hooked_CreateSwapChainForHwnd(
    IDXGIFactory2* This,
    IUnknown* pDevice,
    HWND hWnd,
    const DXGI_SWAP_CHAIN_DESC1* pDesc,
    const DXGI_SWAP_CHAIN_FULLSCREEN_DESC* pFullscreenDesc,
    IDXGIOutput* pRestrictToOutput,
    IDXGISwapChain1** ppSwapChain
) {
    LogDebug("[DXGI_HOOK] IDXGIFactory2::CreateSwapChainForHwnd intercepted for HWND=0x%p\n", hWnd);

    DXGI_SWAP_CHAIN_DESC1 descCopy;
    if (pDesc) {
        descCopy = *pDesc;
        descCopy.Flags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
        if (descCopy.Scaling == DXGI_SCALING_NONE) {
            descCopy.Scaling = DXGI_SCALING_ASPECT_RATIO_STRETCH;
            LogDebug("[DXGI_HOOK] Ép Scaling = DXGI_SCALING_ASPECT_RATIO_STRETCH để bung tràn màn hình\n");
        }
        pDesc = &descCopy;
    }

    DXGI_SWAP_CHAIN_FULLSCREEN_DESC fsDescCopy;
    if (pFullscreenDesc) {
        g_bGameRequestedFullscreen = true;
        fsDescCopy = *pFullscreenDesc;
        fsDescCopy.Windowed = TRUE;
        pFullscreenDesc = &fsDescCopy;
        LogDebug("[DXGI_HOOK] FullscreenDesc phát hiện -> Ép Windowed=TRUE\n");
    }

    HRESULT hr = g_pOrigCreateSwapChainForHwnd ?
        g_pOrigCreateSwapChainForHwnd(This, pDevice, hWnd, pDesc, pFullscreenDesc, pRestrictToOutput, ppSwapChain) : E_FAIL;

    if (SUCCEEDED(hr) && ppSwapChain && *ppSwapChain) {
        if (pDesc) {
            if (pDesc->Width > 0) g_uBufferWidth.store(pDesc->Width);
            if (pDesc->Height > 0) g_uBufferHeight.store(pDesc->Height);
        }
        if (hWnd) g_hGameWnd.store(hWnd);
        HookSwapChainInstance((IDXGISwapChain*)*ppSwapChain);
        if (hWnd) {
            ForceBorderlessWindow(hWnd);
        }
    }

    return hr;
}

// 6. Hook D3D11CreateDeviceAndSwapChain
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
    ID3D11DeviceContext** ppImmediateContext
) {
    LogDebug("[DXGI_HOOK] D3D11CreateDeviceAndSwapChain intercepted\n");

    DXGI_SWAP_CHAIN_DESC descCopy;
    if (pSwapChainDesc) {
        descCopy = *pSwapChainDesc;
        if (!descCopy.Windowed) {
            g_bGameRequestedFullscreen = true;
            LogDebug("[DXGI_HOOK] D3D11 SwapChain requested Fullscreen -> Ép Windowed=TRUE\n");
        }
        descCopy.Windowed = TRUE;
        descCopy.Flags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
        if (descCopy.BufferDesc.Scaling == DXGI_MODE_SCALING_UNSPECIFIED || descCopy.BufferDesc.Scaling == DXGI_MODE_SCALING_CENTERED) {
            descCopy.BufferDesc.Scaling = DXGI_MODE_SCALING_STRETCHED;
        }
        pSwapChainDesc = &descCopy;
    }

    HRESULT hr = g_pOrigD3D11CreateDeviceAndSwapChain ?
        g_pOrigD3D11CreateDeviceAndSwapChain(
            pAdapter, DriverType, Software, Flags, pFeatureLevels, FeatureLevels,
            SDKVersion, pSwapChainDesc, ppSwapChain, ppDevice, pFeatureLevel, ppImmediateContext
        ) : E_FAIL;

    if (SUCCEEDED(hr) && ppSwapChain && *ppSwapChain) {
        if (pSwapChainDesc) {
            if (pSwapChainDesc->BufferDesc.Width > 0) g_uBufferWidth.store(pSwapChainDesc->BufferDesc.Width);
            if (pSwapChainDesc->BufferDesc.Height > 0) g_uBufferHeight.store(pSwapChainDesc->BufferDesc.Height);
            if (pSwapChainDesc->OutputWindow) g_hGameWnd.store(pSwapChainDesc->OutputWindow);
        }
        HookSwapChainInstance(*ppSwapChain);
        if (pSwapChainDesc && pSwapChainDesc->OutputWindow) {
            ForceBorderlessWindow(pSwapChainDesc->OutputWindow);
        }
    }

    return hr;
}

// 7. Hook Factory Creators
HRESULT WINAPI Hooked_CreateDXGIFactory(REFIID riid, void** ppFactory) {
    HRESULT hr = g_pOrigCreateDXGIFactory ? g_pOrigCreateDXGIFactory(riid, ppFactory) : E_FAIL;
    if (SUCCEEDED(hr) && ppFactory && *ppFactory) {
        void** vtbl = *(void***)*ppFactory;
        if (vtbl && vtbl[10]) {
            MH_CreateHook(vtbl[10], (LPVOID)&Hooked_CreateSwapChain, (LPVOID*)&g_pOrigCreateSwapChain);
            MH_EnableHook(vtbl[10]);
        }
    }
    return hr;
}

HRESULT WINAPI Hooked_CreateDXGIFactory1(REFIID riid, void** ppFactory) {
    HRESULT hr = g_pOrigCreateDXGIFactory1 ? g_pOrigCreateDXGIFactory1(riid, ppFactory) : E_FAIL;
    if (SUCCEEDED(hr) && ppFactory && *ppFactory) {
        void** vtbl = *(void***)*ppFactory;
        if (vtbl && vtbl[10]) {
            MH_CreateHook(vtbl[10], (LPVOID)&Hooked_CreateSwapChain, (LPVOID*)&g_pOrigCreateSwapChain);
            MH_EnableHook(vtbl[10]);
        }
    }
    return hr;
}

HRESULT WINAPI Hooked_CreateDXGIFactory2(UINT Flags, REFIID riid, void** ppFactory) {
    HRESULT hr = g_pOrigCreateDXGIFactory2 ? g_pOrigCreateDXGIFactory2(Flags, riid, ppFactory) : E_FAIL;
    if (SUCCEEDED(hr) && ppFactory && *ppFactory) {
        void** vtbl = *(void***)*ppFactory;
        if (vtbl && vtbl[10]) {
            MH_CreateHook(vtbl[10], (LPVOID)&Hooked_CreateSwapChain, (LPVOID*)&g_pOrigCreateSwapChain);
            MH_EnableHook(vtbl[10]);
        }
        if (vtbl && vtbl[15]) {
            MH_CreateHook(vtbl[15], (LPVOID)&Hooked_CreateSwapChainForHwnd, (LPVOID*)&g_pOrigCreateSwapChainForHwnd);
            MH_EnableHook(vtbl[15]);
        }
    }
    return hr;
}

// ===== CHẨN ĐOÁN 1.11: Ghi log hình học / chuột / DPI ra file =====
// File: %LOCALAPPDATA%\WindowsHandheldTools\logs\dxgi_diag.log (ghi nối tiếp, mọi tiến trình game đều ghi được)
static void DiagWrite(const char* format, ...) {
    char msg[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(msg, sizeof(msg), format, args);
    va_end(args);

    char line[1200];
    SYSTEMTIME st;
    GetLocalTime(&st);
    int n = snprintf(line, sizeof(line), "%02d:%02d:%02d.%03d [PID %lu] %s\r\n",
        st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, GetCurrentProcessId(), msg);
    if (n <= 0) return;

    // Gộp chung thư mục dữ liệu ứng dụng: %LOCALAPPDATA%\WindowsHandheldTools\logs\dxgi_diag.log
    static char logPath[MAX_PATH] = {0};
    if (!logPath[0]) {
        char base[MAX_PATH] = {0};
        DWORD len = GetEnvironmentVariableA("LOCALAPPDATA", base, MAX_PATH);
        if (len == 0 || len >= MAX_PATH) strncpy_s(base, "C:\\Users\\Public", _TRUNCATE);
        char dir1[MAX_PATH], dir2[MAX_PATH];
        snprintf(dir1, sizeof(dir1), "%s\\WindowsHandheldTools", base);
        snprintf(dir2, sizeof(dir2), "%s\\logs", dir1);
        CreateDirectoryA(dir1, NULL);
        CreateDirectoryA(dir2, NULL);
        snprintf(logPath, sizeof(logPath), "%s\\dxgi_diag.log", dir2);
    }
    HANDLE hFile = CreateFileA(logPath, FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteFile(hFile, line, (DWORD)n, &written, NULL);
        CloseHandle(hFile);
    }
    OutputDebugStringA(line);
}

// Chụp ảnh trạng thái và so sánh: BackBuffer vs ClientRect vs WindowRect vs DWM Frame vs DPI vs ClipCursor vs CursorPos
static void DiagSnapshot(const char* tag, bool force, char* lastSnapshot, size_t lastSize) {
    HWND hWnd = g_hGameWnd.load();
    if (!hWnd || !IsWindow(hWnd)) {
        hWnd = GetForegroundWindow();
        DWORD pid = 0;
        GetWindowThreadProcessId(hWnd, &pid);
        if (pid != GetCurrentProcessId()) hWnd = nullptr;
    }
    if (!hWnd) return;

    RECT cr = {0}, wr = {0}, clip = {0}, dwmR = {0};
    GetClientRect(hWnd, &cr);
    GetWindowRect(hWnd, &wr);
    BOOL hasClip = GetClipCursor(&clip);
    POINT pt = {0};
    GetCursorPos(&pt);
    POINT ptClient = pt;
    ScreenToClient(hWnd, &ptClient);

    int dwmOk = -1;
    HMODULE hDwm = LoadLibraryW(L"dwmapi.dll");
    if (hDwm) {
        typedef HRESULT (WINAPI* PFN_DwmGetWindowAttribute)(HWND, DWORD, PVOID, DWORD);
        auto pfn = (PFN_DwmGetWindowAttribute)GetProcAddress(hDwm, "DwmGetWindowAttribute");
        if (pfn) dwmOk = SUCCEEDED(pfn(hWnd, 9 /*DWMWA_EXTENDED_FRAME_BOUNDS*/, &dwmR, sizeof(dwmR))) ? 1 : 0;
    }

    UINT winDpi = 0, sysDpi = 0;
    int awareness = -1;
    HMODULE hUser = GetModuleHandleW(L"user32.dll");
    if (hUser) {
        typedef UINT (WINAPI* PFN_GetDpiForWindow)(HWND);
        typedef UINT (WINAPI* PFN_GetDpiForSystem)(void);
        typedef void* (WINAPI* PFN_GetThreadDpiAwarenessContext)(void);
        typedef int (WINAPI* PFN_GetAwarenessFromDpiAwarenessContext)(void*);
        auto pGetDpiWnd = (PFN_GetDpiForWindow)GetProcAddress(hUser, "GetDpiForWindow");
        auto pGetDpiSys = (PFN_GetDpiForSystem)GetProcAddress(hUser, "GetDpiForSystem");
        auto pGetCtx = (PFN_GetThreadDpiAwarenessContext)GetProcAddress(hUser, "GetThreadDpiAwarenessContext");
        auto pGetAw = (PFN_GetAwarenessFromDpiAwarenessContext)GetProcAddress(hUser, "GetAwarenessFromDpiAwarenessContext");
        if (pGetDpiWnd) winDpi = pGetDpiWnd(hWnd);
        if (pGetDpiSys) sysDpi = pGetDpiSys();
        if (pGetCtx && pGetAw) awareness = pGetAw(pGetCtx()); // 0=Unaware, 1=System, 2=PerMonitor
    }

    HMONITOR hMon = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = { sizeof(mi) };
    GetMonitorInfo(hMon, &mi);

    UINT bw = g_uBufferWidth.load(), bh = g_uBufferHeight.load();
    int cw = cr.right - cr.left, ch = cr.bottom - cr.top;
    int mw = mi.rcMonitor.right - mi.rcMonitor.left, mh = mi.rcMonitor.bottom - mi.rcMonitor.top;
    double sx = (cw > 0 && bw > 0) ? (double)cw / bw : 0.0;
    double sy = (ch > 0 && bh > 0) ? (double)ch / bh : 0.0;

    char snap[900];
    snprintf(snap, sizeof(snap),
        "HWND=0x%p Buffer=%ux%u Client=%dx%d Window=(%ld,%ld,%ld,%ld) DwmFrame[%d]=(%ld,%ld,%ld,%ld) Monitor=%dx%d@(%ld,%ld) "
        "Scale(Client/Buffer)=%.3fx%.3f DPI(win=%u,sys=%u,awareness=%d,setResult=%d) Clip[%d]=(%ld,%ld,%ld,%ld) "
        "Cursor=(%ld,%ld) CursorClient=(%ld,%ld) Fg=%d PanelActive=%d",
        hWnd, bw, bh, cw, ch, wr.left, wr.top, wr.right, wr.bottom,
        dwmOk, dwmR.left, dwmR.top, dwmR.right, dwmR.bottom, mw, mh, mi.rcMonitor.left, mi.rcMonitor.top,
        sx, sy, winDpi, sysDpi, awareness, g_dpiSetResult,
        hasClip, clip.left, clip.top, clip.right, clip.bottom,
        pt.x, pt.y, ptClient.x, ptClient.y,
        (GetForegroundWindow() == hWnd) ? 1 : 0, IsPanelActive() ? 1 : 0);

    // So sánh bỏ phần vị trí chuột (luôn đổi) để chỉ log khi hình học/trạng thái đổi
    char key[900];
    strncpy_s(key, sizeof(key), snap, _TRUNCATE);
    char* cur = strstr(key, " Cursor=");
    if (cur) *cur = '\0';

    if (force || strcmp(key, lastSnapshot) != 0) {
        strncpy_s(lastSnapshot, lastSize, key, _TRUNCATE);
        DiagWrite("[%s] %s", tag, snap);
        if (sx > 0 && sy > 0 && (fabs(sx - 1.0) > 0.01 || fabs(sy - 1.0) > 0.01)) {
            DiagWrite("[%s] !!! LỆCH TỈ LỆ: Client/Buffer = %.3f x %.3f -> chuột sẽ lệch nếu engine dùng tọa độ buffer", tag, sx, sy);
        }
        if (hasClip && (clip.right - clip.left) != mw && (clip.right - clip.left) != cw) {
            DiagWrite("[%s] !!! ClipCursor khác kích thước Client/Monitor: %ldx%ld", tag, clip.right - clip.left, clip.bottom - clip.top);
        }
    }
}

static DWORD WINAPI DiagThreadProc(LPVOID) {
    DiagWrite("===== DXGI Hook Diagnostic thread started (exe pid=%lu) =====", GetCurrentProcessId());
    char last[900] = {0};
    bool lastPanel = false;
    int tick = 0;
    for (; g_bInitialized.load();) {
        bool panel = IsPanelActive();
        if (panel != lastPanel) {
            lastPanel = panel;
            // Chụp ngay tại thời điểm chuyển trạng thái, và thêm 1 mẫu sau 300ms để thấy game phản ứng
            DiagSnapshot(panel ? "PANEL_OPEN" : "PANEL_CLOSE", true, last, sizeof(last));
            Sleep(300);
            DiagSnapshot(panel ? "PANEL_OPEN+300ms" : "PANEL_CLOSE+300ms", true, last, sizeof(last));
            Sleep(1200);
            DiagSnapshot(panel ? "PANEL_OPEN+1.5s" : "PANEL_CLOSE+1.5s", true, last, sizeof(last));
            continue;
        }
        // Mỗi 1s kiểm tra thay đổi; mỗi 10s ghi một mẫu định kỳ để đối chiếu vị trí chuột
        DiagSnapshot((tick % 10 == 0) ? "PERIODIC" : "CHANGE", (tick % 10 == 0), last, sizeof(last));
        tick++;
        Sleep(1000);
    }
    return 0;
}

// Khởi tạo Bootstrap bằng Dummy Window
bool InitDxgiHook() {
    if (g_bInitialized.exchange(true)) return true;

    // Kích hoạt nhận thức Per-Monitor V2 DPI cho tiến trình Game
    InitDpiAwareness();

    // Luồng chẩn đoán 1.11 (ghi log hình học/chuột ra %LOCALAPPDATA%\WindowsHandheldTools\logs\dxgi_diag.log)
    HANDLE hDiag = CreateThread(NULL, 0, DiagThreadProc, NULL, 0, NULL);
    if (hDiag) CloseHandle(hDiag);

    if (MH_Initialize() != MH_OK) {
        LogDebug("[DXGI_HOOK] MH_Initialize failed!\n");
        return false;
    }

    // 1. Tạo Dummy Window để lấy con trỏ VMT tức thời
    WNDCLASSA wc = { 0 };
    wc.lpfnWndProc = DefWindowProcA;
    wc.hInstance = GetModuleHandle(NULL);
    wc.lpszClassName = "DXGI_Dummy_Hook_Class";
    RegisterClassA(&wc);

    HWND hDummyWnd = CreateWindowExA(
        0, wc.lpszClassName, "DXGI_Dummy_Window", WS_OVERLAPPEDWINDOW,
        0, 0, 100, 100, NULL, NULL, wc.hInstance, NULL
    );

    if (hDummyWnd) {
        D3D_FEATURE_LEVEL featureLevel;
        ID3D11Device* pDummyDevice = NULL;
        ID3D11DeviceContext* pDummyContext = NULL;
        IDXGISwapChain* pDummySwapChain = NULL;

        DXGI_SWAP_CHAIN_DESC scDesc = { 0 };
        scDesc.BufferCount = 1;
        scDesc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
        scDesc.BufferDesc.Width = 100;
        scDesc.BufferDesc.Height = 100;
        scDesc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        scDesc.OutputWindow = hDummyWnd;
        scDesc.SampleDesc.Count = 1;
        scDesc.Windowed = TRUE;

        HRESULT hr = D3D11CreateDeviceAndSwapChain(
            NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
            D3D11_SDK_VERSION, &scDesc, &pDummySwapChain, &pDummyDevice,
            &featureLevel, &pDummyContext
        );

        if (FAILED(hr)) {
            hr = D3D11CreateDeviceAndSwapChain(
                NULL, D3D_DRIVER_TYPE_WARP, NULL, 0, NULL, 0,
                D3D11_SDK_VERSION, &scDesc, &pDummySwapChain, &pDummyDevice,
                &featureLevel, &pDummyContext
            );
        }

        if (SUCCEEDED(hr) && pDummySwapChain) {
            HookSwapChainInstance(pDummySwapChain);

            IDXGIFactory* pFactory = NULL;
            if (SUCCEEDED(pDummySwapChain->GetParent(__uuidof(IDXGIFactory), (void**)&pFactory)) && pFactory) {
                void** factoryVtbl = *(void***)pFactory;
                MH_CreateHook(factoryVtbl[10], (LPVOID)&Hooked_CreateSwapChain, (LPVOID*)&g_pOrigCreateSwapChain);
                MH_EnableHook(factoryVtbl[10]);

                IDXGIFactory2* pFactory2 = NULL;
                if (SUCCEEDED(pFactory->QueryInterface(__uuidof(IDXGIFactory2), (void**)&pFactory2)) && pFactory2) {
                    void** factory2Vtbl = *(void***)pFactory2;
                    MH_CreateHook(factory2Vtbl[15], (LPVOID)&Hooked_CreateSwapChainForHwnd, (LPVOID*)&g_pOrigCreateSwapChainForHwnd);
                    MH_EnableHook(factory2Vtbl[15]);
                    pFactory2->Release();
                }
                pFactory->Release();
            }

            pDummySwapChain->Release();
        }

        if (pDummyContext) pDummyContext->Release();
        if (pDummyDevice) pDummyDevice->Release();
        DestroyWindow(hDummyWnd);
    }
    UnregisterClassA(wc.lpszClassName, wc.hInstance);

    // 2. Móc chặn các hàm Export từ dxgi.dll và d3d11.dll
    HMODULE hDxgi = GetModuleHandleW(L"dxgi.dll");
    if (hDxgi) {
        void* pCreateFactory = (void*)GetProcAddress(hDxgi, "CreateDXGIFactory");
        if (pCreateFactory) {
            MH_CreateHook(pCreateFactory, (LPVOID)&Hooked_CreateDXGIFactory, (LPVOID*)&g_pOrigCreateDXGIFactory);
        }
        void* pCreateFactory1 = (void*)GetProcAddress(hDxgi, "CreateDXGIFactory1");
        if (pCreateFactory1) {
            MH_CreateHook(pCreateFactory1, (LPVOID)&Hooked_CreateDXGIFactory1, (LPVOID*)&g_pOrigCreateDXGIFactory1);
        }
        void* pCreateFactory2 = (void*)GetProcAddress(hDxgi, "CreateDXGIFactory2");
        if (pCreateFactory2) {
            MH_CreateHook(pCreateFactory2, (LPVOID)&Hooked_CreateDXGIFactory2, (LPVOID*)&g_pOrigCreateDXGIFactory2);
        }
    }

    HMODULE hD3D11 = GetModuleHandleW(L"d3d11.dll");
    if (hD3D11) {
        void* pD3D11Create = (void*)GetProcAddress(hD3D11, "D3D11CreateDeviceAndSwapChain");
        if (pD3D11Create) {
            MH_CreateHook(pD3D11Create, (LPVOID)&Hooked_D3D11CreateDeviceAndSwapChain, (LPVOID*)&g_pOrigD3D11CreateDeviceAndSwapChain);
        }
    }

    // 3. Móc chặn XInputGetState để cô lập điều khiển tay cầm
    const wchar_t* xinputDlls[] = { L"xinput1_4.dll", L"xinput1_3.dll", L"xinput9_1_0.dll" };
    for (const wchar_t* dllName : xinputDlls) {
        HMODULE hXInput = LoadLibraryW(dllName);
        if (hXInput) {
            void* pGetState = (void*)GetProcAddress(hXInput, "XInputGetState");
            if (pGetState && !g_pOrigXInputGetState) {
                if (MH_CreateHook(pGetState, (LPVOID)&Hooked_XInputGetState, (LPVOID*)&g_pOrigXInputGetState) == MH_OK) {
                    MH_EnableHook(pGetState);
                    g_bXInputHooked = true;
                    LogDebug("[DXGI_HOOK] Đã móc thành công XInputGetState từ %ls\n", dllName);
                }
            }
        }
    }

    MH_EnableHook(MH_ALL_HOOKS);
    LogDebug("[DXGI_HOOK] InitDxgiHook hoàn tất thành công.\n");
    return true;
}

// Gỡ bỏ hooks
void ShutdownDxgiHook() {
    if (!g_bInitialized.exchange(false)) return;
    MH_DisableHook(MH_ALL_HOOKS);
    MH_Uninitialize();
    if (g_hPanelActiveEvent) {
        CloseHandle(g_hPanelActiveEvent);
        g_hPanelActiveEvent = nullptr;
    }
    LogDebug("[DXGI_HOOK] ShutdownDxgiHook hoàn tất.\n");
}

DWORD GetHookStatus() {
    DWORD status = 0;
    if (g_bInitialized.load()) status |= 0x1;
    if (g_bGameRequestedFullscreen.load()) status |= 0x2;
    if (g_bSwapChainHooked.load()) status |= 0x4;
    if (g_bXInputHooked.load()) status |= 0x8;
    return status;
}
