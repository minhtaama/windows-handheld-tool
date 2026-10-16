import json
from typing import List
from PySide6.QtCore import QObject, Slot
from PySide6.QtNetwork import QHostAddress
from PySide6.QtWebSockets import QWebSocketServer, QWebSocket
from src.bridge.web_bridge import WebBridge
from src.core.logger import setup_logger

logger = setup_logger("WsServer")

class WsServer(QObject):
    def __init__(self, bridge: WebBridge, port: int = 8765, parent=None):
        super().__init__(parent)
        self.bridge = bridge
        self.port = port
        self.clients: List[QWebSocket] = []

        self.server = QWebSocketServer("HandheldWsServer", QWebSocketServer.SslMode.NonSecureMode, self)
        if self.server.listen(QHostAddress.SpecialAddress.LocalHost, self.port):
            logger.info(f"WebSocket Server đã lắng nghe thành công tại ws://127.0.0.1:{self.port}")
            self.server.newConnection.connect(self._on_new_connection)
        else:
            logger.error(f"Không thể khởi động WebSocket Server tại cổng {self.port}: {self.server.errorString()}")

        # Lắng nghe Signal đẩy dữ liệu cảm biến và trạng thái hiển thị từ WebBridge
        self.bridge.telemetryUpdated.connect(self._broadcast_telemetry)
        self.bridge.configUpdated.connect(self._broadcast_config)
        self.bridge.overlayVisibilityChanged.connect(self._broadcast_visibility)
        self.bridge.hotkeyEvent.connect(self._broadcast_hotkey_event)
        self.bridge.gamepadButtonEvent.connect(self._broadcast_gamepad_button)

    def _on_new_connection(self):
        client = self.server.nextPendingConnection()
        self.clients.append(client)
        client.textMessageReceived.connect(lambda msg, c=client: self._on_message(c, msg))
        client.disconnected.connect(lambda c=client: self._on_disconnected(c))
        logger.info(f"[WS] Client mới kết nối từ {client.peerAddress().toString()}:{client.peerPort()}")

        # Gửi ngay trạng thái ban đầu cho Client
        try:
            init_json = self.bridge.getInitialState()
            client.sendTextMessage(json.dumps({"type": "init", "data": json.loads(init_json)}))
            # Đồng bộ ngay trạng thái ẩn/hiện thực tế của cửa sổ khi trình duyệt vừa kết nối
            parent_panel = self.parent()
            if parent_panel and hasattr(parent_panel, "win_mgr") and parent_panel.win_mgr:
                is_vis = bool(parent_panel.win_mgr.is_visible)
                client.sendTextMessage(json.dumps({"type": "visibility", "data": {"visible": is_vis}}))
        except Exception as e:
            logger.error(f"Lỗi khi gửi initial state sang client: {e}")

    def _on_disconnected(self, client: QWebSocket):
        if client in self.clients:
            self.clients.remove(client)
            logger.info(f"[WS] Client đã ngắt kết nối.")

    def _broadcast_telemetry(self, snap_json_str: str):
        if not self.clients:
            return
        try:
            payload = json.dumps({"type": "telemetry", "data": json.loads(snap_json_str)})
            for client in self.clients:
                client.sendTextMessage(payload)
        except Exception as e:
            logger.error(f"Lỗi broadcast telemetry: {e}")

    def _broadcast_config(self, cfg_json_str: str):
        if not self.clients:
            return
        try:
            payload = json.dumps({"type": "config", "data": json.loads(cfg_json_str)})
            for client in self.clients:
                client.sendTextMessage(payload)
        except Exception as e:
            logger.error(f"Lỗi broadcast config: {e}")

    def _broadcast_visibility(self, is_visible: bool):
        if not self.clients:
            return
        try:
            payload = json.dumps({"type": "visibility", "data": {"visible": bool(is_visible)}})
            for client in self.clients:
                client.sendTextMessage(payload)
        except Exception as e:
            logger.error(f"Lỗi broadcast visibility: {e}")

    def _broadcast_hotkey_event(self, event_json_str: str):
        if not self.clients:
            return
        try:
            for client in self.clients:
                client.sendTextMessage(event_json_str)
        except Exception as e:
            logger.error(f"Lỗi broadcast hotkey event: {e}")

    def _broadcast_gamepad_button(self, button_name: str):
        if not self.clients:
            return
        try:
            payload = json.dumps({"type": "gamepadButton", "data": {"button": button_name}})
            for client in self.clients:
                client.sendTextMessage(payload)
        except Exception as e:
            logger.error(f"Lỗi broadcast gamepad button: {e}")

    def _on_message(self, client: QWebSocket, msg: str):
        try:
            req = json.loads(msg)
            action = req.get("action")
            if not action:
                return

            if action == "setTdp":
                self.bridge.setTdp(int(req.get("watts", 15)))
            elif action == "setFan":
                self.bridge.setFan(int(req.get("percent", 50)), bool(req.get("is_auto", False)))
            elif action == "setVolume":
                self.bridge.setVolume(int(req.get("percent", 50)))
            elif action == "toggleMute":
                self.bridge.toggleMute()
            elif action == "setBrightness":
                self.bridge.setBrightness(int(req.get("percent", 70)))
            elif action == "toggleTouchscreen":
                self.bridge.toggleTouchscreen()
            elif action == "toggleVirtualKeyboard":
                self.bridge.toggleVirtualKeyboard()
            elif action == "setFpsLimit":
                self.bridge.setFpsLimit(int(req.get("limit", 60)))
            elif action == "updateOsdText":
                self.bridge.updateOsdText(str(req.get("text", "")))
            elif action == "clearOsdText":
                self.bridge.clearOsdText()
            elif action == "setOsdMetric":
                self.bridge.setOsdMetric(str(req.get("metric", "fps")), bool(req.get("enabled", True)))
            elif action == "setPanelWidth":
                self.bridge.setPanelWidth(int(req.get("width", 420)))
            elif action == "setPanelScale":
                self.bridge.setPanelScale(float(req.get("scale", 1.0)))
            elif action == "setHotkey":
                self.bridge.setHotkey(
                    str(req.get("target", "overlay")),
                    str(req.get("hotkey", "")),
                    str(req.get("device", "keyboard"))
                )
            elif action == "setAutostart":
                self.bridge.setAutostart(bool(req.get("enabled", True)))
            elif action == "bringToFront":
                self.bridge.bringToFront()
            elif action == "closeOverlay":
                self.bridge.closeOverlay()
            elif action == "exitApp":
                self.bridge.exitApp()
            elif action == "launchTaskManager":
                self.bridge.launchTaskManager()
            elif action == "launchDisplaySettings":
                self.bridge.launchDisplaySettings()
            elif action == "trimMemory":
                self.bridge.trimMemory()
            elif action == "startCaptureHotkey":
                self.bridge.startCaptureHotkey(str(req.get("target", "overlay")))
            elif action == "cancelCaptureHotkey":
                self.bridge.cancelCaptureHotkey()
            else:
                logger.warning(f"[WS] Không nhận diện được action: {action}")
        except Exception as e:
            logger.error(f"Lỗi xử lý tin nhắn từ client: {e}")

    def close(self):
        for client in self.clients:
            client.close()
        self.clients.clear()
        self.server.close()

