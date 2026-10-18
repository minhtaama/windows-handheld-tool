# Tình trạng hiện tại của dự án

## 1. Kiến trúc tổng thể
- Giao diện (Frontend): Flutter Web (HTML/JS/CanvasKit) độc lập trong thư mục `frontend/`, biên dịch tại `frontend/build/web`.
- Môi trường thực thi chính (Host Runtime): Python độc lập trong thư mục `backend/` (PySide6 QWebEngineView kết hợp Win32 API).
- Giao tiếp liên tiến trình (IPC): WebSocket nội bộ (`ws://127.0.0.1:8765`) và kênh QWebChannel Bridge.
- Cơ chế lớp phủ (Overlay): Can thiệp dải Z-Order đặc quyền `ZBID_UIACCESS` (Band 2) kết hợp cờ `WS_EX_NOACTIVATE` (0x08000000) để hiển thị đè trực tiếp lên 100% game Toàn màn hình độc quyền (Exclusive Fullscreen - FSE).

## 2. Các tính năng đã hoàn thành & Hoạt động ổn định
1. **Quản lý cửa sổ & Trải nghiệm thị giác:**
   - Mở/đóng QuickPanel trượt mượt mà có animation fade-in/fade-out, overlay lớp nền đen mờ (backdrop) toàn màn hình.
   - Hỗ trợ đóng mở linh hoạt qua nhấp chuột vào backdrop hoặc bấm hotkey.
   - Xóa bỏ hiện tượng giật lag khi điều chỉnh độ rộng Side Panel (xử lý nội bộ trong Flutter Web).
   - Giao diện người dùng hiển thị chuẩn xác, không bị lỗi layout hay co giãn bất thường.
2. **Hệ thống điều khiển phần cứng & Tiện ích:**
   - Điều chỉnh độ sáng màn hình và âm lượng hệ thống hoạt động tốt.
   - Đo đạc và hiển thị chuẩn xác tài nguyên thực tế: % CPU và % RAM trên bảng điều khiển.
   - Khay hệ thống (System Tray Icon) hoạt động tốt, hiển thị menu điều khiển và trạng thái ngầm.
   - Thao tác nhanh (Mở Task Manager `taskmgr.exe`, Mở Cài đặt Màn hình `ms-settings:display`, Dọn dẹp RAM `EmptyWorkingSet`).
   - Điều khiển công suất TDP (RyzenAdj driver Ring 0 nạp thành công, cấu hình STAPM/Fast/Slow limit mượt mà).
   - Điều khiển quạt tản nhiệt (Fan curves) bọc an toàn WMI theo nhiệt độ tức thời.
3. **Phân hệ Phím tắt & Gamepad:**
   - Bắt và gán lại phím tắt toàn cục động (Hotkey Reassignment) qua `HotkeyCaptureService` từ Python backend cho cả Bàn phím PC và Gamepad.
   - Hỗ trợ gán phím nóng mở Bảng điều khiển (Overlay) và mở Bàn phím ảo TabTip.
   - Điều hướng giao diện bằng Gamepad: Chuyển tiếp sự kiện nút bấm XInput từ Python sang WebSocket kèm cơ chế chống dội nút (Debounce).

## 3. Các vấn đề lỗi phát sinh cần khắc phục

### 3.1. Lỗi Game bị văng khỏi Exclusive Mode (thu về 720p nửa giây), mất Focus, nháy đen và Crash ứng dụng
1. **Hiện tượng thực tế trước khi khắc phục:**
   - Khi chơi game Fullscreen 720p trên màn 1080p và ấn Hotkey lần đầu: Game bị thu nhỏ về góc trái 720p trong 0.5s, Panel cũng bị co về kích thước 720p.
   - Khi đóng Panel và nhấp chuột lại vào Game: Game lấy lại Focus và kéo màn hình từ 1080p về 720p gây ra cú nháy đen màn hình (Mode Switch).
   - Khi thao tác phím nóng / tay cầm liên tục: Ứng dụng bị văng/crash do gọi WebSocket từ luồng ngoài Main Thread.

2. **Bóc trần nguyên nhân vật lý cốt lõi:**
   - **Thủ phạm 1 — DWM tắt Composed Flip khi bề mặt trống rỗng (`Alpha = 0`):** Khi Panel đóng, Flutter bỏ qua lệnh vẽ (`alpha = 0`) kết hợp `WS_EX_TRANSPARENT` khiến `dwmcore.dll` coi bề mặt Overlay là rỗng và trả quyền 720p Exclusive cho Game. Khi mở Panel, DWM ép chuyển sang 1080p Composed Mode $\rightarrow$ Giật mode switch.
   - **Thủ phạm 2 — `update_geometry` đọc nhầm 720p:** Tại mili-giây đầu tiên mở Panel, màn hình đang ở mode 720p của Game nên `_get_screen_dimensions` trả về 1280x720 và tự tay co nhỏ `self.widget` về 720p.
   - **Thủ phạm 3 — Cửa sổ con của `QWebEngineView` tự cướp Focus:** Click chuột vào Panel/Backdrop rơi vào `focusProxy()` của Chromium. Do có `StrongFocus`, Qt/Chromium tự gọi `SetFocus` cướp mất `ForegroundWindow` của Game. Đồng thời cờ `SWP_FRAMECHANGED` kích hoạt kiểm tra Fullscreen Occlusion của DXGI.
   - **Thủ phạm 4 — Xung đột đa luồng Signal Qt:** `GamepadService` và `HotkeyCaptureService` phát Signal từ `threading.Thread` thuần vào `WsServer` không qua `QueuedConnection`, làm `QWebSocket.sendTextMessage` chạy ngoài Main Thread gây Access Violation Crash.

3. **Giải pháp vật lý triệt để đã triển khai:**
   - **Cột trụ 1 — Điểm neo DWM 1x1 Pixel (`Alpha = 1/255`):** Trong `overlay_screen.dart`, luôn duy trì cố định 1 pixel ở góc `(0, 0)` với màu `Color.fromARGB(1, 0, 0, 0)` ngoài `FadeTransition`. DWM bị neo cố định ở chế độ *1080p Composed Flip* ngay từ khi mở Game, không bao giờ nhả về *720p Exclusive Mode* $\rightarrow$ Xóa bỏ 100% hiện tượng co 720p nửa giây và nháy đen.
   - **Cột trụ 2 — Khóa độ phân giải gốc (Native Resolution):** `WindowManager` lưu `native_w, native_h` lúc khởi động Desktop và không bao giờ cho phép kích thước cửa sổ tụt xuống dưới độ phân giải gốc. Loại bỏ việc co kéo `view.setGeometry` thủ công.
   - **Cột trụ 3 — Khóa Focus tuyệt đối & Bỏ `SWP_FRAMECHANGED`:**
     - Ép tạo `HWND` qua `winId()` và gán cứng `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_LAYERED` trước khi `show()`.
     - Gán `NoFocus` cho `QuickPanel`, `QWebEngineView`, và `focusProxy()`. Quét gán `WS_EX_NOACTIVATE` cho toàn bộ cửa sổ con của Chromium (`enforce_no_activate_children`).
     - Tích hợp `preserve_foreground_window` và `restore_foreground_window` bảo vệ `HWND` của Game trước mọi cú click.
     - Loại bỏ hoàn toàn cờ `SWP_FRAMECHANGED` khi bật/tắt `WS_EX_TRANSPARENT`.
   - **Cột trụ 4 — An toàn đa luồng (`QueuedConnection`):** Toàn bộ Signal IPC từ `WebBridge` và `GamepadService` sang `WsServer` đều được xếp hàng qua `Qt.ConnectionType.QueuedConnection`, loại bỏ triệt để lỗi Crash.

## 4. Các tính năng chưa kiểm tra
- **Lớp phủ RTSS Overlay:** Đã tích hợp khởi chạy tiến trình ngầm và kết nối Shared Memory, cần kiểm tra hiển thị thực tế trong game.
- **Tự động khởi động cùng Windows (Windows Startup):** Cần kiểm tra ghi khóa Registry `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.
- **Bật/tắt màn hình cảm ứng (Touchscreen Toggle):** Cần kiểm tra can thiệp thiết bị HID Touch qua PnP / PowerShell cmdlets.

## 5. Bảng trạng thái nhiệm vụ

| STT | Phân hệ / Nhiệm vụ | Mức độ | Trạng thái | Ghi chú kỹ thuật |
|---|---|---|---|---|
| 1 | Mở/đóng panel, backdrop, animation, tray, hotkey tabtip, đo CPU/RAM, độ sáng/âm lượng | Tiêu chuẩn | **Đã hoạt động tốt** | Duy trì ổn định |
| 2 | Gán lại phím tắt (Hotkey Reassignment) | **Critical** | **Đã khắc phục** | Đã kết nối `HotkeyCaptureService` Win32 GetAsyncKeyState & XInput cho cả Bàn phím & Gamepad |
| 3 | Điều khiển công suất TDP (RyzenAdj) | **Critical** | **Đã hoạt động** | RyzenAdj nạp driver Ring 0 thành công, đã thiết lập STAPM / Fast / Slow limit mượt mà |
| 4 | Điều khiển đường cong quạt (Fan curves) | **Critical** | **Đã khắc phục** | Bọc an toàn WMI Asus ROG Ally & đồng bộ luồng điều tốc theo nhiệt độ CPU tức thời |
| 5 | Độ mượt khi chỉnh kích thước Panel Width | UI Bug | **Đã khắc phục** | Flutter co giãn container nội bộ 60/120fps, không gọi Win32 SetWindowPos liên tục |
| 6 | Thao tác nhanh (Task Manager, Cài đặt màn hình, Dọn RAM) | Chức năng | **Đã khắc phục** | Đã kết nối `taskmgr.exe`, `ms-settings:display`, và `EmptyWorkingSet` qua Bridge |
| 7 | Điều hướng giao diện bằng Gamepad | **Critical** | **Đã khắc phục** | Đã chuyển tiếp (forward) sự kiện nút XInput từ Python sang WebSocket kèm Debounce |
| 8 | Game bị thu về 720p nửa giây khi mở lần đầu + Mất Focus & Nháy đen + Bị Crash ứng dụng | **Critical** | **Đã khắc phục** | Điểm neo DWM 1x1px alpha=1/255 giữ Composed Flip 1080p, khóa NoFocus trên focusProxy/children, bỏ SWP_FRAMECHANGED, và QueuedConnection chống crash |
| 9 | RTSS Overlay trong game | Chức năng | Chờ kiểm tra | Đã sẵn sàng tiến trình daemon và kết nối bộ nhớ chia sẻ |
| 10 | Tự khởi động cùng Windows & Bật/tắt Touchscreen | Chức năng | Chờ kiểm tra | Kiểm tra can thiệp Registry và thiết bị HID khi thực chiến |
