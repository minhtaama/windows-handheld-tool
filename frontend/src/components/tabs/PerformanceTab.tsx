import React, { useState } from 'react';
import { Sliders, Monitor, Gauge } from 'lucide-react';
import { bridge } from '../../services/bridge';

interface PerformanceTabProps {
  tdp: number;
  onTdpChange: (val: number) => void;
  fpsLimit: number;
  onFpsLimitChange: (val: number) => void;
}

export const PerformanceTab: React.FC<PerformanceTabProps> = ({
  tdp,
  onTdpChange,
  fpsLimit,
  onFpsLimitChange,
}) => {
  const [fastLimit, setFastLimit] = useState(tdp + 3);
  const [osdMetrics, setOsdMetrics] = useState({
    fps: true,
    tdp: true,
    cpu_temp: true,
    ram: true,
    battery: true,
  });

  const toggleMetric = (key: keyof typeof osdMetrics) => {
    const next = !osdMetrics[key];
    setOsdMetrics((prev) => ({ ...prev, [key]: next }));
    bridge.setOsdMetric(key, next);
  };

  const presets = [
    { name: '10W Pin', watts: 10, desc: 'Tiết kiệm pin, game nhẹ' },
    { name: '15W Chuẩn', watts: 15, desc: 'Cân bằng pin và hiệu năng' },
    { name: '25W Game', watts: 25, desc: 'Trải nghiệm mượt AAA' },
    { name: '30W Turbo', watts: 30, desc: 'Cực hạn công suất cắm sạc' },
  ];

  return (
    <div className="flex flex-col gap-3 p-3 overflow-y-auto max-h-full pb-8">
      {/* 1. Presets */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2.5">
        <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <Gauge className="w-4 h-4 text-violet-400" />
          <span>Hồ sơ công suất (Presets)</span>
        </div>

        <div className="grid grid-cols-2 gap-2">
          {presets.map((p) => (
            <button
              key={p.watts}
              onClick={() => onTdpChange(p.watts)}
              className={`p-2.5 rounded-xl border text-left transition-all cursor-pointer ${
                tdp === p.watts
                  ? 'bg-violet-600/20 border-violet-500/60 shadow-lg shadow-violet-600/20'
                  : 'bg-white/5 border-white/5 hover:border-white/20'
              }`}
            >
              <div className="flex items-center justify-between">
                <span className="font-bold text-xs text-white">{p.name}</span>
                <span className="text-xs font-mono text-violet-300 font-bold">{p.watts}W</span>
              </div>
              <p className="text-[10px] text-slate-400 mt-0.5 line-clamp-1">{p.desc}</p>
            </button>
          ))}
        </div>
      </div>

      {/* 2. Advanced SMU Limits */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-3">
        <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <Sliders className="w-4 h-4 text-violet-400" />
          <span>Tinh chỉnh APU chuyên sâu (SMU Limits)</span>
        </div>

        <div>
          <div className="flex items-center justify-between text-xs text-slate-300 mb-1">
            <span>STAPM Limit (Công suất ổn định):</span>
            <span className="font-mono font-bold text-violet-400">{tdp} W</span>
          </div>
          <input
            type="range"
            min={5}
            max={35}
            value={tdp}
            onChange={(e) => onTdpChange(Number(e.target.value))}
            className="w-full"
          />
        </div>

        <div>
          <div className="flex items-center justify-between text-xs text-slate-300 mb-1">
            <span>Fast Limit (Peak Turbo Boost):</span>
            <span className="font-mono font-bold text-amber-400">{fastLimit} W</span>
          </div>
          <input
            type="range"
            min={5}
            max={40}
            value={fastLimit}
            onChange={(e) => setFastLimit(Number(e.target.value))}
            className="w-full"
          />
        </div>
      </div>

      {/* 3. RTSS FPS Limit */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2.5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
            <Monitor className="w-4 h-4 text-emerald-400" />
            <span>Giới hạn tốc độ khung hình (RTSS)</span>
          </div>
          <span className="px-2.5 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 font-mono font-bold text-xs border border-emerald-500/30">
            {fpsLimit > 0 ? `${fpsLimit} FPS` : 'OFF'}
          </span>
        </div>

        <input
          type="range"
          min={0}
          max={120}
          step={5}
          value={fpsLimit}
          onChange={(e) => onFpsLimitChange(Number(e.target.value))}
          className="w-full"
        />

        <div className="grid grid-cols-5 gap-1 mt-1">
          {[30, 40, 45, 60, 0].map((f) => (
            <button
              key={f}
              onClick={() => onFpsLimitChange(f)}
              className={`py-1 rounded-lg text-xs font-semibold transition-colors cursor-pointer ${
                fpsLimit === f
                  ? 'bg-emerald-600 text-white shadow-md shadow-emerald-600/30'
                  : 'bg-white/5 text-slate-300 hover:bg-white/10'
              }`}
            >
              {f === 0 ? 'Max' : `${f}f`}
            </button>
          ))}
        </div>
      </div>

      {/* 4. OSD Metrics */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2">
        <span className="text-xs font-semibold text-violet-400 uppercase tracking-wider">
          Chỉ số hiển thị trên màn hình (OSD)
        </span>

        <div className="flex flex-col gap-1.5 mt-1">
          {[
            { key: 'fps' as const, label: 'Tốc độ khung hình (FPS)' },
            { key: 'tdp' as const, label: 'Công suất tiêu thụ (TDP Watt)' },
            { key: 'cpu_temp' as const, label: 'Nhiệt độ vi xử lý (CPU Temp)' },
            { key: 'ram' as const, label: 'Dung lượng RAM sử dụng' },
            { key: 'battery' as const, label: 'Tỉ lệ phần trăm Pin' },
          ].map((m) => (
            <label
              key={m.key}
              onClick={() => toggleMetric(m.key)}
              className="flex items-center justify-between p-2 rounded-xl bg-[#121420]/60 border border-white/5 hover:border-white/15 cursor-pointer transition-all"
            >
              <span className="text-xs text-slate-300 font-medium">{m.label}</span>
              <div
                className={`w-4 h-4 rounded flex items-center justify-center transition-all ${
                  osdMetrics[m.key] ? 'bg-violet-600 text-white' : 'border border-slate-600'
                }`}
              >
                {osdMetrics[m.key] && <span className="text-[10px]">✓</span>}
              </div>
            </label>
          ))}
        </div>
      </div>
    </div>
  );
};
