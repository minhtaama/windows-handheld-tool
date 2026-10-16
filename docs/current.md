# Tình trạng hiện tại của dự án

## 1. Kiến trúc tổng thể
- Giao diện (Frontend): Flutter Web (HTML/JS/CanvasKit) độc lập trong thư mục `frontend/`, biên dịch tại `frontend/build/web`.
- Môi trường thực thi chính (Host Runtime): Python độc lập trong thư mục `backend/` (PySide6 QWebEngineView kết hợp Win32 API).
- Giao tiếp liên tiến trình (IPC): WebSocket nội bộ (`ws://127.0.0.1:54321`) và kênh QWebChannel Bridge.
- Cơ chế lớp phủ (Overlay): Can thiệp dải Z-Order đặc quyền `ZBID_UIACCESS` (Band 2) kết hợp cờ `WS_EX_NOACTIVATE` (0x08000000) để hiển thị đè trực tiếp lên 100% game Toàn màn hình độc quyền (Exclusive Fullscreen - FSE).

## 2. Tiến độ đã hoàn thành
## 2. Tiến độ đã hoàn thành & Tính năng hoạt động ổn định
- Mở/đóng QuickPanel trượt mượt mà có animation, overlay lớp nền đen mờ (backdrop) toàn màn hình; đóng mở qua nhấp chuột vào backdrop hoặc bấm hotkey đều hoạt động chính xác và ổn định.
- Phím tắt (Hotkey) bật/tắt bàn phím ảo (TabTip) hoạt động tốt.
- Giao diện người dùng hiển thị ổn định, không bị lỗi layout hay co giãn bất thường.
- Điều chỉnh độ sáng màn hình và âm lượng hệ thống hoạt động tốt.
- Đo đạc và hiển thị chuẩn xác tài nguyên thực tế: % CPU và % RAM trên bảng điều khiển.
- Khay hệ thống (System Tray Icon) hoạt động tốt, hiển thị menu điều khiển và trạng thái ngầm.
- Xóa bỏ triệt để hiện tượng nháy đen (Display Mode Switch) và lệch tọa độ trên game Toàn màn hình độc quyền (FSE) bằng cơ chế Focus Lock (`WS_EX_NOACTIVATE`, `MA_NOACTIVATE = 3`) và đọc trực tiếp kích thước khung nhìn thực tế `GetClientRect()`.

## 3. Các vấn đề lỗi phát sinh cần khắc phục

### 3.1. Lỗi nghiêm trọng (Critical)
1. **Tính năng gán lại phím tắt (Hotkey Reassignment) không hoạt động:**
   - *Nguyên nhân kỹ thuật:* Widget `HotkeyTile` trong Flutter Web phụ thuộc vào `HardwareKeyboard.instance.addHandler`. Tuy nhiên, do cửa sổ QuickPanel đặt cờ `WindowDoesNotAcceptFocus` và trả về `MA_NOACTIVATE = 3` khi chuột tương tác nhằm tránh cướp tiêu điểm của game FSE, nhân trình duyệt Chromium / Flutter Web không bao giờ nhận được sự kiện bàn phím từ Windows OS (`WM_KEYDOWN` / `WM_KEYUP`). Ngoài ra, `GamepadService.startRecordingCombo()` hiện đang là một hàm rỗng.
   - *Phương hướng giải quyết:* Chuyển toàn bộ tác vụ lắng nghe phím khi gán lại sang tầng Python Host (sử dụng Win32 Global Hook hoặc `GetAsyncKeyState` / `XInput` polling). Khi người dùng nhấn nút gán phím trên Flutter, gửi thông điệp yêu cầu Python ghi nhận tổ hợp phím toàn cục, sau đó đẩy sự kiện phím đã ghi nhận trở lại Flutter qua WebSocket/Bridge.

2. **Toàn bộ phân hệ điều khiển TDP và Fan curves không hoạt động:**
   - *Nguyên nhân kỹ thuật (TDP):* `init_ryzenadj` trả về `NULL` và gọi CLI `ryzenadj.exe` báo lỗi mã `4294967295` (`Unable to get os_access Obj, check permission`). Nguyên nhân do driver `WinRing0x64.sys` bị Windows Defender hoặc cơ chế bảo vệ nhân (HVCI / Core Isolation) chặn, hoặc tiến trình thiếu quyền nâng cao SYSTEM/Admin để mở cổng truy cập phần cứng MSR/SMU.
   - *Nguyên nhân kỹ thuật (Fan Curves):* `_apply_ec_io()` cố gắng ghi trực tiếp vào cổng I/O `0x6C` / `0x68` thông qua `inpoutx64.dll`. Cơ chế này hoàn toàn bị vô hiệu hóa trên Windows 11 hiện đại nếu không có signed driver tương thích hoặc phương thức WMI chuyên biệt của từng hãng sản xuất (ASUS, Lenovo, GPD, Ayaneo...).
   - *Phương hướng giải quyết:*
     - Với TDP: Tích hợp và tự động đăng ký tác vụ Scheduled Task chạy ngầm với đặc quyền cao nhất (SYSTEM / Highest Privileges) thông qua file cấu hình `RyzenAdjServiceTask.xml` / `installServiceTask.bat` đã có sẵn trong dự án để bỏ qua rào cản UAC/HVCI.
     - Với Fan: Thiết lập lớp bọc an toàn kiểm tra hỗ trợ thiết bị, ưu tiên gọi ACPI/WMI methods hoặc giao diện chuyên biệt của dòng máy thay vì ghi trực tiếp cổng I/O trần.

### 3.2. Lỗi giao diện & thao tác nhanh (UI Bug & Quick Actions)
1. **Điều chỉnh độ rộng bảng điều khiển (Panel Width) bị giật lag (Clunky):**
   - *Nguyên nhân kỹ thuật:* Khi kéo thanh trượt độ rộng, Flutter gửi tín hiệu thay đổi phần trăm về Python Host qua `BridgeService.instance.setPanelWidth(percent)`. Tầng Python lại liên tục gọi `win_mgr.update_geometry(width)` -> `user32.SetWindowPos` trên cửa sổ Win32. Do cửa sổ QuickPanel bản chất đã phủ kín toàn màn hình (fullscreen backdrop trong suốt), việc liên tục gọi Win32 API thay đổi kích thước cửa sổ hệ thống gây hiện tượng reflow và giật khung hình không cần thiết.
   - *Phương hướng giải quyết:* Giữ nguyên kích thước cửa sổ Win32 toàn màn hình. Khi người dùng điều chỉnh độ rộng, chỉ cập nhật biến trạng thái `panelWidth` và kích thước container ngay trong Flutter để animation diễn ra mượt mà 60/120fps; đồng thời lưu cấu hình xuống tệp `config.json` mà không gọi lại `SetWindowPos` của OS.

2. **Các tính năng mở Task Manager, Xóa RAM, Mở cài đặt màn hình không hoạt động:**
   - *Nguyên nhân kỹ thuật:* Trong `frontend/lib/ui/quick_panel.dart`, các sự kiện `onTaskManager` và `onDisplaySettings` chỉ gọi `OverlayController.instance.hideOverlay()` mà không gọi bất kỳ lệnh khởi chạy tiến trình nào. Tương tự, `SystemOptimizer.trimMemory()` trong Flutter hiện chỉ in log ra console mà chưa kết nối với Win32 API.
   - *Phương hướng giải quyết:* Bổ sung các handler tương ứng qua `BridgeService` sang Python Backend:
     - Mở Task Manager: Gọi `subprocess.Popen("taskmgr.exe")`.
     - Mở Cài đặt Màn hình: Mở URI hệ thống `ms-settings:display`.
     - Dọn dẹp RAM (RAM Trim): Gọi hàm Win32 `SetProcessWorkingSetSize(-1, -1)` / `EmptyWorkingSet` thông qua `psapi.dll` từ Python Host.

3. **Toàn bộ phân hệ điều hướng bằng tay cầm Gamepad chưa hoạt động:**
   - *Nguyên nhân kỹ thuật:* Khi chuyển sang Flutter Web, `gamepad_service.dart` chỉ là mockup rỗng, `_buttonEventsController` không bao giờ nhận sự kiện từ phần cứng. Phía Python Host, `gamepad_service.py` chỉ quét duy nhất combo mở panel (`BACK + RB`) rồi dừng, không chuyển tiếp các nút điều hướng Console (`DPAD_UP`, `DPAD_DOWN`, `DPAD_LEFT`, `DPAD_RIGHT`, `A`, `B`, `X`, `Y`, `LB`, `RB`) sang Flutter khi panel đang mở.
   - *Phương hướng giải quyết:*
     - Khi Panel đang mở (`is_visible == True`), luồng `gamepad_service.py` đọc toàn bộ trạng thái nút bấm XInput kèm cơ chế lặp/chống dội nút (Debounce).
     - Phát tín hiệu gửi sự kiện `{"type": "gamepadButton", "data": {"button": "dpadUp"}}` sang WebSocket.
     - Phía Flutter Web: `BridgeService` lắng nghe gói tin này và đẩy vào `GamepadService.buttonEvents` để kích hoạt `_onGamepadButton()` điều hướng giao diện.

### 3.3. Lỗi lệch kích thước khung nhìn khi Game chạy độ phân giải thấp hơn Desktop (Resolution Mismatch)
1. **Bảng điều khiển và lớp phủ bị thu nhỏ, hở màn hình Desktop khi Game chạy 720p:**
   - *Hiện tượng thực tế:* Khi game (ví dụ: Ready Or Not) chạy ở chế độ không toàn màn hình độc quyền (Borderless / Windowed) với độ phân giải thấp hơn màn hình Windows (ví dụ: game render 1280x720 trên màn hình Desktop 1920x1080), cửa sổ QuickPanel bị co cụm về góc trên bên trái theo kích thước của game thay vì phủ trọn vẹn 100% màn hình Desktop vật lý, để lộ thanh Taskbar và các icon Desktop bên ngoài.
   - *Nguyên nhân kỹ thuật (Bóc trần vật lý):* Trong hàm `_get_screen_dimensions()` tại `backend/src/overlay/window_manager.py`:
     ```python
     fg_hwnd = user32.GetForegroundWindow()
     # Đọc client_rc của cửa sổ foreground:
     w = client_rc.right - client_rc.left
     h = client_rc.bottom - client_rc.top
     if win_rc.left == 0 and win_rc.top == 0 ...:
         return w, h
     ```
     Khi game đặt tọa độ góc trên (0, 0) nhưng chỉ có kích thước `1280x720`, đoạn code trên đã nhận diện nhầm kích thước của cửa sổ Game đó là kích thước toàn màn hình của toàn bộ hệ thống (`screen_w = 1280, screen_h = 720`). Hậu quả là `SetWindowPos` thu nhỏ cửa sổ overlay lại thành `1280x720`, khiến lớp backdrop đen mờ và thanh trượt QuickPanel bị co hẹp, làm lộ thanh Taskbar và nền Desktop 1080p bên dưới.
   - *Phương hướng giải quyết:*
     - Tách bạch rõ ràng: Cửa sổ Overlay của ứng dụng là một lớp phủ toàn diện của hệ điều hành (**System Desktop Overlay**), nó **luôn luôn phải bao phủ toàn bộ vùng quét vật lý của Monitor** (`SM_CXSCREEN`, `SM_CYSCREEN` hoặc màn hình chứa cửa sổ game qua `MonitorFromWindow` / `GetMonitorInfo`).
     - Chỉ bám theo kích thước Game nếu Game đó đang thực sự chuyển đổi chế độ hiển thị phần cứng độc quyền (Exclusive Fullscreen Display Mode Switch làm thay đổi độ phân giải quét của GPU Display Engine, lúc này `SM_CXSCREEN` sẽ tự nhảy về 1280). Khi Desktop vẫn là 1080p, cửa sổ Overlay bắt buộc phải giữ kích thước `1920x1080` của Monitor vật lý để phủ kín toàn màn hình.

## 4. Các tính năng chưa kiểm tra
- **Lớp phủ RTSS Overlay:** Đã tích hợp khởi chạy tiến trình ngầm và kết nối Shared Memory, cần kiểm tra hiển thị thực tế trong game.
- **Tự động khởi động cùng Windows (Windows Startup):** Cần kiểm tra ghi khóa Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- **Bật/tắt màn hình cảm ứng (Touchscreen Toggle):** Cần kiểm tra can thiệp thiết bị HID Touch qua PnP / PowerShell cmdlets.

## 5. Bảng trạng thái nhiệm vụ

| STT | Phân hệ / Nhiệm vụ | Mức độ | Trạng thái | Ghi chú kỹ thuật |
|---|---|---|---|---|
| 1 | Mở/đóng panel, backdrop, animation, tray, hotkey tabtip, đo CPU/RAM, độ sáng/âm lượng | Tiêu chuẩn | **Đã hoạt động tốt** | Duy trì ổn định, bảo toàn tiêu điểm game FSE |
| 2 | Gán lại phím tắt (Hotkey Reassignment) | **Critical** | **Đã khắc phục** | Đã kết nối `HotkeyCaptureService` Win32 GetAsyncKeyState & XInput; hỗ trợ gán động cả Bàn phím & Gamepad combo (Overlay + Virtual Keyboard) |
| 3 | Điều khiển công suất TDP (RyzenAdj) | **Critical** | **Đã hoạt động** | RyzenAdj nạp driver Ring 0 thành công, đã thiết lập STAPM / Fast / Slow limit mượt mà |
| 4 | Điều khiển đường cong quạt (Fan curves) | **Critical** | **Đã khắc phục** | Bọc an toàn WMI Asus ROG Ally & đồng bộ luồng điều tốc theo nhiệt độ CPU tức thời |
| 5 | Độ mượt khi chỉnh kích thước Panel Width | UI Bug | **Đã khắc phục** | Flutter co giãn container nội bộ 60/120fps, không gọi Win32 SetWindowPos liên tục |
| 6 | Thao tác nhanh (Task Manager, Cài đặt màn hình, Dọn RAM) | Chức năng | **Đã khắc phục** | Đã kết nối `taskmgr.exe`, `ms-settings:display`, và `EmptyWorkingSet` qua Bridge |
| 7 | Điều hướng giao diện bằng Gamepad | **Critical** | **Đã khắc phục** | Đã chuyển tiếp (forward) sự kiện nút XInput từ Python sang WebSocket kèm Debounce; nhận diện động tổ hợp mở Panel & Bàn phím ảo từ cấu hình |
| 8 | Lệch kích thước khi game chạy độ phân giải < Desktop (720p vs 1080p) | UI Bug | **Đã khắc phục** | Đã thay thế việc đọc `client_rc` bằng API `MonitorFromWindow` / `GetMonitorInfoW`, luôn phủ 100% Monitor vật lý |
| 9 | RTSS Overlay trong game | Chức năng | Chờ kiểm tra | Đã sẵn sàng tiến trình daemon và kết nối bộ nhớ chia sẻ |
| 10 | Tự khởi động cùng Windows & Bật/tắt Touchscreen | Chức năng | Chờ kiểm tra | Kiểm tra can thiệp Registry và thiết bị HID khi thực chiến |


