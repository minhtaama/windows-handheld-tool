import 'dart:ui';
import 'bridge_service.dart';

/// Dịch vụ quản lý kích thước cửa sổ Dock neo mép phải thông qua BridgeService.
class NativeWindowService {

  static Size getPhysicalScreenSize() => const Size(1920, 1080);

  static void showDockWindow({required int panelWidth}) {
    BridgeService.instance.setPanelWidth(panelWidth);
  }

  static void hideDockWindow() {
    BridgeService.instance.closeOverlay();
  }

  static void resizeDockWindow({required int panelWidth}) {
    BridgeService.instance.setPanelWidth(panelWidth);
  }

  static int getForegroundWindow() => 0;
  static int getWindowHandle() => 0;
  static void setForegroundWindow(int hwnd) {}
  static void prepareForContextMenu() {}
}
