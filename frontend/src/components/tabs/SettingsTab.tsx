import React from 'react';
import { Sliders, Laptop, Keyboard, Power } from 'lucide-react';
import { bridge } from '../../services/bridge';

interface SettingsTabProps {
  panelWidth: number;
  onPanelWidthChange: (val: number) => void;
  scale: number;
  onScaleChange: (val: number) => void;
  autostart: boolean;
  onAutostartChange: (val: boolean) => void;
}

export const SettingsTab: React.FC<SettingsTabProps> = ({
  panelWidth,
  onPanelWidthChange,
  scale,
  onScaleChange,
  autostart,
  onAutostartChange,
}) => {
  return (
    <div className="flex flex-col gap-3 p-3 overflow-y-auto max-h-full pb-8">
      {/* 1. Panel Geometry */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-3">
        <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <Sliders className="w-4 h-4 text-violet-400" />
          <span>Kích thước thanh điều khiển</span>
        </div>

        <div>
          <div className="flex items-center justify-between text-xs text-slate-300 mb-1">
            <span>Độ rộng thanh bên (Width):</span>
            <span className="font-mono font-bold text-violet-400">{panelWidth} px</span>
          </div>
          <input
            type="range"
            min={300}
            max={520}
            step={10}
            value={panelWidth}
            onChange={(e) => onPanelWidthChange(Number(e.target.value))}
            className="w-full"
          />
        </div>

        <div>
          <div className="flex items-center justify-between text-xs text-slate-300 mb-1">
            <span>Tỉ lệ phóng to (Scale):</span>
            <span className="font-mono font-bold text-cyan-400">{scale.toFixed(1)}x</span>
          </div>
          <input
            type="range"
            min={0.8}
            max={1.5}
            step={0.1}
            value={scale}
            onChange={(e) => onScaleChange(Number(e.target.value))}
            className="w-full"
          />
        </div>
      </div>

      {/* 2. System Integration */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2.5">
        <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <Laptop className="w-4 h-4 text-indigo-400" />
          <span>Tích hợp hệ thống Windows</span>
        </div>

        <label
          onClick={() => onAutostartChange(!autostart)}
          className="flex items-center justify-between p-2.5 rounded-xl bg-[#121420]/60 border border-white/5 hover:border-white/15 cursor-pointer transition-all"
        >
          <div>
            <div className="text-xs font-semibold text-white">Khởi động cùng Windows</div>
            <div className="text-[10px] text-slate-400">Tự động kích hoạt khi mở máy</div>
          </div>
          <div
            className={`w-10 h-6 rounded-full transition-colors relative cursor-pointer ${
              autostart ? 'bg-violet-600' : 'bg-slate-700'
            }`}
          >
            <div
              className={`w-4 h-4 rounded-full bg-white absolute top-1 transition-transform ${
                autostart ? 'right-1' : 'left-1'
              }`}
            />
          </div>
        </label>
      </div>

      {/* 3. Hotkeys Summary */}
      <div className="glass-card rounded-2xl p-3.5 flex flex-col gap-2">
        <div className="flex items-center gap-2 text-xs font-semibold text-violet-400 uppercase tracking-wider">
          <Keyboard className="w-4 h-4 text-amber-400" />
          <span>Phím tắt toàn cục</span>
        </div>

        <div className="flex flex-col gap-1.5 mt-1">
          {[
            { label: 'Bật/Tắt bảng điều khiển:', key: 'Ctrl + Shift + Q' },
            { label: 'Tổ hợp nút trên Gamepad:', key: 'BACK + RB' },
            { label: 'Mở bàn phím ảo TabTip:', key: 'Ctrl + Alt + K' },
          ].map((h, i) => (
            <div key={i} className="flex items-center justify-between text-xs py-1">
              <span className="text-slate-400">{h.label}</span>
              <kbd className="px-2 py-0.5 rounded bg-[#121420] border border-white/10 text-violet-300 font-mono text-[11px] font-bold">
                {h.key}
              </kbd>
            </div>
          ))}
        </div>
      </div>

      {/* 4. Danger Zone */}
      <div className="glass-card rounded-2xl p-3.5 border-rose-500/20 bg-rose-500/5 mt-1">
        <button
          onClick={() => bridge.exitApp()}
          className="w-full py-2.5 rounded-xl bg-gradient-to-r from-rose-600 to-red-600 hover:from-rose-500 hover:to-red-500 text-white font-bold text-xs flex items-center justify-center gap-2 transition-all shadow-lg shadow-rose-600/30 cursor-pointer"
        >
          <Power className="w-4 h-4" />
          <span>Thoát hoàn toàn ứng dụng (Exit App)</span>
        </button>
      </div>
    </div>
  );
};
