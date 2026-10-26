"""Logon autostart for the handheld tool.

This build requests administrator rights through its application manifest, and
Windows does not auto-elevate Run-key entries at logon (the user never gets a
prompt they could answer while the desktop is still starting). A logon
Scheduled Task with RunLevel=HighestAvailable starts the app elevated inside
the interactive session instead.

The task is registered through schtasks with an explicit XML definition rather
than the COM API: the definition stays readable in the source, schtasks reports
its rejection reason verbatim into the log, and no COM apartment setup is
needed on the bridge thread.
"""
import locale
import os
import subprocess
import sys
import tempfile
import winreg
from pathlib import Path
from xml.sax.saxutils import escape

from src.core.logger import setup_logger

logger = setup_logger("AutostartService")

TASK_NAME = "WindowsHandheldTool_AutoStart"
TASK_DESCRIPTION = "Khởi động Windows Handheld Tool cùng phiên đăng nhập."
LOGON_DELAY = "PT10S"

# Entry written by the previous Run-key implementation. Removed on every state
# change so no stale, non-elevating duplicate survives next to the task.
LEGACY_RUN_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
LEGACY_RUN_NAME = "WindowsHandheldTool"

# Element order follows the Task Scheduler XML schema; schtasks rejects a
# definition whose elements are out of sequence.
_TASK_XML = """<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>{description}</Description>
  </RegistrationInfo>
  <Triggers>
    <LogonTrigger>
      <Enabled>true</Enabled>
      <UserId>{user}</UserId>
      <Delay>{delay}</Delay>
    </LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>{user}</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <StartWhenAvailable>true</StartWhenAvailable>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>7</Priority>
    <Hidden>false</Hidden>
    <Enabled>true</Enabled>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>{command}</Command>
      <Arguments>{arguments}</Arguments>
      <WorkingDirectory>{working_dir}</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"""


class AutostartService:
    @staticmethod
    def _launch_command() -> tuple:
        """Return ``(executable, arguments)`` for the registered task."""
        python_exe = Path(sys.executable).resolve()

        # Frozen build: sys.executable is the shipped exe (both onefile and
        # onedir). sys.argv[0] would be relative to the caller's CWD.
        if getattr(sys, "frozen", False):
            return str(python_exe), ""

        # Development run: python.exe with the entry script as an argument.
        return str(python_exe), f'"{Path(sys.argv[0]).resolve()}"'

    @staticmethod
    def _current_user() -> str:
        domain = os.environ.get("USERDOMAIN", "").strip()
        user = os.environ.get("USERNAME", "").strip()
        return f"{domain}\\{user}" if domain else user

    @classmethod
    def _build_task_xml(cls) -> str:
        command, arguments = cls._launch_command()
        return _TASK_XML.format(
            description=escape(TASK_DESCRIPTION),
            user=escape(cls._current_user()),
            delay=LOGON_DELAY,
            command=escape(command),
            arguments=escape(arguments),
            working_dir=escape(str(Path(command).parent)),
        )

    @staticmethod
    def _schtasks(*args) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["schtasks", *args],
            capture_output=True,
            text=True,
            encoding=locale.getpreferredencoding(False) or "utf-8",
            errors="replace",
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            check=False,
        )

    @classmethod
    def _describe(cls, result: subprocess.CompletedProcess) -> str:
        detail = (result.stderr or result.stdout or "").strip()
        return f"exit={result.returncode} {detail}".strip()

    @classmethod
    def is_enabled(cls) -> bool:
        try:
            return cls._schtasks("/Query", "/TN", TASK_NAME).returncode == 0
        except Exception as exc:
            logger.error(f"Không truy vấn được Task Scheduler: {exc}")
            return False

    @classmethod
    def set_enabled(cls, enable: bool) -> bool:
        try:
            success = cls._enable() if enable else cls._disable()
        except Exception as exc:
            logger.error(f"Không đổi được trạng thái khởi động cùng Windows: {exc}")
            success = False
        cls._remove_legacy_run_entry()
        return success

    @classmethod
    def _enable(cls) -> bool:
        xml_path = None
        try:
            # schtasks only accepts a Unicode XML definition.
            with tempfile.NamedTemporaryFile(
                "w", suffix=".xml", encoding="utf-16", delete=False
            ) as handle:
                handle.write(cls._build_task_xml())
                xml_path = handle.name

            result = cls._schtasks("/Create", "/TN", TASK_NAME, "/XML", xml_path, "/F")
            if result.returncode == 0:
                command, arguments = cls._launch_command()
                logger.info(
                    f"Đã bật khởi động cùng Windows: \"{command}\" {arguments}".strip()
                )
                return True

            logger.error(f"Tạo task khởi động cùng Windows thất bại: {cls._describe(result)}")
            return False
        finally:
            if xml_path:
                Path(xml_path).unlink(missing_ok=True)

    @classmethod
    def _disable(cls) -> bool:
        result = cls._schtasks("/Delete", "/TN", TASK_NAME, "/F")
        if result.returncode != 0:
            logger.info(f"Không xóa được task (có thể vốn đã tắt): {cls._describe(result)}")
        # Trust the query, not the exit code: confirm the desired end state.
        if cls.is_enabled():
            logger.error("Task khởi động cùng Windows vẫn còn sau khi xóa.")
            return False
        logger.info("Đã tắt khởi động cùng Windows.")
        return True

    @staticmethod
    def _remove_legacy_run_entry() -> None:
        try:
            with winreg.OpenKey(
                winreg.HKEY_CURRENT_USER, LEGACY_RUN_KEY, 0, winreg.KEY_SET_VALUE
            ) as key:
                winreg.DeleteValue(key, LEGACY_RUN_NAME)
                logger.info("Đã gỡ mục Run cũ khỏi registry.")
        except FileNotFoundError:
            pass
        except OSError as exc:
            logger.warning(f"Không gỡ được mục Run cũ: {exc}")
