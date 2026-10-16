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

### 3.1. Lỗi Game bị văng khỏi Exclusive Mode (thu về 720p nửa giây), mất Focus và nháy đen khi click lại vào Game
1. **Hiện tượng thực tế (Chuỗi sự kiện liên hoàn):**
   - **Bước 1:** Khi đang trong game (Ready Or Not chạy Fullscreen 720p trên màn 1080p) và ấn Hotkey lần đầu: Game lập tức bị thu nhỏ về góc trái theo đúng kích thước gốc 720p trên nền Desktop 1080p trong khoảng 0.5 giây. Do game vừa nhả chế độ hiển thị, lúc này màn hình đang ở trạng thái chuyển tiếp 720p $\rightarrow$ 1080p nên Panel mở lên lần đầu cũng bị thu nhỏ theo kích thước 720p.
   - **Bước 2:** Khoảng 0.5 giây sau, Windows DWM hoàn tất chuyển đổi sang chế độ **Composed Flip (1080p Upscaled)** để vẽ đè cửa sổ trong suốt lên trên game. Lúc này khi đóng/mở lại Panel lần thứ 2 thì màn hình đã ổn định ở 1080p nên Panel hiển thị chuẩn xác full chiều cao.
   - **Bước 3:** Tuy nhiên, do ở Bước 1 cửa sổ Panel đã **cướp mất Focus (Foreground Activation)** của Game (hoặc đánh bật Game khỏi chuỗi DirectFlip), nên sau khi đóng Panel, Game vẫn nằm ở trạng thái mất Focus (Background/Inactive). Khi người dùng **nhấp chuột trở lại vào màn hình Game**, Game nhận lại Focus và yêu cầu GPU chuyển ngược từ *DWM Composed Mode (1080p)* về *Hardware Exclusive/DirectFlip Mode (720p)* $\rightarrow$ Gây ra cú **nháy màn hình đen (Black Screen Mode Switch)**.

2. **Bóc trần nguyên nhân vật lý (First Principles - Tại sao Game bị mất Focus & văng khỏi Fullscreen?):**
   - **Thủ phạm 1 — Gọi `self.widget.hide()` và `self.widget.show()` của Qt:**
     - Trong Qt (PySide6), khi gọi `self.widget.hide()`, Qt hủy trạng thái hiển thị của cửa sổ. Khi gọi lại `self.widget.show()`, nội bộ hàm `QWidgetPrivate::show_sys()` của Qt tự động gọi hàm Win32 `ShowWindow(hwnd, SW_SHOW)` và can thiệp lại các cờ `WindowFlags`.
     - Đặc biệt nguy hiểm: Khi `QWidget.hide()` rồi `QWidget.show()` được gọi, Windows hủy hoặc reset các thuộc tính mở rộng (`WS_EX_NOACTIVATE` bị Qt ghi đè lại theo `windowFlags()`, và phân lớp `ZBID_UIACCESS` có thể bị tác động). Quan trọng hơn, `self.widget.show()` của Qt kích hoạt thông điệp kích hoạt cửa sổ ngầm trước khi dòng `SetWindowPos(..., SWP_NOACTIVATE)` kịp chạy!
   - **Thủ phạm 2 — Gọi `user32.BringWindowToTop(self.hwnd)`:**
     - Theo tài liệu nhân Win32 (`win32kfull.sys`), hàm `BringWindowToTop(hwnd)` **không có cờ `NOACTIVATE`**. Khi gọi `BringWindowToTop` lên một cửa sổ đang chuẩn bị hiển thị đè lên ứng dụng Exclusive Fullscreen, Windows Window Manager sẽ đánh thức tiến trình đó và tước quyền độc quyền màn hình (Exclusive Fullscreen Ownership) của Game! Đây chính là lý do ngay khoảnh khắc bấm Hotkey, Game bị thu nhỏ về góc 720p trong nửa giây và bị mất Focus!
   - **Thủ phạm 3 — Sự kiện xuất hiện/biến mất đột ngột của cửa sổ Layered (`SWP_SHOWWINDOW` / `SWP_HIDEWINDOW`):**
     - Khi một cửa sổ có `WA_TranslucentBackground` (`WS_EX_LAYERED`) chuyển từ trạng thái `Hidden` sang `Visible` đè lên Game đang chạy chế độ **Independent Flip / Hardware Composed Flip** ở độ phân giải khác Desktop ($720\text{p}$ vs $1080\text{p}$), DWM buộc phải phá vỡ chuỗi Flip trực tiếp của Game để chèn bộ đệm Alpha Blending của Desktop vào. Khi cửa sổ đó biến mất (`SWP_HIDEWINDOW`) và người dùng click vào Game, DWM lại trả quyền Exclusive/DirectFlip cho Game $\rightarrow$ Nháy đen!

3. **Phương hướng giải quyết triệt để (Zero-Activation & Persistent DWM Composition):**
   - **Nguyên tắc 1 — Tuyệt đối KHÔNG gọi `self.widget.hide()`, `self.widget.show()` (sau lần khởi tạo đầu tiên) và `BringWindowToTop()`:**
     - Chỉ gọi `self.widget.show()` **đúng 1 lần duy nhất** lúc khởi tạo ứng dụng (khi chưa mở game), sau đó gán cứng `WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST` và đưa vào `ZBID_UIACCESS`.
     - Loại bỏ hoàn toàn mọi lệnh `user32.BringWindowToTop(self.hwnd)`. Chỉ dùng duy nhất `user32.SetWindowPos(..., HWND_TOPMOST, ..., SWP_NOACTIVATE)`.
   - **Nguyên tắc 2 — Giữ cửa sổ luôn tồn tại với `WS_EX_TRANSPARENT` (Click-Through) khi đóng thay vì `SWP_HIDEWINDOW` hoặc dời tọa độ:**
     - Thay vì ẩn cửa sổ đi (`SWP_HIDEWINDOW`) hoặc dời ra ngoài màn hình (`x = screen_w`) khiến DWM liên tục bật/tắt chế độ DirectFlip của Game (gây co giãn 720p và nháy đen):
     - Giữ cửa sổ Overlay luôn cố định ở tọa độ `(0, 0, screen_w, screen_h)` trên màn hình với độ trong suốt hoàn toàn (Flutter đã fade-out về `opacity = 0.0`).
     - **Khi đóng Panel (`_perform_physical_hide`):** Bật cờ `WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_NOACTIVATE` cho `self.hwnd`. Trong Win32, một cửa sổ có `WS_EX_LAYERED | WS_EX_TRANSPARENT` sẽ trở nên **xuyên thấu 100% với chuột và bàn phím (Click-Through)** ở cấp độ nhân OS — mọi cú click chuột đi thẳng vào Game bên dưới mà không hề chạm vào cửa sổ Overlay!
     - **Khi mở Panel (`show`):** Chỉ cần gỡ bỏ bit `WS_EX_TRANSPARENT` khỏi `GWL_EXSTYLE` để cửa sổ nhận lại tương tác chuột, và yêu cầu Flutter chạy animation Fade-In!
     - **Lợi ích vật lý tuyệt đối:**
       1. Cửa sổ Overlay không bao giờ ẩn/hiện hay thay đổi kích thước $\rightarrow$ DWM duy trì một chế độ tổng hợp duy nhất suốt quá trình chơi game $\rightarrow$ **Không bao giờ có hiện tượng Game bị thu về 720p nửa giây, không bao giờ nháy đen màn hình!**
       2. Không có bất kỳ lệnh `ShowWindow` hay `BringWindowToTop` nào được gọi $\rightarrow$ **Game giữ nguyên 100% Focus suốt thời gian mở và đóng Panel!**
       3. Mở lần thứ nhất hay lần thứ 100 đều luôn khớp chính xác 100% kích thước màn hình ngay lập tức.

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
| 8 | Game bị thu về 720p nửa giây khi mở lần đầu + Mất Focus & Nháy đen + Bị Crash ứng dụng | **Critical** | **Chưa khắc phục / Bị Crash** | Vẫn bị lỗi thu tỉ lệ 720p và nháy đen, đồng thời phát sinh lỗi văng/crash ứng dụng; cần debug lại nguyên nhân crash và cách xử lý tương thích game FSE |
| 9 | RTSS Overlay trong game | Chức năng | Chờ kiểm tra | Đã sẵn sàng tiến trình daemon và kết nối bộ nhớ chia sẻ |
| 10 | Tự khởi động cùng Windows & Bật/tắt Touchscreen | Chức năng | Chờ kiểm tra | Kiểm tra can thiệp Registry và thiết bị HID khi thực chiến |
