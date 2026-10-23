import io
import logging
import os
import sys
from logging.handlers import RotatingFileHandler

APP_DATA_FOLDER_NAME = "WindowsHandheldTools"

def get_app_data_dir() -> str:
    """Thư mục dữ liệu duy nhất của ứng dụng: %LOCALAPPDATA%\\WindowsHandheldTools (chứa logs\\ và cache\\)"""
    base = os.environ.get("LOCALAPPDATA", os.path.expanduser("~"))
    path = os.path.join(base, APP_DATA_FOLDER_NAME)
    os.makedirs(path, exist_ok=True)
    return path

def get_log_dir() -> str:
    path = os.path.join(get_app_data_dir(), "logs")
    os.makedirs(path, exist_ok=True)
    return path

def get_cache_dir() -> str:
    path = os.path.join(get_app_data_dir(), "cache")
    os.makedirs(path, exist_ok=True)
    return path

def setup_logger(name: str = "HandheldTool") -> logging.Logger:
    if isinstance(sys.stdout, io.TextIOWrapper):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    logger = logging.getLogger(name)
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        formatter = logging.Formatter(
            fmt="[%(asctime)s] [%(name)s] [%(levelname)s]: %(message)s",
            datefmt="%Y-%m-%d %H:%M:%S",
        )

        if sys.stdout is not None:
            stream_handler = logging.StreamHandler(sys.stdout)
            stream_handler.setFormatter(formatter)
            logger.addHandler(stream_handler)

        try:
            log_dir = get_log_dir()
            os.makedirs(log_dir, exist_ok=True)
            log_path = os.path.join(log_dir, "app.log")
            file_handler = RotatingFileHandler(log_path, maxBytes=10 * 1024 * 1024, backupCount=3, encoding="utf-8")
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)
        except Exception:
            pass

        if not logger.handlers:
            logger.addHandler(logging.NullHandler())

    return logger

log = setup_logger()
