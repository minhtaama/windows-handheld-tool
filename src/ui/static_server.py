import os
import threading
from functools import partial
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from src.core.logger import setup_logger

logger = setup_logger("StaticServer")


class QuietHTTPHandler(SimpleHTTPRequestHandler):
    """Bộ xử lý HTTP tĩnh tùy biến: tắt log truy cập stdout mặc định và cấm cache trình duyệt"""

    def log_message(self, format, *args):
        # Không in tràn màn hình log từng request tĩnh, chỉ ghi nhận lỗi nếu có
        if len(args) >= 2 and isinstance(args[1], str) and args[1].startswith("4"):
            logger.warning(f"Lỗi tài nguyên web: {args[0]} -> {args[1]}")

    def end_headers(self):
        # Tắt lưu đệm để đảm bảo giao diện luôn nạp bản build mới nhất
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


class StaticServer:
    """Máy chủ HTTP tĩnh siêu nhẹ phục vụ giao diện Flutter Web từ thư mục build/web"""

    def __init__(self, directory: str, port: int = 8766):
        self.directory = directory
        self.port = port
        self.httpd = None
        self.thread = None
        self.is_running = False

    def start(self) -> bool:
        if self.is_running:
            return True

        if not os.path.isdir(self.directory):
            logger.error(f"Thư mục phục vụ giao diện không tồn tại: {self.directory}")
            return False

        try:
            handler = partial(QuietHTTPHandler, directory=self.directory)
            self.httpd = ThreadingHTTPServer(("127.0.0.1", self.port), handler)
            self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
            self.thread.start()
            self.is_running = True
            logger.info(f"Máy chủ giao diện Flutter Web đã kích hoạt tại http://127.0.0.1:{self.port} (Thư mục: {self.directory})")
            return True
        except Exception as e:
            logger.error(f"Không thể khởi động máy chủ tĩnh tại cổng {self.port}: {e}")
            return False

    def stop(self):
        if self.httpd and self.is_running:
            try:
                self.httpd.shutdown()
                self.httpd.server_close()
                self.is_running = False
                logger.info("Đã dừng máy chủ giao diện Flutter Web.")
            except Exception as e:
                logger.warning(f"Lỗi khi dừng máy chủ tĩnh: {e}")
