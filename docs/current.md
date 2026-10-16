# Tình trạng hiện tại của dự án

## 1. Kiến trúc tổng thể
- Giao diện (Frontend): Flutter Web (HTML/JS/CanvasKit) biên dịch tại thư mục `build/web`.
- Môi trường thực thi chính (Host Runtime): Python (PySide6 QWebEngineView kết hợp Win32 API).
- Giao tiếp liên tiến trình (IPC): WebSocket nội bộ (`ws://127.0.0.1:54321`) và kênh QWebChannel Bridge.
- Cơ chế lớp phủ (Overlay): Can thiệp dải Z-Order đặc quyền `ZBID_UIACCESS` (Band 2) kết hợp cờ `WS_EX_NOACTIVATE` (0x08000000) để hiển thị đè trực tiếp lên 100% game Toàn màn hình độc quyền (Exclusive Fullscreen - FSE).

## 2. Tiến độ đã hoàn thành
- Chuyển đổi thành công kiến trúc từ Flutter Desktop sang Flutter Web kết hợp nền tảng Python Host.
- Bảng điều khiển QuickPanel trượt mượt mà từ mép phải màn hình, hỗ trợ phím tắt bàn phím và tay cầm Gamepad.
- Hiển thị dữ liệu đo đạc tài nguyên thực tế: % CPU, dung lượng RAM đã dùng trên tổng dung lượng (GB) qua dịch vụ `system_telemetry.py`.
- Xóa bỏ triệt để hiện tượng màn hình nháy đen (Display Mode Switch):
  - Bổ sung cờ `WindowDoesNotAcceptFocus` và thuộc tính `WA_ShowWithoutActivating` trên QuickPanel.
  - Loại bỏ hoàn toàn các lệnh cướp tiêu điểm `SetForegroundWindow` và `activateWindow()`.
  - Chặn thông điệp Win32 `WM_MOUSEACTIVATE` và trả về `MA_NOACTIVATE = 3` nhằm bảo toàn tiêu điểm cho game FSE.
- Xử lý dứt điểm lỗi lệch tọa độ và sai kích thước bảng điều khiển khi mở lần đầu:
  - Truy vấn trực tiếp kích thước khung nhìn thực tế từ `GetForegroundWindow()` và `GetClientRect()`, đảm bảo panel khớp chuẩn xác độ phân giải của game ngay cả khi game chạy ở độ phân giải thấp hơn màn hình desktop (ví dụ: game 720p/900p trên màn hình 1080p).
- Đồng bộ và tự động kích hoạt tiến trình RivaTuner Statistics Server từ Python:
  - Tích hợp phương thức `ensure_running()` tự động khởi chạy ngầm `RTSS.exe` nếu tiến trình chưa hoạt động.
  - Tự động kiểm tra và cấu hình kích hoạt `[OSD]\nEnableOSD=1` trong tệp cấu hình `Profiles\Global` của RTSS.
  - Tự động liên kết vùng nhớ chia sẻ `RTSSSharedMemoryV2` và nạp dữ liệu chuỗi văn bản OSD.
- Cập nhật tài liệu kiến trúc chuẩn First Principles và lược bỏ toàn bộ các khuyến nghị chuyển sang Borderless Windowed trong `note.md`.

## 3. Các vấn đề chưa ổn định & Lỗi đã biết (Known Bugs)
- Lớp phủ RTSS OSD: Đã hoàn thiện mã nguồn tự động bật tiến trình ngầm và ghi dữ liệu bộ nhớ chia sẻ, hiện đang chờ người dùng kiểm chứng thực tế trong game để xác nhận thông số hiển thị trực quan lên màn hình.
- Tùy chỉnh công suất TDP: Hiện tại chưa tác động được vào phần cứng dù ứng dụng đã được khởi chạy với quyền Administrator (cần kiểm tra luồng gửi lệnh WebSocket từ Flutter sang Python và quyền thực thi thư viện điều khiển RyzenAdj / WinRing0).
- Tùy chỉnh đường cong quạt tản nhiệt (Fan curves): Chưa áp dụng được tốc độ quạt thực tế (cần kiểm tra cơ chế đọc/ghi qua vi điều khiển nhúng Embedded Controller - EC).
- Phím tắt bàn phím ảo: Có hiện tượng hoạt động chưa ổn định trên một số tựa game, cần rà soát lại dịch vụ `VirtualKeyboardService`.

## 4. Danh sách nhiệm vụ & Trạng thái

| STT | Nhiệm vụ | Trạng thái | Ghi chú |
|---|---|---|---|
| 1 | Sửa lỗi nháy đen khi mở/đóng panel trong game FSE | Hoàn thành | Đã áp dụng Focus Lock & MA_NOACTIVATE |
| 2 | Sửa lệch tọa độ/kích thước panel khi game chạy độ phân giải thấp | Hoàn thành | Đọc trực tiếp ClientRect từ ForegroundWindow |
| 3 | Tự động kích hoạt daemon RTSS và bật EnableOSD | Hoàn thành | Đã thêm ensure_running trong rtss_service.py |
| 4 | Kiểm chứng thực tế trong game (FSE Overlay + RTSS OSD) | Đang chờ kiểm tra | Chờ mở game kiểm tra trực quan |
| 5 | Khắc phục phân hệ điều khiển TDP (RyzenAdj / WinRing0) | Chưa thực hiện | Cần kiểm tra WebSocket action & quyền driver |
| 6 | Khắc phục phân hệ điều khiển Fan curves (EC Control) | Chưa thực hiện | Cần kiểm tra giao tiếp EC |
| 7 | Kiểm tra độ ổn định của phím tắt mở bàn phím ảo | Chưa thực hiện | Cần rà soát VirtualKeyboardService |
