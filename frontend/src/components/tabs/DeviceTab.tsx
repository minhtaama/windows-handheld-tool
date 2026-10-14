import React from 'react';
import { Monitor, Gamepad2, Info } from 'lucide-react';
import type { TelemetryData } from '../../services/bridge';

interface DeviceTabProps {
  telemetry: TelemetryData | null;
}

export const DeviceTab: React.FC<DeviceTabProps> = ({ telemetry }) => {
  return (
    <div className="flex flex-col gap-3 p-3 overflow-y-auto max-h-full pb-8">
      {/* 1. System Info */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2.5">
        <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <Info className="w-4 h-4 text-violet-400" />
          <span>Thông tin phần cứng hệ thống</span>
        </div>

        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between text-xs py-1.5 border-b border-white/5">
            <span className="text-slate-400">Vi xử lý (APU):</span>
            <span className="text-white font-semibold">AMD Ryzen 7 Series</span>
          </div>

          <div className="flex items-center justify-between text-xs py-1.5 border-b border-white/5">
            <span className="text-slate-400">Hệ điều hành:</span>
            <span className="text-white font-semibold">Windows 11 Handheld Edition</span>
          </div>

          <div className="flex items-center justify-between text-xs py-1.5">
            <span className="text-slate-400">Tổng bộ nhớ RAM:</span>
            <span className="text-violet-300 font-mono font-bold">
              {telemetry ? `${telemetry.ram_total_gb} GB LPDDR5` : '16.0 GB LPDDR5'}
            </span>
          </div>
        </div>
      </div>

      {/* 2. Display Info */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2.5">
        <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <Monitor className="w-4 h-4 text-cyan-400" />
          <span>Màn hình hiển thị</span>
        </div>

        <div className="flex flex-col gap-2">
          <div className="flex items-center justify-between text-xs py-1.5 border-b border-white/5">
            <span className="text-slate-400">Độ phân giải thực:</span>
            <span className="text-white font-mono font-semibold">
              {window.screen ? `${window.screen.width} x ${window.screen.height}` : '1920 x 1080'}
            </span>
          </div>

          <div className="flex items-center justify-between text-xs py-1.5 border-b border-white/5">
            <span className="text-slate-400">Tần số quét màn hình:</span>
            <span className="text-emerald-400 font-mono font-bold">120 Hz / 60 Hz</span>
          </div>

          <div className="flex items-center justify-between text-xs py-1.5">
            <span className="text-slate-400">Tỉ lệ DPI cửa sổ:</span>
            <span className="text-slate-300 font-mono">
              {window.devicePixelRatio ? `${window.devicePixelRatio.toFixed(2)}x` : '1.0x'}
            </span>
          </div>
        </div>
      </div>

      {/* 3. Peripherals */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2.5">
        <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <Gamepad2 className="w-4 h-4 text-indigo-400" />
          <span>Thiết bị ngoại vi tích hợp</span>
        </div>

        <div className="flex items-center justify-between p-2.5 rounded-xl bg-[#121420]/60 border border-white/5">
          <div className="flex items-center gap-2.5">
            <Gamepad2 className="w-5 h-5 text-emerald-400" />
            <div>
              <div className="text-xs font-bold text-white">Tay cầm Handheld (XInput)</div>
              <div className="text-[10px] text-slate-400">Tổ hợp phím tắt: BACK + RB</div>
            </div>
          </div>
          <span className="px-2 py-0.5 rounded-full text-[10px] font-bold bg-emerald-500/20 text-emerald-400 border border-emerald-500/40">
            SẴN SÀNG
          </span>
        </div>
      </div>
    </div>
  );
};
