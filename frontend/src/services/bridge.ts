// @ts-ignore
import { QWebChannel } from './qwebchannel.js';

export interface TelemetryData {
  cpu_percent: number;
  cpu_temp: number;
  ram_percent: number;
  ram_used_gb: number;
  ram_total_gb: number;
  battery_percent: number;
  is_charging: boolean;
  live_tdp: number;
  fast_limit: number;
  is_touch_enabled: boolean;
  is_fan_auto: boolean;
  fan_speed: number;
  volume: number;
  is_muted: boolean;
  brightness: number;
}

export interface InitialState {
  config: any;
  telemetry: TelemetryData;
  hardware: {
    tdp: number;
    fan: number;
    fan_auto: boolean;
    volume: number;
    is_muted: boolean;
    brightness: number;
    touch_enabled: boolean;
    autostart: boolean;
  };
}

class BackendBridge {
  private backend: any = null;
  private isReady = false;
  private readyCallbacks: (() => void)[] = [];
  private telemetryCallbacks: ((data: TelemetryData) => void)[] = [];

  constructor() {
    this.init();
  }

  private init() {
    // @ts-ignore
    if (typeof window !== 'undefined' && window.qt && window.qt.webChannelTransport) {
      // @ts-ignore
      new QWebChannel(window.qt.webChannelTransport, (channel: any) => {
        this.backend = channel.objects.backend;
        this.isReady = true;
        console.log('QWebChannel connected to Python backend!');

        // Connect telemetry signal
        if (this.backend.telemetryUpdated) {
          this.backend.telemetryUpdated.connect((jsonStr: string) => {
            try {
              const data = JSON.parse(jsonStr) as TelemetryData;
              this.telemetryCallbacks.forEach((cb) => cb(data));
            } catch (e) {
              console.error('Failed to parse telemetry JSON:', e);
            }
          });
        }

        this.readyCallbacks.forEach((cb) => cb());
        this.readyCallbacks = [];
      });
    } else {
      console.warn('Qt WebChannel transport not found. Running in BROWSER MOCK mode.');
      this.isReady = true;
      // Start mock telemetry ticker for development
      setInterval(() => {
        const mock: TelemetryData = {
          cpu_percent: Math.floor(25 + Math.random() * 20),
          cpu_temp: Math.floor(58 + Math.random() * 6),
          ram_percent: 48,
          ram_used_gb: 7.7,
          ram_total_gb: 16.0,
          battery_percent: 85,
          is_charging: true,
          live_tdp: 15,
          fast_limit: 18,
          is_touch_enabled: true,
          is_fan_auto: true,
          fan_speed: 45,
          volume: 50,
          is_muted: false,
          brightness: 75,
        };
        this.telemetryCallbacks.forEach((cb) => cb(mock));
      }, 1000);
    }
  }

  public onReady(cb: () => void) {
    if (this.isReady) {
      cb();
    } else {
      this.readyCallbacks.push(cb);
    }
  }

  public onTelemetry(cb: (data: TelemetryData) => void) {
    this.telemetryCallbacks.push(cb);
  }

  public async getInitialState(): Promise<InitialState> {
    return new Promise((resolve) => {
      this.onReady(() => {
        if (this.backend && this.backend.getInitialState) {
          this.backend.getInitialState((res: string) => {
            try {
              resolve(JSON.parse(res));
            } catch {
              resolve(this.getMockState());
            }
          });
        } else {
          resolve(this.getMockState());
        }
      });
    });
  }

  public setTdp(watts: number) {
    if (this.backend?.setTdp) {
      this.backend.setTdp(watts);
    } else {
      console.log('[MOCK] setTdp:', watts);
    }
  }

  public setFan(percent: number, isAuto: boolean) {
    if (this.backend?.setFan) {
      this.backend.setFan(percent, isAuto);
    } else {
      console.log('[MOCK] setFan:', percent, isAuto);
    }
  }

  public setVolume(percent: number) {
    if (this.backend?.setVolume) {
      this.backend.setVolume(percent);
    } else {
      console.log('[MOCK] setVolume:', percent);
    }
  }

  public toggleMute(): Promise<boolean> {
    return new Promise((resolve) => {
      if (this.backend?.toggleMute) {
        this.backend.toggleMute((val: boolean) => resolve(val));
      } else {
        console.log('[MOCK] toggleMute');
        resolve(true);
      }
    });
  }

  public setBrightness(percent: number) {
    if (this.backend?.setBrightness) {
      this.backend.setBrightness(percent);
    } else {
      console.log('[MOCK] setBrightness:', percent);
    }
  }

  public toggleTouchscreen(): Promise<boolean> {
    return new Promise((resolve) => {
      if (this.backend?.toggleTouchscreen) {
        this.backend.toggleTouchscreen((val: boolean) => resolve(val));
      } else {
        console.log('[MOCK] toggleTouchscreen');
        resolve(true);
      }
    });
  }

  public toggleVirtualKeyboard() {
    if (this.backend?.toggleVirtualKeyboard) {
      this.backend.toggleVirtualKeyboard();
    } else {
      console.log('[MOCK] toggleVirtualKeyboard');
    }
  }

  public setFpsLimit(limit: number) {
    if (this.backend?.setFpsLimit) {
      this.backend.setFpsLimit(limit);
    } else {
      console.log('[MOCK] setFpsLimit:', limit);
    }
  }

  public setOsdMetric(metricKey: string, enabled: boolean) {
    if (this.backend?.setOsdMetric) {
      this.backend.setOsdMetric(metricKey, enabled);
    } else {
      console.log('[MOCK] setOsdMetric:', metricKey, enabled);
    }
  }

  public setPanelWidth(width: number) {
    if (this.backend?.setPanelWidth) {
      this.backend.setPanelWidth(width);
    } else {
      console.log('[MOCK] setPanelWidth:', width);
    }
  }

  public setPanelScale(scale: number) {
    if (this.backend?.setPanelScale) {
      this.backend.setPanelScale(scale);
    } else {
      console.log('[MOCK] setPanelScale:', scale);
    }
  }

  public setAutostart(enabled: boolean) {
    if (this.backend?.setAutostart) {
      this.backend.setAutostart(enabled);
    } else {
      console.log('[MOCK] setAutostart:', enabled);
    }
  }

  public closeOverlay() {
    if (this.backend?.closeOverlay) {
      this.backend.closeOverlay();
    } else {
      console.log('[MOCK] closeOverlay');
    }
  }

  public exitApp() {
    if (this.backend?.exitApp) {
      this.backend.exitApp();
    } else {
      console.log('[MOCK] exitApp');
    }
  }

  private getMockState(): InitialState {
    return {
      config: {},
      telemetry: {
        cpu_percent: 32,
        cpu_temp: 62,
        ram_percent: 50,
        ram_used_gb: 8.0,
        ram_total_gb: 16.0,
        battery_percent: 90,
        is_charging: true,
        live_tdp: 15,
        fast_limit: 18,
        is_touch_enabled: true,
        is_fan_auto: true,
        fan_speed: 50,
        volume: 60,
        is_muted: false,
        brightness: 75,
      },
      hardware: {
        tdp: 15,
        fan: 50,
        fan_auto: true,
        volume: 60,
        is_muted: false,
        brightness: 75,
        touch_enabled: true,
        autostart: false,
      },
    };
  }
}

export const bridge = new BackendBridge();
