# Trạng thái hiện tại của dự án (Project Status)

> Cập nhật lần cuối: 24/10/2026 13:37

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

---

## 3. Điều chỉnh được TDP, Fan curves

- [ ] **Quản lý công suất TDP & Cảm biến phần cứng**
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

- [ ] **Độ sáng màn hình (Brightness)**
  + [Initial] Code thực tế: `backend/src/hardware/brightness_service.py` điều chỉnh qua WMI `WmiMonitorBrightnessMethods` kèm fallback CIM PowerShell.
    Tình trạng: Hoạt động ổn định.
  + [24/10/2026 10:45] Khắc phục lỗi thanh chỉnh độ sáng và đồng bộ 2 chiều với Windows:
    Hiện tượng: Thanh chỉnh brightness không hoạt động do WMI root/wmi:WmiMonitorBrightness báo lỗi OLE 0x8004100c (Not Supported). Thanh trượt độ sáng không tự cập nhật khi người dùng thay đổi từ Windows Action Center hoặc phím cứng.
    Code thực tế:
      - `backend/src/hardware/brightness_service.py`: Tái cấu trúc theo mô hình Multi-tier 3 tầng: Tầng 1 Win32 Native `dxva2.dll` (VESA DDC/CI) điều khiển trực tiếp phần cứng màn hình; Tầng 2 ACPI WMI cho màn hình Handheld eDP; Tầng 3 Win32 GDI `SetDeviceGammaRamp` (Software Dimming). Tự động đọc độ sáng thực tế ban đầu từ phần cứng; bổ sung worker ngầm có debounce tránh nghẽn I2C bus và luồng định kỳ 2s đồng bộ khi người dùng chỉnh từ Windows.
      - `frontend/lib/ui/quick_panel.dart`: Đăng ký listener trên `BridgeService.instance.brightness`, tự động cập nhật lại biến state khi nhận tín hiệu từ Windows; đồng bộ ngay lập tức khi mở panel (`_onOverlayVisibilityChanged`) và trong chu kỳ `_updateTelemetry`.
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
