import React, { useState, useEffect } from 'react';
import { Header } from './components/Header';
import { Sidebar } from './components/Sidebar';
import type { TabId } from './components/Sidebar';
import { HomeTab } from './components/tabs/HomeTab';
import { PerformanceTab } from './components/tabs/PerformanceTab';
import { DeviceTab } from './components/tabs/DeviceTab';
import { SettingsTab } from './components/tabs/SettingsTab';
import { bridge } from './services/bridge';
import type { TelemetryData } from './services/bridge';

export const App: React.FC = () => {
  const [activeTab, setActiveTab] = useState<TabId>('home');
  const [telemetry, setTelemetry] = useState<TelemetryData | null>(null);

  // Hardware state
  const [tdp, setTdp] = useState(15);
  const [fan, setFan] = useState(50);
  const [isFanAuto, setIsFanAuto] = useState(true);
  const [volume, setVolume] = useState(60);
  const [isMuted, setIsMuted] = useState(false);
  const [brightness, setBrightness] = useState(75);
  const [touchEnabled, setTouchEnabled] = useState(true);
  const [fpsLimit, setFpsLimit] = useState(60);
  const [panelWidth, setPanelWidth] = useState(380);
  const [scale, setScale] = useState(1.0);
  const [autostart, setAutostart] = useState(false);

  useEffect(() => {
    // 1. Load initial state from backend
    bridge.getInitialState().then((res) => {
      if (res && res.hardware) {
        setTdp(res.hardware.tdp ?? 15);
        setFan(res.hardware.fan ?? 50);
        setIsFanAuto(res.hardware.fan_auto ?? true);
        setVolume(res.hardware.volume ?? 60);
        setIsMuted(res.hardware.is_muted ?? false);
        setBrightness(res.hardware.brightness ?? 75);
        setTouchEnabled(res.hardware.touch_enabled ?? true);
        setAutostart(res.hardware.autostart ?? false);
      }
      if (res && res.config && res.config.overlay) {
        setPanelWidth(res.config.overlay.width ?? 380);
        setScale(res.config.overlay.scale ?? 1.0);
      }
      if (res && res.config && res.config.hardware && res.config.hardware.rtss) {
        setFpsLimit(res.config.hardware.rtss.fps_limit ?? 60);
      }
      if (res && res.telemetry) {
        setTelemetry(res.telemetry);
      }
    });

    // 2. Listen for real-time telemetry updates (1000ms heartbeat)
    bridge.onTelemetry((data) => {
      setTelemetry(data);
      if (data.volume !== undefined) setVolume(data.volume);
      if (data.is_muted !== undefined) setIsMuted(data.is_muted);
      if (data.brightness !== undefined) setBrightness(data.brightness);
      if (data.is_touch_enabled !== undefined) setTouchEnabled(data.is_touch_enabled);
    });
  }, []);

  const handleTdpChange = (val: number) => {
    setTdp(val);
    bridge.setTdp(val);
  };

  const handleFanChange = (val: number) => {
    setFan(val);
    setIsFanAuto(false);
    bridge.setFan(val, false);
  };

  const handleFanAutoToggle = () => {
    const next = !isFanAuto;
    setIsFanAuto(next);
    bridge.setFan(fan, next);
  };

  const handleVolumeChange = (val: number) => {
    setVolume(val);
    bridge.setVolume(val);
  };

  const handleMuteToggle = async () => {
    const next = await bridge.toggleMute();
    setIsMuted(next);
  };

  const handleBrightnessChange = (val: number) => {
    setBrightness(val);
    bridge.setBrightness(val);
  };

  const handleTouchToggle = async () => {
    const next = await bridge.toggleTouchscreen();
    setTouchEnabled(next);
  };

  const handleFpsLimitChange = (val: number) => {
    setFpsLimit(val);
    bridge.setFpsLimit(val);
  };

  const handlePanelWidthChange = (val: number) => {
    setPanelWidth(val);
    bridge.setPanelWidth(val);
  };

  const handleScaleChange = (val: number) => {
    setScale(val);
    bridge.setPanelScale(val);
  };

  const handleAutostartChange = (val: boolean) => {
    setAutostart(val);
    bridge.setAutostart(val);
  };

  return (
    <div
      className="w-screen h-screen flex flex-col bg-[#0b0d14] text-slate-100 overflow-hidden select-none"
      style={{ zoom: scale }}
    >
      {/* Top Header */}
      <Header telemetry={telemetry} />

      {/* Main Container: Sidebar + Content */}
      <div className="flex-1 flex overflow-hidden">
        {/* Left Vertical Navigation */}
        <Sidebar activeTab={activeTab} onTabChange={setActiveTab} />

        {/* Right Tab Content */}
        <div className="flex-1 overflow-hidden relative">
          {activeTab === 'home' && (
            <HomeTab
              telemetry={telemetry}
              tdp={tdp}
              onTdpChange={handleTdpChange}
              fan={fan}
              onFanChange={handleFanChange}
              isFanAuto={isFanAuto}
              onFanAutoToggle={handleFanAutoToggle}
              volume={volume}
              onVolumeChange={handleVolumeChange}
              isMuted={isMuted}
              onMuteToggle={handleMuteToggle}
              brightness={brightness}
              onBrightnessChange={handleBrightnessChange}
              touchEnabled={touchEnabled}
              onTouchToggle={handleTouchToggle}
            />
          )}

          {activeTab === 'performance' && (
            <PerformanceTab
              tdp={tdp}
              onTdpChange={handleTdpChange}
              fpsLimit={fpsLimit}
              onFpsLimitChange={handleFpsLimitChange}
            />
          )}

          {activeTab === 'device' && <DeviceTab telemetry={telemetry} />}

          {activeTab === 'settings' && (
            <SettingsTab
              panelWidth={panelWidth}
              onPanelWidthChange={handlePanelWidthChange}
              scale={scale}
              onScaleChange={handleScaleChange}
              autostart={autostart}
              onAutostartChange={handleAutostartChange}
            />
          )}
        </div>
      </div>
    </div>
  );
};

export default App;
