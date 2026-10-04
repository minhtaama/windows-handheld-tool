"""
Bảng kiểu dáng QSS (Dark Cyberpunk/Handheld Theme) tối ưu hóa cho màn hình cảm ứng.
"""

MAIN_STYLESHEET = """
QWidget#OverlayRoot {
    background-color: transparent;
}

QFrame#MainPanel {
    background-color: rgba(18, 20, 29, 0.95);
    border-top-left-radius: 20px;
    border-bottom-left-radius: 20px;
    border-left: 2px solid rgba(0, 210, 255, 0.4);
    border-top: 1px solid rgba(255, 255, 255, 0.1);
    border-bottom: 1px solid rgba(255, 255, 255, 0.1);
}

QLabel {
    color: #e0e6ed;
    font-family: 'Segoe UI', system-ui, sans-serif;
}

QLabel#HeaderTitle {
    font-size: 19px;
    font-weight: 700;
    color: #ffffff;
    letter-spacing: 0.5px;
}

QLabel#HeaderSubtitle {
    font-size: 11px;
    color: #7b889b;
}

QFrame#CardFrame {
    background-color: rgba(30, 34, 48, 0.7);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: 12px;
}

QLabel#CardTitle {
    font-size: 13px;
    font-weight: 600;
    color: #b0c0d8;
}

QLabel#CardValue {
    font-size: 14px;
    font-weight: 700;
    color: #00d2ff;
}

QSlider::groove:horizontal {
    height: 8px;
    background: rgba(255, 255, 255, 0.12);
    border-radius: 4px;
}

QSlider::sub-page:horizontal {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #0072ff, stop:1 #00d2ff);
    border-radius: 4px;
}

QSlider::handle:horizontal {
    background: #ffffff;
    border: 2px solid #00d2ff;
    width: 20px;
    height: 20px;
    margin: -6px 0;
    border-radius: 10px;
}

QSlider::handle:horizontal:hover {
    background: #00d2ff;
    border: 2px solid #ffffff;
}

QPushButton.StepButton {
    background-color: rgba(255, 255, 255, 0.08);
    color: #ffffff;
    font-size: 15px;
    font-weight: 700;
    border: 1px solid rgba(255, 255, 255, 0.1);
    border-radius: 8px;
    min-width: 32px;
    max-width: 32px;
    min-height: 32px;
    max-height: 32px;
}

QPushButton.StepButton:hover {
    background-color: rgba(0, 210, 255, 0.25);
    border-color: #00d2ff;
}

QPushButton.StepButton:pressed {
    background-color: #00d2ff;
    color: #000000;
}

QPushButton.ActionButton {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 rgba(35, 42, 60, 0.9), stop:1 rgba(25, 30, 45, 0.9));
    color: #e0e6ed;
    font-size: 13px;
    font-weight: 600;
    border: 1px solid rgba(255, 255, 255, 0.12);
    border-radius: 10px;
    padding: 10px 14px;
}

QPushButton.ActionButton:hover {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:1, stop:0 rgba(0, 210, 255, 0.2), stop:1 rgba(157, 78, 221, 0.2));
    border-color: #00d2ff;
    color: #ffffff;
}

QPushButton.ActionButton:pressed {
    background-color: rgba(0, 210, 255, 0.35);
}

QPushButton#CloseButton {
    background-color: rgba(255, 255, 255, 0.06);
    color: #8fa0b5;
    font-size: 14px;
    font-weight: bold;
    border-radius: 14px;
    min-width: 28px;
    max-width: 28px;
    min-height: 28px;
    max-height: 28px;
    border: none;
}

QPushButton#CloseButton:hover {
    background-color: #ff3366;
    color: #ffffff;
}

QScrollArea {
    background: transparent;
    border: none;
}

QScrollBar:vertical {
    background: transparent;
    width: 6px;
    margin: 0px;
}

QScrollBar::handle:vertical {
    background: rgba(255, 255, 255, 0.2);
    min-height: 24px;
    border-radius: 3px;
}

QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0px;
}
"""
