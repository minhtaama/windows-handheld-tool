# Dark Theme Stylesheet and Palette for Windows Handheld Tool

DARK_THEME_QSS = """
QWidget {
    background-color: #12131C;
    color: #E2E8F0;
    font-family: 'Segoe UI', system-ui, sans-serif;
    font-size: 13px;
    border: none;
    outline: none;
}

QScrollArea {
    background: transparent;
    border: none;
}

QScrollBar:vertical {
    border: none;
    background: #1A1C29;
    width: 6px;
    margin: 0px;
    border-radius: 3px;
}

QScrollBar::handle:vertical {
    background: #3B4261;
    min-height: 20px;
    border-radius: 3px;
}

QScrollBar::handle:vertical:hover {
    background: #7AA2F7;
}

QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
    height: 0px;
}

/* Card Container */
QFrame.Card {
    background-color: #1A1C29;
    border: 1px solid #272A3D;
    border-radius: 12px;
    padding: 12px;
}

/* Header Labels */
QLabel.Title {
    font-size: 16px;
    font-weight: bold;
    color: #FFFFFF;
}

QLabel.Subtitle {
    font-size: 11px;
    color: #7AA2F7;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

QLabel.ValueBadge {
    font-size: 14px;
    font-weight: bold;
    color: #7AA2F7;
    background-color: #24283B;
    border-radius: 6px;
    padding: 3px 8px;
}

/* Sliders */
QSlider::groove:horizontal {
    border: none;
    height: 6px;
    background: #24283B;
    border-radius: 3px;
}

QSlider::sub-page:horizontal {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #7C4DFF, stop:1 #00ADB5);
    border-radius: 3px;
}

QSlider::handle:horizontal {
    background: #FFFFFF;
    border: 2px solid #00ADB5;
    width: 18px;
    height: 18px;
    margin: -6px 0;
    border-radius: 9px;
}

QSlider::handle:horizontal:hover {
    background: #00ADB5;
    border: 2px solid #FFFFFF;
}

/* Buttons */
QPushButton {
    background-color: #24283B;
    color: #E2E8F0;
    border: 1px solid #3B4261;
    border-radius: 8px;
    padding: 8px 14px;
    font-weight: 600;
}

QPushButton:hover {
    background-color: #3B4261;
    border-color: #7AA2F7;
    color: #FFFFFF;
}

QPushButton:pressed {
    background-color: #7C4DFF;
    border-color: #7C4DFF;
    color: #FFFFFF;
}

QPushButton.Primary {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #7C4DFF, stop:1 #00ADB5);
    border: none;
    color: #FFFFFF;
}

QPushButton.Primary:hover {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #8F65FF, stop:1 #1AD1D9);
}

QPushButton.ActiveToggle {
    background-color: #10B981;
    border: 1px solid #10B981;
    color: #FFFFFF;
}

QPushButton.InactiveToggle {
    background-color: #24283B;
    border: 1px solid #3B4261;
    color: #94A3B8;
}

/* Left Sidebar Tab Buttons */
QPushButton.TabBtn {
    background-color: transparent;
    border: none;
    border-radius: 10px;
    padding: 10px;
    color: #94A3B8;
    text-align: center;
    font-size: 11px;
    font-weight: bold;
}

QPushButton.TabBtn:hover {
    background-color: #1E2235;
    color: #E2E8F0;
}

QPushButton.TabBtnSelected {
    background: qlineargradient(x1:0, y1:0, x2:1, y2:0, stop:0 #7C4DFF, stop:1 #00ADB5);
    border-radius: 10px;
    color: #FFFFFF;
    font-size: 11px;
    font-weight: bold;
}

/* Checkbox */
QCheckBox {
    spacing: 8px;
    color: #E2E8F0;
    font-size: 13px;
}

QCheckBox::indicator {
    width: 18px;
    height: 18px;
    border-radius: 4px;
    border: 1px solid #3B4261;
    background-color: #24283B;
}

QCheckBox::indicator:checked {
    background-color: #7C4DFF;
    border-color: #7C4DFF;
}
"""
