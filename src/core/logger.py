import io
import logging
import sys

def setup_logger(name: str = "HandheldTool") -> logging.Logger:
    if isinstance(sys.stdout, io.TextIOWrapper):
        try:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass

    logger = logging.getLogger(name)
    if not logger.handlers:
        logger.setLevel(logging.INFO)
        if sys.stdout is not None:
            formatter = logging.Formatter(
                fmt="[%(asctime)s] [%(name)s] [%(levelname)s]: %(message)s",
                datefmt="%Y-%m-%d %H:%M:%S",
            )
            stream_handler = logging.StreamHandler(sys.stdout)
            stream_handler.setFormatter(formatter)
            logger.addHandler(stream_handler)
        else:
            logger.addHandler(logging.NullHandler())
    return logger

log = setup_logger()
