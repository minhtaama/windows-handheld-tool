#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_NCRENDERING_POLICY
#define DWMWA_NCRENDERING_POLICY 2
#endif
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// Opaque panel background. The overlay is rendered into a normal (non-layered)
// window; the Flutter view paints the real panel on top of this brush.
constexpr COLORREF kBackgroundColor = RGB(0x0A, 0x0B, 0x0E);

HBRUSH BackgroundBrush() {
  static HBRUSH brush = CreateSolidBrush(kBackgroundColor);
  return brush;
}

constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

static int g_active_window_count = 0;

static WNDPROC g_pOrigChildProc = nullptr;

static LRESULT CALLBACK ChildWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  if (msg == WM_MOUSEACTIVATE) {
    return MA_NOACTIVATE;
  }
  if (msg == WM_ERASEBKGND) {
    HDC hdc = reinterpret_cast<HDC>(wParam);
    if (hdc) {
      RECT rc;
      GetClientRect(hwnd, &rc);
      FillRect(hdc, &rc, BackgroundBrush());
    }
    return 1;
  }
  if (g_pOrigChildProc) {
    return CallWindowProc(g_pOrigChildProc, hwnd, msg, wParam, lParam);
  }
  return DefWindowProc(hwnd, msg, wParam, lParam);
}

}  // namespace

class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  const wchar_t* GetWindowClass();
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;
  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = BackgroundBrush();
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  HMONITOR monitor = MonitorFromWindow(GetForegroundWindow(), MONITOR_DEFAULTTONEAREST);
  if (!monitor) {
    POINT pt = {0, 0};
    monitor = MonitorFromPoint(pt, MONITOR_DEFAULTTOPRIMARY);
  }
  MONITORINFO mi = { sizeof(mi) };
  int screen_x = 0;
  int screen_y = 0;
  int screen_w = 1920;
  int screen_h = 1080;
  if (GetMonitorInfoW(monitor, &mi)) {
    screen_x = mi.rcMonitor.left;
    screen_y = mi.rcMonitor.top;
    screen_w = mi.rcMonitor.right - mi.rcMonitor.left;
    screen_h = mi.rcMonitor.bottom - mi.rcMonitor.top;
  }

  int panel_w = static_cast<int>(screen_w * 0.35);
  if (panel_w < 360) panel_w = 360;
  int panel_x = screen_x + screen_w - panel_w;
  int panel_y = screen_y;
  int panel_h = screen_h;

  DWORD dwStyle = WS_POPUP;
  DWORD dwExStyle = WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_TRANSPARENT;

  HWND window = CreateWindowExW(
      dwExStyle,
      window_class, title.c_str(), dwStyle,
      panel_x, panel_y, panel_w, panel_h,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  // The overlay is a normal opaque window. Earlier builds combined
  // WS_EX_LAYERED, DwmExtendFrameIntoClientArea and an empty blur region, which
  // made the Flutter swap chain invisible on some drivers (transparent panel,
  // no UI). Flutter now paints the panel over the opaque background brush.
  DWORD policy = 1; // DWMNCRP_DISABLED
  DwmSetWindowAttribute(window, DWMWA_NCRENDERING_POLICY, &policy, sizeof(policy));

  DWORD corner = 2; // DWMWCP_ROUND
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE, &corner, sizeof(corner));

  UpdateTheme(window);

  if (!OnCreate()) {
    return false;
  }

  // Keep the window in the default desktop band. Moving a Flutter window into
  // ZBID_UIACCESS (Band 2) made the hosted FlutterView child disappear, leaving
  // a black panel. Games are forced to borderless by dxgi_hook, so a TOPMOST
  // window in Band 1 still stays above them.
  return true;
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNOACTIVATE);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;

    case WM_ERASEBKGND: {
      HDC hdc = reinterpret_cast<HDC>(wparam);
      if (hdc) {
        RECT rc;
        GetClientRect(hwnd, &rc);
        FillRect(hdc, &rc, BackgroundBrush());
      }
      return 1;
    }

    case WM_NCACTIVATE:
      return (wparam == 0) ? DefWindowProc(hwnd, message, wparam, lparam) : TRUE;

    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      // DPI geometry is fully coordinated by the backend WindowManager.
      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);

  LONG_PTR exStyle = GetWindowLongPtr(content, GWL_EXSTYLE);
  SetWindowLongPtr(content, GWL_EXSTYLE, exStyle | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT);

  if (!g_pOrigChildProc) {
    g_pOrigChildProc = reinterpret_cast<WNDPROC>(
        SetWindowLongPtr(content, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ChildWndProc)));
  }

  RECT frame = GetClientArea();
  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  return true;
}

void Win32Window::OnDestroy() {
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
