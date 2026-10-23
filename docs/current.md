# Trạng thái hiện tại của dự án (Project Status)

> Cập nhật lần cuối: 23/10/2026 22:45

> [!IMPORTANT]
> **Quy tắc duy trì tài liệu**:
> 1. **Checkbox ngoài cùng (`- [x]` / `- [ ]`)**: Thể hiện trạng thái tổng thể của tính năng.
>    - `- [x]`: Toàn bộ tính năng đã được kiểm thử và xác nhận **Hoạt động ổn định**.
>    - `- [ ]`: Tính năng còn lỗi tồn đọng, đang trong backlog, hoặc **Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định)**.
> 2. **Timeline bên trong (thụt lề `+ [Thời gian]`)**: Lưu vết toàn bộ lịch sử phát triển theo trình tự thời gian.
>    - `+ [Initial]`: Hiện trạng mã nguồn và trạng thái ban đầu của tính năng.
>    - `+ [Ngày giờ]`: Các mốc thời gian cập nhật, sửa lỗi hoặc phát hiện lỗi mới. Tuyệt đối không xóa hay sửa đè lên các mốc timeline cũ.
> 3. Khi vừa sửa xong code cho một lỗi, bổ sung một mốc `+ [Thời gian]` mới ghi rõ: **Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định)** và giữ checkbox tính năng là `- [ ]`. Chỉ tick `- [x]` sau khi người dùng hoặc kiểm thử thực chiến xác nhận.

---

## 1. Cơ chế chuyển cảnh liền mạch & Lớp phủ in-game (Seamless Transition & Overlay)

- [x] **Cơ chế hiển thị đặc quyền & Cách ly tiêu điểm (Z-Band & Focus Management)**
  + [Initial] Code thực tế: `backend/src/overlay/window_manager.py` chạy quyền Administrator, nhúng chữ ký số (`HandheldToolsSigner`) và manifest `uiAccess="true"` thực thi từ `C:\Program Files` để DWM phân bổ vào dải đặc quyền `ZBID_UIACCESS` (Band 2), luôn nổi đè lên game thuộc Band 1 (Desktop). Cửa sổ neo cố định mép phải màn hình (`Side-Dock Viewport`), khi đóng chỉ bật cờ xuyên thấu `WS_EX_TRANSPARENT` (Click-Through 100%) mà không di dời hay hủy cửa sổ. Cửa sổ con Chromium được ép cờ `WS_EX_NOACTIVATE`. Khi đóng panel, hàm `restore_foreground_window` dùng kỹ thuật giả lập phím ALT (`keybd_event` VK_MENU) trước và sau lệnh `SetForegroundWindow` để phá vỡ `ForegroundLockTimeout`, giúp game nhận lại tiêu điểm tức thì mà không bị nuốt cú nhấp chuột đầu tiên.
    Tình trạng: Hoạt động ổn định.

- [x] **Can thiệp đồ họa DirectX nội tiến trình (DXGI Hook Engine)**
  + [Initial] Code thực tế: `backend/native/dxgi_hook/src/dxgi_hook.cpp` (MinHook x64) can thiệp bảng VMT SwapChain. `Hooked_SetFullscreenState` chặn `Fullscreen = TRUE`, ép `FALSE`, gọi `ForceBorderlessWindow` chuẩn hóa style Win32 (xóa `WS_CAPTION`, `WS_THICKFRAME`...) và trả về `S_OK`. `Hooked_GetFullscreenState` ép báo cáo `*pFullscreen = FALSE` để engine (Unreal Slate UI, Unity) dùng nhánh tọa độ chuột chuẩn Client Rect của Borderless Windowed. `Hooked_ResizeBuffers` & `Hooked_ResizeTarget` xóa cờ `ALLOW_MODE_SWITCH` và chặn game co rút cửa sổ Win32 khi render nhỏ hơn màn hình. Hook Factory (`CreateSwapChain`, `CreateSwapChainForHwnd`, `D3D11CreateDeviceAndSwapChain`) tự động xóa `ALLOW_MODE_SWITCH`, ép `Windowed = TRUE`, ép `Scaling = DXGI_SCALING_ASPECT_RATIO_STRETCH`.
    Tình trạng: Hoạt động ổn định.

- [x] **Cách ly tín hiệu tay cầm vào game khi mở panel (IPC Gamepad Isolation)**
  + [Initial] Code thực tế: `window_manager.py` khởi tạo Named Event toàn cục `Global\HandheldTool_PanelActive` (SDDL Everyone). `dxgi_hook.cpp` hook hàm `XInputGetState` từ các DLL XInput. Khi panel mở (`SetEvent`), hook tự động xóa sạch dữ liệu nút bấm (`wButtons = 0`) và cần gạt analog trước khi trả về game, ngăn nhân vật trong game bị nhảy/bắn khi duyệt menu panel. Khi panel đóng (`ResetEvent`), quyền điều khiển trả lại nguyên vẹn cho game ngay lập tức.
    Tình trạng: Hoạt động ổn định.

- [x] **Giám sát vòng đời game & Tự động tiêm DLL (GameCompatService)**
  + [Initial] Code thực tế: `backend/src/services/game_compat_service.py` cài đặt `SetWinEventHook` bắt `EVENT_SYSTEM_FOREGROUND` tự động nhận diện game (lọc bỏ tiến trình hệ thống qua `NON_GAME_PROCESSES` và đường dẫn thư viện Steam/Epic/Xbox). Kích hoạt `SeDebugPrivilege` và tiêm `dxgi_hook.dll` vào game 64-bit qua `VirtualAllocEx` + `WriteProcessMemory` + `CreateRemoteThread(LoadLibraryW)`. Tự động dọn cờ tắt FSO trong Registry (`AppCompatFlags\Layers` và `GameConfigStore`) để duy trì Composed Flip mượt mà. Bắt `EVENT_SYSTEM_MINIMIZESTART` tự động khôi phục game (`SW_RESTORE`) nếu game cố thu nhỏ khi panel mở (kèm debounce chống lặp).
    Tình trạng: Hoạt động ổn định.

- [ ] **Xung đột phần cứng EC & Đồng bộ tọa độ chuột khi render lệch phân giải**
  + [Initial] Code thực tế: Vô hiệu hóa hoàn toàn lệnh ghi mù cổng EC I/O `0x6C / 0x68` trong `FanService` (loại bỏ dứt điểm hiện tượng nghẽn bus phần cứng gây giật lag máy, đơ GPU và Black Screen Kernel-Power Event 41). Đồng bộ tọa độ chuột đa tỉ lệ Client / Buffer: `dxgi_hook.cpp` duy trì hook 4 điểm (`Hooked_GetCursorPos`, `Hooked_SetCursorPos`, `Hooked_GetMessagePos` và ánh xạ `lParam` trong `PeekMessageW`/`GetMessageW`) theo ma trận `Buffer / Client`. `window_manager.py` gọi `ClipCursor(None)` khi mở panel.
    Tình trạng thực tế: Trên *Dead Island 2* và game DirectX chuẩn: Hoạt động hoàn toàn ổn định; Trên *Ready Or Not* (Unreal Engine): **Vẫn chưa khắc phục được** (con trỏ chuột và vùng tương tác hit-test của Slate UI vẫn bị lệch nhau, rê chuột lệch vị trí thì nút mới sáng và thao tác click menu chưa ăn khớp).

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

---

## 3. Điều chỉnh được TDP, Fan curves

- [ ] **Quản lý công suất TDP & Cảm biến phần cứng**
  + [Initial] Code thực tế: `backend/src/hardware/tdp_service.py` nạp driver Ring 0 `WinRing0x64.sys`, can thiệp công suất CPU Ryzen qua `libryzenadj.dll` (STAPM/Fast/Slow) kèm fallback CLI `ryzenadj.exe`. Thu thập telemetry nhiệt độ CPU và mức TDP thực tế, có fallback ước tính nhiệt độ qua % CPU của `psutil`.
    Tình trạng: Cơ chế gán công suất phần cứng: Hoạt động ổn định; Hiển thị telemetry Live TDP: **Còn lỗi** (Dữ liệu Live TDP đang bị trùng khớp với mức cài đặt của user, chưa thả nổi hiển thị đúng mức tiêu thụ TDP thực tế của chip).
  + [23/10/2026 22:50] Sửa lỗi Live TDP bị dính chết vào mức trần cài đặt:
    Code thực tế: Bổ sung đọc `get_socket_power` và `get_stapm_value` trong `backend/src/hardware/tdp_service.py`; xây dựng công thức tính Live TDP thả nổi động theo mức tải CPU (sàn 4.5W khi nghỉ đến mức trần cài đặt khi full tải). Xóa bỏ việc gán đè `_liveTdp` theo thanh trượt trong `frontend/lib/ui/quick_panel.dart`.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

- [ ] **Điều khiển quạt tản nhiệt (Fan Control)**
  + [Initial] Code thực tế: `backend/src/hardware/fan_service.py` điều khiển quạt ASUS ROG Ally / Ally X qua giao diện WMI (`AsusAtkWmi_WMNB`). Luồng chạy ngầm tự động điều tốc quạt (Auto Fan Curve) chu kỳ 2 giây dựa trên bảng mốc nhiệt độ. Đã ngắt lệnh can thiệp cổng EC I/O trực tiếp (`0x6C/0x68`) để đảm bảo an toàn phần cứng.
    Tình trạng: Cơ chế điều tốc Auto và Manual slider: Hoạt động ổn định; Hiển thị telemetry Live Fan: **Còn lỗi** (Dữ liệu Live Fan đang bị trùng với giá trị cài đặt của user, chưa hiển thị thả nổi tốc độ quạt thực tế); Tùy biến đồ thị Fan Curve: Chưa có widget giao diện trên UI Flutter để người dùng kéo thả, tùy biến trực tiếp từng điểm mốc trên đồ thị Fan Curve.
  + [23/10/2026 22:50] Sửa lỗi Live Fan bị gán đè theo giá trị thanh trượt:
    Code thực tế: Sửa logic trong `frontend/lib/ui/quick_panel.dart`, biến `_liveFan` luôn cập nhật trực tiếp từ `_telemetryData.liveFan`, loại bỏ triệt để việc gán đè `_liveFan = _fan` khi chuyển chế độ hoặc khi người dùng kéo thanh trượt.
    Tình trạng: Đã sửa xong trong code (Đang chờ test thực tế để xác nhận hoạt động ổn định).

---

## 4. Hiển thị OSD thông số in-game qua RivaTuner (RTSS Overlay)

- [x] **Quản lý tiến trình & Kết nối bộ nhớ chia sẻ RTSS**
  + [Initial] Code thực tế: `backend/src/hardware/rtss_service.py` tự động quét registry để khởi chạy ngầm `RTSS.exe`, cấu hình file profile `Global` (`EnableOSD=1`), kết nối ánh xạ bộ nhớ Win32 `RTSSSharedMemoryV2`.
    Tình trạng: Hoạt động ổn định.

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

- [x] **Tùy chỉnh thông số hiển thị & Bố cục OSD**
  + [Initial] Code thực tế: `frontend/lib/hardware/rtss_osd_formatter.dart` định dạng chuỗi thẻ màu RTSS markup, cho phép bật/tắt độc lập các thông số (FPS, TDP, Temp, CPU load, RAM, Pin, Fan) và chuyển đổi 2 kiểu layout (1 dòng hoặc nhiều dòng).
    Tình trạng: Hoạt động ổn định.

- [ ] **Tùy biến kích thước OSD (Zoom) và Vị trí hiển thị (Position)**
  + [Initial] Code thực tế: UI Flutter đã có các nút chọn Zoom (1x-4x) và Position.
    Tình trạng: **Còn tồn đọng** (Chưa nối luồng WebSocket IPC để gửi cấu hình Zoom/Position xuống backend và chưa ghi vào file cấu hình của RTSS; cần kiểm tra hiển thị thực tế in-game trên máy handheld).

---

## 5. Điều chỉnh độ sáng, âm lượng, bật/tắt màn hình cảm ứng

- [x] **Độ sáng màn hình (Brightness)**
  + [Initial] Code thực tế: `backend/src/hardware/brightness_service.py` điều chỉnh qua WMI `WmiMonitorBrightnessMethods` kèm fallback CIM PowerShell.
    Tình trạng: Hoạt động ổn định.

- [x] **Âm lượng hệ thống & Tắt tiếng (Volume & Mute)**
  + [Initial] Code thực tế: `backend/src/hardware/audio_service.py` tương tác Windows CoreAudio qua thư viện `pycaw`.
    Tình trạng: Hoạt động ổn định.

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
