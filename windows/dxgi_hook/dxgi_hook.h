#pragma once

#include <windows.h>
#include <dxgi.h>
#include <dxgi1_2.h>
#include <d3d11.h>
#include <xinput.h>

#ifndef DXGI_HOOK_API
#ifdef DXGI_HOOK_EXPORTS
    #define DXGI_HOOK_API __declspec(dllexport)
#else
    #define DXGI_HOOK_API __declspec(dllimport)
#endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

// =========================================================================
// Handheld DXGI Borderless Hook Control APIs (Dart FFI & IPC Compatible)
// =========================================================================

/// Cài đặt Global Windows Hook (WH_CBT) để tự động nạp dxgi_hook.dll vào mọi tiến trình Game 64-bit.
DXGI_HOOK_API BOOL WINAPI InstallGlobalDxgiHook(void);

/// Gỡ bỏ Global Windows Hook.
DXGI_HOOK_API BOOL WINAPI UninstallGlobalDxgiHook(void);

/// Kiểm tra xem Global Windows Hook có đang kích hoạt hay không.
DXGI_HOOK_API BOOL WINAPI IsGlobalDxgiHookActive(void);

/// Chèn trực tiếp dxgi_hook.dll vào một tiến trình cụ thể theo Process ID (PID).
DXGI_HOOK_API BOOL WINAPI InjectDxgiHook(DWORD dwProcessId);

/// Rút dxgi_hook.dll khỏi một tiến trình cụ thể theo Process ID (PID).
DXGI_HOOK_API BOOL WINAPI EjectDxgiHook(DWORD dwProcessId);

/// Chuyển đổi cửa sổ mục tiêu thành Cửa sổ Không viền Toàn màn hình (Borderless Fullscreen).
DXGI_HOOK_API BOOL WINAPI MakeWindowBorderless(HWND hWnd);

/// Thông báo cho Hook biết trạng thái mở/đóng của Quick Settings Overlay.
/// Khi active = TRUE: Gamepad input trong game sẽ bị ngắt (Mute) để người dùng điều khiển Quick Panel mà game không bị nhận nhầm thao tác.
DXGI_HOOK_API void WINAPI SetOverlayActive(BOOL active);

/// Lấy trạng thái kích hoạt hiện tại của Overlay.
DXGI_HOOK_API BOOL WINAPI IsOverlayActive(void);

#ifdef __cplusplus
}
#endif
