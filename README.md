# Handheld Quick Settings Overlay (Windows)

Công cụ Quick Settings dạng Overlay trượt từ mép phải màn hình (tương tự Steam Deck QAM / Handheld Companion / ROG Ally Command Center) dành cho các máy tính chơi game cầm tay chạy hệ điều hành Windows (ASUS ROG Ally, Lenovo Legion Go, Steam Deck Windows, MSI Claw, GPD Win...).

---

## 1. Tính năng nổi bật

* **Giao diện Overlay hiện đại**:
  * Cửa sổ không viền, nền mica/acrylic trong suốt, luôn nằm trên cùng (`TopMost`).
  * Hoạt ảnh trượt mượt mà (Slide-in) từ mép phải màn hình khi kích hoạt.
  * Tối ưu kích thước cảm ứng (Touch-friendly), có đầy đủ nút tăng/giảm bước nhảy (`-` / `+`) và thanh kéo nhanh.
* **Điều khiển phần cứng tức thì**:
  * **TDP (Công suất CPU/GPU)**: Tích hợp interface kết nối `RyzenAdj` để điều chỉnh STAPM, Fast PPT, Slow PPT (5W - 35W). Hỗ trợ chế độ mô phỏng an toàn nếu máy chưa nạp DLL.
  * **Quạt tản nhiệt (Fan Control)**: Tùy chỉnh tốc độ quạt hoặc chuyển đổi nhanh giữa chế độ Tự động (Auto) và Thủ công (Manual).
  * **Độ sáng màn hình (Brightness)**: Điều khiển trực tiếp qua Windows WMI (`WmiMonitorBrightnessMethods`).
  * **Âm lượng (Master Audio)**: Tương tác trực tiếp với Windows Core Audio Endpoint (`pycaw`), hỗ trợ nút Mute nhanh.
* **Thao tác nhanh cảm ứng**:
  * **Bàn phím ảo**: Kích hoạt trực tiếp bàn phím cảm ứng Windows (`TabTip.exe` / `osk.exe`).
  * **Chế độ Turbo 30W**: Kích hoạt nhanh mức TDP tối đa cho các tựa game nặng.
  * **Nút Tắt tiếng nhanh (Mute)**.
* **Lắng nghe phím bấm toàn cục (Global Input)**:
  * **Gamepad (XInput)**: Luồng ngầm theo dõi tổ hợp phím tay cầm (mặc định: `Back + R1 / Right Shoulder`) để mở/đóng menu khi đang ở trong game.
  * **Bàn phím vật lý**: Phím tắt toàn cục (mặc định: `Ctrl + Shift + Q` để bật/tắt Quick Settings, `Ctrl + Shift + K` để bật bàn phím ảo).
  * **Khay hệ thống (System Tray)**: Icon ứng dụng ở góc taskbar với menu chuột phải và hỗ trợ click đúp để mở menu.

---

## 2. Cấu trúc thư mục dự án

Dự án tuân thủ nghiêm ngặt nguyên tắc **Separation of Concerns (SoC)** và **Don't Repeat Yourself (DRY)**:

```
windows-handheld-tools/
├── core/
│   ├── config.py              # Đọc/ghi cấu hình config.json (TDP range, hotkey...)
│   └── logger.py              # Hệ thống log chuẩn hóa UTF-8
├── hardware/
│   ├── base.py                # Lớp cơ sở trừu tượng HardwareController
│   ├── brightness.py          # Điều khiển độ sáng màn hình qua WMI
│   ├── audio.py               # Điều khiển âm lượng qua Windows Core Audio
│   ├── tdp.py                 # Điều khiển TDP APU qua RyzenAdj DLL
│   └── fan.py                 # Điều khiển quạt tản nhiệt (WMI / EC)
├── input_handler/
│   ├── gamepad.py             # Luồng nền theo dõi phím bấm Gamepad (XInput)
│   └── hotkey.py              # Quản lý phím tắt bàn phím toàn cục
├── services/
│   └── virtual_keyboard.py    # Kích hoạt TabTip / bàn phím ảo Windows
├── ui/
│   ├── styles.py              # Stylesheet QSS giao diện tối Handheld
│   ├── quick_panel.py         # Panel nội dung Quick Settings
│   ├── overlay_window.py      # Cửa sổ trượt mép phải màn hình
│   └── widgets/
│       ├── setting_slider.py  # Widget thanh trượt chuẩn hóa (DRY)
│       └── action_button.py   # Widget nút bấm cảm ứng lớn
├── config.json                # File lưu trữ cài đặt người dùng
├── requirements.txt           # Danh sách thư viện phụ thuộc
├── run.bat                    # Script khởi động nhanh
└── main.py                    # Điểm khởi chạy chính của ứng dụng
```

---

## 3. Hướng dẫn sử dụng

### Cách 1: Khởi chạy nhanh bằng file Batch
Nhấp đúp vào file `run.bat` trong thư mục dự án. Script sẽ tự động phát hiện môi trường ảo `.venv` và khởi chạy ứng dụng ngầm không hiện cửa sổ console đen.

### Cách 2: Khởi chạy qua dòng lệnh Terminal
```powershell
.\.venv\Scripts\python.exe main.py
```

### Thao tác điều khiển:
* Nhấn `Ctrl + Shift + Q` hoặc tổ hợp Gamepad `Back + R1` để mở/đóng bảng cài đặt bên phải.
* Nhấn phím `Esc` hoặc bấm nút `✕` góc trên bên phải để ẩn bảng cài đặt.
* Nhấp vào icon hình tròn chữ **H** màu xanh Neon ở góc khay hệ thống (System Tray) để bật/tắt hoặc thoát ứng dụng.

---

## 4. Tùy biến và Bật phần cứng AMD (RyzenAdj)
* Để ứng dụng can thiệp trực tiếp vào SMU/MSR của CPU AMD (ROG Ally, Legion Go, Steam Deck):
  1. Tải file `ryzenadj.dll` (phiên bản 64-bit) từ kho RyzenAdj chính thức.
  2. Tạo thư mục `bin/` trong dự án và đặt file `ryzenadj.dll` vào `windows-handheld-tools/bin/ryzenadj.dll`.
  3. Khởi chạy ứng dụng với quyền **Run as Administrator** để Windows cho phép ghi vào thanh ghi SMU.
