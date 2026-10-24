import os
import sys
import threading
import time
from typing import List, Tuple, Optional, Dict
from src.core.logger import setup_logger
from src.core.config import ConfigManager

logger = setup_logger("FanService")

# Preset Fan Profiles: List of (Temperature_C, Fan_Speed_Percent)
FAN_PROFILES: Dict[str, List[Tuple[int, int]]] = {
    "quiet": [
        (45, 20),
        (55, 30),
        (65, 45),
        (75, 65),
        (85, 85),
        (90, 100),
    ],
    "balanced": [
        (40, 30),
        (50, 42),
        (60, 58),
        (70, 75),
        (80, 90),
        (85, 100),
    ],
    "cool": [
        (40, 45),
        (50, 60),
        (60, 75),
        (70, 90),
        (75, 100),
    ],
}

DEFAULT_FAN_CURVE = list(FAN_PROFILES["balanced"])

class FanService:
    _instance = None

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            cls._instance = super(FanService, cls).__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return

        self.config = ConfigManager()
        self.is_auto = bool(self.config.get("hardware", "fan", "auto", default=True))
        self.current_speed = int(self.config.get("hardware", "fan", "current", default=50))
        self.profile = str(self.config.get("hardware", "fan", "profile", default="balanced"))

        saved_custom = self.config.get("hardware", "fan", "custom_curve", default=None)
        if saved_custom and isinstance(saved_custom, list):
            self.custom_curve = [(int(p[0]), int(p[1])) for p in saved_custom]
        else:
            self.custom_curve = list(DEFAULT_FAN_CURVE)

        if self.profile in FAN_PROFILES:
            self.fan_curve = list(FAN_PROFILES[self.profile])
        else:
            self.profile = "custom"
            self.fan_curve = list(self.custom_curve)

        # Background thread: adjusts fan speed based on thermal curve with hysteresis
        self._running = True
        self._curve_thread = threading.Thread(target=self._fan_curve_worker, daemon=True)
        self._curve_thread.start()

        self._initialized = True
        logger.info(f"[FanService] Initialized: profile='{self.profile}', is_auto={self.is_auto}, speed={self.current_speed}%")

    def calculate_speed_from_temp(self, temp: float) -> int:
        """Linear interpolation of fan speed (%) from current CPU temperature based on active fan curve"""
        if not self.fan_curve:
            return 50
        sorted_curve = sorted(self.fan_curve, key=lambda x: x[0])
        if temp <= sorted_curve[0][0]:
            return sorted_curve[0][1]
        if temp >= sorted_curve[-1][0]:
            return sorted_curve[-1][1]

        for i in range(len(sorted_curve) - 1):
            t1, s1 = sorted_curve[i]
            t2, s2 = sorted_curve[i + 1]
            if t1 <= temp <= t2:
                ratio = (temp - t1) / float(t2 - t1)
                return round(s1 + ratio * (s2 - s1))
        return 50

    def _fan_curve_worker(self):
        """Background loop updating fan speed according to thermal curve with 3C hysteresis & rate-limiting.
        Only actively drives fan speed when in Manual Fan Curve mode (is_auto=False).
        When is_auto=True, hands over complete control to device BIOS / EC hardware default.
        """
        from src.hardware.tdp_service import TdpService
        tdp_svc = TdpService()

        last_applied_time = 0.0
        last_peak_temp = 0.0

        while self._running:
            time.sleep(2.0)
            # In Auto mode, device BIOS / EC hardware controls fan speeds naturally without software override
            if self.is_auto:
                last_applied_time = 0.0
                continue

            try:
                temp, _, _ = tdp_svc.get_telemetry()
                # If temperature cannot be read (e.g. HVCI blocked), do not override fan for hardware safety
                if temp is None or temp <= 0:
                    continue

                target_speed = self.calculate_speed_from_temp(temp)
                now = time.time()

                # Initial calibration on enabling Manual Fan Curves: sync immediately
                if last_applied_time == 0.0:
                    self.current_speed = target_speed
                    self._apply_hardware_speed(target_speed)
                    last_peak_temp = temp
                    last_applied_time = now
                    continue

                # Thermal Hysteresis:
                # - Increase speed immediately if delta >= 2% to protect hardware
                # - Decrease speed only when temperature drops by >= 3C and at least 3 seconds have passed
                should_apply = False
                if target_speed > self.current_speed and (target_speed - self.current_speed) >= 2:
                    should_apply = True
                    last_peak_temp = temp
                elif target_speed < self.current_speed:
                    if (last_peak_temp - temp) >= 3.0 and (now - last_applied_time) >= 3.0:
                        should_apply = True
                        last_peak_temp = temp

                if should_apply:
                    self.current_speed = target_speed
                    self._apply_hardware_speed(target_speed)
                    last_applied_time = now
            except Exception as e:
                logger.error(f"Error in fan curve worker: {e}")

    def _apply_asus_wmi(self, percent: int) -> bool:
        """Send fan speed control command via ASUS ACPI WMI (ROG Ally / Ally X)"""
        try:
            import win32com.client
            wmi = win32com.client.GetObject("winmgmts:\\\\.\\root\\wmi")
            asus_methods = wmi.ExecQuery("SELECT * FROM AsusAtkWmi_WMNB")
            if asus_methods.Count > 0:
                for obj in asus_methods:
                    for dev_id in (0x00110013, 0x00110014):
                        obj.DEVS(dev_id, percent)
                logger.info(f"[ASUS WMI] Synchronized fan speed: {percent}%")
                return True
        except Exception:
            pass
        return False

    def _apply_hardware_speed(self, percent: int):
        """Apply fan speed to ACPI WMI hardware driver or simulate gracefully"""
        if self._apply_asus_wmi(percent):
            return
        logger.info(f"[FanControl] Active speed: {percent}% (Mode: {'Auto' if self.is_auto else 'Manual'}, Profile: '{self.profile}')")

    def set_fan_profile(self, profile: str, custom_curve: Optional[List[Tuple[int, int]]] = None) -> bool:
        """Switch active fan profile ('quiet', 'balanced', 'cool', 'custom')"""
        if profile in FAN_PROFILES:
            self.profile = profile
            self.fan_curve = list(FAN_PROFILES[profile])
        elif profile == "custom":
            self.profile = "custom"
            if custom_curve:
                self.custom_curve = sorted([(int(p[0]), int(p[1])) for p in custom_curve], key=lambda x: x[0])
                self.config.set(self.custom_curve, "hardware", "fan", "custom_curve")
            self.fan_curve = list(self.custom_curve)
        else:
            return False

        self.config.set(self.profile, "hardware", "fan", "profile")
        logger.info(f"[FanService] Applied fan profile '{self.profile}': {self.fan_curve}")
        return True

    def get_fan_profile(self) -> str:
        return self.profile

    def get_fan_curve(self) -> List[Tuple[int, int]]:
        return list(self.fan_curve)

    def set_auto(self, auto: bool) -> bool:
        self.is_auto = auto
        self.config.set(auto, "hardware", "fan", "auto")
        logger.info(f"Fan Mode: {'Device BIOS Default (Auto)' if auto else 'Manual Fan Curves'}")
        return True

    def get_speed(self) -> int:
        return self.current_speed
