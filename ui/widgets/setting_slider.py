from typing import Optional, Callable
from PyQt6.QtWidgets import (
    QWidget, QFrame, QVBoxLayout, QHBoxLayout, QLabel, QSlider, QPushButton
)
from PyQt6.QtCore import Qt, pyqtSignal
from hardware.base import HardwareController

class SettingSlider(QFrame):
    """
    Widget thanh trượt cài đặt phần cứng chuẩn hóa (DRY).
    Tái sử dụng cho toàn bộ các cài đặt: TDP, Độ sáng, Âm lượng, Quạt tản nhiệt.
    """
    valueChanged = pyqtSignal(int)

    def __init__(
        self,
        icon: str,
        title: str,
        controller: HardwareController,
        on_change: Optional[Callable[[int], None]] = None,
        parent: Optional[QWidget] = None
    ):
        super().__init__(parent)
        self.setObjectName("CardFrame")
        self.controller = controller
        self.on_change_callback = on_change
        self.icon = icon
        self.title_text = title

        self._init_ui()
        self.refresh_value()

    def _init_ui(self) -> None:
        layout = QVBoxLayout(self)
        layout.setContentsMargins(14, 12, 14, 12)
        layout.setSpacing(10)

        # Header: Icon + Tiêu đề + Giá trị số
        header_layout = QHBoxLayout()
        header_layout.setSpacing(8)

        icon_label = QLabel(self.icon)
        icon_label.setStyleSheet("font-size: 16px;")

        title_label = QLabel(self.title_text)
        title_label.setObjectName("CardTitle")

        self.value_label = QLabel()
        self.value_label.setObjectName("CardValue")
        self.value_label.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)

        header_layout.addWidget(icon_label)
        header_layout.addWidget(title_label)
        header_layout.addStretch()
        header_layout.addWidget(self.value_label)
        layout.addLayout(header_layout)

        # Row điều khiển: Nút [-] + Thanh Slider cảm ứng + Nút [+]
        control_layout = QHBoxLayout()
        control_layout.setSpacing(10)

        self.btn_minus = QPushButton("-")
        self.btn_minus.setProperty("class", "StepButton")
        self.btn_minus.clicked.connect(self._step_down)

        self.slider = QSlider(Qt.Orientation.Horizontal)
        self.slider.setRange(self.controller.min_val, self.controller.max_val)
        self.slider.setSingleStep(self.controller.step)
        self.slider.setPageStep(self.controller.step * 2)
        self.slider.valueChanged.connect(self._on_slider_value_changed)

        self.btn_plus = QPushButton("+")
        self.btn_plus.setProperty("class", "StepButton")
        self.btn_plus.clicked.connect(self._step_up)

        control_layout.addWidget(self.btn_minus)
        control_layout.addWidget(self.slider)
        control_layout.addWidget(self.btn_plus)
        layout.addLayout(control_layout)

    def _update_label_text(self, val: int) -> None:
        unit = self.controller.unit
        self.value_label.setText(f"{val} {unit}".strip())

    def _on_slider_value_changed(self, value: int) -> None:
        self._update_label_text(value)
        self.controller.set_value(value)
        self.valueChanged.emit(value)
        if self.on_change_callback:
            self.on_change_callback(value)

    def _step_down(self) -> None:
        new_val = self.controller.clamp(self.slider.value() - self.controller.step)
        self.slider.setValue(new_val)

    def _step_up(self) -> None:
        new_val = self.controller.clamp(self.slider.value() + self.controller.step)
        self.slider.setValue(new_val)

    def refresh_value(self) -> None:
        """Đọc giá trị từ phần cứng và đồng bộ lên giao diện."""
        current_val = self.controller.get_value()
        self.slider.blockSignals(True)
        self.slider.setValue(current_val)
        self._update_label_text(current_val)
        self.slider.blockSignals(False)
