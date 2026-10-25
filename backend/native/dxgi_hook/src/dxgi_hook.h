#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <dxgi1_2.h>
#include <dxgi1_5.h>
#include <xinput.h>
#include <cstdint>

#include "../minhook/include/MinHook.h"

#ifdef __cplusplus
extern "C" {
#endif

// Khởi tạo toàn bộ các móc can thiệp DXGI
bool InitDxgiHook();

// Gỡ bỏ an toàn toàn bộ các móc can thiệp
void ShutdownDxgiHook();

// Cưỡng bức cửa sổ chuyển sang Borderless Fullscreen khớp với kích thước màn hình
__declspec(dllexport) void ForceBorderlessWindow(HWND hWnd);

// Kiểm tra trạng thái hoạt động của hook (Trả về bitmask: 1 = Hooked, 2 = Game Requested Fullscreen)
__declspec(dllexport) DWORD GetHookStatus();

#ifdef __cplusplus
}
#endif

