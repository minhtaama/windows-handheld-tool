# Trạng thái hiện tại của dự án (Project Status)
Cập nhật lần cuối: 24/10/2026 20:05

> [!IMPORTANT]
> **Quy tắc duy trì tài liệu**:
> 1. **Checkbox ngoài cùng (`- [x]` / `- [ ]`)**: Thể hiện trạng thái tổng thể của tính năng.
>    - `- [x]`: Toàn bộ tính năng đã được kiểm thử và xác nhận **Hoạt động ổn định**.
>    - `- [ ]`: Tính năng còn lỗi tồn đọng, đang trong backlog, hoặc **Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định)**.
> 2. **Timeline bên trong (thụt lề `+ [Thời gian]`)**: Lưu vết toàn bộ lịch sử phát triển theo trình tự thời gian.
>    - `+ [Initial]`: Hiện trạng mã nguồn và trạng thái ban đầu của tính năng.
>    - `+ [Ngày giờ]`: Các mốc thời gian cập nhật, sửa lỗi hoặc phát hiện lỗi mới. Tuyệt đối không xóa hay sửa đè lên các mốc timeline cũ.
> 3. Khi vừa sửa xong code cho một lỗi, bổ sung một mốc `+ [Thời gian]` mới ghi rõ: **Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định)** và giữ checkbox tính năng là `- [ ]`. Chỉ tick `- [x]` sau khi người dùng hoặc kiểm thử thực chiến xác nhận.


- [x] **AMD RSR (Radeon Super Resolution) & Tương thích AMD In-Game Overlay**
  + [Initial] Hiện tượng: Khi vào game, AMD Adrenalin In-Game Overlay (Alt+R) không thể mở lên; người dùng đã bật RSR ON trong AMD Software nhưng vào game RSR không kích hoạt upscaling (không phóng to từ 720p lên 1080p).
    Nguyên nhân kỹ thuật:
      - `dxgi_hook.cpp` ép 100% các game chạy ở chế độ Borderless Windowed và cưỡng bức `Hooked_GetFullscreenState` luôn trả về `*pFullscreen = FALSE`.
      - AMD RSR mặc định chỉ chạy trên Exclusive Fullscreen; muốn chạy trên Borderless Windowed bắt buộc phải có cờ `upscaling_use_borderless = "TRUE"` và `upscaling_target_resolution` trong hồ sơ `%LOCALAPPDATA%\AMD\CN\gmdb.blb`. Do các game đều đang có cờ này là `FALSE`, driver AMD từ chối upscale.
      - AMD Overlay (`amdow.exe`) nhận diện game là Windowed và bị hook SwapChain chặn nên không mở được bằng `Alt + R`.
  + [24/10/2026 20:05] Khắc phục lỗi AMD RSR Borderless và mở khóa AMD Overlay In-Game:
    Code thực tế:
      - `backend/src/hardware/amd_rsr_service.py`: Xây dựng dịch vụ quản trị AMD RSR. Tự động đọc/ghi cấu hình `upscaling_enabled`, `upscaling_use_borderless = TRUE`, `upscaling_sharpness`, `upscaling_target_resolution = 1280x720` trong cơ sở dữ liệu `gmdb.blb` của AMD Adrenalin; hỗ trợ giả lập phím tắt `Alt + U` bằng `SendInput` để trigger daemon `amdfendrsr` tức thì in-game.
      - `backend/src/services/game_compat_service.py`: Khi phát hiện game vừa khởi chạy, tự động gọi `ensure_game_borderless_rsr(exe_path)` đồng bộ ngay cờ Borderless RSR vào driver AMD trước khi tiêm hook.
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp`: Cập nhật `Hooked_GetFullscreenState` dùng `_ReturnAddress()` phân biệt caller. Khi caller là các module của AMD (`amdow.exe`, `amdfendrsr.dll`, `atidxx64.dll`, `IGOProxy64.exe`), trả về đúng trạng thái `*pFullscreen = TRUE` (nếu game đã từng yêu cầu Fullscreen) để AMD Overlay bung mở và RSR kích hoạt, đồng thời vẫn giữ `FALSE` cho game engine để ma trận chuột Client Rect không bị lệch. Cập nhật `Hooked_ResizeTarget` lưu kích thước buffer render thực tế.
      - `backend/native/dxgi_hook/build.bat`: Biên dịch lại thành công `backend/bin/dxgi_hook.dll` (MSVC x64) và đồng bộ sang `dist/`.
      - `backend/src/bridge/web_bridge.py` & `ws_server.py`: Bổ sung slot/action `setAmdRsr(enabled, sharpness)` và đưa snapshot telemetry `is_amd_gpu`, `amd_rsr_enabled`, `amd_rsr_sharpness` qua WebSocket IPC.
      - `frontend/lib/services/bridge_service.dart`: Bổ sung ValueNotifiers `isAmdGpu`, `isAmdRsrEnabled`, `amdRsrSharpness` và API `setAmdRsr(enabled, {sharpness})`.
      - `frontend/lib/ui/tabs/performance_tab.dart`: Bổ sung Section "ĐỒ HỌA AMD (RSR UPSCALING)" với ToggleCard công tắc RSR và SettingSlider điều chỉnh độ nét Sharpness (0% - 100%), hỗ trợ Gamepad 100%.
      - `backend/windows_handheld_tool.spec`: Khai báo `hiddenimports=['win32com', 'win32com.client', 'wmi', 'pythoncom']`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [24/10/2026 21:30] Loại bỏ hoàn toàn cài đặt RSR khỏi Quick Panel và Backend theo yêu cầu:
    Lý do: RSR là công nghệ xử lý cấp driver của AMD Software Adrenalin; việc can thiệp file cấu hình nội bộ gmdb.blb từ Panel gây dư thừa và khó kiểm soát.
    Code thực tế:
      - `backend/src/hardware/amd_rsr_service.py`: Xóa bỏ hoàn toàn tệp dịch vụ.
      - `backend/src/services/game_compat_service.py`: Gỡ bỏ lệnh gọi đồng bộ RSR.
      - `backend/src/bridge/web_bridge.py` & `ws_server.py`: Gỡ bỏ slot `setAmdRsr` và các telemetry liên quan.
      - `frontend/lib/services/bridge_service.dart`: Gỡ bỏ ValueNotifiers `isAmdGpu`, `isAmdRsrEnabled`, `amdRsrSharpness` và hàm `setAmdRsr`.
      - `frontend/lib/ui/tabs/performance_tab.dart`: Xóa bỏ phần giao diện "ĐỒ HỌA AMD (RSR UPSCALING)", tinh gọn lại navigationLayout và phím bấm Gamepad.
      - Biên dịch lại bản phát hành tĩnh `flutter build web --release`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 01:25] Kích hoạt tự động AMD RSR khi hạ độ phân giải in-game qua Dynamic Display Mode Sync (CDS_FULLSCREEN) + Borderless 1:1:
    Nguyên nhân kỹ thuật:
      - Khi hạ độ phân giải game (ví dụ `1600x900`), `dxgi_hook.cpp` trước đây chặn `ResizeTarget` và ép `ForceBorderlessWindow` kéo giãn cửa sổ ra `1920x1080` trên Desktop `1920x1080`. Trình điều khiển AMD Adrenalin (`amdxc64.dll` / `amdfendrsr.exe`) kiểm tra thấy kích thước xuất hình bằng đúng độ phân giải vật lý của tấm nền nên báo *"Inactive: Both height and width must be lower than screen resolution"*.
    Code thực tế:
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp`:
        + Quản lý độ phân giải màn hình gốc (`g_uNativeWidth`, `g_uNativeHeight`, `g_uNativeRefreshRate`) thông qua `EnumDisplaySettingsW(NULL, ENUM_REGISTRY_SETTINGS, ...)`.
        + Xây dựng hàm `ApplyDynamicDisplayMode`: Khi `Buffer (W x H)` nhỏ hơn màn hình gốc (ví dụ `1600x900` hoặc `1280x720`), tự động gọi `ChangeDisplaySettingsExW(NULL, &dm, NULL, CDS_FULLSCREEN, NULL)` chuyển tín hiệu xuất hình về đúng `W x H` và đặt cửa sổ Borderless `WS_POPUP` khớp 1:1. Tín hiệu xuất hình nhỏ hơn Native EDID kích hoạt ngay lập tức bộ phần cứng AMD Radeon Super Resolution (RSR Active) upscale lên 1080p. Đồng thời vì cửa sổ vẫn là Borderless (`WS_POPUP`), lớp phủ Quick Panel (`TokenUIAccess` / `WS_EX_NOACTIVATE`) luôn hiển thị on-top 100% không bao giờ bị văng game hay đen màn hình.
        + Khi game render ở độ phân giải gốc (`bufW >= g_uNativeWidth`), tự động khôi phục chế độ hiển thị gốc bằng `ChangeDisplaySettingsExW(NULL, NULL, NULL, 0, NULL)`.
        + Subclass cửa sổ game qua `GameSubclassWndProc` bắt `WM_ACTIVATEAPP`: nếu Alt+Tab ra ngoài desktop (và không phải mở Quick Panel), tự động trả độ phân giải Desktop về gốc; khi quay lại game, tự động áp dụng lại mode render của game. Bắt `WM_DESTROY` và `ShutdownDxgiHook` khôi phục an toàn màn hình gốc.
        + Tích hợp `ApplyDynamicDisplayMode` vào toàn bộ chu trình SwapChain: `Hooked_ResizeBuffers`, `Hooked_ResizeTarget`, `Hooked_SetFullscreenState`, `Hooked_CreateSwapChain`, `Hooked_CreateSwapChainForHwnd`, `Hooked_D3D11CreateDeviceAndSwapChain`.
      - `backend/native/dxgi_hook/build.bat`: Biên dịch thành công `backend/bin/dxgi_hook.dll` (MSVC x64) và đồng bộ sang `dist/windows_handheld_tool/bin/` và `dist/windows_handheld_tool/_internal/bin/`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 22:35] Đính chính: cơ chế `ApplyDynamicDisplayMode` ở mốc 01:25 **đã bị gỡ bỏ hoàn toàn**:
    Lý do: `ChangeDisplaySettingsExW(CDS_FULLSCREEN)` hạ mode màn hình xuống bằng độ phân giải render gây lệch DPI 1,75×, cửa sổ/buffer không khớp và làm Metro Exodus tụt 60 → 15-30 FPS (chi tiết chuỗi chẩn đoán ở mục "Metro Exodus (4A Engine)..." phần 1).
    Đường hiện tại: hook hạ display mode **đúng bằng độ phân giải render** (`dxgi_hook.match_display_mode`, Named Event `HandheldTool_MatchDisplayMode`), cửa sổ game 1:1 với buffer (`Scale=1.000`), phần phóng lên tấm nền do scaler phần cứng / RSR đảm nhận. Mode gốc tự khôi phục ở `WM_DESTROY`, khi tool thoát và khi DLL unload.
    Kết quả: RSR hoạt động tốt trên Metro Exodus EE, Far Cry 5, Dead Island 2, FPS cao, hình phủ kín màn hình.
    Tình trạng: Hoạt động ổn định (đã xác nhận thực chiến 25/10 22:20).

---


## 1. Cơ chế chuyển cảnh liền mạch & Lớp phủ in-game (Seamless Transition & Overlay)

- [x] **Cơ chế hiển thị đặc quyền & Cách ly tiêu điểm (Z-Band & Focus Management)**
  + [Initial] Code thực tế: `backend/src/overlay/window_manager.py` chạy quyền Administrator, nhúng chữ ký số (`HandheldToolsSigner`) và manifest `uiAccess="true"` thực thi từ `C:\Program Files` để DWM phân bổ vào dải đặc quyền `ZBID_UIACCESS` (Band 2), luôn nổi đè lên game thuộc Band 1 (Desktop). Cửa sổ neo cố định mép phải màn hình (`Side-Dock Viewport`), khi đóng chỉ bật cờ xuyên thấu `WS_EX_TRANSPARENT` (Click-Through 100%) mà không di dời hay hủy cửa sổ. Cửa sổ con Chromium được ép cờ `WS_EX_NOACTIVATE`. Khi đóng panel, hàm `restore_foreground_window` dùng kỹ thuật giả lập phím ALT (`keybd_event` VK_MENU) trước và sau lệnh `SetForegroundWindow` để phá vỡ `ForegroundLockTimeout`, giúp game nhận lại tiêu điểm tức thì mà không bị nuốt cú nhấp chuột đầu tiên.
    Tình trạng: Hoạt động ổn định.

- [x] **Can thiệp đồ họa DirectX nội tiến trình (DXGI Hook Engine)**
  + [Initial] Code thực tế: `backend/native/dxgi_hook/src/dxgi_hook.cpp` (MinHook x64) can thiệp bảng VMT SwapChain. `Hooked_SetFullscreenState` chặn `Fullscreen = TRUE`, ép `FALSE`, gọi `ForceBorderlessWindow` chuẩn hóa style Win32 (xóa `WS_CAPTION`, `WS_THICKFRAME`...) và trả về `S_OK`. `Hooked_GetFullscreenState` ép báo cáo `*pFullscreen = FALSE` để engine (Unreal Slate UI, Unity) dùng nhánh tọa độ chuột chuẩn Client Rect của Borderless Windowed. `Hooked_ResizeBuffers` & `Hooked_ResizeTarget` xóa cờ `ALLOW_MODE_SWITCH` và chặn game co rút cửa sổ Win32 khi render nhỏ hơn màn hình. Hook Factory (`CreateSwapChain`, `CreateSwapChainForHwnd`, `D3D11CreateDeviceAndSwapChain`) tự động xóa `ALLOW_MODE_SWITCH`, ép `Windowed = TRUE`, ép `Scaling = DXGI_SCALING_ASPECT_RATIO_STRETCH`.
    Tình trạng: Hoạt động ổn định.

  + [25/10/2026 22:35] Bổ sung các cơ chế trình bày/hiển thị (nhật ký chẩn đoán chi tiết nằm ở mục "Metro Exodus (4A Engine)..." phần 1):
    - **`ALLOW_TEARING`**: thêm `DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING` khi tạo swapchain FLIP **và** ở mỗi `ResizeBuffers` (tự rút cờ + gọi lại nếu DXGI trả `E_INVALIDARG`); `Hooked_Present`/`Present1` thêm `DXGI_PRESENT_ALLOW_TEARING` khi `syncInterval == 0`. Nhờ vậy `Present` không bị DWM khoá vào nhịp composition 60Hz — triệt tiêu hiện tượng FPS tụt đúng 30,0 và cho phép vượt 60.
    - **`DXGI_SCALING_STRETCH`**: thay cho `DXGI_SCALING_ASPECT_RATIO_STRETCH` (giá trị này chỉ hợp lệ cho composition swapchain, với swapchain hwnd bị xử lý như `NONE` nên ảnh vẽ 1:1 ở góc).
    - **`match_display_mode`**: hạ display mode đúng bằng độ phân giải render, theo dõi lại mỗi lần game đổi resolution → `Scale = 1.000`, loại bỏ pass scale mỗi frame của DWM.
    - **Pass-through khi tool thoát**: `IsShutdownRequested()`/`IsHookInert()` + Named Event `HandheldTool_Shutdown` — hook ngừng sửa hành vi game (không tháo MinHook để tránh deadlock luồng render).
    - **Chẩn đoán**: hook `Present`/`Present1` ghi `HRESULT`/`SyncInterval`/`PresentFlags` + nhịp khung hình (`[FPS]`), log `[MSG]`/`[TEARING]`/`[SCALING]`/`[DISPMODE]`/`Overlays=` ra `dxgi_diag.log`.
    Tình trạng: Hoạt động ổn định (đã xác nhận thực chiến 25/10 22:20).

- [x] **Cách ly tín hiệu tay cầm vào game khi mở panel (IPC Gamepad Isolation)**
  + [Initial] Code thực tế: `window_manager.py` khởi tạo Named Event toàn cục `Global\HandheldTool_PanelActive` (SDDL Everyone). `dxgi_hook.cpp` hook hàm `XInputGetState` từ các DLL XInput. Khi panel mở (`SetEvent`), hook tự động xóa sạch dữ liệu nút bấm (`wButtons = 0`) và cần gạt analog trước khi trả về game, ngăn nhân vật trong game bị nhảy/bắn khi duyệt menu panel. Khi panel đóng (`ResetEvent`), quyền điều khiển trả lại nguyên vẹn cho game ngay lập tức.
    Tình trạng: Hoạt động ổn định.

- [x] **Giám sát vòng đời game & Tự động tiêm DLL (GameCompatService)**
  + [Initial] Code thực tế: `backend/src/services/game_compat_service.py` cài đặt `SetWinEventHook` bắt `EVENT_SYSTEM_FOREGROUND` tự động nhận diện game (lọc bỏ tiến trình hệ thống qua `NON_GAME_PROCESSES` và đường dẫn thư viện Steam/Epic/Xbox). Kích hoạt `SeDebugPrivilege` và tiêm `dxgi_hook.dll` vào game 64-bit qua `VirtualAllocEx` + `WriteProcessMemory` + `CreateRemoteThread(LoadLibraryW)`. Tự động dọn cờ tắt FSO trong Registry (`AppCompatFlags\Layers` và `GameConfigStore`) để duy trì Composed Flip mượt mà. Bắt `EVENT_SYSTEM_MINIMIZESTART` tự động khôi phục game (`SW_RESTORE`) nếu game cố thu nhỏ khi panel mở (kèm debounce chống lặp).
    Tình trạng: Hoạt động ổn định.

  + [25/10/2026 22:35] Bổ sung công tắc cấu hình + thu hẹp phạm vi dọn cờ tương thích:
    - `backend/src/services/game_compat_service.py`: đọc `dxgi_hook.enabled` (bỏ qua tiêm DLL) và `dxgi_hook.auto_borderless` (bỏ qua `convert_to_borderless`) từ `config.json` → A/B test không cần quyền admin hay đổi tên tệp trong Program Files.
    - `optimize_fso_registry()`: chỉ gỡ đúng token `DISABLEDXMAXIMIZEDWINDOWEDMODE`; **giữ nguyên** `PERMONITORV2`/`HIGHDPIAWARE` và các shim DPI khác (trước đây xoá sạch cả dấu `~`, làm game bị DPI ảo hoá 1,75× → lệch chuột + mất FPS).
    - `backend/src/overlay/window_manager.py`: tạo thêm Named Event `HandheldTool_Shutdown` để hook trong tiến trình game chuyển sang chế độ pass-through khi tool thoát hẳn.
    Ghi chú còn tồn: hai giá trị toàn cục `GameDVR_DXGIHonorFSEWindowsCompatible=1` và `GameDVR_FSEBehaviorMode=2` vẫn được ghi mỗi lần nhận diện game; cần rà lại xem chúng có cản trở đường "windowed flip" của Windows 11 hay không.
    Tình trạng: Hoạt động ổn định.

- [x] **Metro Exodus (4A Engine) tự hạ FPS xuống 15 khi công cụ đang chạy**
  + [Initial] Hiện tượng: Khi Windows Handheld Tool đang chạy, Metro Exodus (cửa sổ `4A Engine`) tự giới hạn khoảng 15 FPS như thể engine cho rằng ứng dụng đã mất tiêu điểm; đóng panel (chỉ còn cửa sổ xuyên thấu) vẫn bị, tức thủ phạm tồn tại liên tục chứ không phải thao tác mở/đóng panel.
    Bằng chứng đã thu thập (log tại `%LOCALAPPDATA%\WindowsHandheldTools\logs`):
      - `app.log`: không có bất kỳ dòng `[SEAMLESS-1.6] Bắt WM_ACTIVATE` nào → panel chưa bao giờ được activate; chỉ có `WM_MOUSEACTIVATE → MA_NOACTIVATE`.
      - `dxgi_diag.log`: suốt thời gian panel mở (01:53:29-01:53:37, 01:56:06-01:56:21) hook trong tiến trình game ghi `Fg=1` → `GetForegroundWindow()` vẫn trả về HWND của game. Vì vậy tín hiệu "mất focus" không đến từ `WM_ACTIVATE`/`WM_ACTIVATEAPP`.
      - `dxgi_hook.cpp` chưa hook `Present` nên log chưa có nhịp khung hình thực tế để đối chiếu.
      - `config.json` có khóa `dxgi_hook.enabled` nhưng `GameCompatService` không đọc → DLL luôn bị tiêm, không thể A/B test bằng cấu hình.
  + [25/10/2026 02:13] Bổ sung chẩn đoán 1.12 (chỉ đo, không đổi hành vi của hook):
    Code thực tế:
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp`: Hook `IDXGISwapChain::Present` (VMT slot 8) và `IDXGISwapChain1::Present1` (VMT slot 22) bằng MinHook; ghi nhận `HRESULT`, `SyncInterval`, `PresentFlags`, khoảng thời gian giữa 2 lần Present (QPC) và thống kê `ok/occluded/failed`.
      - Ghi dòng `[FPS] fps=.. avgFrame=.. maxFrame=.. hr[ok/occ/fail] lastHr=.. syncInt=.. flags=.. PanelActive=.. Fg=.. SWFlags=.. BufCount=.. Overlays=..` mỗi giây khi FPS < 40 hoặc khi có `DXGI_STATUS_OCCLUDED`/Present lỗi, và mỗi 10 giây ở trạng thái bình thường.
      - `DiagSnapshot` bổ sung `GetGUIThreadInfo` của luồng UI game (`hwndActive`, `hwndFocus`, `hwndCapture`, `hwndMenuOwner`, `flags`) cùng `FgHwnd`, đủ để phân biệt "mất activation" với "mất keyboard focus/capture".
      - `GameSubclassWndProc` ghi log `[MSG]` cho toàn bộ thông điệp kích hoạt/tiêu điểm mà engine thật sự nhận (`WM_ACTIVATE`, `WM_ACTIVATEAPP`, `WM_KILLFOCUS`, `WM_SETFOCUS`, `WM_NCACTIVATE`, `WM_CANCELMODE`, `WM_SHOWWINDOW`, `WM_SIZE`, `WM_SYSCOMMAND`, `WM_ENTERMENULOOP`...), giới hạn 60 dòng/giây.
      - Ghi log `[SWAPCHAIN]` (buffer, `SwapEffect`, `Flags`, `ALLOW_TEARING`), `[DISPMODE]` (`ChangeDisplaySettingsExW` thành công/thất bại) và `[BORDERLESS]` (thời điểm đổi style/vị trí cửa sổ game) để đối chiếu mốc thời gian với lúc FPS tụt.
      - Thêm bộ đếm `Overlays=` quét các cửa sổ `WS_EX_LAYERED | WS_EX_NOACTIVATE` đang hiện diện (kèm PID + rect) để biết panel còn nằm trên màn hình hay không, dù Named Event `PanelActive=0`.
      - `backend/native/dxgi_hook/build.bat`: biên dịch lại thành công `backend/bin/dxgi_hook.dll` (MSVC x64, 45.056 bytes).
    Tình trạng: Đã bổ sung công cụ chẩn đoán trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 02:30] Kết quả đo lần 1 (Metro Exodus Enhanced Edition, 187 mẫu `[FPS]` trong 02:22-02:26):
    Số liệu thực đo:
      - Panel ĐANG mở (`PanelActive=1`): 27 mẫu, FPS trung vị **13,0** (10,9-15,0).
      - Panel ĐÓNG, app còn chạy (`Overlays=1`): 130 mẫu, trung vị **29,9** (6,9-46,3).
      - Đã thoát hẳn app (`Overlays=0`): 29 mẫu, trung vị **24,1** (6,7-46,2).
      - Toàn bộ 187 mẫu: `occ=0`, `fail=0`, `syncInt=0`, `flags=0` → không có `DXGI_STATUS_OCCLUDED`, không có Present lỗi.
    Kết luận: **panel không phải nguyên nhân gây tụt FPS**. Bằng chứng:
      - Tại mọi lần `PANEL_OPEN`, engine vẫn giữ `Fg=1`, `Active=<HWND game>`, `Focus=<HWND game>`, `Capture=0`, và **không có** thông điệp `WM_ACTIVATE`/`WM_ACTIVATEAPP`/`WM_KILLFOCUS` nào được gửi tới cửa sổ game.
      - FPS đã tụt từ 39,4 (02:24:08) xuống 12,7 (02:24:26) **trước khi panel mở lần đầu** (02:24:28), và vẫn giữ 13-14 suốt 13 giây **sau khi panel đóng** (02:24:43-02:24:55).
      - Sau khi thoát hẳn app (`Overlays=0`) FPS vẫn 22-25 → không liên quan tới cửa sổ panel.
    Dạng suy giảm thực tế: 39,4 → 13 trong ~19 giây, giữ phẳng ở 13; sau đó game mất focus 8 giây (02:25:20-02:25:28, `WM_ACTIVATEAPP=0`) rồi lấy lại focus → FPS bùng lên 39,8 rồi lại tụt dần về ~23. Đây là dấu hiệu **throttle công suất/nhiệt (STAPM/thermal)**, không phải mất focus.
    Nguyên nhân khả dĩ: công cụ đã ghi SMU `STAPM=15W / slow=15W / fast=18W` lúc 00:05 (`set_tdp(15)`, `fast_offset=+3`); các giới hạn này nằm trong SMU nên phiên 02:20 không cần set lại. Quạt khởi tạo `balanced`, auto, 50%.
    Code thực tế (chỉ bổ sung đo):
      - `backend/src/bridge/web_bridge.py`: ghi `[TELEMETRY] cpu=..% temp=..C power=..W fast_limit=..W fan=..% fan_auto=.. fan_profile=.. fps=.. game=..` vào `app.log` mỗi 5 giây (`_diag_tick`) để đối chiếu cùng mốc thời gian với các dòng `[FPS]` của `dxgi_diag.log`.
    Tình trạng: Đã bổ sung công cụ chẩn đoán trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định). (Số liệu trên đã được thay thế bằng kết luận ở mốc 03:02 bên dưới.)

  + [25/10/2026 03:02] Chốt nguyên nhân thật: **display mode sync trong `e167952`**, không phải panel/focus/TDP. Đã revert.
    Bằng chứng:
      - `git log -S"ChangeDisplaySettings"` → **chỉ duy nhất commit `e167952`** ("fix amd rsr features", hôm nay) có lời gọi `ChangeDisplaySettingsExW`. Bản `07ac67a` (819 dòng hook) có **0** lời gọi → đó là bản chơi 60 fps, RSR vẫn upscale bằng đường driver.
      - Người dùng xác nhận thực tế: tắt tool nhưng DLL đã tiêm thì vẫn bám trong tiến trình game → display mode bị trả về 1920x1080 nhưng cửa sổ game giữ kích thước 1280x720 → game chỉ hiện **1 góc màn hình**; restart PC (không còn DLL) → game vào fullscreen thật và **mượt**.
      - Đo phiên 35W (174 mẫu `[FPS]`, PID 1988): avg 21,8 fps, 116/174 mẫu < 25 fps, cực đại 51,8 → nâng 15W → 35W **không cải thiện**, nên TDP không phải nút thắt.
      - Phiên 35W: `PanelActive` không tương quan FPS; không có `WM_ACTIVATE`/`WM_ACTIVATEAPP` nào khi panel mở; `occ=0`, `fail=0`.
    Code thực tế:
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp`: xoá toàn bộ `QueryNativeDisplayResolution`, `RestoreNativeDisplayMode`, `ApplyDynamicDisplayMode`, 4 biến `g_uNative*`/`g_bDisplayModeSwitched`, 8 điểm gọi và nhánh `WM_ACTIVATEAPP`/`WM_DESTROY` có đổi display mode. Giữ lại subclass (chỉ siết borderless khi game lấy lại activation) và toàn bộ hook cũ (chuột, XInput, swapchain, fullscreen).
      - `backend/src/services/game_compat_service.py`: đọc `dxgi_hook.enabled` (bỏ qua tiêm DLL) và `dxgi_hook.auto_borderless` (bỏ qua `convert_to_borderless`) từ `config.json` để A/B test không cần quyền admin.
      - `backend/native/dxgi_hook/build.bat`: build lại `backend/bin/dxgi_hook.dll` (MSVC x64, 42.496 bytes); kiểm tra binary không còn chuỗi `ChangeDisplaySettings`.
    Ghi chú: đường RSR trong borderless (nếu cần lại) là ghi cờ `upscaling_use_borderless = TRUE` + `upscaling_target_resolution` vào `gmdb.blb` của AMD (đúng cách đã từng chạy ở mục 24/10 20:05), **không** dùng display mode.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 09:23] Hoàn tất phần còn lại: hook tự tắt khi thoát tool + không xoá cờ DPI của game.
    Code thực tế:
      - `backend/src/overlay/window_manager.py`: tạo Named Event `Global\HandheldTool_Shutdown` (SDDL Everyone) trong `_init_panel_event()` và `SetEvent` trong `cleanup()` trước khi đóng handle.
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp`: thêm `IsShutdownRequested()` (diag thread kiểm tra 1 Hz) và `IsHookInert()` (cờ cache cho đường nóng). Khi event bật: `ForceBorderlessWindow` ngừng can thiệp, `GetCursorMappingParams` trả `false` (thôi ánh xạ chuột), `Hooked_XInputGetState` thôi zero state, `GameSubclassWndProc` forward nguyên xi, diag thread dừng và ghi `[SHUTDOWN]`. **Không** gọi `MH_DisableHook` (rủi ro deadlock khi luồng render đang nằm trong detour) — hook ở lại dưới dạng pass-through.
      - `backend/src/services/game_compat_service.py::optimize_fso_registry`: chỉ gỡ đúng token `DISABLEDXMAXIMIZEDWINDOWEDMODE`, **giữ nguyên** `PERMONITORV2`/`HIGHDPIAWARE` và các shim khác. Trước đây hàm này xoá sạch cả `PERMONITORV2` lẫn dấu `~`, khiến game bị DPI ảo hoá 1,75× (cửa sổ lớn hơn render buffer → lệch chuột + mất hiệu năng).
      - Build lại `backend/bin/dxgi_hook.dll` (MSVC x64, 42.496 bytes): có chuỗi `HandheldTool_Shutdown`/`[SHUTDOWN]`, **không** còn `ChangeDisplaySettings`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 09:41] Chống "khoá nhịp" 60 ↔ 30 fps của cửa sổ Borderless (bật tearing).
    Hiện tượng: Metro Exodus đã về 60 fps nhưng luân phiên từng đợt dài đúng **30,0 fps** (`avgFrame=33,3ms`, `presents=30/s`), xen kẽ các đợt 51-60 fps → cảm giác sụt giật.
    Nguyên nhân kỹ thuật: swapchain flip 2 buffer + `Present(syncInterval=0)` vẫn bị DWM khoá vào nhịp composition 60Hz. Khi frame time chỉ hơn 16,67ms một chút, mọi frame bị đẩy sang vblank kế tiếp → khoá đúng 30 fps (đúng như khi chạy exclusive fullscreen thì mượt, vì không qua composition).
    Code thực tế:
      - `backend/native/dxgi_hook/src/dxgi_hook.h`: thêm `<dxgi1_5.h>` (định nghĩa `DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING`).
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp`: `Hooked_CreateSwapChainForHwnd` thêm `ALLOW_TEARING` cho swapchain **FLIP** (tự tạo lại không tearing nếu driver/OS từ chối → không bao giờ làm hỏng game); `Hooked_Present`/`Hooked_Present1` thêm `DXGI_PRESENT_ALLOW_TEARING` khi `syncInterval == 0`, tự tắt tearing + trình bày lại kiểu cũ nếu DXGI trả lỗi; ghi log `[TEARING]`.
      - Build lại `backend/bin/dxgi_hook.dll` (MSVC x64, 43.520 bytes).
    Đánh đổi: frame time 17-20ms sẽ ra 50-58 fps liên tục (thay vì 60/30 nhảy từng đợt) và có thể thấy tearing nhẹ. Phương án thay thế nếu không thích tearing: ép `BufferCount = 3` (triple buffering, không tearing, chỉ còn judder nhẹ).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 09:58] Sửa lỗi game không phủ kín màn hình (ảnh chỉ chiếm đúng vùng 1280x720).
    Hiện tượng: Sau khi bật tearing, FPS > 60 và rất mượt nhưng hình chỉ nằm trong vùng 1280x720 thay vì phủ 1920x1080.
    Chẩn đoán từ log (PID 15936): cửa sổ game **đã đúng** 1920x1080 (`Window=(0,0,1920,1080)`, `DwmFrame=(0,0,1920,1080)`, `Client=1920x1080`), nhưng backbuffer chỉ 1280x720 (`Scale(Client/Buffer)=1.500`) và ảnh vẽ 1:1 ở góc. Nguyên nhân: hook cũ đổi `DXGI_SCALING_NONE` -> `DXGI_SCALING_ASPECT_RATIO_STRETCH`, nhưng `ASPECT_RATIO_STRETCH` chỉ hợp lệ cho composition swapchain; với swapchain hwnd nó bị xử lý như `NONE` → không phóng to.
    Code thực tế:
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp::Hooked_CreateSwapChainForHwnd`: ép `Scaling = DXGI_SCALING_STRETCH` (0) cho swapchain hwnd để presenter phóng backbuffer phủ kín client area; log `[SCALING]`.
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp::Hooked_ResizeBuffers`: giữ `ALLOW_TEARING` qua mọi lần `ResizeBuffers` (nếu rơi cờ này, `Present(ALLOW_TEARING)` lỗi và game quay lại khoá nhịp 60 ↔ 30 fps).
      - Build lại `backend/bin/dxgi_hook.dll` (MSVC x64, 43.520 bytes).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 10:19] C1: khớp display mode với độ phân giải render (tuỳ chọn, mặc định TẮT).
    Hiện tượng: Sau khi phủ kín màn hình (backbuffer 720p trong cửa sổ 1080p), game khựng 100-900ms (14/29 mẫu > 100ms, đỉnh 935ms) trong khi phiên 1:1 trước đó chỉ có `maxFrame` 15ms. Đổi độ phân giải render trong game lên 1920x1080 thì hết khựng.
    Nguyên nhân: buffer ≠ cửa sổ → DWM không được dùng independent flip, mỗi frame phải chạy pass scale 720p→1080p trong composition; kết hợp tearing (`syncInterval=0`, 2 buffer) làm hàng đợi dồn và `Present` bị chặn. Khi buffer = cửa sổ = màn hình thì không còn pass scale.
    Giải pháp: hạ **display mode** xuống đúng độ phân giải render để game 1:1 với buffer, phần phóng lên tấm nền do scaler phần cứng / AMD RSR đảm nhận (không tốn GPU của game).
    Code thực tế:
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp`: thêm `MatchDisplayModeToBuffer()` (chỉ hạ mode, lưu mode gốc từ registry để chống trường hợp lần chạy trước crash), `RestoreDisplayMode()` gọi ở `WM_DESTROY`, ở nhánh shutdown (Named Event) và trong `ShutdownDxgiHook()`. Hook 6 điểm gọi trước `ForceBorderlessWindow` (swapchain factory + x3 `ResizeBuffers/ResizeTarget/SetFullscreenState`). Bật/tắt bằng Named Event `HandheldTool_MatchDisplayMode` do app tạo.
      - `backend/src/overlay/window_manager.py`: `_init_match_display_mode_event()` tạo event khi `dxgi_hook.match_display_mode = true`, giải phóng trong `cleanup()`.
      - `backend/src/core/config.py` + `backend/config.json`: thêm khoá `dxgi_hook.match_display_mode` (mặc định `false`).
      - Build lại `backend/bin/dxgi_hook.dll` (MSVC x64, 45.056 bytes).
    Đánh đổi: nháy đen ~1s khi vào/thoát game (đổi mode); nếu app bị kill cứng thì mode có thể còn 720p cho tới lần chạy sau (hook tự khôi phục khi game đóng).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 10:45] Người dùng xác nhận hoạt động ổn định — đóng item:
    - `dxgi_hook.match_display_mode` được chuyển mặc định **true** (trước đó false) để bật luôn mà không cần sửa config tay (`backend/config.json`, `config.py`, `window_manager.py`).
    - Kết quả thực tế: game phủ kín màn hình, fps cao và không còn khựng; display mode tự khôi phục khi thoát.
    Tình trạng: Hoạt động ổn định (đã xác nhận thực chiến).

  + [25/10/2026 11:54] Tái phát 30 fps sau khi thêm code sửa TDP — nguyên nhân là tearing bị mất, không phải TDP:
    Chẩn đoán từ log (PID 10248, 11:48): `[DISPMODE] Hạ mode màn hình xuống 1366x768` và `Scale=1.000` (C1 vẫn chạy đúng), nhưng **không có** dòng `[TEARING]`/`[SWAPCHAIN]` nào → hook `CreateSwapChainForHwnd` không chặn được lần tạo swapchain (đua tranh lúc tiêm, timing khởi động của exe mới khác). Hệ quả `g_bTearingSwapChain=false` → `Present(syncInterval=0)` không có `ALLOW_TEARING` → bị khoá nhịp composition 60Hz → game tụt đúng 30 fps (`avgFrame=33,3ms`, `presents=30`). TDP 30-35W không liên quan (SMU đã set đủ, log trả về toàn 0).
    Code thực tế:
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp::Hooked_ResizeBuffers`: luôn thử thêm `DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING` ngay trong lần resize (độc lập với hook tạo swapchain), tự rút cờ + gọi lại nếu DXGI từ chối, và bật `g_bTearingSwapChain` khi thành công. Nhờ vậy tearing không còn phụ thuộc vào việc có chặn được lúc tạo swapchain hay không.
      - Build lại `backend/bin/dxgi_hook.dll` (MSVC x64, 45.056 bytes).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 12:10] Đổi res trong game sang 1280x720 nhưng fps vẫn 22-30 — mode không khớp lại:
    Chẩn đoán từ log (PID 18296, 12:07): tearing **đã bật đúng** (`[TEARING]` cả 2 đường + `flags=0x200`), `[DISPMODE]` hạ mode xuống **1366x768** lúc đầu, nhưng sau khi người dùng đổi game sang 1280x720 thì `Buffer=1280x720` còn `Client/Window=1366x768` → **`Scale=1.067`** → DWM lại phải chạy pass scale mỗi frame → fps tụt 22-30.
    Nguyên nhân: `MatchDisplayModeToBuffer()` có guard một lần (`g_bDisplayModeChanged`) nên sau lần khớp đầu tiên nó **không theo kịp** khi game đổi độ phân giải render.
    Bằng chứng TDP/nhiệt không liên quan (`[TELEMETRY]`): `power=3-6W`, `temp=42-48C`, `fan=50%`, `fast_limit=30W` — máy đang idle mát, không throttle.
    Code thực tế:
      - `backend/native/dxgi_hook/src/dxgi_hook.cpp::MatchDisplayModeToBuffer`: bỏ guard một lần, chỉ so `mode hiện tại` với `buffer` để quyết định — nên mỗi lần game đổi resolution (ResizeBuffers/ResizeTarget/SetFullscreenState) mode sẽ được khớp lại ngay, `Scale` luôn về `1.000`.
      - Build lại `backend/bin/dxgi_hook.dll` (MSVC x64, 45.568 bytes).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 12:31] FPS vẫn thấp dù đã kéo TDP lên 30W — lệnh kéo không tới backend + code TDP ghi đè sai:
    Chẩn đoán từ log (12:17-12:24): **không có dòng `[Bridge] Đặt TDP` nào sau 12:17:43** (lệnh kéo không tới backend) và `[TELEMETRY] fast_limit=15W` suốt phiên. Nguyên nhân kép:
      1. `hardware.tdp.auto = true` → `performance_tab.dart` ẩn slider (`shouldShowSlider: !_tdpAuto`) nên không thể chỉnh TDP từ panel.
      2. `WebBridge._apply_persisted_tdp()` ghi đè **15W** lúc khởi động (đọc `config.hardware.tdp.current = 15`) dù UI báo "Auto", và mỗi lần deploy lại thì `backend/config.json` (15) copy đè lên config đã cài.
    Đối chiếu 2 phiên test gần nhất: 12:07 có **30W nhưng `Scale=1.067`**; 12:17 có **`Scale=1.000` nhưng 15W** — chưa lần nào đúng đồng thời cả hai, nên fps đều thấp.
    Code thực tế:
      - `backend/src/hardware/tdp_service.py`: `set_tdp()` không còn ghi `set_apu_slow_limit` (giới hạn SoC/iGPU, ép xuống bằng STAPM làm GPU bị bóp: 72-85 fps → 26-44 fps ở cùng 15W) và khôi phục burst `fast = watts + 3` (`FAST_BURST_OFFSET_W`). TDP người dùng đặt được lưu ở `%LOCALAPPDATA%\WindowsHandheldTools\tdp_state.json` để deploy không ghi đè.
      - `backend/src/bridge/web_bridge.py`: `_apply_persisted_tdp()` bỏ qua khi `tdp.auto = true`, chỉ áp khi có giá trị người dùng đã lưu; `getInitialState()` trả TDP thực đang áp (`last_set_tdp`) thay vì giá trị trong config.
      - `frontend/lib/ui/tabs/performance_tab.dart`: slider TDP luôn hiển thị; kéo slider/preset tự chuyển sang chế độ thủ công (`tdp.auto = false`); layout gamepad luôn có mục slider.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 22:35] Chốt item: đã xác nhận thực chiến trên 3 tựa game (Metro Exodus EE, Far Cry 5, Dead Island 2):
    Kết quả: cả 3 phủ kín màn hình, RSR hoạt động, FPS cao và không khựng; display mode tự khôi phục khi thoát game.
    Đối chiếu cùng mức 15W: phiên 12:17 được 26-44 FPS (iGPU bị bóp + `Scale=1.067`), phiên 22:20 được 53-77 FPS (Dead Island 2) và 63-64 FPS (Far Cry 5) với công suất trung bình 13,2W.
    Tổng hợp 4 nút thắt đã gỡ trong ngày: (1) `ChangeDisplaySettingsExW` cũ gây lệch DPI 1,75× / FPS 15-30 → revert; (2) thiếu `ALLOW_TEARING` → bị khoá nhịp 60 ↔ 30; (3) buffer ≠ cửa sổ → DWM scale mỗi frame; (4) mô hình TDP sai (`apu_slow` + mất burst + bị ghi đè 15W lúc khởi động) — chi tiết ở mục "Quản lý công suất TDP & Cảm biến phần cứng" phần 3.
    Tình trạng: Hoạt động ổn định (đã xác nhận thực chiến).

- [ ] **Xung đột phần cứng EC & Đồng bộ tọa độ chuột khi render lệch phân giải**
  + [Initial] Code thực tế: Vô hiệu hóa hoàn toàn lệnh ghi mù cổng EC I/O `0x6C / 0x68` trong `FanService` (loại bỏ dứt điểm hiện tượng nghẽn bus phần cứng gây giật lag máy, đơ GPU và Black Screen Kernel-Power Event 41). Đồng bộ tọa độ chuột đa tỉ lệ Client / Buffer: `dxgi_hook.cpp` duy trì hook 4 điểm (`Hooked_GetCursorPos`, `Hooked_SetCursorPos`, `Hooked_GetMessagePos` và ánh xạ `lParam` trong `PeekMessageW`/`GetMessageW`) theo ma trận `Buffer / Client`. `window_manager.py` gọi `ClipCursor(None)` khi mở panel.
    Tình trạng thực tế: Trên *Dead Island 2* và game DirectX chuẩn: Hoạt động hoàn toàn ổn định; Trên *Ready Or Not* (Unreal Engine): **Vẫn chưa khắc phục được** (con trỏ chuột và vùng tương tác hit-test của Slate UI vẫn bị lệch nhau, rê chuột lệch vị trí thì nút mới sáng và thao tác click menu chưa ăn khớp).
  + [25/10/2026 22:35] Quyết định phạm vi: phần lệch chuột **chỉ còn ở Ready Or Not** (Slate UI của Unreal Engine); Metro Exodus EE, Far Cry 5, Dead Island 2 đều chính xác → **tạm hoãn** hạng mục này, không chặn các việc khác. Phần xung đột EC I/O (`0x6C/0x68`) vẫn giữ nguyên trạng thái vô hiệu hoá và ổn định.
    Tình trạng: Tạm hoãn theo quyết định của người dùng (không còn là lỗi chặn tiến độ).

---

## 2. Giao diện bảng điều khiển & Trải nghiệm người dùng (UI / UX & Navigation)

- [x] **Cài đặt bề rộng bảng điều khiển (Panel Width Setting)**
  + [Initial] Code thực tế: Thanh trượt tùy chỉnh bề rộng trên Flutter UI và hàm `update_geometry` trong `backend/src/overlay/window_manager.py`.
    Tình trạng: Đang bị lỗi không hoạt động. Cửa sổ panel không co giãn hay thay đổi kích thước hiển thị theo cài đặt của người dùng do `web_bridge.py` thiếu phát tín hiệu `requestWidthChange`.
  + [23/10/2026 22:28] Sửa lỗi phát tín hiệu đổi kích thước:
    Code thực tế: Bổ sung `self.requestWidthChange.emit(width)` trong `setPanelWidth` tại `backend/src/bridge/web_bridge.py`, kết nối trực tiếp đến hàm `update_geometry` trong `backend/src/overlay/window_manager.py`.
    Tình trạng: Đã sửa xong trong code (Đã hoạt động ổn định).

- [ ] **Điều hướng bảng điều khiển bằng Gamepad (Gamepad Navigation)**
  + [Initial] Code thực tế: `frontend/lib/input/gamepad_service.dart` tiếp nhận và giải mã tín hiệu nút bấm từ tay cầm để duyệt qua các tab và widget trên giao diện Flutter.
    Tình trạng: Còn tồn đọng lỗi. Hiện chỉ điều hướng được bằng cụm nút mũi tên D-Pad bên trái; Joystick bên trái (Left Thumbstick) chưa nhận tín hiệu điều hướng menu.
  + [23/10/2026 22:28] Sửa lỗi ánh xạ Joystick trái sang D-Pad:
    Code thực tế: Bổ sung đọc 2 trục analog `state.Gamepad.sThumbLX` và `sThumbLY` với Deadzone 16000 trong `_poll_loop` tại `backend/src/input/gamepad_service.py`, tự động ánh xạ sang `dpadUp`, `dpadDown`, `dpadLeft`, `dpadRight` kèm cơ chế hold-to-repeat.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 10:55] Tái cấu trúc module hóa QuickPanel & phân tán điều hướng Gamepad vào từng Tab:
    Code thực tế:
      - `frontend/lib/ui/navigation/gamepad_navigable.dart`: Xây dựng mixin `GamepadNavigableMixin` quản lý điều hướng 2D grid, di chuyển focus và auto-scroll dùng chung (DRY) cho tất cả các tab.
      - Xóa bỏ hoàn toàn khối hardcode `_getTabLayout()` (L411-L465), `_handleGamepadA()` và `_adjustFocusedSlider()` trong `quick_panel.dart`. Mỗi tab (`HomeTab`, `PerformanceTab`, `DeviceTab`, `SettingsTab`) tự định nghĩa `navigationLayout` và tự xử lý các thao tác tương tác của riêng mình.
      - Tách logic state và kết nối service của TDP, Fan, RTSS, Brightness, Audio, Touchscreen, Hotkey vào bên trong từng Tab riêng biệt dưới dạng `StatefulWidget`, triệt tiêu hoàn toàn hiện tượng prop-drilling.
      - Tách `frontend/lib/ui/quick_panel/panel_footer.dart`, tinh gọn `quick_panel.dart` từ 1.286 dòng xuống còn 188 dòng đóng vai trò Shell Scaffold.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 11:00] Tinh gọn và quy tụ toàn bộ cụm Quick Panel vào frontend/lib/ui/quick_panel/:
    Code thực tế:
      - Xóa bỏ comment cũ sai lệch về "Dimmed Backdrop", gộp trực tiếp `OverlayScreen` (animation Fade + Slide) và `QuickSettingsPanel` vào một tệp duy nhất: `frontend/lib/ui/quick_panel/quick_panel.dart` (205 dòng).
      - Di chuyển `gamepad_navigable.dart` từ `frontend/lib/ui/navigation/` vào `frontend/lib/ui/quick_panel/gamepad_navigable.dart` để đồng bộ cụm module Quick Panel, xóa bỏ thư mục rỗng `ui/navigation/` và các file wrapper trung gian thừa (`overlay_screen.dart`, `ui/quick_panel.dart`).
      - Cập nhật entrypoint `frontend/lib/main.dart` nạp `OverlayScreen` trực tiếp từ `ui/quick_panel/quick_panel.dart`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 11:31] Tái cấu trúc cấu trúc Tab: Gộp Thiết bị vào Trang chủ & Tách RTSS/OSD thành RTSS Tab riêng:
    Code thực tế:
      - `frontend/lib/ui/tabs/home_tab.dart`: Tích hợp các bộ điều khiển và thanh trượt Độ sáng màn hình, Âm lượng loa và công tắc Cảm ứng màn hình vào ngay bên dưới phần đồng hồ; kết nối listener 2 chiều với Windows; cập nhật navigationLayout và xử lý Gamepad A / Slider.
      - `frontend/lib/ui/tabs/rtss_tab.dart`: Tạo mới tab chuyên biệt cho RTSS và OSD in-game; chuyển toàn bộ logic khóa FPS, bộ điều khiển OSD (Zoom, Position, Layout, Metric Toggles) và thẻ cài đặt tự động RTSS Installer sang tab mới.
      - `frontend/lib/ui/tabs/performance_tab.dart`: Tinh gọn từ 871 dòng xuống còn 203 dòng, loại bỏ toàn bộ code liên quan đến RTSS/OSD, chỉ tập trung vào quản lý công suất TDP và quạt tản nhiệt Fan.
      - `frontend/lib/ui/quick_panel/quick_panel.dart`: Cập nhật 4 tab theo thứ tự mới: 1. Trang chủ, 2. Hiệu năng, 3. RTSS / OSD, 4. Cài đặt; xóa bỏ hoàn toàn tệp thừa `frontend/lib/ui/tabs/device_tab.dart`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

- [ ] **Đóng gói hiển thị biểu tượng Material Icons Offline (Offline Font Assets)**
  + [Initial] Code thực tế: Sử dụng cấu hình mặc định uses-material-design: true của Flutter Web.
    Hiện tượng: Khi thiết bị offline hoặc trình duyệt nhúng QtWebEngine không tải được font từ CDN fonts.gstatic.com, toàn bộ biểu tượng (Icons) bị lỗi biến thành các ô chữ nhật có dấu gạch chéo (Missing Glyph / Tofu Box).
    Tình trạng: Còn tồn đọng lỗi.
  + [24/10/2026 14:03] Khắc phục lỗi thiếu font biểu tượng (Missing Glyph / Tofu Box):
    Code thực tế:
      - frontend/fonts/MaterialIcons-Regular.otf: Đóng gói tệp font Material Icons 1.64 MB trực tiếp vào project từ Flutter SDK cache.
      - frontend/pubspec.yaml: Khai báo font family MaterialIcons trỏ vào asset nội bộ fonts/MaterialIcons-Regular.otf.
      - scripts/deploy/deploy_test.bat: Bổ sung cờ --no-tree-shake-icons vào lệnh flutter build web để ngăn chặn compiler loại bỏ glyph icon trong quá trình tối ưu mã.
      - frontend/build/web/assets/FontManifest.json: Xác nhận tạo thành công mục ánh xạ font offline, trình duyệt nhúng nạp trực tiếp từ máy chủ tĩnh cục bộ mà không cần kết nối internet.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

- [ ] **Biểu tượng ứng dụng và Khay hệ thống (App Icon & System Tray)**
  + [Initial] Code thực tế: Sử dụng biểu tượng Gamepad màu trắng đặt trên nền hình tròn màu xanh (#0067C0).
    Tình trạng: Hoạt động ổn định.
  + [24/10/2026 14:12] Loại bỏ vòng tròn xanh, tinh chỉnh icon Gamepad trong suốt:
    Code thực tế:
      - backend/assets/app_icon.png & app_icon.ico: Loại bỏ hoàn toàn hình tròn nền màu xanh, chỉ giữ hình bóng Gamepad màu trắng sắc nét kèm hiệu ứng bóng mờ viền (subtle drop shadow) và thumbstick chi tiết, nền trong suốt 100%.
      - dist/windows_handheld_tool/assets & _internal/assets: Tự động đồng bộ các tệp icon mới sang thư mục dist.
      - backend/main.py: Cập nhật mã vector SVG trong hàm fallback get_app_icon() đồng bộ loại bỏ hình tròn nền xanh.
      - scripts/generate_app_icon.py: Cung cấp công cụ tái tạo icon vector đa độ phân giải (16x16 đến 256x256).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

---

## 3. Điều chỉnh được TDP, Fan curves

- [x] **Quản lý công suất TDP & Cảm biến phần cứng**
  + [Initial] Code thực tế: `backend/src/hardware/tdp_service.py` nạp driver Ring 0 `WinRing0x64.sys`, can thiệp công suất CPU Ryzen qua `libryzenadj.dll` (STAPM/Fast/Slow) kèm fallback CLI `ryzenadj.exe`. Thu thập telemetry nhiệt độ CPU và mức TDP thực tế, có fallback ước tính nhiệt độ qua % CPU của `psutil`.
    Tình trạng: Cơ chế gán công suất phần cứng: Hoạt động ổn định; Hiển thị telemetry Live TDP: **Còn lỗi** (Dữ liệu Live TDP đang bị trùng khớp với mức cài đặt của user, chưa thả nổi hiển thị đúng mức tiêu thụ TDP thực tế của chip).
  + [23/10/2026 22:50] Sửa lỗi Live TDP bị dính chết vào mức trần cài đặt:
    Code thực tế: Bổ sung đọc `get_socket_power` và `get_stapm_value` trong `backend/src/hardware/tdp_service.py`; xây dựng công thức tính Live TDP thả nổi động theo mức tải CPU (sàn 4.5W khi nghỉ đến mức trần cài đặt khi full tải). Xóa bỏ việc gán đè `_liveTdp` theo thanh trượt trong `frontend/lib/ui/quick_panel.dart`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 10:15] Phát hiện lỗi LiveTDP bị kẹt cố định tại 4W:
    Code thực tế: `backend/src/hardware/tdp_service.py` hàm fallback tính `idle_tdp = 4.5`, kết hợp `round()` trong `system_telemetry.py` làm tròn theo chuẩn số chẵn thành 4. Khi driver Ring 0 chưa nạp được số đo phần cứng trực tiếp, LiveTDP bị kẹt cứng ở 4W trên mọi thiết bị.
    Hiện tượng: LiveTDP hiển thị 4W trên mọi thiết bị, không phản ánh đúng công suất APU thực tế.
    Tình trạng: Còn tồn đọng lỗi.
  + [24/10/2026 10:30] Sửa lỗi LiveTDP và bổ sung cảnh báo khi WinRing0 bị chặn bởi HVCI:
    Code thực tế:
      - `backend/src/hardware/tdp_service.py`: Xóa bỏ hoàn toàn công thức fallback fake 4.5W. Khi driver WinRing0 bị Windows 11 Memory Integrity (HVCI) chặn hoặc không khởi tạo được SMU, hệ thống ghi nhận cờ `is_hvci_blocked = True` và trả về `(temp, None, fast)`.
      - `backend/src/services/system_telemetry.py`: Truyền `live_tdp: None` khi không có phần cứng, bổ sung `is_tdp_hardware_active` và `is_hvci_blocked` vào telemetry snapshot gửi lên UI.
      - `frontend/lib/services/system_telemetry_service.dart` & `frontend/lib/services/bridge_service.dart`: Chuyển `liveTdp` sang kiểu `int?` nullable, parse các cờ trạng thái HVCI.
      - `frontend/lib/hardware/tdp_service.dart`: `getLiveTdp()` trả về `null` khi driver không hoạt động; cung cấp `isHardwareActive()` và `isHvciBlocked()`.
      - `frontend/lib/ui/widgets/setting_slider.dart`: Thêm cờ `isWarning` và `warningTooltip`. Khi driver bị chặn, thanh trượt hiển thị badge `!` màu vàng cam kế bên mục tiêu kèm tooltip giải thích, không hiển thị số fake.
      - `frontend/lib/ui/tabs/performance_tab.dart`: Kết nối trạng thái cảnh báo HVCI vào `SettingSlider` TDP.
      - `frontend/lib/ui/tabs/home_tab.dart`: Khi `liveTdp == null` do bị chặn bởi HVCI, hiển thị nhãn `"Tắt HVCI !"`.
      - `frontend/lib/ui/tabs/settings_tab.dart`: Thẻ chẩn đoán `RyzenAdj TDP Driver` hiển thị đúng trạng thái cảnh báo màu cam với icon `warning_amber_rounded` và thông báo `"Bị chặn bởi Memory Integrity (HVCI) - Cần tắt HVCI"` thay vì hiển thị xanh lá.
      - `frontend/lib/hardware/rtss_osd_formatter.dart`: Bỏ qua hiển thị TDP trên màn hình OSD khi `liveTdp == null` để tránh hiển thị số đo giả lập.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [24/10/2026 21:30] Khắc phục lỗi nạp Driver WinRing0 và xử lý giá trị NaN của cảm biến TDP/Nhiệt độ:
    Hiện tượng: Cả Quick Panel và RTSS OSD đều không hiển thị được TDP và nhiệt độ CPU thực tế.
    Nguyên nhân:
      - `libryzenadj.dll` gọi `WinRing0x64.dll` tìm tệp driver `WinRing0x64.sys` tại CWD (thư mục làm việc hiện tại). Khi ứng dụng chạy từ thư mục gốc, driver không tìm thấy dẫn tới `init_table` thất bại với mã lỗi `-5` (`Unable to get memory access`).
      - Trên APU AMD Rembrandt/Phoenix di động, `get_socket_power()` trả về `nan`. Trong Python, phép so sánh `nan <= 0.0` luôn trả về `False` khiến code bỏ qua hàm đọc công suất thực `get_stapm_value()`, sau đó `nan > 0.0` cũng trả về `False` dẫn đến telemetry luôn trả về `None`.
      - Hàm nhiệt độ `get_tctl_temp()` trả về `100.0` (ngưỡng TJMax) thay vì nhiệt độ thực tế.
    Code thực tế:
      - `backend/src/hardware/tdp_service.py`: Cập nhật `_load_library` tự động chuyển đổi ngữ cảnh thư mục sang `bin/` chứa driver `WinRing0x64.sys` trong quá trình khởi tạo `init_ryzenadj` và `init_table`. Nhập khẩu `math` và sử dụng `math.isnan()` để bắt trường hợp `nan` trên vi xử lý di động; tự động fallback đọc công suất thực tế qua `get_stapm_value()`. Đọc nhiệt độ CPU tức thời qua `get_tctl_temp_value()`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 22:15] Khắc phục triệt để lỗi xung đột nạp driver WinRing0, báo sai trạng thái HVCI và khôi phục telemetry TDP/Nhiệt độ trên Panel và OSD:
    Hiện tượng: Cả Quick Panel và RTSS OSD đều không hiển thị được TDP và nhiệt độ CPU thực tế; SettingSlider TDP hiển thị chấm than cảnh báo màu cam; FanCurveGraph hiển thị chữ "HVCI (!)" dù người dùng đã tắt hoàn toàn Memory Integrity.
    Nguyên nhân:
      - Trong `backend/src/hardware/tdp_service.py`, hàm `_load_library` nạp thử `WinRing0x64.dll` độc lập và gọi `InitializeOls()` khi thư mục làm việc (CWD) là thư mục gốc ứng dụng thay vì `bin/`. Do không tìm thấy file driver `WinRing0x64.sys` tại CWD, `GetDllStatus()` trả về mã lỗi 2 (`OLS_DLL_DRIVER_NOT_LOADED`). Code cũ quy chụp cứng `if status == 2: self.is_hvci_blocked = True`, dẫn đến việc báo sai trạng thái HVCI bị chặn.
      - Việc thăm dò driver trước này gây khóa/xung đột handle, khiến `libryzenadj.dll` khi nạp sau đó gọi `init_table()` bị thất bại với mã lỗi `-5` (`Unable to get memory access`), làm mất toàn bộ dữ liệu telemetry CPU Temp và Live TDP.
      - Trong `frontend/lib/ui/widgets/fan_curve_graph.dart` (dòng 90), chuỗi nhãn bị hardcode: `liveTemp != null ? "$liveTemp°C • $liveFan%" : "HVCI (!) • $liveFan%"`, dẫn đến bất kỳ khi nào `liveTemp == null` thì đều in ra nhãn cảnh báo `HVCI (!)`.
    Code thực tế:
      - `backend/src/hardware/tdp_service.py`: Loại bỏ hoàn toàn khối nạp thăm dò `WinRing0x64.dll` đơn lẻ. Đổi ngữ cảnh thư mục sang `bin/` trước khi nạp `libryzenadj.dll` và khôi phục lại trong khối `finally`. Xác thực kết quả `init_table()`: nếu trả về 0 thì gán `is_active = True`, `is_hvci_blocked = False`. Xử lý an toàn `math.isnan()` và fallback sang `get_stapm_value()`.
      - `frontend/lib/ui/widgets/fan_curve_graph.dart`: Bổ sung thuộc tính `final bool isHvciBlocked`. Cập nhật logic: chỉ hiển thị `"HVCI (!) • $liveFan%"` khi `isHvciBlocked == true`, ngược lại hiển thị `"--°C • $liveFan%"`.
      - `frontend/lib/ui/tabs/performance_tab.dart`: Truyền giá trị `isHvciBlocked: _tdpCtrl.isHvciBlocked()` vào `FanCurveGraph`.
      - Biên dịch lại Flutter Web và đóng gói PyInstaller vào thư mục `dist/windows_handheld_tool`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 23:55] Phân tách độc lập quyền điều khiển TDP và trạng thái PMTable, triệt tiêu báo lỗi giả HVCI:
    Hiện tượng: Người dùng đã tắt Memory Integrity trong Windows Security nhưng giao diện Quick Panel vẫn hiển thị chấm than cảnh báo màu cam [ ! ] trên thanh TDP và hiện banner "Memory Integrity (HVCI) đang chặn đọc nhiệt độ phần cứng".
    Nguyên nhân:
      - Trong `backend/src/hardware/tdp_service.py`, hàm `init_ryzenadj()` đã nạp driver thành công và trả về `ry_handle` hợp lệ (HVCI không chặn). Tuy nhiên hàm đọc bảng cảm biến `init_table()` trả về `-5` do định dạng PMTable trên kiến trúc Rembrandt/Phoenix 6800U không khớp bảng mẫu của thư viện.
      - Code cũ đã quy kết sai: khi `init_table != 0` liền gán `is_hvci_blocked = True` và `is_active = False`. Theo tài liệu RyzenAdj, mã lỗi `-5` của PMTable chỉ ảnh hưởng tới việc đọc cảm biến monitoring, hoàn toàn KHÔNG ảnh hưởng đến việc can thiệp giới hạn công suất TDP (STAPM/Fast/Slow) qua SMU mailbox.
    Code thực tế:
      - `backend/src/hardware/tdp_service.py`: Khi `self.ry_handle` hợp lệ, xác định ngay `self.is_active = True` và `self.is_hvci_blocked = False`. Không biến lỗi `-5` của `init_table` thành lỗi chặn HVCI.
      - `backend/src/services/system_telemetry.py`: Tối ưu cơ chế fallback: khi `self.tdp_service.is_active` hoạt động, nếu cảm biến PMTable chưa đọc được công suất thực tế thì báo cáo mức TDP danh định mục tiêu (`last_set_tdp`), và ước tính nhiệt độ CPU theo tải CPU thực tế để đồ thị Fan Curve tiếp tục hoạt động mượt mà.
      - Đóng gói hoàn tất bản build vào thư mục `dist/windows_handheld_tool`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [25/10/2026 00:20] Tích hợp bộ đếm phần cứng Windows RAPL Energy Meter đo Live TDP thực tế tức thời:
    Hiện tượng: Live TDP trên Quick Panel và OSD không biến thiên theo tải thực tế mà bị kẹt trùng khớp với mức cài đặt trần (Max TDP) của người dùng do rơi vào fallback của PMTable.
    Nguyên nhân:
      - Các hàm đọc công suất PMTable (`get_socket_power`, `get_stapm_value`) của RyzenAdj bị vô hiệu khi `init_table: -5`, khiến hệ thống không có dữ liệu watt thực tế từ cảm biến và phải dùng tạm giá trị `last_set_tdp` của thanh trượt.
    Code thực tế:
      - `backend/src/hardware/rapl_service.py`: Xây dựng module dịch vụ mới kết nối trực tiếp bộ đếm hiệu năng kernel Windows: `\Energy Meter(rapl_package0_pkg)\power` qua giao diện `win32pdh`. Đo trực tiếp công suất tiêu thụ thực tế của APU package ở mức phần cứng (đơn vị milliwatt) độc lập hoàn toàn với PMTable hay driver bên thứ ba.
      - `backend/src/hardware/tdp_service.py`: Nhập khẩu và tích hợp `RaplService`, ưu tiên lấy công suất tức thời từ bộ đếm RAPL trong `get_telemetry()`.
      - `backend/src/services/system_telemetry.py`: Truyền trực tiếp số đo công suất thực tế tức thời lên Quick Panel và RTSS OSD; loại bỏ tình trạng bị kẹt vào mức trần cài đặt.
      - Kiểm thử thực tế xác nhận công suất biến thiên tự nhiên: 3.3W - 5.0W khi nghỉ, 8W - 15W+ khi tải game.
      - Đóng gói PyInstaller và đồng bộ toàn diện vào `dist/windows_handheld_tool`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [25/10/2026 11:05] Khắc phục lỗi Live TDP vượt quá giới hạn TDP đã cài & mất giới hạn sau khởi động lại:
    Hiện tượng: Người dùng chỉnh giới hạn TDP (ví dụ cài 10W) nhưng Live TDP trên Panel/OSD vẫn hiển thị 13–15W khi tải, tức thiết bị không bị kẹp đúng mức đã cài; sau khi khởi động lại ứng dụng/máy, giới hạn cũ bị mất về mặc định BIOS.
    Nguyên nhân:
      - `set_tdp()` ghi Fast PPT = `watts + fast_offset(3)` khiến khi cài 10W thì Fast PPT = 13W. Vì RAPL đo công suất tức thời, APU boost ngắn hạn theo Fast PPT nhảy lên đúng `giới hạn + 3W`, gây hiểu nhầm "không giới hạn".
      - Trên APU Rembrandt/Phoenix, giới hạn duy trì thực tế có thể do EC dùng "APU SLOW" (`set_apu_slow_limit`, lệnh SMU `0x23`) thay vì STAPM; code cũ chưa ghi tham số này.
      - Không có cơ chế re-apply định kỳ nên EC/firmware có thể ghi đè ngược giới hạn; và app không re-apply TDP lúc khởi động nên sau reboot SMU reset về mặc định BIOS.
      - `get_core_power` khai báo sai signature (thiếu tham số core index); `fast_limit` trong telemetry là số giả `last_set_tdp + 3` do `init_table=-5` khiến `get_fast_limit()` trả NAN.
    Code thực tế:
      - `backend/src/hardware/tdp_service.py`: Bỏ `fast_offset`, áp giới hạn phẳng `STAPM = Fast PPT = Slow PPT = APU SLOW = watts`. Tách hàm `_invoke_set` (log mã SMU trả về 0/-1/-3/-4) và `_write_limits_dll` (DRY, kèm `threading.Lock`). Bổ sung luồng nền `_reapply_worker` ghi lại giới hạn mỗi 5 giây chống EC ghi đè. Sửa signature `get_core_power` và fallback `fast_limit` (bỏ `+3`).
      - `backend/src/bridge/web_bridge.py`: Bổ sung `_apply_persisted_tdp()` gọi ngay sau khi nạp driver để re-apply TDP đã lưu lúc khởi động.
      - `backend/src/services/system_telemetry.py`: Chuẩn hóa `fast_limit = round(fast_limit)` (bỏ hardcode fallback 18).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [25/10/2026 22:35] Đảo lại mô hình giới hạn công suất (bản 11:05 gây tụt FPS) + tách trạng thái Auto:
    Hiện tượng: Sau khi áp "giới hạn phẳng" (mốc 11:05), Metro Exodus ở **cùng mức 15W** tụt từ 72-85 FPS xuống 26-44 FPS; đồng thời kéo slider TDP không có tác dụng và app tự kẹp 15W mỗi lần khởi động.
    Nguyên nhân:
      - `set_apu_slow_limit = watts` là giới hạn ngân sách **SoC/iGPU**: ép nó bằng STAPM làm iGPU bị bóp trong khi gói CPU vẫn bung (log ghi nhận `power` tới 28W dù "đặt 15W") → máy vẫn ăn điện nhưng FPS thấp.
      - `fast = watts` (bỏ `+3W`) làm mất headroom burst → frame nặng tụt ngay.
      - `_apply_persisted_tdp()` đọc `config.hardware.tdp.current` (mặc định 15, bị mỗi lần deploy ghi đè) nên mở app là kẹp về 15W; cộng thêm `tdp.auto = true` làm slider bị ẩn nên không thể nâng lại.
    Code thực tế:
      - `backend/src/hardware/tdp_service.py`: `_write_limits_dll` chỉ ghi `stapm = slow = target`, `fast = target + FAST_BURST_OFFSET_W (3)`, **không** ghi `set_apu_slow_limit`. Thêm `_state_path/_load_persisted_tdp/_save_persisted_tdp` lưu TDP vào `%LOCALAPPDATA%\WindowsHandheldTools\tdp_state.json`; `__init__` nạp lại giá trị này (chưa có thì đọc STAPM hiện tại từ SMU) để UI hiển thị đúng mức đang áp.
      - `backend/src/bridge/web_bridge.py`: `_apply_persisted_tdp()` bỏ qua khi `tdp.auto = true` và chỉ áp giá trị người dùng đã lưu; `getInitialState()` trả `last_set_tdp` thay vì giá trị trong config.
      - `frontend/lib/ui/tabs/performance_tab.dart`: slider TDP luôn hiển thị; kéo slider/preset tự đặt `tdp.auto = false`; `navigationLayout` luôn có mục slider.
    Ghi chú hành vi (kiểm chứng bằng 462 mẫu telemetry khi chơi game): "TDP nhảy cao hơn mức đặt" là **bình thường** — `power` là công suất package tức thời (RAPL, cửa sổ ~1 giây), còn trần SMU là **trung bình STAPM** + burst Fast PPT (+3W). Tại mức 15W: trung bình 13,2W, đỉnh 16-18W trong vài giây. Quyết định **không** thêm hard-cap (`fast = stapm`) để giữ FPS.
    Tình trạng: Hoạt động ổn định (đã xác nhận thực chiến 25/10 22:20).

- [ ] **Điều khiển quạt tản nhiệt (Fan Control)**
  + [Initial] Code thực tế: `backend/src/hardware/fan_service.py` điều khiển quạt ASUS ROG Ally / Ally X qua giao diện WMI (`AsusAtkWmi_WMNB`). Luồng chạy ngầm tự động điều tốc quạt (Auto Fan Curve) chu kỳ 2 giây dựa trên bảng mốc nhiệt độ. Đã ngắt lệnh can thiệp cổng EC I/O trực tiếp (`0x6C/0x68`) để đảm bảo an toàn phần cứng.
    Tình trạng: Cơ chế điều tốc Auto và Manual slider: Hoạt động ổn định; Hiển thị telemetry Live Fan: **Còn lỗi** (Dữ liệu Live Fan đang bị trùng với giá trị cài đặt của user, chưa hiển thị thả nổi tốc độ quạt thực tế); Tùy biến đồ thị Fan Curve: Chưa có widget giao diện trên UI Flutter để người dùng kéo thả, tùy biến trực tiếp từng điểm mốc trên đồ thị Fan Curve.
  + [23/10/2026 22:50] Sửa lỗi Live Fan bị gán đè theo giá trị thanh trượt:
    Code thực tế: Sửa logic trong `frontend/lib/ui/quick_panel.dart`, biến `_liveFan` luôn cập nhật trực tiếp từ `_telemetryData.liveFan`, loại bỏ triệt để việc gán đè `_liveFan = _fan` khi chuyển chế độ hoặc khi người dùng kéo thanh trượt.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [24/10/2026 12:50] Triển khai hệ thống Fan Curves toàn diện & Xóa bỏ triệt để mã nguồn chết:
    Code thực tế:
      - `backend/src/hardware/fan_service.py`: Xóa bỏ hoàn toàn hàm chết `_apply_ec_io`, loại bỏ phụ thuộc `inpoutx64.dll` theo đúng nguyên tắc Cấm Backward Compatibility. Tích hợp 3 Profile Fan Curve tối ưu (`quiet`, `balanced`, `cool`) và 1 Profile `custom` lưu trong `config.json`. Bổ sung bộ lọc trễ nhiệt độ Hysteresis 3°C và cơ chế Rate-limit an toàn (tối đa 1 lệnh/3s) trong luồng nền `_fan_curve_worker`.
      - `backend/src/bridge/web_bridge.py` & `ws_server.py`: Bổ sung API `setFanCurve(profile, curve)`, truyền trạng thái `fan_profile` và `fan_curve` qua WebSocket IPC.
      - `frontend/lib/services/bridge_service.dart` & `fan_service.dart`: Bổ sung ValueNotifier `fanProfile` và `fanCurve`, API `setFanCurve(profile, curve)`.
      - `frontend/lib/ui/widgets/fan_curve_graph.dart`: Xây dựng widget biểu đồ CustomPainter hiển thị đồ thị đường cong spline, các điểm mốc nhiệt độ, và Live Indicator Dot (chấm chỉ báo thời gian thực) chuyển động theo nhiệt độ và tốc độ quạt hiện tại.
      - `frontend/lib/ui/tabs/performance_tab.dart`: Tích hợp bộ chọn `PresetSelector` (Yên tĩnh, Cân bằng, Mát lạnh, Tùy chỉnh) và biểu đồ `FanCurveGraph`. Hỗ trợ điều hướng Gamepad (D-pad Trái/Phải chọn điểm mốc, Lên/Xuống chỉnh % tốc độ quạt).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 13:02] Khắc phục lỗi TypeError int() khi nạp cấu hình FanService:
    Code thực tế:
      - `backend/src/core/config.py`: Nâng cấp hàm `get()` hỗ trợ linh hoạt cả dot-notation (`"hardware.fan.current"`) và positional fallback (`get("a.b", fallback)`), tự động mở rộng các chuỗi phân cấp có dấu chấm thành danh sách keys. Bổ sung giá trị cấu hình mặc định cho `profile` ("balanced") và `custom_curve` trong `DEFAULT_CONFIG`.
      - `backend/src/hardware/fan_service.py`: Chuẩn hóa các lệnh gọi đọc cấu hình sang `self.config.get("hardware", "fan", "current", default=50)`, loại bỏ nguy cơ ném lỗi `TypeError` khi nạp giá trị số nguyên lúc khởi động ứng dụng.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 13:26] Triệt tiêu nhiệt độ giả lập, cảnh báo HVCI và chuẩn hóa Logic Chế độ Quạt (Auto vs Manual Curves):
    Code thực tế:
      - `backend/src/hardware/tdp_service.py`: Xóa bỏ hoàn toàn công thức ước lượng nhiệt độ giả qua % CPU (psutil). Khi driver phần cứng bị chặn bởi HVCI hoặc không đọc được cảm biến, trả về `cpu_temp = None` để kích hoạt giao diện cảnh báo thay vì số ảo.
      - `backend/src/services/system_telemetry.py`: Trả về `cpu_temp = None` khi không có cảm biến thực tế.
      - `backend/src/hardware/fan_service.py`: Chuẩn hóa logic chế độ quạt theo thiết bị Handheld: Auto (`is_auto=True`) giao toàn quyền cho BIOS / EC phần cứng tự vận hành mà không can thiệp đè lệnh; Manual (`is_auto=False`) kích hoạt luồng `_fan_curve_worker` điều tốc theo Fan Curves đã chọn. Tự động đồng bộ ngay tốc độ quạt chu kỳ đầu tiên. Xóa bỏ hoàn toàn hàm khóa cứng tốc độ quạt một mức `set_speed`.
      - `backend/src/bridge/web_bridge.py` & `ws_server.py`: Cập nhật slot `setFan` và `setFanAuto`.
      - `frontend/lib/services/system_telemetry_service.dart` & `bridge_service.dart` & `tdp_service.dart`: Đổi `cpuTemp` sang kiểu `int?` nullable, loại bỏ hoàn toàn các fallback số fake 40°C hay 45°C.
      - `frontend/lib/ui/widgets/fan_curve_graph.dart`: Hỗ trợ `liveTemp` nullable. Khi bị chặn bởi HVCI, hiển thị badge cảnh báo màu cam `HVCI (!) • liveFan%` và không vẽ chấm trắng giả lơ lửng trên đồ thị.
      - `frontend/lib/ui/tabs/performance_tab.dart`: Đổi ToggleCard Quạt: Bật = Do BIOS / Phần cứng tự điều khiển; Tắt = Tùy biến theo Fan Curve. Khi tắt (Manual), hiển thị PresetSelector và FanCurveGraph kèm Banner cảnh báo nếu HVCI đang bật. Khi bật (Auto), hiển thị thẻ trạng thái bảo vệ an toàn của BIOS. Xóa bỏ hoàn toàn thanh trượt Slider khóa cứng tốc độ quạt. Cập nhật navigationLayout và phím bấm Gamepad tương ứng.
      - `scripts/run.bat`: Bổ sung nhãn `:CLEAN_PREVIOUS_INSTANCE` tự động dọn dẹp tiến trình cũ chạy ngầm trước khi nạp ứng dụng.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 13:37] Khắc phục lỗi Flutter Web treo trắng màn hình & Chuẩn hóa tiến trình Dev Hot Reload:
    Code thực tế:
      - `frontend/lib/services/bridge_service.dart`: Bắt lỗi an toàn trên `_channel!.ready` bằng `.catchError(...)`, triệt tiêu hoàn toàn ngoại lệ `Uncaught (in promise) WebSocketChannelException` trong microtask loop của Dart Web SDK khi backend chưa kịp bắt tay WebSocket, giúp Flutter Web render giao diện bình thường và tự động retry kết nối sau 2 giây.
      - `scripts/run.bat`: Thay thế cơ chế thăm dò cổng socket sớm bằng kiểm tra HTTP GET thực tế (`http://127.0.0.1:5173`) trả về mã 200 OK. Đảm bảo backend Python chỉ nạp sau khi máy chủ Flutter Web đã biên dịch hoàn tất toàn bộ 530 module Javascript.
      - `backend/src/overlay/quick_panel.py`: Bổ sung cơ chế tự động thử nạp lại (`reload()`) sau 1.5 giây trong `_on_page_load_finished` nếu ở chế độ dev mà trang web nạp không thành công (`ok == False`).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 13:49] Triệt tiêu hiện tượng Transparent Layer (Giao diện tàng hình) trong Dev Hot Reload:
    Code thực tế:
      - `frontend/lib/services/overlay_controller.dart`: Khởi tạo `_isVisible = true` mặc định, chấm dứt hiện tượng UI tự tàng hình trước khi nhận gói tin WebSocket.
      - `frontend/lib/ui/quick_panel/quick_panel.dart`: Khởi tạo `_animController` với `value: 1.0` (Opacity = 1.0), loại bỏ Race Condition khi gói tin `visibility: true` bị gửi trượt trong lúc Flutter Web đang compile DDC. Đảm bảo toàn bộ Tab Bar và thẻ cấu hình hiển thị ngay khi trang web tải xong.
      - `frontend/build/web`: Biên dịch lại bản build tĩnh bằng `flutter build web --release --pwa-strategy=none` để đồng bộ toàn diện.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 14:20] Loại bỏ hoàn toàn AnimationController & Transition thừa thãi, sửa triệt để lỗi mục 2 run.bat:
    Code thực tế:
      - frontend/lib/ui/quick_panel/quick_panel.dart: Xóa bỏ hoàn toàn SingleTickerProviderStateMixin, _animController, _fadeAnim, _slideAnim, FadeTransition, SlideTransition, IgnorePointer(ignoring: !isVisible) và các callback onAnimateShow/Hide theo đúng nguyên tắc DRY, SoC và Cấm Backward Compatibility. Giao diện Flutter chỉ cần render Scaffold trực tiếp.
      - frontend/lib/services/overlay_controller.dart: Xóa bỏ các callback animation thừa thãi (onAnimateShow, onAnimateHide). Trách nhiệm hiển thị, kích thước khung viền Side-Dock và cờ xuyên thấu WS_EX_TRANSPARENT (Click-through 100%) khi đóng đã được WindowManager Win32 đảm trách hoàn toàn.
      - frontend/build/web: Biên dịch lại thành công toàn bộ bản build web tĩnh (flutter build web), flutter analyze đạt 0 issues.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
---

## 4. Hiển thị OSD thông số in-game qua RivaTuner (RTSS Overlay)

- [ ] **Quản lý tiến trình & Kết nối bộ nhớ chia sẻ RTSS**
  + [Initial] Code thực tế: `backend/src/hardware/rtss_service.py` tự động quét registry để khởi chạy ngầm `RTSS.exe`, cấu hình file profile `Global` (`EnableOSD=1`), kết nối ánh xạ bộ nhớ Win32 `RTSSSharedMemoryV2`.
    Tình trạng: Hoạt động ổn định.
  + [24/10/2026 10:15] Phát hiện thiếu cơ chế tự động cài đặt RTSS khi chạy run.bat:
    Code thực tế: `scripts/run.bat` và `frontend/lib/services/rtss_installer_service.dart` chưa có quy trình kiểm tra và tự động cài đặt RTSS trên máy mới.
    Hiện tượng: Chưa tự động cài RTSS trên các máy chưa có khi chạy `scripts/run.bat`. Trên các máy chưa cài đặt sẵn RTSS, ứng dụng khởi chạy sẽ không kích hoạt được OSD và không thể đo FPS / khóa FPS.
    Tình trạng: Còn tồn đọng lỗi.
  + [24/10/2026 10:30] Tự động cài đặt RTSS khi chạy run.bat và trong ứng dụng:
    Code thực tế:
      - `scripts/run.bat`: Bổ sung đoạn mã `:ENSURE_RTSS` tự động quét sự hiện diện của `RTSS.exe` trong `%ProgramFiles(x86)%` và `%ProgramFiles%`. Nếu chưa có, tự động cài đặt ngầm qua winget (`Guru3D.RTSS`) kèm fallback thực thi installer qua backend. Tích hợp tiền trạm trước khi chạy các lệnh 1 (Gaming Overlay), 2 (Dev Hot Reload), 4 (Deploy).
      - `backend/src/hardware/rtss_service.py`: Bổ sung hàm `install_rtss_silent()` hỗ trợ cài đặt ngầm bằng winget hoặc tải silent installer từ mirror và chạy `/S`.
      - `backend/src/bridge/web_bridge.py` & `backend/src/bridge/ws_server.py`: Thêm slot `installRtss` tiếp nhận yêu cầu cài đặt từ frontend qua QWebChannel / WebSocket.
      - `frontend/lib/services/bridge_service.dart` & `frontend/lib/services/rtss_installer_service.dart`: Kết nối nút bấm cài đặt trực tiếp trên tab Performance đến backend.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 11:05] Chuẩn hóa toàn bộ nội dung scripts/run.bat sang tiếng Anh:
    Code thực tế: Cập nhật menu lựa chọn, cảnh báo kiểm tra RTSS và thông báo tiến trình khởi chạy trong `scripts/run.bat` sang 100% tiếng Anh (English).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 11:08] Sửa lỗi khởi chạy tùy chọn [2] (Dev Hot Reload) trong scripts/run.bat:
    Code thực tế: Sử dụng cờ `/D` của lệnh `start` và `cmd /k` để loại bỏ lỗi lồng dấu ngoặc kép và giữ cửa sổ log Flutter luôn mở; bổ sung vòng lặp kiểm tra kết nối TCP cổng 5173 bằng socket Python, tự động chờ Flutter Web Server sẵn sàng trước khi nạp ứng dụng backend.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [24/10/2026 20:35] Khắc phục lỗi RTSS OSD vẽ đè lên bề mặt Quick Panel:
    Hiện tượng: RTSS OSD hiển thị đè lên Quick Panel do nhân giao diện Chromium (QWebEngineView / ANGLE D3D11) bị RTSS quét và tự động inject hook D3D11 khi Global Profile bật EnableOSD=1.
    Code thực tế:
      - `backend/src/hardware/rtss_service.py`: Tái cấu trúc hàm `_ensure_rtss_profiles()`. Tự động tạo hồ sơ loại trừ chuyên biệt (`windows_handheld_tool.exe`, `QtWebEngineProcess.exe`, `python.exe`, `pythonw.exe` cùng các biến thể `.cfg`) trong thư mục `Profiles\` của RTSS với `[Hooking] EnableHooking=0` và `[OSD] EnableOSD=0`. Đồng thời qua API `RTSSHooks64.dll`, thiết lập `AppDetectionLevel=0`, `EnableHooking=0`, `EnableOSD=0` và gọi `UpdateProfiles()` để RTSS giải phóng hook khỏi giao diện Quick Panel ngay lập tức. Cập nhật `_IGNORED_APPS` bổ sung `qtwebengineprocess.exe` và `pythonw.exe`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
- [ ] **Bộ đếm khung hình in-game (FPS Counter)**
  + [Initial] Code thực tế: Đọc số liệu FPS từ bộ nhớ chia sẻ `RTSSSharedMemoryV2` và định dạng đưa vào chuỗi OSD.
    Tình trạng: Tưởng như đã hoàn thành.
  + [23/10/2026 23:00] Phát hiện lỗi FPS bị khóa cứng:
    Code thực tế: Cần kiểm tra lại cấu trúc đọc `AppEntries` trong `RTSSSharedMemoryV2` tại `backend/src/hardware/rtss_service.py`.
    Hiện tượng: FPS counter trong RTSS chưa hoạt động thực tế, đang bị khóa cứng cố định tại số 60 chứ không hiển thị đúng với giá trị FPS thực tế của game.
    Tình trạng: Còn tồn đọng lỗi.
  + [23/10/2026 23:18] Khắc phục lỗi hardcode và tích hợp đọc AppEntries:
    Code thực tế:
      - `backend/src/hardware/rtss_service.py`: Mở rộng kích thước map bộ nhớ chia sẻ lên 5.57 MB bao phủ mảng 256 `AppEntries` (offset 2,396,256). Bổ sung hàm `get_active_game_and_fps()` quét tiến trình game 3D thực tế, đọc thời gian vi mô `dwFrameTime` tính instantaneous FPS (`1000000.0 / dwFrameTime`) và trích xuất tên file thực thi `szName`.
      - `backend/src/services/system_telemetry.py`: Tích hợp `live_fps` và `active_game` vào snapshot telemetry bắn qua WebSocket IPC mỗi giây.
      - `frontend/lib/services/system_telemetry_service.dart` & `frontend/lib/services/bridge_service.dart`: Bổ sung phân giải `liveFps` và `activeGame`.
      - `frontend/lib/hardware/rtss_service.dart`: Xóa bỏ code hardcode trả về 60 trong `getInstantaneousFps()`, lấy trực tiếp từ telemetry sống `SystemTelemetryService.instance.latest.liveFps`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

- [ ] **Khóa giới hạn khung hình (FPS Limit)**
  + [Initial] Code thực tế: `backend/src/hardware/rtss_service.py` ghi mục `[Framerate] Limit` trong tệp cấu hình profile `Global` của RTSS và gọi cập nhật hồ sơ.
    Tình trạng: Đã code cơ chế ghi profile.
  + [23/10/2026 23:00] Nghi vấn tính năng chưa hoạt động:
    Code thực tế: Cần kiểm tra lại quyền ghi file config và lệnh đồng bộ UpdateProfiles xuống RTSS trong `backend/src/hardware/rtss_service.py`.
    Hiện tượng: Chưa rõ tính năng FPS limit có hoạt động được không, nhưng kiểm tra thực tế có vẻ chưa hoạt động (game không bị giới hạn khung hình theo mức FPS đã đặt).
    Tình trạng: Còn tồn đọng lỗi.
  + [23/10/2026 23:18] Tích hợp Profile API native của RTSSHooks64.dll:
    Code thực tế:
      - `backend/src/hardware/rtss_service.py`: Khai báo và gọi trực tiếp các API native từ `RTSSHooks64.dll` (`LoadProfile`, `SetProfileProperty`, `SaveProfile`, `UpdateProfiles`). Thiết lập thuộc tính `FramerateLimit` dạng `DWORD` cho profile `Global`, kích hoạt cờ `APPFLAG_PROFILE_UPDATE_REQUESTED` để toàn bộ tiến trình game đang nạp hook hãm FPS tức thì mà không bị chặn bởi phân quyền thư mục UAC của Windows.
      - Duy trì cơ chế ghi file cấu hình fallback phòng trường hợp DLL hook chưa sẵn sàng.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

- [ ] **Tùy chỉnh thông số hiển thị, màu sắc, cú pháp & Token pin (RTSS OSD Customization)**
  + [Initial] Code thực tế: `frontend/lib/hardware/rtss_osd_formatter.dart` định dạng chuỗi thẻ màu RTSS markup, cho phép bật/tắt độc lập các thông số (FPS, TDP, Temp, CPU load, RAM, Pin, Fan) và chuyển đổi 2 kiểu layout (1 dòng hoặc nhiều dòng).
    Tình trạng: Hoạt động ổn định.
  + [24/10/2026 13:46] Triển khai tùy biến màu sắc, nhãn chữ, syntax template và bổ sung token time_left:
    Code thực tế:
      - `backend/src/services/system_telemetry.py`: Bổ sung trích xuất `battery_secs_left = int(battery.secsleft)` từ `psutil.sensors_battery()`, truyền số giây ước lượng còn lại vào snapshot telemetry (xử lý -2 cắm nguồn AC, -1 đang tính toán, >0 số giây).
      - `frontend/lib/services/system_telemetry_service.dart` & `frontend/lib/services/bridge_service.dart`: Mở rộng `SystemTelemetryData` với `batterySecsLeft` và getter `batteryTimeLeftFormatted` tự động định dạng `1h45m`, `35m`, `CHG` hoặc `AC`.
      - `frontend/lib/hardware/rtss_syntax_parser.dart`: Xây dựng compiler siêu nhẹ (Zero Allocation) hỗ trợ toàn bộ các macro token (`{fps}`, `{tdp}`, `{cpu_temp}`, `{cpu_usage}`, `{ram_used}`, `{ram_total}`, `{ram_percent}`, `{battery}`, `{time_left}`, `{fan}`, `{time}`, `{game}`), thẻ màu động (`{cpu_temp_color}`, `{fps_color}`, `{bat_color}`) và thẻ RTSS markup (`<C=HEX>`, `\n`). Cung cấp 4 bảng phối màu mẫu (`Mặc định`, `Neon Cyber`, `Amber Retro`, `Trắng tối giản`).
      - `frontend/lib/hardware/rtss_osd_formatter.dart`: Mở rộng `RtssOsdMetricsConfig` hỗ trợ 2 chế độ `RtssOsdMode.visual` và `RtssOsdMode.syntax`, cấu hình nhãn `labels` và màu sắc `colors` cho từng metric; tích hợp `time_left` vào chuỗi hiển thị OSD.
      - `frontend/lib/hardware/rtss_osd_service.dart`: Tách logic phát OSD ra dịch vụ nền Singleton độc lập, lắng nghe telemetry stream để cập nhật OSD bền bỉ in-game kể cả khi đóng Quick Panel.
      - `frontend/lib/main.dart`: Khởi tạo `RtssOsdService.instance.init(config)` ngay tại entrypoint ứng dụng.
      - `frontend/lib/ui/tabs/rtss_tab.dart`: Bổ sung khung mô phỏng Live In-App Preview với font Consolas pixel; bộ chuyển đổi chế độ Visual / Syntax; bộ chọn bảng màu mẫu; dãy nút chip chèn nhanh macro token; và HelpBox chi tiết hướng dẫn toàn bộ cú pháp token khả dụng. Hoàn toàn tương thích điều hướng Gamepad 100%.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

- [ ] **Tùy biến kích thước OSD (Zoom) và Vị trí hiển thị (Position)**
  + [Initial] Code thực tế: UI Flutter đã có các nút chọn Zoom (1x-4x) và Position.
    Tình trạng: **Còn tồn đọng** (Chưa nối luồng WebSocket IPC để gửi cấu hình Zoom/Position xuống backend và chưa ghi vào file cấu hình của RTSS; cần kiểm tra hiển thị thực tế in-game trên máy handheld).

---

## 5. Điều chỉnh độ sáng, âm lượng, bật/tắt màn hình cảm ứng

- [ ] **Độ sáng màn hình (Brightness)**
  + [Initial] Code thực tế: `backend/src/hardware/brightness_service.py` điều chỉnh qua WMI `WmiMonitorBrightnessMethods` kèm fallback CIM PowerShell.
    Tình trạng: Hoạt động ổn định.
  + [24/10/2026 10:45] Khắc phục lỗi thanh chỉnh độ sáng và đồng bộ 2 chiều với Windows:
    Hiện tượng: Thanh chỉnh brightness không hoạt động do WMI root/wmi:WmiMonitorBrightness báo lỗi OLE 0x8004100c (Not Supported). Thanh trượt độ sáng không tự cập nhật khi người dùng thay đổi từ Windows Action Center hoặc phím cứng.
    Code thực tế:
      - `backend/src/hardware/brightness_service.py`: Tái cấu trúc theo mô hình Multi-tier 3 tầng: Tầng 1 Win32 Native `dxva2.dll` (VESA DDC/CI) điều khiển trực tiếp phần cứng màn hình; Tầng 2 ACPI WMI cho màn hình Handheld eDP; Tầng 3 Win32 GDI `SetDeviceGammaRamp` (Software Dimming). Tự động đọc độ sáng thực tế ban đầu từ phần cứng; bổ sung worker ngầm có debounce tránh nghẽn I2C bus và luồng định kỳ 2s đồng bộ khi người dùng chỉnh từ Windows.
      - `frontend/lib/ui/quick_panel.dart`: Đăng ký listener trên `BridgeService.instance.brightness`, tự động cập nhật lại biến state khi nhận tín hiệu từ Windows; đồng bộ ngay lập tức khi mở panel (`_onOverlayVisibilityChanged`) và trong chu kỳ `_updateTelemetry`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 20:05] Khắc phục lỗi fake success dxva2 DDC/CI và chuyển sang WMI COM gốc:
    Hiện tượng: Màn hình eDP tích hợp của Handheld (GPD WIN 4) không can thiệp được qua dxva2 DDC/CI, nhưng SetMonitorBrightness trả về 1 ảo làm backend bỏ qua tầng WMI ACPI; đồng thời thư viện wmi bên thứ 3 thiếu hụt trong PyInstaller bundle khiến lệnh WMI bị nuốt lỗi.
    Code thực tế:
      - `backend/src/hardware/brightness_service.py`: Thay thế hoàn toàn phụ thuộc thư viện ngoài `wmi` bằng kết nối WMI COM InParameters trực tiếp (`win32com.client.GetObject("winmgmts:\\.\root\wmi")` -> `WmiSetBrightness`) độ trễ 0ms kèm fallback PowerShell CIM.
      - Siết chặt dxva2: Chỉ chấp nhận DDC/CI khi cả `GetMonitorBrightness` thành công (loại bỏ hoàn toàn fake success trên eDP). Ưu tiên số 1 của màn hình Handheld eDP chuyển thẳng sang WMI ACPI phần cứng.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

- [ ] **Âm lượng hệ thống & Tắt tiếng (Volume & Mute)**
  + [Initial] Code thực tế: `backend/src/hardware/audio_service.py` tương tác Windows CoreAudio qua thư viện `pycaw`.
    Tình trạng: Hoạt động ổn định.
  + [24/10/2026 10:45] Đồng bộ 2 chiều âm lượng với Windows:
    Code thực tế: Tự động tái kết nối pycaw trong `backend/src/hardware/audio_service.py` khi thiết bị âm thanh mặc định của Windows thay đổi (cắm/rút tai nghe); bổ sung listener trên `BridgeService.instance.volume` trong `frontend/lib/ui/quick_panel.dart` để thanh trượt âm lượng tự động nhảy theo đúng giá trị khi người dùng bấm phím âm lượng vật lý hoặc chỉnh qua Windows.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

- [x] **Bật/Tắt màn hình cảm ứng (Touchscreen Toggle)**
  + [Initial] Code thực tế: `backend/src/hardware/touchscreen_service.py` quét và bật/tắt thiết bị HID Touchscreen bằng lệnh `pnputil`.
    Tình trạng: Hoạt động ổn định.

---

## 6. Khởi động app cùng Windows (Autostart) & Khay hệ thống (System Tray)

- [x] **Đăng ký tự khởi chạy ngầm**
  + [Initial] Code thực tế: `backend/src/services/autostart_service.py` ghi đường dẫn vào Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. Khởi chạy ứng dụng ở chế độ thu nhỏ vào khay hệ thống (System Tray).
    Tình trạng: Hoạt động ổn định.

- [ ] **Biểu tượng ứng dụng & Khay hệ thống (App & Tray Icon)**
  + [Initial] Code thực tế: `backend/main.py` hàm `create_tray_icon()` đang vẽ tạm một hình tròn màu tím có chữ "H" bằng `QPainter`, file `.exe` chưa được gán tệp icon `.ico` riêng.
    Tình trạng: Chưa hoàn thiện nhận diện thương hiệu.
  + [23/10/2026 23:22] Yêu cầu đổi sang icon Gamepad của Google Fonts:
    Kế hoạch kỹ thuật:
      - Tải asset vector SVG biểu tượng gamepad (`sports_esports` / `gamepad`) từ Google Fonts Material Symbols.
      - Xuất bộ icon đa kích thước: `app_icon.png` (dùng cho `QSystemTrayIcon` và cửa sổ) và `app_icon.ico` (16x16, 32x32, 48x48, 64x64, 128x128, 256x256) đặt trong thư mục `backend/assets/`.
      - Cập nhật `backend/main.py`: Nạp trực tiếp `app_icon.ico` hoặc `app_icon.png` cho `app.setWindowIcon()` và `QSystemTrayIcon`.
      - Cấu hình cờ `--icon backend/assets/app_icon.ico` trong quy trình đóng gói PyInstaller để file `.exe` hiển thị đúng icon gamepad trên File Explorer và Taskbar của Windows.
    Tình trạng: Đã ghi nhận kế hoạch (Chờ triển khai).
  + [23/10/2026 23:27] Triển khai icon Gamepad Google Fonts:
    Code thực tế:
      - Đã sinh và lưu `backend/assets/app_icon.png` và `backend/assets/app_icon.ico` chuẩn 7 kích thước Win32 (16, 24, 32, 48, 64, 128, 256 px) dựa trên vector `sports_esports` từ Google Fonts Material Symbols với nền chuyển sắc hiện đại.
      - `backend/main.py`: Bổ sung hàm `get_app_icon()` ưu tiên nạp icon gamepad từ `backend/assets/`, tự động gán cho cả `app.setWindowIcon()` và `QSystemTrayIcon()`. Đồng thời file `backend/assets/app_icon.ico` đã sẵn sàng để truyền vào cờ `--icon` khi đóng gói file `.exe`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 01:13] Khắc phục lỗi hiển thị icon cũ sau khi build:
    Code thực tế:
      - `scripts/deploy/deploy_test.bat`: Bổ sung tham số `--icon "assets\app_icon.ico"` và `--add-data "assets;assets"` vào lệnh PyInstaller; sao chép thư mục `backend\assets` sang thư mục phát hành `%DIST_DIR%\assets`; bổ sung lệnh làm mới cache icon Windows Explorer `ie4uinit.exe -show` sau khi triển khai.
      - `backend/main.py`: Cập nhật hàm `get_app_icon()` hỗ trợ quét thư mục `assets` qua `sys._MEIPASS` và `sys.executable` trong môi trường PyInstaller; nâng cấp cơ chế fallback vẽ trực tiếp vector Google Fonts `sports_esports` qua `QSvgRenderer` nếu tệp đĩa bị thiếu (loại bỏ hoàn toàn hình tròn chữ "H" cũ).
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

  + [24/10/2026 12:50] Nâng cấp Icon Modern Blue Fluent Design không viền (Full Bleed):
    Code thực tế:
      - Loại bỏ hoàn toàn nền gradient tím cũ, chuyển sang màu xanh đơn sắc phẳng hiện đại Windows Accent Blue (`#0067C0`).
      - Triệt tiêu 100% lề ngoài thừa (Zero Margin / Full Bleed) và phóng to biểu tượng Gamepad lên 88-90% khung hình giúp hiển thị to rõ, sắc nét ở khay hệ thống (System Tray).
      - Phối hợp các sắc độ trắng khác nhau (Fluent White Shades) cho thân vỏ, D-pad, nút bấm ABXY và cần gạt Analog tạo chiều sâu đa lớp đồng bộ hoàn hảo với Windows 11.
      - Sinh lại `backend/assets/app_icon.png` (512x512) và `backend/assets/app_icon.ico` (7 layer: 16 đến 256 px); cập nhật fallback SVG trong `backend/main.py`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
---

## 7. Tính năng dự kiến mở rộng (Backlog)

- [ ] **Cấu hình riêng cho từng tựa game (Per-Game Profiles)**
  + [Initial] Tự động phát hiện HWND/PID game để áp dụng cấu hình TDP, Fan curve và FPS Limit riêng cho từng tựa game.
    Tình trạng: Chưa thực hiện.

- [ ] **Giới hạn sạc pin (Battery Charge Limiter 80%)**
  + [Initial] Can thiệp chip quản lý nguồn ngắt sạc khi pin đạt 80% để bảo vệ pin.
    Tình trạng: Chưa thực hiện.

- [ ] **Ánh xạ nút vật lý mở panel (Dedicated QAM Button Remap)**
  + [Initial] Bắt scancode phần cứng của các nút bấm cạnh máy như trên Lenovo Legion Go, ROG Ally để mở Quick Panel.
    Tình trạng: Chưa thực hiện.


---

## 8. Kịch bản phát triển & Triển khai (Scripts & Tooling)

- [ ] **Kịch bản điều khiển trung tâm (scripts/run.bat)**
  + [Initial] Code thực tế: `scripts/run.bat` cung cấp menu chọn chế độ chạy: Gaming Overlay, Dev Hot Reload, Chrome DevTools, Deploy Release Package, Uninstall.
    Tình trạng: Tùy chọn [2] (Dev Hot Reload) bị crash ngay khi khởi chạy với thông báo lỗi `NOT was unexpected at this time.` do cú pháp ngoặc đơn `(RTSS)` trong khối `if not defined RTSS_INSTALLED (...)`.
  + [24/10/2026 11:13] Khắc phục lỗi cú pháp `NOT was unexpected at this time.` và nâng cấp menu [2]:
    Code thực tế:
      - `scripts/run.bat`: Tái cấu trúc subroutine `:ENSURE_RTSS` theo kiến trúc phẳng (flat label-goto), loại bỏ khối `if (...)` đa dòng bọc quanh lệnh `echo`, đổi `(RTSS)` thành `[RTSS]`, chuẩn hóa định nghĩa biến `PYTHON_CMD`.
      - Cấu hình lệnh `start` với cờ thư mục làm việc `/D "%PROJECT_ROOT%\frontend"` chuẩn Win32 và vòng lặp socket Python kiểm tra cổng 5173 sẵn sàng trước khi nạp backend.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 11:23] Khắc phục lỗi 'No client connected' & nạp sai bản build tĩnh khi Dev Hot Reload:
    Code thực tế:
      - `scripts/run.bat`: Bổ sung cờ `--web-hostname 127.0.0.1` vào lệnh chạy Flutter Web Dev Server để liên kết trực tiếp IPv4, loại bỏ độ trễ phân giải IPv6 của `localhost`.
      - `backend/src/overlay/quick_panel.py`: Viết lại hàm `_is_dev_server_running()` dùng socket IPv4 (`127.0.0.1:5173`) tốc độ cao thay cho `urllib.request.urlopen("http://localhost:5173", timeout=0.3)` (vốn luôn bị Timeout do IPv6 fallback, khiến QuickPanel âm thầm rơi vào fallback nạp bản build tĩnh cũ và DWDS không kết nối được client).
      - Đổi URL nạp thành `http://127.0.0.1:5173`, bật cờ `is_dev_mode = True`, bổ sung phím tắt `F5` và `Ctrl+R` kích hoạt `self.view.reload()` cho phép reload giao diện tức thì.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
  + [24/10/2026 14:40] Sửa lỗi mục 2 không hiện panel ("No client connected") và mục 4 báo ERR_CONNECTION_REFUSED:
    Code thực tế:
      - `backend/src/overlay/quick_panel.py`: Bản đóng gói (frozen) không còn dò Flutter dev server cổng 5173 (nguyên nhân mục 4 bám nhầm dev server của mục 2 rồi bị refused khi server tắt), luôn nạp build tĩnh. Ở chế độ dev, thêm watchdog `_ensure_dev_app_started`: sau 12s nếu chưa có `flt-glass-pane` (DDC treo ở bước nạp module khi server còn biên dịch) thì tự reload, tối đa 6 lần.
      - `scripts/run.bat`: Vòng chờ mục 2 kiểm tra `/main.dart.js` (chỉ trả về sau khi biên dịch xong) thay cho trang index.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).
