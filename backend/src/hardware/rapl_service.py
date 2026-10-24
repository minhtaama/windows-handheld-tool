import win32pdh
from typing import Optional
from src.core.logger import setup_logger

logger = setup_logger("RaplService")

class RaplService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(RaplService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self._query = None
        self._counter = None
        self._is_available = False
        self._init_pdh()
        self._initialized = True

    def _init_pdh(self):
        try:
            self._query = win32pdh.OpenQuery()
            candidates = [
                r"\Energy Meter(rapl_package0_pkg)\power",
                r"\Energy Meter(rapl_package0)\power",
            ]
            for path in candidates:
                try:
                    self._counter = win32pdh.AddCounter(self._query, path)
                    win32pdh.CollectQueryData(self._query)
                    self._is_available = True
                    logger.info(f"Connected to Windows Energy Meter RAPL counter: {path}")
                    return
                except Exception:
                    self._counter = None

            # Fallback to wildcard search in Energy Meter instances
            try:
                _, instances = win32pdh.EnumObjectItems(None, None, "Energy Meter", win32pdh.PERF_DETAIL_WIZARD)
                for inst in instances:
                    if "pkg" in inst.lower() or "package" in inst.lower():
                        c_path = f"\\Energy Meter({inst})\\power"
                        self._counter = win32pdh.AddCounter(self._query, c_path)
                        win32pdh.CollectQueryData(self._query)
                        self._is_available = True
                        logger.info(f"Connected to dynamic Energy Meter counter: {c_path}")
                        return
            except Exception as e:
                logger.debug(f"EnumObjectItems fallback check: {e}")
        except Exception as e:
            logger.debug(f"Could not initialize Windows Energy Meter PDH: {e}")
            self._is_available = False

    def get_power_watts(self) -> Optional[float]:
        """Returns live processor package wattage in Watts, or None if unavailable."""
        if not self._is_available or not self._query or not self._counter:
            return None
        try:
            win32pdh.CollectQueryData(self._query)
            _, val = win32pdh.GetFormattedCounterValue(self._counter, win32pdh.PDH_FMT_DOUBLE)
            if val > 0:
                return round(val / 1000.0, 1)
        except Exception as e:
            logger.debug(f"Error reading RAPL power: {e}")
        return None

    def close(self):
        if self._query:
            try:
                win32pdh.CloseQuery(self._query)
            except Exception:
                pass
            self._query = None
            self._counter = None

