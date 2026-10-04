from typing import Optional, Callable
from PyQt6.QtWidgets import QPushButton, QWidget
from PyQt6.QtCore import pyqtSignal

class ActionButton(QPushButton):
    """
    Nút thao tác nhanh cảm ứng cho thiết bị handheld.
    """
    def __init__(
        self,
        icon: str,
        text: str,
        on_click: Optional[Callable[[], None]] = None,
        parent: Optional[QWidget] = None
    ):
        full_text = f"{icon}  {text}" if icon else text
        super().__init__(full_text, parent)
        self.setProperty("class", "ActionButton")
        self.setCursor(self.cursor())
        if on_click:
            self.clicked.connect(on_click)
