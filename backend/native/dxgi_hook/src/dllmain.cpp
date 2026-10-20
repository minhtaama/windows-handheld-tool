#include "dxgi_hook.h"

static DWORD WINAPI InitWorker(LPVOID lpParam) {
    // Chờ một khoảng ngắn để tiến trình hoàn tất nạp các thư viện cơ bản nếu được tiêm lúc khởi động
    Sleep(50);
    InitDxgiHook();
    return 0;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH:
        DisableThreadLibraryCalls(hModule);
        // Tạo luồng riêng để né hoàn toàn cơ chế khóa nạp thư viện LdrpLoaderLock của Windows
        CreateThread(NULL, 0, (LPTHREAD_START_ROUTINE)InitWorker, NULL, 0, NULL);
        break;

    case DLL_PROCESS_DETACH:
        if (lpReserved == NULL) {
            ShutdownDxgiHook();
        }
        break;
    }
    return TRUE;
}

