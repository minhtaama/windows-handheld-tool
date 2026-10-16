import os
import subprocess
import ctypes
from ctypes import wintypes
import psutil
from src.core.logger import setup_logger

logger = setup_logger("SystemOptimizer")

class SystemOptimizerService:
    """Dịch vụ tối ưu hóa tài nguyên hệ thống và phím tắt thao tác nhanh cho Handheld"""

    @staticmethod
    def launch_task_manager() -> bool:
        """Khởi chạy Windows Task Manager độc lập không chặn luồng"""
        try:
            subprocess.Popen(
                ["taskmgr.exe"],
                creationflags=0x08000000 | 0x00000200,  # CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP
                shell=False
            )
            logger.info("Đã khởi chạy Task Manager thành công.")
            return True
        except Exception as e:
            logger.error(f"Lỗi khởi chạy Task Manager: {e}")
            try:
                os.system("start taskmgr.exe")
                return True
            except Exception:
                return False

    @staticmethod
    def launch_display_settings() -> bool:
        """Mở trang Cài đặt Hiển thị của Windows Settings"""
        try:
            subprocess.Popen(
                ["cmd.exe", "/c", "start", "ms-settings:display"],
                creationflags=0x08000000,
                shell=False
            )
            logger.info("Đã mở Cài đặt Hiển thị Windows Settings.")
            return True
        except Exception as e:
            logger.error(f"Lỗi mở Cài đặt Hiển thị: {e}")
            return False

    @staticmethod
    def trim_working_set() -> int:
        """
        Dọn dẹp bộ nhớ RAM đệm (Working Set Trimming) qua psapi.dll:
        Giải phóng các trang bộ nhớ vật lý không sử dụng của tiến trình người dùng,
        trả lại RAM trống cho game mà không làm gián đoạn hay treo ứng dụng.
        """
        psapi = ctypes.windll.psapi
        kernel32 = ctypes.windll.kernel32

        PROCESS_QUERY_INFORMATION = 0x0400
        PROCESS_SET_QUOTA = 0x0100

        current_pid = os.getpid()
        trimmed_count = 0

        for proc in psutil.process_iter(['pid', 'name']):
            pid = proc.info['pid']
            if pid <= 4 or pid == current_pid:
                continue

            try:
                h_process = kernel32.OpenProcess(
                    PROCESS_QUERY_INFORMATION | PROCESS_SET_QUOTA,
                    False,
                    pid
                )
                if h_process:
                    try:
                        res = psapi.EmptyWorkingSet(h_process)
                        if res:
                            trimmed_count += 1
                    finally:
                        kernel32.CloseHandle(h_process)
            except Exception:
                pass

        logger.info(f"Đã hoàn thành dọn dẹp RAM (EmptyWorkingSet trên {trimmed_count} tiến trình).")
        return trimmed_count

