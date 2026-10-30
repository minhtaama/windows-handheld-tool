import json
import ctypes
from typing import List
from PySide6.QtCore import QObject, Slot, Qt
from PySide6.QtNetwork import QHostAddress
from PySide6.QtWebSockets import QWebSocketServer, QWebSocket
from src.bridge.web_bridge import WebBridge
from src.core.logger import setup_logger

logger = setup_logger("WsServer")
user32 = ctypes.windll.user32

class WsServer(QObject):
    def __init__(self, bridge: WebBridge, port: int = 8765, parent=None):
        super().__init__(parent)
        self.bridge = bridge
        self.port = port
        self.clients: List[QWebSocket] = []
        self.win_mgr = None

        self.server = QWebSocketServer("HandheldWsServer", QWebSocketServer.SslMode.NonSecureMode, self)
        if self.server.listen(QHostAddress.SpecialAddress.LocalHost, self.port):
            logger.info(f"WebSocket Server listening successfully at ws://127.0.0.1:{self.port}")
            self.server.newConnection.connect(self._on_new_connection)
        else:
            logger.error(f"Failed to start WebSocket Server on port {self.port}: {self.server.errorString()}")

        # Listen to signals pushing sensor telemetry and visibility updates from WebBridge
        # QueuedConnection ensures worker threads do not directly invoke QWebSocket methods outside Main Thread
        self.bridge.telemetryUpdated.connect(self._broadcast_telemetry, Qt.ConnectionType.QueuedConnection)
        self.bridge.configUpdated.connect(self._broadcast_config, Qt.ConnectionType.QueuedConnection)
        self.bridge.overlayVisibilityChanged.connect(self._broadcast_visibility, Qt.ConnectionType.QueuedConnection)
        self.bridge.hotkeyEvent.connect(self._broadcast_hotkey_event, Qt.ConnectionType.QueuedConnection)
        self.bridge.gamepadButtonEvent.connect(self._broadcast_gamepad_button, Qt.ConnectionType.QueuedConnection)

    def _on_new_connection(self):
        client = self.server.nextPendingConnection()
        self.clients.append(client)
        client.textMessageReceived.connect(lambda msg, c=client: self._on_message(c, msg))
        client.disconnected.connect(lambda c=client: self._on_disconnected(c))
        logger.info(f"[WS] Client connected from {client.peerAddress().toString()}:{client.peerPort()}")

        win_mgr = getattr(self, "win_mgr", None) or (getattr(self.parent(), "win_mgr", None) if self.parent() else None)
        if win_mgr:
            # If the UI window wasn't ready during initial startup, bind to it now that client connected
            if not win_mgr.hwnd or not win_mgr.hwnd.value or not user32.IsWindow(win_mgr.hwnd):
                win_mgr.ensure_flutter_ui()

        # Send initial state to newly connected client
        try:
            init_json = self.bridge.getInitialState()
            client.sendTextMessage(json.dumps({"type": "init", "data": json.loads(init_json)}))
            if win_mgr:
                is_vis = bool(win_mgr.is_visible)
                client.sendTextMessage(json.dumps({"type": "visibility", "data": {"visible": is_vis}}))
                logger.info(f"[WS] Initial visibility={is_vis} sent to new client")
        except Exception as e:
            logger.error(f"Error sending initial state to client: {e}")

    def _on_disconnected(self, client: QWebSocket):
        if client in self.clients:
            self.clients.remove(client)
            logger.info("[WS] Client disconnected.")

    def _broadcast_telemetry(self, snap_json_str: str):
        if not self.clients:
            return
        try:
            payload = json.dumps({"type": "telemetry", "data": json.loads(snap_json_str)})
            for client in list(self.clients):
                client.sendTextMessage(payload)
        except Exception as e:
            logger.error(f"Error broadcasting telemetry: {e}")

    def _broadcast_config(self, cfg_json_str: str):
        if not self.clients:
            return
        try:
            payload = json.dumps({"type": "config", "data": json.loads(cfg_json_str)})
            for client in list(self.clients):
                client.sendTextMessage(payload)
        except Exception as e:
            logger.error(f"Error broadcasting config: {e}")

    def _broadcast_visibility(self, is_visible: bool):
        if not self.clients:
            logger.warning(f"[WS] Visibility={bool(is_visible)} requested but no Flutter UI client is connected")
            return
        try:
            payload = json.dumps({"type": "visibility", "data": {"visible": bool(is_visible)}})
            for client in list(self.clients):
                client.sendTextMessage(payload)
            logger.info(f"[WS] Broadcast visibility={bool(is_visible)} to {len(self.clients)} client(s)")
        except Exception as e:
            logger.error(f"Error broadcasting visibility: {e}")

    def _broadcast_hotkey_event(self, event_json_str: str):
        if not self.clients:
            return
        try:
            for client in list(self.clients):
                client.sendTextMessage(event_json_str)
        except Exception as e:
            logger.error(f"Error broadcasting hotkey event: {e}")

    def _broadcast_gamepad_button(self, button_name: str):
        if not self.clients:
            return
        try:
            payload = json.dumps({"type": "gamepadButton", "data": {"button": button_name}})
            for client in list(self.clients):
                client.sendTextMessage(payload)
        except Exception as e:
            logger.error(f"Error broadcasting gamepad button: {e}")

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
            elif action == "setFanAuto":
                self.bridge.setFanAuto(bool(req.get("is_auto", True)))
            elif action == "setFanCurve":
                profile = str(req.get("profile", "balanced"))
                curve = req.get("curve", None)
                self.bridge.setFanCurve(profile, json.dumps(curve) if curve is not None else "")
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
            elif action == "installRtss":
                self.bridge.installRtss()
            elif action == "setOsdMetric":
                self.bridge.setOsdMetric(str(req.get("metric", "fps")), bool(req.get("enabled", True)))
            elif action == "setOsdLayout":
                self.bridge.setOsdLayout(
                    int(req.get("zoom", 1)),
                    str(req.get("position", "topLeft")),
                )
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
                logger.warning(f"[WS] Unrecognized action: {action}")
        except Exception as e:
            logger.error(f"Error handling message from client: {e}")

    def close(self):
        for client in self.clients:
            client.close()
        self.clients.clear()
        self.server.close()
