import React from 'react';
import { Cpu, Thermometer, HardDrive, Zap, Wind, Volume2, VolumeX, Sun, Touchpad, Keyboard } from 'lucide-react';
import { bridge } from '../../services/bridge';
import type { TelemetryData } from '../../services/bridge';

interface HomeTabProps {
  telemetry: TelemetryData | null;
  tdp: number;
  onTdpChange: (val: number) => void;
  fan: number;
  onFanChange: (val: number) => void;
  isFanAuto: boolean;
  onFanAutoToggle: () => void;
  volume: number;
  onVolumeChange: (val: number) => void;
  isMuted: boolean;
  onMuteToggle: () => void;
  brightness: number;
  onBrightnessChange: (val: number) => void;
  touchEnabled: boolean;
  onTouchToggle: () => void;
}

export const HomeTab: React.FC<HomeTabProps> = ({
  telemetry,
  tdp,
  onTdpChange,
  fan,
  onFanChange,
  isFanAuto,
  onFanAutoToggle,
  volume,
  onVolumeChange,
  isMuted,
  onMuteToggle,
  brightness,
  onBrightnessChange,
  touchEnabled,
  onTouchToggle,
}) => {
  return (
    <div className="flex flex-col gap-3 p-3 overflow-y-auto max-h-full pb-8">
      {/* 1. Live Telemetry Card */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2.5">
        <div className="flex items-center justify-between text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <span>Chỉ số phần cứng thực tế</span>
          <span className="text-emerald-400 flex items-center gap-1 font-mono">
            <span className="h-1.5 w-1.5 rounded-full bg-emerald-400 animate-ping" />
            LIVE
          </span>
        </div>

        <div className="grid grid-cols-2 gap-2">
          <div className="bg-[#121420]/80 rounded-xl p-2.5 flex items-center gap-2.5 border border-white/5">
            <div className="p-2 rounded-lg bg-violet-500/10 text-violet-400">
              <Cpu className="w-4 h-4" />
            </div>
            <div>
              <div className="text-[11px] text-slate-400">CPU Usage</div>
              <div className="text-sm font-bold text-white font-mono">
                {telemetry ? `${telemetry.cpu_percent}%` : '--%'}
              </div>
            </div>
          </div>

          <div className="bg-[#121420]/80 rounded-xl p-2.5 flex items-center gap-2.5 border border-white/5">
            <div className="p-2 rounded-lg bg-rose-500/10 text-rose-400">
              <Thermometer className="w-4 h-4" />
            </div>
            <div>
              <div className="text-[11px] text-slate-400">Nhiệt độ CPU</div>
              <div className="text-sm font-bold text-white font-mono">
                {telemetry ? `${telemetry.cpu_temp}°C` : '--°C'}
              </div>
            </div>
          </div>

          <div className="bg-[#121420]/80 rounded-xl p-2.5 flex items-center gap-2.5 border border-white/5">
            <div className="p-2 rounded-lg bg-sky-500/10 text-sky-400">
              <HardDrive className="w-4 h-4" />
            </div>
            <div>
              <div className="text-[11px] text-slate-400">Bộ nhớ RAM</div>
              <div className="text-sm font-bold text-white font-mono">
                {telemetry ? `${telemetry.ram_used_gb}G / ${telemetry.ram_total_gb}G` : '--'}
              </div>
            </div>
          </div>

          <div className="bg-[#121420]/80 rounded-xl p-2.5 flex items-center gap-2.5 border border-white/5">
            <div className="p-2 rounded-lg bg-amber-500/10 text-amber-400">
              <Zap className="w-4 h-4" />
            </div>
            <div>
              <div className="text-[11px] text-slate-400">Công suất TDP</div>
              <div className="text-sm font-bold text-amber-300 font-mono">
                {telemetry ? `${telemetry.live_tdp} W` : `${tdp} W`}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* 2. TDP Slider Card */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
            <Zap className="w-4 h-4 text-amber-400" />
            <span>Công suất APU (TDP)</span>
          </div>
          <span className="px-2.5 py-0.5 rounded-full bg-violet-500/20 text-violet-300 font-mono font-bold text-xs border border-violet-500/30">
            {tdp} W
          </span>
        </div>

        <input
          type="range"
          min={5}
          max={35}
          step={1}
          value={tdp}
          onChange={(e) => onTdpChange(Number(e.target.value))}
          className="w-full mt-1"
        />

        {/* Quick presets */}
        <div className="grid grid-cols-4 gap-1.5 mt-1">
          {[10, 15, 25, 30].map((w) => (
            <button
              key={w}
              onClick={() => onTdpChange(w)}
              className={`py-1 rounded-lg text-xs font-semibold transition-colors cursor-pointer ${
                tdp === w
                  ? 'bg-violet-600 text-white shadow-md shadow-violet-600/30'
                  : 'bg-white/5 text-slate-300 hover:bg-white/10'
              }`}
            >
              {w}W
            </button>
          ))}
        </div>
      </div>

      {/* 3. Fan Speed Card */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
            <Wind className="w-4 h-4 text-cyan-400" />
            <span>Quạt tản nhiệt</span>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={onFanAutoToggle}
              className={`px-2 py-0.5 rounded-full text-xs font-bold transition-all cursor-pointer ${
                isFanAuto
                  ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/40 shadow-[0_0_8px_rgba(16,185,129,0.3)]'
                  : 'bg-white/5 text-slate-400 border border-white/10 hover:text-white'
              }`}
            >
              AUTO
            </button>
            <span className="px-2.5 py-0.5 rounded-full bg-cyan-500/20 text-cyan-300 font-mono font-bold text-xs border border-cyan-500/30">
              {fan}%
            </span>
          </div>
        </div>

        <input
          type="range"
          min={0}
          max={100}
          step={5}
          value={fan}
          disabled={isFanAuto}
          onChange={(e) => onFanChange(Number(e.target.value))}
          className={`w-full mt-1 ${isFanAuto ? 'opacity-40 cursor-not-allowed' : ''}`}
        />
      </div>

      {/* 4. Volume Card */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
            {isMuted ? (
              <VolumeX className="w-4 h-4 text-rose-400" />
            ) : (
              <Volume2 className="w-4 h-4 text-indigo-400" />
            )}
            <span>Âm lượng hệ thống</span>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={onMuteToggle}
              className={`px-2 py-0.5 rounded-full text-xs font-bold transition-all cursor-pointer ${
                isMuted
                  ? 'bg-rose-500/20 text-rose-400 border border-rose-500/40'
                  : 'bg-white/5 text-slate-400 border border-white/10 hover:text-white'
              }`}
            >
              {isMuted ? 'MUTED' : 'MUTE'}
            </button>
            <span className="px-2.5 py-0.5 rounded-full bg-indigo-500/20 text-indigo-300 font-mono font-bold text-xs border border-indigo-500/30">
              {volume}%
            </span>
          </div>
        </div>

        <input
          type="range"
          min={0}
          max={100}
          step={2}
          value={volume}
          onChange={(e) => onVolumeChange(Number(e.target.value))}
          className="w-full mt-1"
        />
      </div>

      {/* 5. Brightness Card */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
            <Sun className="w-4 h-4 text-amber-400" />
            <span>Độ sáng màn hình</span>
          </div>
          <span className="px-2.5 py-0.5 rounded-full bg-amber-500/20 text-amber-300 font-mono font-bold text-xs border border-amber-500/30">
            {brightness}%
          </span>
        </div>

        <input
          type="range"
          min={0}
          max={100}
          step={5}
          value={brightness}
          onChange={(e) => onBrightnessChange(Number(e.target.value))}
          className="w-full mt-1"
        />
      </div>

      {/* 6. Quick Action Tiles */}
      <div className="grid grid-cols-2 gap-2 mt-1">
        <button
          onClick={onTouchToggle}
          className={`glass-card rounded-2xl p-3 flex flex-col items-center justify-center gap-1.5 transition-all cursor-pointer ${
            touchEnabled
              ? 'border-emerald-500/40 bg-emerald-500/10'
              : 'border-white/5 hover:border-white/20'
          }`}
        >
          <Touchpad className={`w-5 h-5 ${touchEnabled ? 'text-emerald-400' : 'text-slate-400'}`} />
          <span className="text-xs font-semibold text-white">Cảm ứng</span>
          <span className={`text-[10px] font-bold ${touchEnabled ? 'text-emerald-400' : 'text-slate-500'}`}>
            {touchEnabled ? 'ĐANG BẬT' : 'ĐÃ TẮT'}
          </span>
        </button>

        <button
          onClick={() => bridge.toggleVirtualKeyboard()}
          className="glass-card rounded-2xl p-3 flex flex-col items-center justify-center gap-1.5 transition-all hover:border-white/20 hover:bg-white/5 cursor-pointer"
        >
          <Keyboard className="w-5 h-5 text-indigo-400" />
          <span className="text-xs font-semibold text-white">Bàn phím ảo</span>
          <span className="text-[10px] font-bold text-slate-400">MỞ TABTIP</span>
        </button>
      </div>
    </div>
  );
};
