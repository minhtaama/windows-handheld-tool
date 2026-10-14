# Kiến Trúc Lớp Phủ Hệ Thống (Windows System Z-Band) Và Lọc Nhập Liệu Cấp Nhân (Kernel Input Filter)

Tài liệu này đúc kết toàn bộ cơ sở khoa học, bản chất vật lý của hệ điều hành Windows và lộ trình kỹ thuật triển khai hệ thống lớp phủ bảng điều khiển (Gaming Overlay) cho thiết bị máy tính cầm tay, phân tách triệt để thành 2 công đoạn độc lập theo nguyên lý phân ly bài toán (Separation of Concerns).

---

## 1. Nguyên Lý Phân Tách Hai Trục Vật Lý Trong Hệ Điều Hành

Một hệ thống lớp phủ chơi game (Gaming Overlay) trên Windows chịu sự chi phối của hai trục vật lý hoàn toàn độc lập:

1. **Trục hiển thị bề mặt và thứ tự lớp cửa sổ (Surface Composition & Window Z-Order)**:
   - Do Bộ quản lý Cửa sổ Máy tính (Desktop Window Manager - DWM) và chuỗi xuất hình của card đồ họa (GPU Scanout Pipeline) điều phối.
   - Bản chất: Đảm bảo điểm ảnh của bảng điều khiển vẽ đè lên điểm ảnh của trò chơi mà không làm gián đoạn chu kỳ xuất hình của trò chơi ra màn hình vật lý.
2. **Trục thu thập và phân phối tín hiệu điều khiển (Peripheral Input Polling & Dispatching)**:
   - Do hệ thống con nhập liệu (XInput / Raw Input Subsystem) và trình điều khiển thiết bị nhân (Kernel Device Driver) điều phối.
   - Bản chất: Đảm bảo khi người dùng thao tác phím bấm hoặc cần điều khiển trên bảng điều khiển, trò chơi không tiếp tục tiếp nhận các tín hiệu đó để tránh kích hoạt hành động không mong muốn trong không gian ảo (Ghost Input / Input Leakage).

---

## 2. Xuất Phát Từ Bế Tắc Thực Tế (The "Why")

- **Trước đây làm bằng cách nào?**:
  - Dồn toàn bộ hai trục vật lý vào một điểm can thiệp duy nhất: Tiêm tập tin nhị phân chèn mã ([[Móc Đồ Họa DXGI (DXGI Hook)]] - phương pháp can thiệp trực tiếp vào bảng địa chỉ hàm ảo trong không gian nhớ của trò chơi) để vừa cưỡng bức cửa sổ chuyển sang chế độ không viền (Borderless Windowed), vừa chặn đứng hàm đọc tay cầm (`XInputGetState`).
- **Bị nghẽn kỹ thuật gì?**:
  1. Khi gặp trò chơi tích hợp cơ chế bảo vệ cấp nhân (Kernel Anti-Cheat như BattlEye, Vanguard) hoặc sử dụng API đồ họa khác (Vulkan, OpenGL), việc tiêm mã bị chặn đứng hoàn toàn $\rightarrow$ Lớp phủ không thể hiển thị trên trò chơi độc quyền, gây biến mất hoặc làm sập tiến trình.
  2. Việc móc chuỗi khung hình đồ họa phụ thuộc nặng nề vào cấu trúc engine (như Far Cry 5 văng do bão thông điệp `WM_SIZE` tại `ResizeTarget`, Dead Island 2 lỗi con trỏ rỗng tại `GetFullscreenState`, Metro Exodus bị bóp nghẽn FPS do tiêu điểm cửa sổ).
  3. Vi phạm nguyên lý phân ly trách nhiệm khi bắt một mô-đun đồ họa phải gánh thêm việc lọc tín hiệu tay cầm.
- **Công nghệ mới giải quyết triệt để ra sao?**:
  - **Trục hiển thị (Công đoạn 1)**: Đưa cửa sổ lên thẳng Phân lớp Công cụ Hệ thống (`ZBID_SYSTEM_TOOLS = 2`) với cờ đặc quyền `TokenUIAccess`. DWM tự động ghép nối bề mặt hiển thị ở tầng bộ trộn màn hình, cho phép vẽ đè tự nhiên lên mọi trò chơi mà không cần chạm vào một byte bộ nhớ của trò chơi.
  - **Trục nhập liệu (Công đoạn 2)**: Sử dụng trình điều khiển lọc thiết bị ở tầng nhân ([[Trình Điều Khiển Lọc HidHide (HidHide Filter Driver)]]), ngắt quyền đọc thiết bị của trò chơi từ bên ngoài, xóa bỏ vĩnh viễn sự tồn tại của kỹ thuật tiêm mã DLL.

---

## 3. Lộ Trình Kỹ Thuật Hai Công Đoạn (Two-Stage Execution Roadmap)

```mermaid
flowchart TD
    subgraph Stage_1["Công Đoạn 1: Tối Ưu Hiển Thị Tuyệt Đối (Production UI Foundation)"]
        S1_Manifest["Thiết lập cờ uiAccess trong Manifest"]
        S1_Cert["Tạo và nạp chứng chỉ số Authenticode nội bộ"]
        S1_ZBand["Gán phân lớp ZBID_SYSTEM_TOOLS trong C++ Runner"]
        S1_Cleanup["Xóa sạch 100% mã nguồn DXGI Hook và Input Muting cũ"]
        S1_Manifest --> S1_Cert --> S1_ZBand --> S1_Cleanup
    end

    subgraph Stage_1_State["Trạng Thái Vận Hành Sau Công Đoạn 1"]
        S1_UI["Lớp phủ hiển thị ổn định trên mọi game (DX11, DX12, Vulkan, Anti-Cheat)"]
        S1_Input["Tạm thời chấp nhận cả game và lớp phủ cùng nhận tín hiệu Gamepad"]
    end

    subgraph Stage_2["Công Đoạn 2: Chặn Nhập Liệu Tầng Nhân (Kernel-Level Input Muting)"]
        S2_HidHide["Giao tiếp trình điều khiển lọc tầng nhân hidhide.sys qua IOCTL"]
        S2_PID["Tạm thời ẩn Gamepad vật lý đối với PID của game khi mở panel"]
        S2_Restore["Khôi phục quyền truy cập Gamepad cho game khi đóng panel"]
        S2_HidHide --> S2_PID --> S2_Restore
    end

    Stage_1 --> Stage_1_State
    Stage_1_State -->|Kiểm thử ổn định đạt chuẩn Production| Stage_2
```

---

## 4. Công Đoạn 1: Triển Khai Windows System Z-Band & Dọn Dẹp Toàn Bộ DXGI Hook

### Bản chất vật lý của cơ chế bảo vệ UIAccess
Để ngăn chặn mã độc lợi dụng việc vẽ đè lên các màn hình đăng nhập bảo mật (như UAC Prompt), nhân hệ điều hành Windows (`ntoskrnl.exe`) chỉ cấp cờ đặc quyền `TokenUIAccess` vào thẻ định danh tiến trình khi thỏa mãn đồng thời **3 điều kiện vật lý**:
1. Tập tin nhị phân khai báo thuộc tính `uiAccess="true"` trong tài nguyên Manifest.
2. Tập tin nhị phân được gắn chữ ký số Authenticode bắt nguồn từ một Nhà cấp chứng chỉ tin cậy nằm trong kho máy tính cục bộ (`LocalMachine\Root` và `LocalMachine\TrustedPublisher`).
3. Tập tin nhị phân nằm trong thư mục được bảo vệ của hệ điều hành (`C:\Program Files` hoặc `C:\Windows\System32`).

### Các bước kỹ thuật thực hiện chi tiết

#### Bước 1: Khai báo đặc quyền trong Manifest ứng dụng
- Mở tập tin cấu hình manifest: `windows/runner/runner.exe.manifest`.
- Tìm thẻ `requestedExecutionLevel` trong nhánh `trustInfo` -> `security` -> `requestedPrivileges`.
- Thiết lập cú pháp: `<requestedExecutionLevel level="asInvoker" uiAccess="true"/>`.

#### Bước 2: Tạo chứng chỉ số ký mã nội bộ (Self-Signed Code Signing Certificate)
- Khởi chạy PowerShell với quyền Quản trị viên (Run as Administrator).
- Tạo chứng chỉ ký mã thời hạn 10 năm lưu vào kho cá nhân của máy cục bộ bằng lệnh:
  `New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=HandheldToolsSigner" -CertStoreLocation "Cert:\LocalMachine\My" -KeySpec Signature -NotAfter (Get-Date).AddYears(10)`
- Trích xuất con trỏ chứng chỉ vừa tạo:
  `$cert = (Get-ChildItem Cert:\LocalMachine\My -CodeSigningCert | Where-Object Subject -match "HandheldToolsSigner")[0]`
- Nạp chứng chỉ vào kho Chứng chỉ Gốc Tin cậy (Trusted Root Certification Authorities):
  `$rootStore = Get-Item Cert:\LocalMachine\Root; $rootStore.Open("ReadWrite"); $rootStore.Add($cert); $rootStore.Close()`
- Nạp chứng chỉ vào kho Nhà phát hành Tin cậy (Trusted Publishers):
  `$pubStore = Get-Item Cert:\LocalMachine\TrustedPublisher; $pubStore.Open("ReadWrite"); $pubStore.Add($cert); $pubStore.Close()`

#### Bước 3: Đưa cửa sổ vào Z-Band trong mã nguồn C++ Runner
- Trong tập tin điều khiển cửa sổ Win32 (`windows/runner/win32_window.cpp`):
  - Định nghĩa chỉ số phân lớp công cụ hệ thống: `#define ZBID_SYSTEM_TOOLS 2`.
  - Khai báo kiểu con trỏ hàm nội bộ của Windows:
    `typedef BOOL (WINAPI *pfnSetWindowBand)(HWND hWnd, HWND hwndInsertAfter, DWORD dwBand);`.
  - Trong phương thức khởi tạo cửa sổ (sau khi hàm tạo cửa sổ hoàn tất tạo ra `m_hwnd`):
    `pfnSetWindowBand SetWindowBand = (pfnSetWindowBand)GetProcAddress(GetModuleHandleW(L"user32.dll"), "SetWindowBand");`
    `if (SetWindowBand) SetWindowBand(m_hwnd, NULL, ZBID_SYSTEM_TOOLS);`.

#### Bước 4: Dọn dẹp triệt để toàn bộ mã nguồn DXGI Hook (Tuân thủ nguyên tắc không tương thích ngược)
- **Tầng mã nguồn C++**:
  - Xóa bỏ hoàn toàn thư mục `windows/dxgi_hook/` gồm các tập tin `dxgi_hook.cpp`, `dxgi_hook.h`, `dxgi.def`, thư viện MinHook đi kèm.
  - Xóa bỏ lệnh nạp thư mục con `add_subdirectory("dxgi_hook")` trong `windows/CMakeLists.txt`.
  - Xóa bỏ tập tin script biên dịch `build_dxgi_hook.bat`.
  - Xóa bỏ tập tin script đóng gói cũ `package_release.bat`.
- **Tầng dịch vụ Dart / Flutter**:
  - Xóa bỏ hoàn toàn tập tin `lib/services/dxgi_hook_service.dart`.
  - Trong `lib/services/overlay_controller.dart`:
    - Xóa bỏ việc nhập thư viện `dxgi_hook_service.dart`.
    - Xóa bỏ toàn bộ các lệnh gọi `DxgiHookService.instance.setOverlayActive(true)` tại phương thức `showOverlay()` và `setOverlayActive(false)` tại phương thức `hideOverlay()`.
  - Trong `lib/main.dart`:
    - Xóa bỏ đoạn mã khởi tạo `DxgiHookService.instance.init(config)`.

#### Bước 4.1: Đồng bộ cơ chế hòa trộn khung hình DWM và vượt rào cản cách ly đặc quyền UIPI

##### 1. Bản chất vật lý của sự cố màn hình đen khi mở lớp phủ
- **Trước đây làm bằng cách nào?**: Ứng dụng gọi hàm gán thuộc tính cửa sổ phân tầng (`SetLayeredWindowAttributes`) với cờ chỉ định độ mờ (`LWA_ALPHA`) và tham số 255 nhằm mục đích yêu cầu cửa sổ hiển thị rõ nét 100%.
- **Bị nghẽn/thảm họa kỹ thuật gì?**: Bộ dựng hình Flutter trên Windows kết xuất khung hình bằng Direct3D 11 và DirectComposition swapchain với 4 kênh màu ARGB độc lập (Per-Pixel Alpha). Khi gọi hàm `SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA)`, bộ ghép hình DWM (Desktop Window Manager) lập tức ngắt bỏ cơ chế hòa trộn độ mờ từng điểm ảnh (Per-Pixel Alpha Blending) và ép toàn bộ bề mặt cửa sổ nhận một hệ số mờ đồng nhất (Constant Alpha = 255). Do vùng không gian bên trái bảng điều khiển có giá trị màu là 0 nhưng độ mờ bị ép thành 255, DWM hiển thị vùng này thành màu đen đặc (Black Opaque), biến toàn bộ màn hình thành một tấm màn đen sì che khuất trò chơi bên dưới.
- **Giải quyết triệt để ra sao?**:
  - Loại bỏ hoàn toàn 100% các lệnh gọi hàm `SetLayeredWindowAttributes` trong cả tầng C++ (`win32_window.cpp`) và tầng Dart (`native_window_service.dart`).
  - Mở rộng khung viền DWM vào toàn bộ vùng thao tác của cửa sổ bằng hàm `DwmExtendFrameIntoClientArea(window, &margins)` với lề âm `MARGINS{-1, -1, -1, -1}`. Thao tác này trao toàn quyền hòa trộn độ trong suốt cho kênh Alpha của DirectComposition, giúp vùng trống hoàn toàn trong suốt nhìn xuyên thấu xuống màn hình trò chơi.
  - Bắt thông điệp xóa nền `WM_ERASEBKGND` và trả về giá trị 1 để ngăn chặn thư viện đồ họa GDI tự ý quét cọ màu đen/trắng lên khung hình.

##### 2. Bản chất vật lý của sự cố khay hệ thống (System Tray) không phản hồi
- **Trước đây làm bằng cách nào?**: Thư viện quản lý khay hệ thống (`tray_manager`) sử dụng hàm API Windows `Shell_NotifyIcon` để tạo biểu tượng và đăng ký mã thông điệp phản hồi là `WM_USER + 1` (giá trị số `0x0401`).
- **Bị nghẽn/thảm họa kỹ thuật gì?**: Khi ứng dụng được cấu hình đặc quyền `uiAccess="true"`, tiến trình của ứng dụng được hệ điều hành nâng cấp mức toàn vẹn bảo mật (Integrity Level) lên mức rất cao (`UIAccess`). Trong khi đó, tiến trình quản lý thanh tác vụ Windows (`explorer.exe`) chạy ở mức toàn vẹn bình thường (`Medium Integrity`). Khi người dùng click chuột vào biểu tượng khay hệ thống, `explorer.exe` gửi gói thông điệp `0x0401` tới cửa sổ ứng dụng. Tường lửa hạt nhân của hệ điều hành Windows (`win32k.sys`) kích hoạt cơ chế cách ly đặc quyền giao diện (User Interface Privilege Isolation - UIPI) và lập tức chặn đứng, tiêu hủy (drop) gói thông điệp này ngay tại hàng đợi (Message Queue) vì người gửi có mức đặc quyền thấp hơn người nhận. Hậu quả là ứng dụng hoàn toàn không nhận được tín hiệu nhấp chuột lẫn lệnh hiển thị menu ngữ cảnh (`TrackPopupMenu`).
- **Giải quyết triệt để ra sao?**:
  - Khai báo mở bộ lọc thông điệp toàn cục và theo từng cửa sổ thông qua các hàm Win32 API: `ChangeWindowMessageFilter` và `ChangeWindowMessageFilterEx`.
  - Cấp phép xuyên qua tường lửa UIPI cho 3 thông điệp thiết yếu:
    - Thông điệp phản hồi khay hệ thống: `WM_USER + 1` (cờ `MSGFLT_ALLOW = 1`).
    - Thông điệp chọn mục trên trình đơn: `WM_COMMAND`.
    - Thông điệp tái tạo khay hệ thống khi Explorer khởi động lại: chuỗi định danh đã đăng ký `RegisterWindowMessageW(L"TaskbarCreated")`.

##### 3. Bản chất vật lý của sự cố nuốt chuột và Phân tích tối ưu: Right Dock Window vs. Fullscreen Overlay
- **Trước đây làm bằng cách nào?**: Ứng dụng tạo một cửa sổ toàn màn hình bao phủ 100% diện tích hiển thị (`1920x1080`), dự định bắt thông điệp `WM_NCHITTEST` trên cửa sổ cha (`FLUTTER_RUNNER_WIN32_WINDOW`) để trả về `HTTRANSPARENT` cho vùng bên trái và `HTCLIENT` cho Side Panel bên phải.
- **Bị nghẽn/thảm họa kỹ thuật gì?**:
  1. *Cửa sổ con nuốt chuột*: Kiến trúc Flutter Windows Runner chia làm 2 tầng: Cửa sổ cha (`FLUTTER_RUNNER_WIN32_WINDOW`) và Cửa sổ con chứa khung vẽ đồ họa DirectX (`FLUTTER_VIEW_WINDOW`). Khi chuột tương tác, Windows gửi `WM_NCHITTEST` tới cửa sổ con nằm sâu nhất dưới tọa độ con trỏ. Thủ tục cửa sổ của `FLUTTER_VIEW_WINDOW` (bên trong `flutter_windows.dll`) mặc định luôn trả về `HTCLIENT` cho toàn bộ tọa độ trên màn hình. Do đó, mã lọc `WM_NCHITTEST` ở cửa sổ cha bị bỏ qua hoàn toàn, khiến toàn màn hình bị nuốt trọn chuột.
  2. *Thanh tác vụ Windows 11 ngắt kết nối khay hệ thống khi ẩn*: Khi dùng lệnh `ShowWindow(hwnd, SW_HIDE)` để ẩn cửa sổ, tiến trình `explorer.exe` của Windows 11 kiểm tra `IsWindowVisible(hwnd) == FALSE` và tự động hủy bỏ (drop) mọi thông điệp click chuột `WM_USER + 1`, làm icon khay hệ thống bị tê liệt hoàn toàn.
- **So sánh tối ưu giữa hai phương án giải quyết triệt để**:

```mermaid
flowchart TD
    subgraph PA_A["Phương Án A: Right Dock Window (Tối ưu tuyệt đối)"]
        A1["Cửa sổ Win32 chỉ có kích thước đúng bằng Panel: Width = 35% màn hình, Height = 100%"]
        A2["VRAM Swapchain chỉ cấp phát ~1.9 MB (giảm 70% VRAM so với Fullscreen)"]
        A3["65% màn hình bên trái trống rỗng vật lý -> Chuột tương tác Desktop/Game 100% tự nhiên không cần Hit-Test"]
        A4["Khi đóng: Dời tọa độ ra ngoài màn hình (Off-screen) giữ IsWindowVisible=TRUE -> System Tray hoạt động vĩnh viễn"]
    end
    subgraph PA_B["Phương Án B: Fullscreen Transparent Overlay (Nặng & Phức tạp)"]
        B1["Cửa sổ bao phủ toàn màn hình 1920x1080 (hoặc 2560x1600 trên máy Handheld 2K)"]
        B2["VRAM Swapchain tiêu tốn 16-50 MB cho 65% vùng trống vô hình"]
        B3["Phải gán WS_EX_TRANSPARENT vào cửa sổ con FLUTTER_VIEW_WINDOW để luồn lách thông điệp WM_NCHITTEST"]
        B4["DWM phải gánh tải phối trộn Alpha Blending toàn màn hình ở mọi chu kỳ quét 60Hz/120Hz"]
    end
```

| Tiêu chí kỹ thuật | Phương án A: Right Dock Window (Khuyến nghị) | Phương án B: Fullscreen + Hit-Test Hack |
| :--- | :--- | :--- |
| **Tiêu tốn bộ nhớ VRAM** | **Rất thấp**: Bộ đệm tráo đổi (Swapchain) chỉ cấp phát dải 450x1080 (~1.9 MB/buffer), tiết kiệm tới ~70% VRAM. | **Rất cao**: Cấp phát toàn màn hình 1920x1080 (hoặc 2560x1600), lãng phí 16 - 50 MB VRAM cho khoảng trống vô hình. |
| **Gánh nặng GPU & DWM** | **Tối ưu**: DWM chỉ phối trộn dải mép phải. Vùng bên trái trống hoàn toàn, game kích hoạt cơ chế độc chiếm phần cứng (Independent Flip). | **Nặng nề**: DWM phải phối trộn kênh Alpha toàn màn hình liên tục ở từng chu kỳ quét 60Hz/120Hz. |
| **Cơ chế chuột & Cảm ứng** | **Vật lý tự nhiên**: Vùng bên trái không có cửa sổ che chắn, chuột rơi thẳng xuống Desktop/Game. Vùng Panel nhận chuột tự nhiên. | **Luồn lách thông điệp**: Phải gán `WS_EX_TRANSPARENT` vào cửa sổ con để chuyển tiếp `WM_NCHITTEST` lên cha, tiềm ẩn xung đột gesture. |
| **Độ ổn định System Tray** | **Tuyệt đối**: Cửa sổ thu nhỏ 1x1 hoặc đưa Off-screen khi đóng, duy trì `IsWindowVisible = TRUE` cho Windows 11 Taskbar. | **Tương tự**: Phải đưa Off-screen khi đóng để tránh `SW_HIDE` làm chết kết nối khay hệ thống. |
| **Điều chỉnh độ rộng Panel** | **Trực tiếp**: Dart gọi `SetWindowPos` co dãn kích thước vật lý tức thời khi kéo slider Cài đặt. | **Gián tiếp**: Phải đồng bộ thuộc tính `SetPropW` xuống Win32 để tính lại ranh giới `boundaryX`. |

- **Kết luận giải pháp triệt để**:
  - **Phương án A (Right Dock Window)** tối ưu và vượt trội hơn toàn diện về hiệu năng phần cứng, mức tiêu thụ VRAM, độ mượt mà của Game và sự trong sáng của mã nguồn Win32.
  - Khi triển khai: Cửa sổ Win32 khởi tạo neo sát mép phải với chiều rộng `panelWidth`. Khi đóng, dời cửa sổ ra tọa độ ngoài màn hình (`X = screenWidth, Y = 0`) mà không dùng `SW_HIDE` để giữ kết nối khay hệ thống. Khi mở, dịch chuyển về `X = screenWidth - panelWidth` và hiển thị bằng `SWP_NOACTIVATE`. Khi người dùng kéo thanh trượt độ rộng, gọi `SetWindowPos` cập nhật trực tiếp kích thước cửa sổ.

#### Bước 5: Ký số tập tin thực thi sau khi biên dịch
- Sau khi đóng gói ứng dụng bản Release (`flutter build windows --release`), định vị công cụ `signtool.exe` trong Windows SDK (thường tại `C:\Program Files (x86)\Windows Kits\10\bin\<version>\x64\signtool.exe`).
- Thực thi lệnh ký số nhị phân:
  `signtool.exe sign /sm /s My /n "HandheldToolsSigner" /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 "build\windows\x64\runner\Release\windows_handheld_tools.exe"`.

#### Bước 6: Cài đặt và nghiệm thu trong thư mục bảo mật

##### Cấu trúc tập tin bắt buộc khi chép vào thư mục an toàn
- Do ứng dụng Flutter trên Windows vận hành theo mô hình đóng gói thư mục liên kết động (Application Bundle), nhân Windows (`ntoskrnl.exe`) chỉ cấp quyền `TokenUIAccess` khi tập tin `.exe` có cờ `uiAccess="true"` cư ngụ tại thư mục an toàn của hệ điều hành (`C:\Program Files\`), đồng thời bộ nạp liên kết động (Dynamic Linker) yêu cầu các thư viện dùng chung phải nằm cạnh tập tin thực thi để nạp vào cùng một không gian địa chỉ ảo.
- Bắt buộc phải sao chép **toàn bộ thư mục đóng gói Release**, bao gồm:
  - Tập tin thực thi chính: `windows_handheld_tool.exe` (đã ký số Authenticode).
  - Toàn bộ các thư viện liên kết động: `flutter_windows.dll`, các `.dll` của plugin (`window_manager_plugin.dll`, `tray_manager_plugin.dll`, `screen_retriever_windows_plugin.dll`), và các thư viện điều khiển phần cứng (`ryzenadj.dll`, `libryzenadj.dll`, `WinRing0x64.dll`, `WinRing0x64.sys`, `inpoutx64.dll`).
  - Toàn bộ thư mục dữ liệu: `data/` (chứa `icudtl.dat` và thư mục con `flutter_assets/` lưu trữ bytecode Dart, hình ảnh, phông chữ).
  - Tập tin cấu hình: `config.json`.

##### Phương thức phân phối: Kịch bản thử nghiệm nội bộ và Bộ cài đặt phát hành
- **Giai đoạn phát triển và kiểm thử nội bộ**:
  - Không xây dựng gói cài đặt `.msi` để tránh tốn thời gian cài đặt và gỡ bỏ liên tục trong vòng lặp thử nghiệm.
  - Sử dụng hai tập tin kịch bản chuyên biệt chạy với quyền Quản trị viên:
    - `deploy_test.bat`: Tự động ngắt tiến trình `windows_handheld_tool.exe` đang chạy, tạo thư mục an toàn `C:\Program Files\WindowsHandheldTools\`, đồng bộ toàn bộ nội dung thư mục Release sang đó và tự động khởi chạy ứng dụng để kiểm thử.
    - `uninstall_test.bat`: Cưỡng bức đóng tiến trình và xóa sạch toàn bộ thư mục `C:\Program Files\WindowsHandheldTools\` để đưa môi trường về trạng thái ban đầu trước mỗi lần triển khai mới.
- **Giai đoạn phát hành hoàn chỉnh cho người dùng cuối (Production Release)**:
  - Sau khi hoàn thành cả Công đoạn 1 và Công đoạn 2, đóng gói toàn bộ thành một trình cài đặt tự động duy nhất (sử dụng Inno Setup tạo `setup.exe` hoặc WiX Toolset tạo `.msi`).
  - Trình cài đặt tự động thực hiện 3 tác vụ có quyền Quản trị viên:
    1. Nạp chứng chỉ ký số nội bộ vào kho `LocalMachine\Root` và `LocalMachine\TrustedPublisher`.
    2. Giải nén toàn bộ thư mục ứng dụng vào `C:\Program Files\WindowsHandheldTools\`.
    3. Thiết lập lối tắt khởi chạy cùng hệ thống (Startup Shortcut).

##### Tiêu chí nghiệm thu Công đoạn 1
1. Cửa sổ lớp phủ hiển thị đè mượt mà lên các trò chơi Direct3D 11, Direct3D 12, Vulkan, OpenGL ở cả chế độ Toàn màn hình độc quyền (Exclusive Fullscreen) và Cửa sổ không viền.
2. Không xảy ra hiện tượng sập tiến trình (Crash) khi thay đổi độ phân giải màn hình hoặc khi mở/đóng bảng điều khiển.
3. Dự án hoàn toàn không còn bất kỳ tập tin nhị phân chèn mã DLL nào chạy ngầm.
4. Chấp nhận đặc tính tạm thời: Nút bấm trên tay cầm điều khiển song song cả bảng điều khiển và hành động nhân vật trong trò chơi.
5. Bảo toàn và duy trì hoạt động 100% của toàn bộ hệ thống tính năng phần cứng:
   - Lớp phủ thông số hiệu năng RTSS OSD Overlay (FPS, CPU, GPU, RAM, Frametime) qua bộ nhớ chia sẻ RTSS Shared Memory.
   - Điều khiển công suất vi xử lý APU TDP (5W - 35W) qua `RyzenAdj` và kernel driver `WinRing0`.
   - Điều khiển tốc độ quạt tản nhiệt (Fan Control) qua WMI/EC.
   - Điều khiển độ sáng màn hình (WMI Brightness), âm lượng hệ thống (Core Audio), bàn phím cảm ứng (TabTip), và lắng nghe phím tắt toàn cục (Gamepad Combo `BACK + RB`, hotkey `Ctrl+Shift+Q`).

##### Hiện trạng triển khai thực tế và Lộ trình nghiệm thu (Current Implementation Status)

- **Hoàn tất chuyển đổi toàn diện sang Môi trường Thực thi Python (Python Native Runtime)**:
  - Đã xóa sạch 100% mã nguồn và tài nguyên phụ thuộc Flutter (`lib/`, `windows/`, `build/`, `.dart_tool`, `pubspec.yaml`, `analysis_options.yaml`), tuân thủ nghiêm ngặt nguyên tắc loại bỏ tương thích ngược.
  - Tái cấu trúc dự án theo nguyên lý phân ly trách nhiệm (Separation of Concerns) vào không gian mã nguồn `src/` với các mô-đun độc lập: `core/`, `hardware/`, `services/`, `input/`, `overlay/`, `ui/`.
- **Giải quyết triệt để sự cố tiêu điểm và khay hệ thống (Focus Loss & System Tray Resolution)**:
  - Khung giao diện PySide6 quản lý trực tiếp tay cầm cửa sổ Win32 (`HWND`), gắn trực tiếp cờ mở rộng `WS_EX_NOACTIVATE` (`0x08000000`) và `WS_EX_TOOLWINDOW` (`0x00000080`).
  - Khi thao tác chạm cảm ứng hoặc click chuột trên thanh bên, nhân Windows không chuyển tiêu điểm ra khỏi trò chơi tiền cảnh, đảm bảo trò chơi không bị tạm dừng hoặc tụt FPS.
  - Vùng cửa sổ thực tế chỉ chiếm đúng chiều rộng Side Panel (`panelWidth x screenHeight`) neo mép phải; phần còn lại hoàn toàn không có cửa sổ che chắn, cho phép chuột tương tác tự do 100% với Desktop và Game.
  - Biểu tượng khay hệ thống (`QSystemTrayIcon`) và phím tắt toàn cục (`Ctrl+Shift+Q` qua `RegisterHotKey`) nhận sự kiện tức thì trên luồng thông điệp Windows mà không bị nghẽn luồng.
- **Hoạt động của các dịch vụ hệ thống & phần cứng**:
  - `TdpService`: Nạp trực tiếp `libryzenadj.dll` và driver `WinRing0x64.sys` bằng `ctypes`.
  - `FanService`: Điều khiển cổng I/O vật lý của Embedded Controller qua `inpoutx64.dll`.
  - `AudioService`: Tương tác trực tiếp giao diện COM của Windows Core Audio API qua `pycaw`.
  - `BrightnessService`: Điều khiển độ sáng màn hình trực tiếp qua không gian tên `root/wmi`.
  - `TouchscreenService`: Dò tìm và bật/tắt thiết bị HID Touchscreen qua `pnputil`.
  - `GamepadService`: Luồng quét trạng thái cần điều khiển và tổ hợp `BACK + RB` từ `xinput1_4.dll`.
  - `RtssService`: Giao tiếp tệp bộ nhớ chia sẻ `RTSSSharedMemoryV2` để hiển thị OSD.
- **Quy trình triển khai**:
  - Kịch bản chạy phát triển: [run_dev.bat](file:///d:/dev-projects/windows-handheld-tool/run_dev.bat) khởi chạy trực tiếp với Python.
  - Kịch bản đóng gói và phân phối: [deploy_test.bat](file:///d:/dev-projects/windows-handheld-tool/deploy_test.bat) tự động đóng gói qua PyInstaller với `app.manifest` (`uiAccess="true"`), ký chứng chỉ số Authenticode nội bộ `HandheldToolsSigner`, đồng bộ vào `C:\Program Files\WindowsHandheldTools\` và kích hoạt trên phân lớp `ZBID_SYSTEM_TOOLS`.

---

## 5. Công Đoạn 2: Chặn Nhập Liệu Tầng Nhân Thông Qua Trình Điều Khiển Lọc HidHide

Sau khi Công đoạn 1 đã được kiểm thử ổn định và đạt chuẩn xuất bản (Production Ready), hệ thống sẽ tiến hành bổ sung khả năng ngắt nhập liệu tay cầm thông qua trình điều khiển lọc thiết bị ở tầng nhân mà không làm biến đổi bất kỳ byte nhớ nào của trò chơi.

### Bản chất vật lý của cơ chế lọc HidHide
- **Vị trí trong ngăn xếp thiết bị**: `hidhide.sys` hoạt động như một trình điều khiển lọc tầng trên (Upper Filter Driver) được chèn trực tiếp vào ngăn xếp thiết bị USB/Bluetooth Human Interface Device (HID).
- **Cơ chế ngăn chặn luồng I/O**:
  - Khi một ứng dụng cố gắng mở thiết bị (thông qua hàm API Win32 `CreateFile` tới đường dẫn giao diện thiết bị `\\?\HID#...`), nhân Windows sẽ chuyển tiếp gói yêu cầu I/O (IRP - I/O Request Packet) qua ngăn xếp driver.
  - Driver `hidhide.sys` chặn gói IRP, đối chiếu mã định danh tiến trình yêu cầu (Caller Process ID) với bảng danh sách đen (Blacklist) được lưu trong bộ nhớ nhân:
    - Nếu trùng khớp PID của trò chơi: Driver lập tức trả về mã lỗi `STATUS_ACCESS_DENIED`. Trò chơi hoàn toàn không nhận được dữ liệu trạng thái tay cầm.
    - Nếu là PID của ứng dụng lớp phủ (Handheld Tools): Driver cho phép gói IRP đi qua bình thường.

### Quy trình kỹ thuật dự kiến của Công đoạn 2

```mermaid
flowchart TD
    subgraph User_Action["Thao Tác Người Dùng"]
        Open_Panel["Mở Bảng Điều Khiển (Overlay Show)"]
        Close_Panel["Đóng Bảng Điều Khiển (Overlay Hide)"]
    end

    subgraph Service_Logic["Dịch Vụ Điều Khiển Nhập Liệu (HidHideService)"]
        Get_PID["Lấy PID Trò Chơi Đang Chạy: GetWindowThreadProcessId"]
        Send_Block_IOCTL["Gửi Gói Tin IOCTL_SET_BLACKLIST Chặn PID Của Game"]
        Send_Unblock_IOCTL["Gửi Gói Tin IOCTL_CLEAR_BLACKLIST Mở Lại Quyền Cho Game"]
    end

    subgraph Kernel_Driver["Trình Điều Khiển Nhân (hidhide.sys)"]
        Drop_IRP["Hủy Bỏ Gói Tin IRP Đọc Dữ Liệu Của Game (Access Denied)"]
        Pass_IRP["Chuyển Tiếp Bình Thường Gói Tin IRP Cho Game"]
    end

    Open_Panel --> Get_PID --> Send_Block_IOCTL --> Drop_IRP
    Close_Panel --> Send_Unblock_IOCTL --> Pass_IRP
```

- **Bước 1**: Thiết lập kênh liên lạc với driver `hidhide.sys` bằng cách mở tay cầm thiết bị điều khiển thông qua hàm `CreateFileW(L"\\\\.\\HidHide", GENERIC_READ | GENERIC_WRITE, ...)` trong dịch vụ mới `HidHideService`.
- **Bước 2**: Đăng ký mã định danh phần cứng (Hardware ID) của tay cầm tích hợp trên máy vào danh sách quản lý của driver.
- **Bước 3**: Khi mở lớp phủ (`OverlayController.showOverlay`):
  - Xác định cửa sổ trò chơi tiền cảnh thông qua `GetForegroundWindow`.
  - Trích xuất Process ID bằng `GetWindowThreadProcessId`.
  - Gửi mã điều khiển thiết bị (DeviceIoControl với mã IOCTL của HidHide) để thêm PID trò chơi vào danh sách chặn.
- **Bước 4**: Khi đóng lớp phủ (`OverlayController.hideOverlay`):
  - Gửi mã điều khiển thiết bị để xóa PID trò chơi khỏi danh sách chặn, hoàn trả luồng dữ liệu tay cầm cho trò chơi ngay lập tức.

---

## 6. Bản Chất Vật Lý Của Môi Trường Thực Thi Tiến Trình Chủ (Host Runtime Architecture)

### Xuất phát từ bế tắc thực tế giữa tầng giao diện đồ họa và dịch vụ hệ thống (The "Why")

- **Trước đây làm bằng cách nào?**:
  - Sử dụng khung giao diện đồ họa đa nền tảng ([[Khung Giao Diện Đồ Họa Đa Nền Tảng (Cross-Platform UI Framework)]] - điển hình là Flutter Engine) nhúng trong tiến trình thực thi C++ Win32 Runner để quản lý cả giao diện bảng điều khiển lẫn các dịch vụ can thiệp phần cứng.
- **Bị nghẽn kỹ thuật gì?**:
  1. **Xung đột quyền kiểm soát cửa sổ và tiêu điểm (Window Focus Conflict)**: Động cơ đồ họa Flutter Engine đòi hỏi độc quyền chuỗi hoán đổi điểm ảnh (Swapchain) và liên tục tranh chấp tiêu điểm cửa sổ (`WM_ACTIVATE`). Khi người dùng chạm hoặc click vào bảng điều khiển, Flutter cưỡng bức kích hoạt cửa sổ, khiến trò chơi tiền cảnh bị mất tiêu điểm (Focus Loss), gây thu nhỏ cửa sổ game hoặc tụt tốc độ khung hình.
  2. **Vô hiệu hóa cờ mở rộng hệ thống (`WS_EX_NOACTIVATE`)**: Thuộc tính cho phép chuột/cảm ứng tương tác với cửa sổ mà không cướp tiêu điểm của ứng dụng nền bị xung đột trực tiếp với cơ chế nhận sự kiện bàn phím/chuột của Flutter Engine.
  3. **Lớp trừu tượng cồng kềnh (Abstraction Overhead)**: Việc giao tiếp giữa luồng thực thi giao diện (Dart Isolate) và luồng xử lý thông điệp Windows (Win32 Message Loop) phải thông qua kênh nhị phân tuần tự (Platform Channels / Dart FFI), gây tắc nghẽn thông điệp hệ thống khay (System Tray `WM_USER + 1`) và lỗi bộ lọc hit-test chuột (`WM_NCHITTEST`).
- **Môi trường thực thi trực tiếp giải quyết triệt để ra sao?**:
  - Chuyển đổi sang [[Môi Trường Tương Tác Hệ Thống Python (Python System Runtime)]] kết hợp giao diện tăng tốc phần cứng (PySide6 / QML) và API Win32 nguyên thủy.
  - Loại bỏ hoàn toàn tầng bao bọc động cơ đồ họa trung gian; cho phép tiến trình can thiệp trực tiếp vào từng bit thuộc tính của tay cầm cửa sổ (`HWND`), thiết lập đồng thời cờ `WS_EX_NOACTIVATE` (`0x08000000`) và `WS_EX_TOOLWINDOW` (`0x00000080`).
  - Giao tiếp trực tiếp với cổng phần cứng vật lý và trình điều khiển nhân (`libryzenadj.dll`, `WinRing0x64.sys`) qua giao diện gọi hàm ngoại vi nhị phân (`ctypes`) với 0% độ trễ phụ trội.

### Sơ đồ đối chiếu kiến trúc thực thi

```mermaid
flowchart TD
    subgraph Engine_Model["Mô Hình Động Cơ Đa Nền Tảng (Flutter Engine)"]
        UI_Dart["Mã Giao Diện (Dart Isolate)"]
        Channel["Kênh Cầu Nối (Platform Channel / FFI)"]
        Engine_Core["Hộp Đen Động Cơ (Flutter Engine - Đòi Tiêu Điểm WM_ACTIVATE)"]
        Win32_HWND1["Tay Cầm Cửa Sổ (HWND Bị Khóa Swapchain)"]
        UI_Dart --> Channel --> Engine_Core --> Win32_HWND1
    end

    subgraph Direct_Model["Mô Hình Thực Thi Trực Tiếp (Python Native + QML/Win32)"]
        UI_QML["Bề Mặt Giao Diện Tăng Tốc Phần Cứng (QML / PySide6)"]
        Direct_Call["Gọi Trực Tiếp Không Gian Tầng Thấp (ctypes / Win32 API)"]
        Win32_HWND2["Tay Cầm Cửa Sổ Hệ Thống (HWND với cờ WS_EX_NOACTIVATE)"]
        Direct_Hardware["Trình Điều Khiển Phần Cứng (WinRing0 / RyzenAdj / WMI)"]
        UI_QML --> Win32_HWND2
        Direct_Call --> Win32_HWND2
        Direct_Call --> Direct_Hardware
    end
```

### Đánh giá khả thi 3 trụ cột kỹ thuật khi chuyển dịch sang Python

1. **Bảo toàn bề mặt giao diện Tab Bar và khả năng tùy biến hình học (UI Geometry & Pixel Scaling)**:
   - **Cơ chế vật lý**: Khung giao diện Qt Quick (QML) trong PySide6 sử dụng kiến trúc biểu đồ cảnh tăng tốc phần cứng (Hardware-Accelerated Scene Graph) biên dịch trực tiếp sang tập lệnh Direct3D 11 trên Windows.
   - **Tái hiện Tab Bar**: Sử dụng các thành phần gốc `TabBar`, `TabButton` và `StackLayout` để phân tách 4 không gian điều khiển (`Home`, `Performance`, `Device`, `Settings`), hỗ trợ hiệu ứng trong suốt (Acrylic / Mica) và bo góc mượt mà.
   - **Tùy biến Scale & Width**:
     - Chiều rộng thanh bên: Điều chỉnh kích thước vật lý của cửa sổ bằng hàm thay đổi kích thước bề mặt đồ họa `QQuickWindow.setWidth` kết hợp cập nhật vị trí neo mép phải màn hình qua hàm `SetWindowPos` của `user32.dll`.
     - Tỉ lệ điểm ảnh: Kiểm soát ma trận phóng to toàn cục thông qua thuộc tính tỉ lệ `scale` của nút gốc (Root Item) hoặc biến môi trường `QT_SCALE_FACTOR`.

2. **Duy trì và tối ưu hóa toàn bộ hệ thống dịch vụ phần cứng (Hardware & System Services)**:
   - **Điều khiển công suất APU (TDP)**: Nạp thư viện `libryzenadj.dll` và trình điều khiển nhân `WinRing0x64.sys` bằng `ctypes.cdll.LoadLibrary`, ánh xạ con trỏ cấu hình SMU và gọi hàm `set_stapm_limit` / `set_fast_limit` trực tiếp không qua FFI trung gian.
   - **Đường cong quạt tản nhiệt (Fan Curves)**: Giao tiếp trực tiếp với vi điều khiển nhúng (Embedded Controller) thông qua cổng I/O vật lý (`0x62` / `0x66`) bằng thư viện `InpOutx64.dll` qua `ctypes`, hoặc truy vấn giao diện WMI OEM bằng mô-đun `wmi`.
   - **Bật/Tắt màn hình cảm ứng**: Thao tác mã định danh thiết bị vật lý qua hàm quản lý cấu hình nhân `CM_Disable_DevNode` / `CM_Enable_DevNode` thuộc `cfgmgr32.dll`.
   - **Âm lượng và độ sáng màn hình**:
     - Âm lượng: Giao tiếp giao diện COM của Windows Core Audio API (`IAudioEndpointVolume`) bằng thư viện `pycaw`.
     - Độ sáng: Truy xuất phương thức `WmiSetBrightness` trong không gian tên `root/wmi` hoặc gọi hàm `SetMonitorBrightness` từ `dxva2.dll`.
   - **Khởi động cùng Windows**: Ghi trực tiếp giá trị chuỗi đường dẫn tệp thực thi vào nhánh khóa thanh ghi `HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run` bằng mô-đun chuẩn `winreg`.
   - **Lớp phủ thông số hiệu năng RTSS OSD**: Ánh xạ tệp bộ nhớ chia sẻ vào không gian địa chỉ ảo của tiến trình bằng mô-đun chuẩn `mmap` đối với tay cầm ánh xạ `RTSSSharedMemoryV2`, đọc/ghi trực tiếp cấu trúc nhị phân `RTSS_SHARED_MEMORY`.

3. **Cơ chế lớp phủ trên các chế độ hiển thị trò chơi (Overlay Pipeline on Game Displays)**:
   - **Chế độ Không viền và Tối ưu hóa Toàn màn hình (Borderless / Fullscreen Optimizations - iFlip)**:
     - Khả thi 100% và triệt tiêu lỗi mất tiêu điểm.
     - Lấy tay cầm cửa sổ Win32 từ đối tượng giao diện bằng thuộc tính `winId()`.
     - Gán cửa sổ vào phân lớp công cụ hệ thống bằng hàm nội bộ: `SetWindowBand(hwnd, NULL, ZBID_SYSTEM_TOOLS)`.
     - Bổ sung cờ `WS_EX_NOACTIVATE` vào kiểu dáng mở rộng của `HWND`, đảm bảo DWM vẽ đè bảng điều khiển lên điểm ảnh của trò chơi mà không làm trò chơi mất trạng thái tiền cảnh.
   - **Chế độ Toàn màn hình Độc quyền Cổ điển (Legacy Exclusive Fullscreen - DWM Bypass)**:
     - Bản chất vật lý: Khi trò chơi chiếm dụng độc quyền bộ điều khiển xuất hình vật lý của card đồ họa (Hardware Scanout Bypass DWM), mọi cửa sổ Win32 độc lập ở cấp hệ điều hành đều không thể hiển thị đè lên nếu không can thiệp vào chuỗi lệnh vẽ nội bộ của trò chơi ([[Móc Đồ Họa DXGI (DXGI Hook)]]).
     - Phương án xử lý tối ưu: Windows 10/11 mặc định kích hoạt cơ chế Tối ưu hóa Toàn màn hình (FSO) chuyển đổi chuỗi xuất hình sang cơ chế Độc quyền Độc lập (Independent Flip), giúp bảo toàn 100% hiệu năng đồ họa mà DWM vẫn duy trì khả năng ghép nối lớp phủ `ZBID_SYSTEM_TOOLS`. Đối với các trò chơi cá biệt tắt FSO, hệ thống chỉ cần kích hoạt cờ tương thích FSO thông qua thanh ghi hệ thống mà không cần sử dụng kỹ thuật tiêm mã DLL.
