import React from 'react';
import { Home, Zap, Gamepad2, Settings } from 'lucide-react';

export type TabId = 'home' | 'performance' | 'device' | 'settings';

interface SidebarProps {
  activeTab: TabId;
  onTabChange: (tab: TabId) => void;
}

export const Sidebar: React.FC<SidebarProps> = ({ activeTab, onTabChange }) => {
  const tabs = [
    { id: 'home' as TabId, label: 'Trang chủ', icon: Home },
    { id: 'performance' as TabId, label: 'Hiệu năng', icon: Zap },
    { id: 'device' as TabId, label: 'Thiết bị', icon: Gamepad2 },
    { id: 'settings' as TabId, label: 'Cài đặt', icon: Settings },
  ];

  return (
    <div className="w-18 bg-[#10121d] border-r border-white/5 flex flex-col items-center py-4 gap-2 select-none">
      {tabs.map((tab) => {
        const Icon = tab.icon;
        const isActive = activeTab === tab.id;

        return (
          <button
            key={tab.id}
            onClick={() => onTabChange(tab.id)}
            className={`w-14 h-14 rounded-xl flex flex-col items-center justify-center gap-1 transition-all duration-200 cursor-pointer ${
              isActive
                ? 'bg-gradient-to-br from-violet-600 to-indigo-600 text-white shadow-lg shadow-violet-500/25 scale-102'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            <Icon className="w-5 h-5" />
            <span className="text-[10px] font-semibold tracking-tight">
              {tab.label}
            </span>
          </button>
        );
      })}
    </div>
  );
};
