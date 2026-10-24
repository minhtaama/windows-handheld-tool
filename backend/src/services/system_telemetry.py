import psutil
from typing import Dict, Any
from src.hardware.tdp_service import TdpService
from src.hardware.fan_service import FanService
from src.hardware.rtss_service import RtssService
from src.core.logger import setup_logger

logger = setup_logger("SystemTelemetry")

class SystemTelemetryService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(SystemTelemetryService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return
        self.tdp_service = TdpService()
        self.fan_service = FanService()
        self.rtss_service = RtssService()
        try:
            psutil.cpu_percent(interval=None)  # Mồi trước để chu kỳ sau trả về đúng % CPU
        except Exception:
            pass
        self._initialized = True

    def get_snapshot(self) -> Dict[str, Any]:
        """Thu thập các chỉ số phần cứng tức thời: CPU, RAM, Pin, Nhiệt độ, TDP, Quạt, FPS và Game"""
        cpu_usage = psutil.cpu_percent(interval=None)
        mem = psutil.virtual_memory()
        ram_usage = mem.percent
        ram_used_gb = round(mem.used / (1024 ** 3), 1)
        ram_total_gb = round(mem.total / (1024 ** 3), 1)

        battery = psutil.sensors_battery()
        battery_percent = int(battery.percent) if battery else 100
        is_charging = battery.power_plugged if battery else True

        cpu_temp, live_tdp, fast_limit = self.tdp_service.get_telemetry()
        current_fan = self.fan_service.get_speed()
        is_auto_fan = self.fan_service.is_auto

        active_game, live_fps = self.rtss_service.get_active_game_and_fps()

        return {
            "cpu_percent": int(cpu_usage),
            "cpu_usage": int(cpu_usage),
            "cpu_temp": round(cpu_temp) if cpu_temp > 0 else 45,
            "ram_percent": int(ram_usage),
            "ram_usage_percent": int(ram_usage),
            "ram_used_gb": ram_used_gb,
            "ram_total_gb": ram_total_gb,
            "battery_percent": battery_percent,
            "is_charging": is_charging,
            "live_tdp": round(live_tdp) if (live_tdp is not None and live_tdp > 0) else None,
            "fast_limit": round(fast_limit) if fast_limit > 0 else 18,
            "fan_speed": current_fan,
            "live_fan": current_fan,
            "is_fan_auto": is_auto_fan,
            "fan_auto": is_auto_fan,
            "live_fps": live_fps,
            "active_game": active_game,
            "is_tdp_hardware_active": self.tdp_service.is_active,
            "is_hvci_blocked": getattr(self.tdp_service, "is_hvci_blocked", False),
        }


