from typing import Optional, Callable
from PyQt6.QtWidgets import (
    QWidget, QFrame, QVBoxLayout, QHBoxLayout, QGridLayout, QLabel,
    QPushButton, QScrollArea
)
from PyQt6.QtCore import Qt, pyqtSignal

from core.config import ConfigManager
from hardware.tdp import TdpController
from hardware.fan import FanController
from hardware.brightness import BrightnessController
from hardware.audio import AudioController
from services.virtual_keyboard import VirtualKeyboardService
from .widgets.setting_slider import SettingSlider
from .widgets.action_button import ActionButton

class QuickSettingsPanel(QFrame):
    """
    Nội dung thanh Quick Settings dạng trượt dành cho máy Handheld.
    """
    closeRequested = pyqtSignal()

    def __init__(self, config_manager: ConfigManager, parent: Optional[QWidget] = None):
        super().__init__(parent)
        self.setObjectName("MainPanel")
        self.config = config_manager

        # Khởi tạo các Hardware Controllers
        self.tdp_ctrl = TdpController(
            min_val=self.config.get("hardware.tdp.min", 5),
            max_val=self.config.get("hardware.tdp.max", 35),
            step=self.config.get("hardware.tdp.step", 1),
            default_val=self.config.get("hardware.tdp.current", 15)
        )
        self.fan_ctrl = FanController(
            min_val=self.config.get("hardware.fan.min", 0),
            max_val=self.config.get("hardware.fan.max", 100),
            step=self.config.get("hardware.fan.step", 5),
            default_val=self.config.get("hardware.fan.current", 50)
        )
        self.brightness_ctrl = BrightnessController(
            min_val=self.config.get("hardware.brightness.min", 0),
            max_val=self.config.get("hardware.brightness.max", 100),
            step=self.config.get("hardware.brightness.step", 5)
        )
        self.audio_ctrl = AudioController(
            min_val=self.config.get("hardware.audio.min", 0),
            max_val=self.config.get("hardware.audio.max", 100),
            step=self.config.get("hardware.audio.step", 2)
        )

        self._init_ui()

    def _init_ui(self) -> None:
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(18, 20, 18, 20)
        main_layout.setSpacing(14)

        # 1. Header (Tiêu đề + nút Đóng)
        header_layout = QHBoxLayout()
        title_box = QVBoxLayout()
        title_box.setSpacing(2)

        title_label = QLabel("QUICK SETTINGS")
        title_label.setObjectName("HeaderTitle")

        subtitle_label = QLabel("Handheld Companion Tools")
        subtitle_label.setObjectName("HeaderSubtitle")

        title_box.addWidget(title_label)
        title_box.addWidget(subtitle_label)

        btn_close = QPushButton("✕")
        btn_close.setObjectName("CloseButton")
        btn_close.clicked.connect(self.closeRequested.emit)

        header_layout.addLayout(title_box)
        header_layout.addStretch()
        header_layout.addWidget(btn_close)
        main_layout.addLayout(header_layout)

        # 2. Vùng cuộn chứa các thiết lập (Scroll Area)
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)

        content_widget = QWidget()
        content_layout = QVBoxLayout(content_widget)
        content_layout.setContentsMargins(0, 4, 6, 4)
        content_layout.setSpacing(12)

        # Thanh trượt cài đặt chuẩn hóa (DRY)
        self.slider_tdp = SettingSlider(
            icon="⚡",
            title="Công suất TDP",
            controller=self.tdp_ctrl,
            on_change=lambda val: self.config.set("hardware.tdp.current", val)
        )

        self.slider_fan = SettingSlider(
            icon="🌀",
            title="Tốc độ quạt",
            controller=self.fan_ctrl,
            on_change=lambda val: self.config.set("hardware.fan.current", val)
        )

        self.slider_brightness = SettingSlider(
            icon="💡",
            title="Độ sáng",
            controller=self.brightness_ctrl,
            on_change=lambda val: self.config.set("hardware.brightness.current", val)
        )

        self.slider_audio = SettingSlider(
            icon="🔊",
            title="Âm lượng",
            controller=self.audio_ctrl,
            on_change=lambda val: self.config.set("hardware.audio.current", val)
        )

        content_layout.addWidget(self.slider_tdp)
        content_layout.addWidget(self.slider_fan)
        content_layout.addWidget(self.slider_brightness)
        content_layout.addWidget(self.slider_audio)

        # 3. Khu vực nút thao tác nhanh (Quick Action Buttons)
        actions_label = QLabel("THAO TÁC NHANH")
        actions_label.setObjectName("CardTitle")
        actions_label.setStyleSheet("margin-top: 8px;")
        content_layout.addWidget(actions_label)

        grid_actions = QGridLayout()
        grid_actions.setSpacing(10)

        btn_keyboard = ActionButton(
            icon="⌨",
            text="Bàn phím ảo",
            on_click=lambda: VirtualKeyboardService.toggle_keyboard()
        )

        btn_mute = ActionButton(
            icon="🔇",
            text="Tắt âm",
            on_click=self._toggle_mute
        )

        btn_turbo = ActionButton(
            icon="🚀",
            text="Turbo 30W",
            on_click=self._set_turbo_tdp
        )

        btn_fan_auto = ActionButton(
            icon="🌀",
            text="Quạt Tự động",
            on_click=self._set_fan_auto
        )

        grid_actions.addWidget(btn_keyboard, 0, 0)
        grid_actions.addWidget(btn_mute, 0, 1)
        grid_actions.addWidget(btn_turbo, 1, 0)
        grid_actions.addWidget(btn_fan_auto, 1, 1)

        content_layout.addLayout(grid_actions)
        content_layout.addStretch()

        scroll.setWidget(content_widget)
        main_layout.addWidget(scroll)

        # 4. Footer ghi chú phím tắt
        footer_layout = QHBoxLayout()
        hotkey_str = self.config.get("hotkey.toggle_overlay", "Ctrl+Shift+Q")
        gamepad_str = " + ".join(self.config.get("gamepad.toggle_combo", ["Back", "R1"]))
        hint_label = QLabel(f"Phím tắt: {hotkey_str.upper()} | Gamepad: {gamepad_str}")
        hint_label.setObjectName("HeaderSubtitle")
        hint_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        footer_layout.addWidget(hint_label)
        main_layout.addLayout(footer_layout)

    def _toggle_mute(self) -> None:
        muted = self.audio_ctrl.is_muted()
        self.audio_ctrl.set_mute(not muted)
        self.slider_audio.refresh_value()

    def _set_turbo_tdp(self) -> None:
        self.tdp_ctrl.set_value(30)
        self.slider_tdp.refresh_value()

    def _set_fan_auto(self) -> None:
        self.fan_ctrl.set_auto(True)

    def refresh_values(self) -> None:
        """Đồng bộ toàn bộ giá trị hiển thị từ phần cứng."""
        self.slider_tdp.refresh_value()
        self.slider_fan.refresh_value()
        self.slider_brightness.refresh_value()
        self.slider_audio.refresh_value()
