#include "dxgi_hook.h"
#include <cstdio>
#include <cmath>
#include <atomic>
#include <windowsx.h>
#include <intrin.h>

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

static std::atomic<HWND> g_hHookedGameWnd(nullptr);
static WNDPROC g_pOrigGameWndProc = nullptr;

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

typedef HRESULT (STDMETHODCALLTYPE* PFN_Present)(IDXGISwapChain* This, UINT SyncInterval, UINT PresentFlags);
typedef HRESULT (STDMETHODCALLTYPE* PFN_Present1)(IDXGISwapChain1* This, UINT SyncInterval, UINT PresentFlags, const DXGI_PRESENT_PARAMETERS* pPresentParameters);

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
static PFN_Present g_pOrigPresent = nullptr;
static PFN_Present1 g_pOrigPresent1 = nullptr;
static PFN_XInputGetState g_pOrigXInputGetState = nullptr;
static HANDLE g_hPanelActiveEvent = nullptr;

// Cờ tắt an toàn: khi tool thoát, toàn bộ hook chuyển sang chế độ "pass-through" (không sửa hành vi
// của game nữa) thay vì tháo MinHook — MH_DisableHook có thể deadlock nếu luồng render đang chạy
// bên trong một detour tại thời điểm đó.
static std::atomic<bool> g_bShutdownRequested(false);
static HANDLE g_hShutdownEvent = nullptr;

// ===== CHẨN ĐOÁN 1.12: Nhịp khung hình (frame cadence) & kết quả Present =====
// Chỉ đo và ghi log, tuyệt đối không thay đổi giá trị trả về hay hành vi của hook.
static void DiagWrite(const char* format, ...);  // Định nghĩa ở phần chẩn đoán bên dưới

static std::atomic<unsigned long long> g_qpcFrequency(0);
static std::atomic<unsigned> g_presentCount(0);      // số lần engine gọi Present trong 1 giây
static std::atomic<unsigned> g_frameCount(0);        // số khoảng thời gian giữa 2 lần Present
static std::atomic<long long> g_frameQpcSum(0);      // tổng thời gian các khoảng (QPC ticks)
static std::atomic<long long> g_maxFrameQpc(0);      // khoảng lớn nhất trong 1 giây
static std::atomic<long long> g_lastPresentQpc(0);
static std::atomic<unsigned> g_presentOk(0);
static std::atomic<unsigned> g_presentOccluded(0);
static std::atomic<unsigned> g_presentFailed(0);
static std::atomic<long> g_lastPresentHr(0);
static std::atomic<unsigned> g_lastSyncInterval(0);
static std::atomic<unsigned> g_lastPresentFlags(0);
static std::atomic<unsigned> g_swapChainFlags(0);
static std::atomic<unsigned> g_swapChainBufferCount(0);

// ===== Chống "khoá nhịp" 60 ↔ 30 fps của cửa sổ Borderless =====
// Với swapchain flip 2 buffer, Present(syncInterval=0) vẫn chờ nhịp composition 60Hz của DWM.
// Khi frame time chỉ hơn 16,67ms một chút, mọi frame bị đẩy sang vblank kế tiếp -> tụt đúng 30 fps.
// Bật ALLOW_TEARING để Present không chờ vblank, game chạy đúng nhịp thật của nó (vd 52-58 fps).
static std::atomic<bool> g_bTearingSwapChain(false);
static std::atomic<bool> g_bTearingUnsupported(false);

static void RecordPresentTiming(HRESULT hr, UINT syncInterval, UINT flags) {
    if (g_qpcFrequency.load() == 0) {
        LARGE_INTEGER f;
        if (QueryPerformanceFrequency(&f)) {
            g_qpcFrequency.store((unsigned long long)f.QuadPart);
        }
    }

    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);

    long long prev = g_lastPresentQpc.exchange(now.QuadPart);
    if (prev > 0 && now.QuadPart > prev) {
        long long delta = now.QuadPart - prev;
        g_frameQpcSum.fetch_add(delta);
        g_frameCount.fetch_add(1);

        long long curMax = g_maxFrameQpc.load();
        while (delta > curMax && !g_maxFrameQpc.compare_exchange_weak(curMax, delta)) {
        }
    }

    g_presentCount.fetch_add(1);
    if (hr == S_OK) {
        g_presentOk.fetch_add(1);
    } else if (hr == DXGI_STATUS_OCCLUDED) {
        g_presentOccluded.fetch_add(1);
    } else {
        g_presentFailed.fetch_add(1);
    }
    g_lastPresentHr.store((long)hr);
    g_lastSyncInterval.store(syncInterval);
    g_lastPresentFlags.store(flags);
}

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

// Tool đã thoát hẳn hay chưa (Named Event do WindowManager bật lúc cleanup)
static bool IsShutdownRequested() {
    if (g_bShutdownRequested.load()) return true;
    if (!g_hShutdownEvent) {
        g_hShutdownEvent = OpenEventW(SYNCHRONIZE, FALSE, L"Global\\HandheldTool_Shutdown");
        if (!g_hShutdownEvent) {
            g_hShutdownEvent = OpenEventW(SYNCHRONIZE, FALSE, L"HandheldTool_Shutdown");
        }
    }
    if (g_hShutdownEvent && WaitForSingleObject(g_hShutdownEvent, 0) == WAIT_OBJECT_0) {
        g_bShutdownRequested.store(true);
        return true;
    }
    return false;
}

// Bản nhẹ dùng trong các đường nóng (mỗi thông điệp chuột / mỗi khung hình): chỉ đọc cờ đã cache.
static inline bool IsHookInert() {
    return g_bShutdownRequested.load(std::memory_order_relaxed);
}

// ===== Chẩn đoán 1.13: khớp display mode với độ phân giải render (tuỳ chọn, mặc định TẮT) =====
// Khi buffer swapchain nhỏ hơn cửa sổ, DWM phải chạy một pass scale mỗi frame (rất tốn với APU yếu).
// Hạ mode màn hình xuống đúng độ phân giải render thì cửa sổ game 1:1 với buffer, phần phóng lên
// tấm nền do scaler phần cứng (hoặc AMD RSR) đảm nhận -> không còn pass scale trong composition.
// App bật tính năng này bằng cách tạo Named Event HandheldTool_MatchDisplayMode.
static std::atomic<bool> g_bMatchDisplayMode(false);
static HANDLE g_hMatchDisplayModeEvent = nullptr;
static bool g_bDisplayModeChanged = false;
static bool g_bOriginalDisplayModeSaved = false;
static DEVMODEW g_originalDisplayMode = {};

static void RefreshMatchDisplayModeFlag() {
    if (!g_hMatchDisplayModeEvent) {
        g_hMatchDisplayModeEvent = OpenEventW(SYNCHRONIZE, FALSE, L"Global\\HandheldTool_MatchDisplayMode");
        if (!g_hMatchDisplayModeEvent) {
            g_hMatchDisplayModeEvent = OpenEventW(SYNCHRONIZE, FALSE, L"HandheldTool_MatchDisplayMode");
        }
    }
    if (g_hMatchDisplayModeEvent) {
        g_bMatchDisplayMode.store(WaitForSingleObject(g_hMatchDisplayModeEvent, 0) == WAIT_OBJECT_0);
    }
}

static bool IsMatchDisplayModeEnabled() {
    if (!g_bMatchDisplayMode.load()) {
        RefreshMatchDisplayModeFlag();
    }
    return g_bMatchDisplayMode.load();
}

static void SaveOriginalDisplayMode() {
    if (g_bOriginalDisplayModeSaved) return;
    ZeroMemory(&g_originalDisplayMode, sizeof(g_originalDisplayMode));
    g_originalDisplayMode.dmSize = sizeof(g_originalDisplayMode);
    // Ưu tiên mode trong registry (mode desktop người dùng đã chọn): nếu lần chạy trước bị crash
    // giữa chừng, mode hiện tại có thể đang là 720p và không còn là mode gốc nữa.
    if (EnumDisplaySettingsW(NULL, ENUM_REGISTRY_SETTINGS, &g_originalDisplayMode)) {
        g_bOriginalDisplayModeSaved = true;
        return;
    }
    if (EnumDisplaySettingsW(NULL, ENUM_CURRENT_SETTINGS, &g_originalDisplayMode)) {
        g_bOriginalDisplayModeSaved = true;
    } else {
        g_originalDisplayMode.dmSize = 0;
    }
}

static void RestoreDisplayMode() {
    if (!g_bDisplayModeChanged) return;
    g_bDisplayModeChanged = false;

    LONG res = DISP_CHANGE_BADMODE;
    if (g_bOriginalDisplayModeSaved) {
        DEVMODEW dm = g_originalDisplayMode;
        dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY;
        res = ChangeDisplaySettingsExW(NULL, &dm, NULL, 0, NULL);
    }
    if (res != DISP_CHANGE_SUCCESSFUL) {
        res = ChangeDisplaySettingsExW(NULL, NULL, NULL, 0, NULL);
    }
    DiagWrite("[DISPMODE] Khôi phục display mode gốc (code=%ld)", res);
}

static void MatchDisplayModeToBuffer(HWND hWnd, UINT bufW, UINT bufH) {
    if (IsHookInert()) return;
    if (!hWnd || !IsWindow(hWnd) || bufW < 320 || bufH < 240) return;
    if (!IsMatchDisplayModeEnabled()) return;

    MONITORINFO mi = { sizeof(mi) };
    HMONITOR hMon = MonitorFromWindow(hWnd, MONITOR_DEFAULTTONEAREST);
    if (!hMon || !GetMonitorInfoW(hMon, &mi)) return;

    UINT monW = (UINT)(mi.rcMonitor.right - mi.rcMonitor.left);
    UINT monH = (UINT)(mi.rcMonitor.bottom - mi.rcMonitor.top);
    if (bufW >= monW || bufH >= monH) return;  // game đã render bằng/hơn native, không cần hạ mode

    DEVMODEW cur = { sizeof(cur) };
    if (!EnumDisplaySettingsW(NULL, ENUM_CURRENT_SETTINGS, &cur)) return;
    if (cur.dmPelsWidth == bufW && cur.dmPelsHeight == bufH) {
        // Mode đã khớp sẵn (hoặc còn sót từ lần chạy trước): vẫn đánh dấu để lúc game đóng
        // khôi phục về mode desktop gốc trong registry.
        SaveOriginalDisplayMode();
        g_bDisplayModeChanged = true;
        return;
    }

    // Game vừa đổi độ phân giải render -> phải khớp lại mode, nếu không cửa sổ và buffer lệch nhau
    // (Scale > 1.0) và DWM phải chạy pass scale mỗi frame -> tụt fps.
    SaveOriginalDisplayMode();

    DEVMODEW dm = { sizeof(dm) };
    dm.dmSize = sizeof(dm);
    dm.dmPelsWidth = bufW;
    dm.dmPelsHeight = bufH;
    dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
    UINT hz = g_bOriginalDisplayModeSaved ? g_originalDisplayMode.dmDisplayFrequency : 0;
    if (hz > 1) {
        dm.dmDisplayFrequency = hz;
        dm.dmFields |= DM_DISPLAYFREQUENCY;
    }

    LONG res = ChangeDisplaySettingsExW(NULL, &dm, NULL, CDS_FULLSCREEN, NULL);
    if (res != DISP_CHANGE_SUCCESSFUL) {
        dm.dmFields = DM_PELSWIDTH | DM_PELSHEIGHT;
        res = ChangeDisplaySettingsExW(NULL, &dm, NULL, CDS_FULLSCREEN, NULL);
    }

    if (res == DISP_CHANGE_SUCCESSFUL) {
        g_bDisplayModeChanged = true;
        DiagWrite("[DISPMODE] Hạ mode màn hình xuống %ux%u@%uHz để buffer 1:1 (scaler phần cứng phóng lên panel)",
            bufW, bufH, hz);
    } else {
        DiagWrite("[DISPMODE] Không đổi được mode sang %ux%u (code=%ld) -> giữ mode hiện tại", bufW, bufH, res);
    }
}

// Con trỏ hàm gốc của API vị trí chuột màn hình và hàng đợi thông điệp
typedef BOOL (WINAPI* PFN_GetCursorPos)(LPPOINT lpPoint);
typedef BOOL (WINAPI* PFN_SetCursorPos)(int X, int Y);
typedef DWORD (WINAPI* PFN_GetMessagePos)(VOID);
typedef BOOL (WINAPI* PFN_PeekMessageW)(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg);
typedef BOOL (WINAPI* PFN_GetMessageW)(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax);

static PFN_GetCursorPos g_pOrigGetCursorPos = nullptr;
static PFN_SetCursorPos g_pOrigSetCursorPos = nullptr;
static PFN_GetMessagePos g_pOrigGetMessagePos = nullptr;
static PFN_PeekMessageW g_pOrigPeekMessageW = nullptr;
static PFN_GetMessageW g_pOrigGetMessageW = nullptr;

// Lấy hệ số Client/Buffer và gốc Client của cửa sổ game. Trả về false nếu không cần ánh xạ (tỉ lệ 1:1)
static bool GetCursorMappingParams(double& ratioX, double& ratioY, POINT& origin) {
    if (IsHookInert()) return false;
    HWND hGame = g_hGameWnd.load();
    UINT bufW = g_uBufferWidth.load(), bufH = g_uBufferHeight.load();
    if (!hGame || bufW == 0 || bufH == 0 || !IsWindow(hGame)) return false;

    RECT rcClient;
    if (!GetClientRect(hGame, &rcClient)) return false;
    int clientW = rcClient.right - rcClient.left;
    int clientH = rcClient.bottom - rcClient.top;
    if (clientW <= 0 || clientH <= 0) return false;
    if (clientW == (int)bufW && clientH == (int)bufH) return false;

    origin = { 0, 0 };
    if (!ClientToScreen(hGame, &origin)) return false;
    ratioX = (double)bufW / (double)clientW;
    ratioY = (double)bufH / (double)clientH;
    return true;
}

// Vị trí chuột vật lý thực (không ánh xạ), dùng cho chẩn đoán
static BOOL RawGetCursorPos(LPPOINT lpPoint) {
    return g_pOrigGetCursorPos ? g_pOrigGetCursorPos(lpPoint) : GetCursorPos(lpPoint);
}

// Hook GetCursorPos: Game nhìn thấy chuột theo không gian Buffer (vd 1760x990) thay vì Client (1920x1080)
BOOL WINAPI Hooked_GetCursorPos(LPPOINT lpPoint) {
    if (!g_pOrigGetCursorPos) return FALSE;
    BOOL res = g_pOrigGetCursorPos(lpPoint);
    if (res && lpPoint) {
        double rx, ry; POINT o;
        if (GetCursorMappingParams(rx, ry, o)) {
            lpPoint->x = o.x + (LONG)round((double)(lpPoint->x - o.x) * rx);
            lpPoint->y = o.y + (LONG)round((double)(lpPoint->y - o.y) * ry);
        }
    }
    return res;
}

// Hook SetCursorPos: Phép ngược lại, đưa tọa độ không gian Buffer của game về tọa độ vật lý
BOOL WINAPI Hooked_SetCursorPos(int X, int Y) {
    if (!g_pOrigSetCursorPos) return FALSE;
    double rx, ry; POINT o;
    if (GetCursorMappingParams(rx, ry, o)) {
        X = o.x + (int)round((double)(X - o.x) / rx);
        Y = o.y + (int)round((double)(Y - o.y) / ry);
    }
    return g_pOrigSetCursorPos(X, Y);
}

// Hook GetMessagePos: Đảm bảo bộ đệm vị trí chuột của Windows khớp chuẩn xác với GetCursorPos
DWORD WINAPI Hooked_GetMessagePos(VOID) {
    if (!g_pOrigGetMessagePos) return GetMessagePos();
    DWORD pos = g_pOrigGetMessagePos();
    double rx, ry; POINT o;
    if (GetCursorMappingParams(rx, ry, o)) {
        short rawX = (short)LOWORD(pos);
        short rawY = (short)HIWORD(pos);
        short scaledX = (short)(o.x + (LONG)round((double)(rawX - o.x) * rx));
        short scaledY = (short)(o.y + (LONG)round((double)(rawY - o.y) * ry));
        return MAKELPARAM(scaledX, scaledY);
    }
    return pos;
}

// Ánh xạ tọa độ chuột client trong lParam của các thông điệp chuột (WM_MOUSEMOVE, WM_LBUTTONDOWN...)
static void ScaleMouseMessageLParam(LPMSG lpMsg) {
    if (!lpMsg || !lpMsg->hwnd) return;
    HWND hGame = g_hGameWnd.load();
    if (!hGame || lpMsg->hwnd != hGame) return;

    UINT msg = lpMsg->message;
    if (msg == WM_MOUSEMOVE || msg == WM_LBUTTONDOWN || msg == WM_LBUTTONUP || msg == WM_LBUTTONDBLCLK ||
        msg == WM_RBUTTONDOWN || msg == WM_RBUTTONUP || msg == WM_RBUTTONDBLCLK ||
        msg == WM_MBUTTONDOWN || msg == WM_MBUTTONUP || msg == WM_MBUTTONDBLCLK) {
        double rx, ry; POINT o;
        if (GetCursorMappingParams(rx, ry, o)) {
            short rawX = (short)LOWORD(lpMsg->lParam);
            short rawY = (short)HIWORD(lpMsg->lParam);
            short scaledX = (short)round((double)rawX * rx);
            short scaledY = (short)round((double)rawY * ry);
            lpMsg->lParam = MAKELPARAM(scaledX, scaledY);
        }
    }
}

BOOL WINAPI Hooked_PeekMessageW(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg) {
    if (!g_pOrigPeekMessageW) return FALSE;
    BOOL res = g_pOrigPeekMessageW(lpMsg, hWnd, wMsgFilterMin, wMsgFilterMax, wRemoveMsg);
    if (res && lpMsg) {
        ScaleMouseMessageLParam(lpMsg);
    }
    return res;
}

BOOL WINAPI Hooked_GetMessageW(LPMSG lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax) {
    if (!g_pOrigGetMessageW) return -1;
    BOOL res = g_pOrigGetMessageW(lpMsg, hWnd, wMsgFilterMin, wMsgFilterMax);
    if (res > 0 && lpMsg) {
        ScaleMouseMessageLParam(lpMsg);
    }
    return res;
}

void ForceBorderlessWindow(HWND hWnd);

// ===== CHẨN ĐOÁN 1.12: Ghi lại đúng những thông điệp kích hoạt/tiêu điểm engine thật sự nhận =====
static const char* DiagMsgName(UINT m) {
    switch (m) {
    case WM_ACTIVATE: return "WM_ACTIVATE";
    case WM_ACTIVATEAPP: return "WM_ACTIVATEAPP";
    case WM_NCACTIVATE: return "WM_NCACTIVATE";
    case WM_SETFOCUS: return "WM_SETFOCUS";
    case WM_KILLFOCUS: return "WM_KILLFOCUS";
    case WM_CANCELMODE: return "WM_CANCELMODE";
    case WM_SHOWWINDOW: return "WM_SHOWWINDOW";
    case WM_ENABLE: return "WM_ENABLE";
    case WM_SIZE: return "WM_SIZE";
    case WM_DISPLAYCHANGE: return "WM_DISPLAYCHANGE";
    case WM_WINDOWPOSCHANGED: return "WM_WINDOWPOSCHANGED";
    case WM_STYLECHANGING: return "WM_STYLECHANGING";
    case WM_STYLECHANGED: return "WM_STYLECHANGED";
    case WM_SYSCOMMAND: return "WM_SYSCOMMAND";
    case WM_ENTERMENULOOP: return "WM_ENTERMENULOOP";
    case WM_EXITMENULOOP: return "WM_EXITMENULOOP";
    case WM_SYSKEYDOWN: return "WM_SYSKEYDOWN";
    case WM_SYSKEYUP: return "WM_SYSKEYUP";
    case WM_SYSCHAR: return "WM_SYSCHAR";
    case WM_SETTINGCHANGE: return "WM_SETTINGCHANGE";
    case WM_NCLBUTTONDOWN: return "WM_NCLBUTTONDOWN";
    default: return nullptr;
    }
}

static void DiagLogGameMessage(const char* where, HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    const char* name = DiagMsgName(uMsg);
    if (!name) return;

    // Giới hạn 60 dòng/giây: WM_SIZE và WM_WINDOWPOSCHANGED có thể bắn liên tục khi đổi mode
    static DWORD s_budgetTick = 0;
    static LONG s_budget = 0;
    DWORD now = GetTickCount();
    if (now - s_budgetTick >= 1000) {
        s_budgetTick = now;
        s_budget = 60;
    }
    if (s_budget-- <= 0) return;

    HWND fg = GetForegroundWindow();
    DiagWrite("[MSG] %s uMsg=0x%04X (%s) wParam=0x%llX lParam=0x%llX PanelActive=%d FgMatch=%d FgHwnd=0x%p",
        where, uMsg, name, (unsigned long long)wParam, (unsigned long long)lParam,
        IsPanelActive() ? 1 : 0, (fg == hWnd) ? 1 : 0, (void*)fg);
}

static LRESULT CALLBACK GameSubclassWndProc(HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    if (IsHookInert()) {
        return g_pOrigGameWndProc ? CallWindowProcW(g_pOrigGameWndProc, hWnd, uMsg, wParam, lParam)
                                  : DefWindowProcW(hWnd, uMsg, wParam, lParam);
    }

    DiagLogGameMessage("GameWndProc", hWnd, uMsg, wParam, lParam);

    if (uMsg == WM_ACTIVATEAPP) {
        // Game vừa lấy lại activation: siết lại borderless phòng khi engine tự khôi phục viền/kích thước.
        // Không đổi display mode ở đây (chỉ đổi một lần khi tạo swapchain, xem MatchDisplayModeToBuffer).
        if (wParam) {
            ForceBorderlessWindow(hWnd);
        }
        LogDebug("[DXGI_HOOK] GameSubclassWndProc WM_ACTIVATEAPP: bActive=%d, PanelActive=%d\n",
            (BOOL)wParam, IsPanelActive() ? 1 : 0);
    } else if (uMsg == WM_DESTROY) {
        // Game đóng: trả màn hình về mode gốc ngay, không đợi tool thoát
        RestoreDisplayMode();
    }

    if (g_pOrigGameWndProc) {
        return CallWindowProcW(g_pOrigGameWndProc, hWnd, uMsg, wParam, lParam);
    }
    return DefWindowProcW(hWnd, uMsg, wParam, lParam);
}

static void SubclassGameWindow(HWND hWnd) {
    if (!hWnd || !IsWindow(hWnd)) return;
    HWND prevWnd = g_hHookedGameWnd.exchange(hWnd);
    if (prevWnd == hWnd) return; // Already subclassed

    LONG_PTR prevProc = GetWindowLongPtrW(hWnd, GWLP_WNDPROC);
    if (prevProc && prevProc != (LONG_PTR)GameSubclassWndProc) {
        g_pOrigGameWndProc = (WNDPROC)prevProc;
        SetWindowLongPtrW(hWnd, GWLP_WNDPROC, (LONG_PTR)GameSubclassWndProc);
        LogDebug("[DXGI_HOOK] Subclassed game window HWND=0x%p successfully\n", hWnd);
    }
}

// Cưỡng bức chuyển cửa sổ sang Borderless Fullscreen triệt để (Chuẩn hóa cả Style, ExStyle và Scaling)
void ForceBorderlessWindow(HWND hWnd) {
    if (!hWnd || !IsWindow(hWnd)) return;
    if (IsHookInert()) return;  // Tool đã thoát: để game tự quản lý cửa sổ của nó

    SubclassGameWindow(hWnd);

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

    DiagWrite("[BORDERLESS] Applied HWND=0x%p rect=(%d,%d,%dx%d) styleChange=%d geoChange=%d PanelActive=%d",
        hWnd, mi.rcMonitor.left, mi.rcMonitor.top, screen_w, screen_h,
        needsStyleUpdate ? 1 : 0, needsGeoUpdate ? 1 : 0, IsPanelActive() ? 1 : 0);
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

    // Tearing: swapchain flip có thể nhận ALLOW_TEARING ngay trong ResizeBuffers. Luôn thử thêm cờ
    // (kể cả khi hook CreateSwapChain* không chặn được do đua tranh lúc tiêm) để Present(0) không bị
    // khoá vào nhịp composition 60Hz -> game tụt đúng 30 fps. Nếu bị từ chối thì rút cờ và thử lại.
    bool tryTearing = !g_bTearingUnsupported.load();
    if (tryTearing) {
        SwapChainFlags |= DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING;
    }

    if (Width > 0 && Height > 0) {
        g_uBufferWidth.store(Width);
        g_uBufferHeight.store(Height);
    }

    HRESULT hr = g_pOrigResizeBuffers ?
        g_pOrigResizeBuffers(This, BufferCount, Width, Height, NewFormat, SwapChainFlags) : E_FAIL;

    if (FAILED(hr) && tryTearing) {
        g_bTearingUnsupported.store(true);
        DiagWrite("[TEARING] ResizeBuffers kèm ALLOW_TEARING thất bại hr=0x%08lX -> thử lại không tearing", (unsigned long)hr);
        SwapChainFlags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING;
        hr = g_pOrigResizeBuffers ?
            g_pOrigResizeBuffers(This, BufferCount, Width, Height, NewFormat, SwapChainFlags) : E_FAIL;
        tryTearing = false;
    }
    if (SUCCEEDED(hr) && tryTearing) {
        g_bTearingSwapChain.store(true);
        static bool s_resizeTearingLogged = false;
        if (!s_resizeTearingLogged) {
            s_resizeTearingLogged = true;
            DiagWrite("[TEARING] Đã bật ALLOW_TEARING qua ResizeBuffers (%ux%u)", Width, Height);
        }
    }

    DXGI_SWAP_CHAIN_DESC desc;
    if (SUCCEEDED(This->GetDesc(&desc)) && desc.OutputWindow) {
        g_hGameWnd.store(desc.OutputWindow);
        MatchDisplayModeToBuffer(desc.OutputWindow, g_uBufferWidth.load(), g_uBufferHeight.load());
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
        if (pNewTargetParameters->Width > 0 && pNewTargetParameters->Height > 0) {
            g_uBufferWidth.store(pNewTargetParameters->Width);
            g_uBufferHeight.store(pNewTargetParameters->Height);
        }
    }

    DXGI_SWAP_CHAIN_DESC desc;
    if (SUCCEEDED(This->GetDesc(&desc)) && desc.OutputWindow) {
        g_hGameWnd.store(desc.OutputWindow);
        MatchDisplayModeToBuffer(desc.OutputWindow, g_uBufferWidth.load(), g_uBufferHeight.load());
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
            g_hGameWnd.store(desc.OutputWindow);
            MatchDisplayModeToBuffer(desc.OutputWindow, g_uBufferWidth.load(), g_uBufferHeight.load());
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

    // Identify caller to preserve AMD Adrenalin In-Game Overlay (amdow.exe / amdfendrsr / IGOProxy)
    void* callerAddr = _ReturnAddress();
    HMODULE hCallerMod = NULL;
    bool isAmdOverlayCaller = false;
    if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCSTR)callerAddr, &hCallerMod) && hCallerMod) {
        char modName[MAX_PATH] = { 0 };
        GetModuleFileNameA(hCallerMod, modName, MAX_PATH);
        _strlwr_s(modName);
        if (strstr(modName, "amd") || strstr(modName, "igo") || strstr(modName, "radeon") || strstr(modName, "overlay")) {
            isAmdOverlayCaller = true;
        }
    }

    if (pFullscreen) {
        if (isAmdOverlayCaller && g_bGameRequestedFullscreen.load()) {
            *pFullscreen = TRUE; // Report Fullscreen to AMD Overlay so RSR & Alt+R overlay activates!
        } else {
            *pFullscreen = FALSE; // Keep Windowed for game engine mouse hit-testing
        }
    }
    if (ppTarget && !isAmdOverlayCaller) {
        *ppTarget = NULL;
    }

    return hr;
}

// 3. Hook XInputGetState để cô lập điều khiển tay cầm khi Quick Panel mở
DWORD WINAPI Hooked_XInputGetState(DWORD dwUserIndex, XINPUT_STATE* pState) {
    if (!g_pOrigXInputGetState) return ERROR_DEVICE_NOT_CONNECTED;

    DWORD res = g_pOrigXInputGetState(dwUserIndex, pState);
    if (res == ERROR_SUCCESS && pState && !IsHookInert() && IsPanelActive()) {
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

// 3b. Hook Present / Present1 để đo nhịp khung hình thực tế và kết quả DXGI trả về
// (Giữ nguyên giá trị trả về; chỉ thêm cờ ALLOW_TEARING khi swapchain được tạo kèm cờ đó.)
static inline UINT ApplyTearingToPresentFlags(UINT syncInterval, UINT presentFlags) {
    if (g_bTearingSwapChain.load() && syncInterval == 0 && !g_bTearingUnsupported.load() &&
        (presentFlags & DXGI_PRESENT_ALLOW_TEARING) == 0) {
        return presentFlags | DXGI_PRESENT_ALLOW_TEARING;
    }
    return presentFlags;
}

static inline void DisableTearingAfterFailure(HRESULT hr) {
    g_bTearingSwapChain.store(false);
    g_bTearingUnsupported.store(true);
    DiagWrite("[TEARING] Present(ALLOW_TEARING) thất bại hr=0x%08lX -> tắt tearing, trình bày lại kiểu cũ",
        (unsigned long)hr);
}

HRESULT STDMETHODCALLTYPE Hooked_Present(IDXGISwapChain* This, UINT SyncInterval, UINT PresentFlags) {
    UINT flags = ApplyTearingToPresentFlags(SyncInterval, PresentFlags);
    HRESULT hr = g_pOrigPresent ? g_pOrigPresent(This, SyncInterval, flags) : E_FAIL;
    if (flags != PresentFlags && FAILED(hr)) {
        DisableTearingAfterFailure(hr);
        flags = PresentFlags;
        hr = g_pOrigPresent ? g_pOrigPresent(This, SyncInterval, flags) : E_FAIL;
    }
    RecordPresentTiming(hr, SyncInterval, flags);
    return hr;
}

HRESULT STDMETHODCALLTYPE Hooked_Present1(IDXGISwapChain1* This, UINT SyncInterval, UINT PresentFlags, const DXGI_PRESENT_PARAMETERS* pPresentParameters) {
    UINT flags = ApplyTearingToPresentFlags(SyncInterval, PresentFlags);
    HRESULT hr = g_pOrigPresent1 ? g_pOrigPresent1(This, SyncInterval, flags, pPresentParameters) : E_FAIL;
    if (flags != PresentFlags && FAILED(hr)) {
        DisableTearingAfterFailure(hr);
        flags = PresentFlags;
        hr = g_pOrigPresent1 ? g_pOrigPresent1(This, SyncInterval, flags, pPresentParameters) : E_FAIL;
    }
    RecordPresentTiming(hr, SyncInterval, flags);
    return hr;
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

        // Bỏ qua swapchain 100x100 của Dummy Window dùng để lấy con trỏ VMT
        bool realSurface = (scDesc.BufferDesc.Width >= 200 && scDesc.BufferDesc.Height >= 200);
        if (realSurface) {
            g_swapChainFlags.store(scDesc.Flags);
            g_swapChainBufferCount.store(scDesc.BufferCount);

            static unsigned s_lastDescHash = 0;
            unsigned descHash = (unsigned)(scDesc.BufferDesc.Width * 73856093u)
                              ^ (unsigned)(scDesc.BufferDesc.Height * 19349663u)
                              ^ (unsigned)scDesc.Flags;
            if (descHash != s_lastDescHash) {
                s_lastDescHash = descHash;
                DiagWrite("[SWAPCHAIN] Windowed=%d BufferCount=%u Format=%d SwapEffect=%d Flags=0x%X (TEARING=%d) Buffer=%ux%u",
                    scDesc.Windowed, scDesc.BufferCount, (int)scDesc.BufferDesc.Format, (int)scDesc.SwapEffect,
                    scDesc.Flags, (scDesc.Flags & DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING) ? 1 : 0,
                    scDesc.BufferDesc.Width, scDesc.BufferDesc.Height);
            }
        }
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

        // Đo nhịp khung hình: IDXGISwapChain::Present = slot 8, IDXGISwapChain1::Present1 = slot 22
        if (vtbl[8]) {
            MH_CreateHook(vtbl[8], (LPVOID)&Hooked_Present, (LPVOID*)&g_pOrigPresent);
            MH_EnableHook(vtbl[8]);
        }
        IDXGISwapChain1* pSc1 = nullptr;
        if (SUCCEEDED(pSwapChain->QueryInterface(__uuidof(IDXGISwapChain1), (void**)&pSc1)) && pSc1) {
            void** vtbl1 = *(void***)pSc1;
            if (vtbl1 && vtbl1[22]) {
                MH_CreateHook(vtbl1[22], (LPVOID)&Hooked_Present1, (LPVOID*)&g_pOrigPresent1);
                MH_EnableHook(vtbl1[22]);
            }
            pSc1->Release();
        }

        LogDebug("[DXGI_HOOK] Đã móc thành công IDXGISwapChain VMT: SetFullscreenState=0x%p, GetFullscreenState=0x%p, ResizeBuffers=0x%p, ResizeTarget=0x%p, Present=0x%p, Present1=0x%p\n",
            vtbl[10], vtbl[11], vtbl[13], vtbl[14], (void*)g_pOrigPresent, (void*)g_pOrigPresent1);
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
            MatchDisplayModeToBuffer(pDesc->OutputWindow, g_uBufferWidth.load(), g_uBufferHeight.load());
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
    bool wantTearing = false;
    if (pDesc) {
        descCopy = *pDesc;
        descCopy.Flags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
        // Backbuffer của game thường nhỏ hơn cửa sổ (vd render 1280x720 trong cửa sổ 1920x1080).
        // DXGI_SCALING_NONE sẽ vẽ 1:1 ở góc trên-trái (game không phủ kín màn hình), nên luôn ép STRETCH
        // để presenter phóng backbuffer phủ kín client area.
        if (descCopy.Scaling != DXGI_SCALING_STRETCH) {
            DiagWrite("[SCALING] Swapchain Scaling %d -> 0 (STRETCH) để phủ kín cửa sổ", (int)descCopy.Scaling);
            descCopy.Scaling = DXGI_SCALING_STRETCH;
        }

        // Chỉ swapchain FLIP mới nhận ALLOW_TEARING; bitblt (DISCARD) sẽ trả E_INVALIDARG.
        bool isFlip = (descCopy.SwapEffect == DXGI_SWAP_EFFECT_FLIP_DISCARD ||
                       descCopy.SwapEffect == DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL);
        if (isFlip && !g_bTearingUnsupported.load()) {
            descCopy.Flags |= DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING;
            wantTearing = true;
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

    // Driver/OS không nhận tearing: tạo lại y như cũ để không bao giờ làm hỏng game
    if (FAILED(hr) && wantTearing) {
        g_bTearingUnsupported.store(true);
        DiagWrite("[TEARING] Tạo swapchain kèm ALLOW_TEARING thất bại hr=0x%08lX -> tạo lại không tearing", (unsigned long)hr);
        wantTearing = false;
        if (pDesc) descCopy.Flags &= ~DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING;
        hr = g_pOrigCreateSwapChainForHwnd ?
            g_pOrigCreateSwapChainForHwnd(This, pDevice, hWnd, pDesc, pFullscreenDesc, pRestrictToOutput, ppSwapChain) : E_FAIL;
    }

    if (SUCCEEDED(hr)) {
        g_bTearingSwapChain.store(wantTearing);
        if (wantTearing) {
            DiagWrite("[TEARING] Đã bật DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING (SyncInterval=0 sẽ không chờ vblank)");
        }
    }

    if (SUCCEEDED(hr) && ppSwapChain && *ppSwapChain) {
        if (pDesc) {
            if (pDesc->Width > 0) g_uBufferWidth.store(pDesc->Width);
            if (pDesc->Height > 0) g_uBufferHeight.store(pDesc->Height);
        }
        if (hWnd) g_hGameWnd.store(hWnd);
        HookSwapChainInstance((IDXGISwapChain*)*ppSwapChain);
        if (hWnd) {
            MatchDisplayModeToBuffer(hWnd, g_uBufferWidth.load(), g_uBufferHeight.load());
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
            MatchDisplayModeToBuffer(pSwapChainDesc->OutputWindow, g_uBufferWidth.load(), g_uBufferHeight.load());
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
    RawGetCursorPos(&pt);
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

    // Trạng thái kích hoạt/tiêu điểm thật của luồng UI game (hạch toán thay cho GetForegroundWindow đơn thuần)
    GUITHREADINFO gti = {0};
    gti.cbSize = sizeof(gti);
    DWORD gameTid = GetWindowThreadProcessId(hWnd, NULL);
    if (gameTid) GetGUIThreadInfo(gameTid, &gti);
    HWND fgWnd = GetForegroundWindow();

    char snap[1800];
    snprintf(snap, sizeof(snap),
        "HWND=0x%p Buffer=%ux%u Client=%dx%d Window=(%ld,%ld,%ld,%ld) DwmFrame[%d]=(%ld,%ld,%ld,%ld) Monitor=%dx%d@(%ld,%ld) "
        "Scale(Client/Buffer)=%.3fx%.3f DPI(win=%u,sys=%u,awareness=%d,setResult=%d) Clip[%d]=(%ld,%ld,%ld,%ld) "
        "Cursor=(%ld,%ld) CursorClient=(%ld,%ld) Fg=%d PanelActive=%d "
        "FgHwnd=0x%p Active=0x%p Focus=0x%p Capture=0x%p MenuOwner=0x%p GuiFlags=0x%X",
        hWnd, bw, bh, cw, ch, wr.left, wr.top, wr.right, wr.bottom,
        dwmOk, dwmR.left, dwmR.top, dwmR.right, dwmR.bottom, mw, mh, mi.rcMonitor.left, mi.rcMonitor.top,
        sx, sy, winDpi, sysDpi, awareness, g_dpiSetResult,
        hasClip, clip.left, clip.top, clip.right, clip.bottom,
        pt.x, pt.y, ptClient.x, ptClient.y,
        (fgWnd == hWnd) ? 1 : 0, IsPanelActive() ? 1 : 0,
        (void*)fgWnd, (void*)gti.hwndActive, (void*)gti.hwndFocus, (void*)gti.hwndCapture,
        (void*)gti.hwndMenuOwner, gti.flags);

    // So sánh bỏ phần vị trí chuột (luôn đổi) để chỉ log khi hình học/trạng thái đổi
    char key[1800];
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

// Đếm các cửa sổ lớp phủ kiểu Quick Panel đang thật sự hiện diện trên Desktop:
// visible + WS_EX_LAYERED + WS_EX_NOACTIVATE + kích thước đáng kể. Dùng để đối chiếu "app còn chạy"
// với nhịp khung hình, độc lập với Named Event PanelActive (panel đóng vẫn để cửa sổ xuyên thấu trên màn hình).
struct OverlayScan {
    int count;
    DWORD pids[4];
    RECT rects[4];
};

static BOOL CALLBACK EnumOverlayWindowsProc(HWND h, LPARAM lp) {
    OverlayScan* scan = (OverlayScan*)lp;
    if (!scan || !IsWindowVisible(h)) return TRUE;

    LONG ex = GetWindowLongW(h, GWL_EXSTYLE);
    if ((ex & (WS_EX_LAYERED | WS_EX_NOACTIVATE)) != (WS_EX_LAYERED | WS_EX_NOACTIVATE)) return TRUE;

    RECT r;
    if (!GetWindowRect(h, &r)) return TRUE;
    if ((r.right - r.left) < 64 || (r.bottom - r.top) < 64) return TRUE;

    if (scan->count < 4) {
        DWORD pid = 0;
        GetWindowThreadProcessId(h, &pid);
        scan->pids[scan->count] = pid;
        scan->rects[scan->count] = r;
        scan->count++;
    }
    return TRUE;
}

// Ghi nhịp khung hình thật của engine trong khoảng thời gian kể từ lần gọi trước.
// FPS suy ra từ thời gian trung bình giữa 2 lần Present nên không phụ thuộc chu kỳ lấy mẫu.
static void LogFrameStats(int tick) {
    unsigned presents = g_presentCount.exchange(0);
    unsigned frames = g_frameCount.exchange(0);
    long long frameSum = g_frameQpcSum.exchange(0);
    long long frameMax = g_maxFrameQpc.exchange(0);
    unsigned okCnt = g_presentOk.exchange(0);
    unsigned occCnt = g_presentOccluded.exchange(0);
    unsigned failCnt = g_presentFailed.exchange(0);

    if (presents == 0) {
        g_lastPresentQpc.store(0);
        return;
    }

    double qpcFreq = (double)g_qpcFrequency.load();
    double avgMs = (frames > 0 && qpcFreq > 0.0) ? ((double)frameSum / (double)frames) / qpcFreq * 1000.0 : 0.0;
    double maxMs = (frameMax > 0 && qpcFreq > 0.0) ? (double)frameMax / qpcFreq * 1000.0 : 0.0;
    double fps = (avgMs > 0.01) ? (1000.0 / avgMs) : 0.0;

    if (fps < 40.0 || occCnt > 0 || failCnt > 0 || (tick % 10 == 0)) {
        HWND gameWnd = g_hGameWnd.load();
        HWND fgWnd = GetForegroundWindow();

        OverlayScan scan = {};
        EnumWindows(EnumOverlayWindowsProc, (LPARAM)&scan);
        char overlayInfo[192];
        if (scan.count > 0) {
            snprintf(overlayInfo, sizeof(overlayInfo), " Overlays=%d BgPid=%lu BgRect=(%ld,%ld,%ld,%ld)",
                scan.count, (unsigned long)scan.pids[0],
                scan.rects[0].left, scan.rects[0].top, scan.rects[0].right, scan.rects[0].bottom);
        } else {
            snprintf(overlayInfo, sizeof(overlayInfo), " Overlays=0");
        }

        DiagWrite("[FPS] fps=%.1f avgFrame=%.2fms maxFrame=%.2fms presents=%u hr[ok=%u occ=%u fail=%u] lastHr=0x%08lX syncInt=%u flags=0x%X PanelActive=%d Fg=%d FgHwnd=0x%p SWFlags=0x%X BufCount=%u%s",
            fps, avgMs, maxMs, presents, okCnt, occCnt, failCnt, (unsigned long)g_lastPresentHr.load(),
            g_lastSyncInterval.load(), g_lastPresentFlags.load(), IsPanelActive() ? 1 : 0,
            (gameWnd && fgWnd == gameWnd) ? 1 : 0, (void*)fgWnd,
            g_swapChainFlags.load(), g_swapChainBufferCount.load(), overlayInfo);
    }
}

static DWORD WINAPI DiagThreadProc(LPVOID) {
    DiagWrite("===== DXGI Hook Diagnostic thread started (exe pid=%lu) =====", GetCurrentProcessId());
    char last[1800] = {0};
    bool lastPanel = false;
    int tick = 0;
    for (; g_bInitialized.load();) {
        if (IsShutdownRequested()) {
            DiagWrite("[SHUTDOWN] HandheldTool_Shutdown signaled -> hooks chuyển sang pass-through (giữ MinHook để tránh deadlock luồng render)");
            RestoreDisplayMode();
            break;
        }

        bool panel = IsPanelActive();
        if (panel != lastPanel) {
            lastPanel = panel;
            LogFrameStats(tick);
            // Chụp ngay tại thời điểm chuyển trạng thái, và thêm 1 mẫu sau 300ms để thấy game phản ứng
            DiagSnapshot(panel ? "PANEL_OPEN" : "PANEL_CLOSE", true, last, sizeof(last));
            Sleep(300);
            DiagSnapshot(panel ? "PANEL_OPEN+300ms" : "PANEL_CLOSE+300ms", true, last, sizeof(last));
            Sleep(1200);
            DiagSnapshot(panel ? "PANEL_OPEN+1.5s" : "PANEL_CLOSE+1.5s", true, last, sizeof(last));
            continue;
        }
        LogFrameStats(tick);
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

    // Ánh xạ tọa độ chuột màn hình giữa không gian Client (cửa sổ) và Buffer (độ phân giải game render)
    HMODULE hUser32Mouse = GetModuleHandleW(L"user32.dll");
    if (hUser32Mouse) {
        void* pGetCursorPos = (void*)GetProcAddress(hUser32Mouse, "GetCursorPos");
        if (pGetCursorPos) {
            MH_CreateHook(pGetCursorPos, (LPVOID)&Hooked_GetCursorPos, (LPVOID*)&g_pOrigGetCursorPos);
        }
        void* pSetCursorPos = (void*)GetProcAddress(hUser32Mouse, "SetCursorPos");
        if (pSetCursorPos) {
            MH_CreateHook(pSetCursorPos, (LPVOID)&Hooked_SetCursorPos, (LPVOID*)&g_pOrigSetCursorPos);
        }
        void* pGetMessagePos = (void*)GetProcAddress(hUser32Mouse, "GetMessagePos");
        if (pGetMessagePos) {
            MH_CreateHook(pGetMessagePos, (LPVOID)&Hooked_GetMessagePos, (LPVOID*)&g_pOrigGetMessagePos);
        }
        void* pPeekMsg = (void*)GetProcAddress(hUser32Mouse, "PeekMessageW");
        if (pPeekMsg) {
            MH_CreateHook(pPeekMsg, (LPVOID)&Hooked_PeekMessageW, (LPVOID*)&g_pOrigPeekMessageW);
        }
        void* pGetMsg = (void*)GetProcAddress(hUser32Mouse, "GetMessageW");
        if (pGetMsg) {
            MH_CreateHook(pGetMsg, (LPVOID)&Hooked_GetMessageW, (LPVOID*)&g_pOrigGetMessageW);
        }
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

    RestoreDisplayMode();

    if (g_hHookedGameWnd.load() && g_pOrigGameWndProc) {
        HWND hWnd = g_hHookedGameWnd.load();
        if (IsWindow(hWnd)) {
            SetWindowLongPtrW(hWnd, GWLP_WNDPROC, (LONG_PTR)g_pOrigGameWndProc);
        }
    }

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
