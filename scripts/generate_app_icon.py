import sys
import os
from PySide6.QtWidgets import QApplication
from PySide6.QtGui import QImage, QPainter
from PySide6.QtSvg import QSvgRenderer
from PySide6.QtCore import QByteArray, QRectF

def main():
    app = QApplication.instance() or QApplication(sys.argv)

    # Pure Gamepad icon with subtle drop-shadow for light/dark contrast, NO circular background
    svg_code = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="256" height="256">
  <!-- Subtle dark drop shadow outline for crisp visibility on light/dark themes -->
  <path fill="rgba(0,0,0,0.25)" transform="translate(0, 0.6)" d="M21.58 16.09l-1.09-7.66C20.21 6.46 18.52 5 16.53 5H7.47C5.48 5 3.79 6.46 3.51 8.43l-1.09 7.66C2.2 17.63 3.39 19 4.94 19c.68 0 1.32-.27 1.8-.75L9 16h6l2.25 2.25c.48.48 1.13.75 1.8.75 1.56 0 2.75-1.37 2.53-2.91zM11 11H9v2H8v-2H6v-1h2V8h1v2h2v1zm4-1c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm2 3c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>
  <!-- Gamepad Main Silhouette in Pure White with crisp edge -->
  <path fill="#FFFFFF" stroke="rgba(40,40,40,0.35)" stroke-width="0.35" stroke-linejoin="round" d="M21.58 16.09l-1.09-7.66C20.21 6.46 18.52 5 16.53 5H7.47C5.48 5 3.79 6.46 3.51 8.43l-1.09 7.66C2.2 17.63 3.39 19 4.94 19c.68 0 1.32-.27 1.8-.75L9 16h6l2.25 2.25c.48.48 1.13.75 1.8.75 1.56 0 2.75-1.37 2.53-2.91zM11 11H9v2H8v-2H6v-1h2V8h1v2h2v1zm4-1c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm2 3c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>
  <!-- Thumbstick subtle details -->
  <circle cx="9.2" cy="15.0" r="1.7" fill="#E8E8E8" stroke="rgba(0,0,0,0.25)" stroke-width="0.25"/>
  <circle cx="14.8" cy="15.0" r="1.7" fill="#E8E8E8" stroke="rgba(0,0,0,0.25)" stroke-width="0.25"/>
  <circle cx="9.2" cy="15.0" r="1.0" fill="#9E9E9E"/>
  <circle cx="14.8" cy="15.0" r="1.0" fill="#9E9E9E"/>
</svg>"""

    renderer = QSvgRenderer(QByteArray(svg_code.encode("utf-8")))

    # Render 256x256 master image
    img = QImage(256, 256, QImage.Format.Format_ARGB32)
    img.fill(0)  # Transparent background
    painter = QPainter(img)
    painter.setRenderHint(QPainter.RenderHint.Antialiasing)
    painter.setRenderHint(QPainter.RenderHint.SmoothPixmapTransform)
    renderer.render(painter, QRectF(0, 0, 256, 256))
    painter.end()

    # Save to backend/assets
    os.makedirs("backend/assets", exist_ok=True)
    img.save("backend/assets/app_icon.png", "PNG")
    img.save("backend/assets/app_icon.ico", "ICO")
    print("Created backend/assets/app_icon.png and app_icon.ico")

    # Sync to dist directories if they exist
    dirs_to_sync = [
        "dist/windows_handheld_tool/assets",
        "dist/windows_handheld_tool/_internal/assets"
    ]
    for d in dirs_to_sync:
        if os.path.isdir(d):
            import shutil
            shutil.copy("backend/assets/app_icon.png", os.path.join(d, "app_icon.png"))
            shutil.copy("backend/assets/app_icon.ico", os.path.join(d, "app_icon.ico"))
            print(f"Synced icon to {d}")

if __name__ == "__main__":
    main()

