import React from 'react';
import { X, BatteryCharging, Battery } from 'lucide-react';
import { bridge } from '../services/bridge';
import type { TelemetryData } from '../services/bridge';

interface HeaderProps {
  telemetry: TelemetryData | null;
}

export const Header: React.FC<HeaderProps> = ({ telemetry }) => {
  return (
    <div className="h-12 border-b border-white/10 bg-[#12141f]/90 px-4 flex items-center justify-between select-none">
      <div className="flex items-center gap-2">
        <div className="h-2.5 w-2.5 rounded-full bg-violet-500 animate-pulse shadow-[0_0_8px_rgba(139,92,246,0.8)]" />
        <span className="font-bold text-sm tracking-wider text-white uppercase">
          Handheld Control
        </span>
      </div>

      <div className="flex items-center gap-3">
        {telemetry && (
          <div className="flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/5 border border-white/10 text-xs font-medium text-slate-300">
            {telemetry.is_charging ? (
              <BatteryCharging className="w-3.5 h-3.5 text-emerald-400 animate-pulse" />
            ) : (
              <Battery className="w-3.5 h-3.5 text-slate-400" />
            )}
            <span>{telemetry.battery_percent}%</span>
          </div>
        )}

        <button
          onClick={() => bridge.closeOverlay()}
          className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-white/10 transition-colors cursor-pointer"
          title="Đóng thanh điều khiển (Esc / Ctrl+Shift+Q)"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
