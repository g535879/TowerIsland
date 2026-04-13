中文 | [English](README.md)

# Tower Island

一款 macOS 菜单栏应用，为你的所有 AI 编程助手提供一个**灵动岛风格的控制塔**。在屏幕顶部的一个浮动面板中，统一监控 Claude Code、Cursor、Codex、OpenCode、Gemini CLI 等多个 AI Agent 的工作状态。

## 功能介绍

Tower Island 以一个紧凑的药丸形状悬浮在屏幕顶部。当 AI Agent 工作时，它会实时显示状态。鼠标悬停即可展开，查看所有活跃会话的详细信息。

**核心功能：**

- **统一面板** — 在一个地方查看所有 AI 编程助手的状态，无论它们运行在哪个终端或 IDE 中
- **实时状态** — 状态指示灯（蓝色 = 工作中，绿色 = 已完成，橙色 = 等待输入，红色 = 出错）
- **权限审批** — 直接在灵动岛中批准或拒绝文件/命令权限，无需切换窗口
- **问题回答** — 在灵动岛中直接回答 Agent 提出的问题
- **计划审查** — 内联审查和批准 Agent 的执行计划
- **音效通知** — 8-bit 风格的音效提醒（可按事件类型单独配置）
- **多会话支持** — 同一 Agent 的多个对话窗口独立追踪
- **窗口跳转** — 点击会话卡片直接跳转到对应的终端标签页或 IDE 窗口（支持 iTerm2 标签级精确跳转）
- **水平拖动** — 可沿屏幕顶部左右拖动灵动岛位置
- **智能标题** — 显示首条用户提问作为标题，工作目录文件夹名作为副标题

**支持的 AI Agent：**

| Agent | 接入方式 | 支持状态 |
|-------|---------|---------|
| Claude Code | 原生 hooks (settings.json) | 完整支持 |
| Cursor | Hooks API (hooks.json) | 完整支持 |
| Codex (OpenAI) | 原生 hooks | 完整支持 |
| OpenCode | JS 插件 | 完整支持 |
| Gemini CLI | 配置 hook | 基础支持 |
| Copilot (VS Code) | 配置 hook | 基础支持 |

## 快速开始

### 环境要求

- macOS 14.0 (Sonoma) 或更高版本
- Swift 5.9+
- 至少安装一个支持的 AI 编程助手

### 构建与运行

```bash
# 克隆仓库
git clone https://github.com/user/tower-island.git
cd tower-island

# 构建（调试版）
swift build

# 直接运行
.build/debug/TowerIsland

# 或构建 Release 版 .app 包（含 bridge 安装）
bash Scripts/build.sh
open ".build/Tower Island.app"
```

### Agent 配置

Tower Island 在首次启动时会**自动配置**所有已检测到的 Agent 的 hook。无需手动设置。

如需验证或手动配置：
- 打开 Tower Island 设置（齿轮图标或菜单栏）
- 进入 **Agents** 标签页
- 按需开启/关闭各 Agent

底层原理：安装一个轻量的 bridge 可执行文件（`di-bridge`）到 `~/.tower-island/bin/`，并在各 Agent 的配置文件中注册 hook。

## 架构

```
┌─────────────────────────────────────────────────┐
│                Tower Island App                  │
│                                                  │
│   NotchWindow (NSPanel)                          │
│   ├── CollapsedPillView (状态指示)                │
│   └── 展开视图                                    │
│       ├── SessionListView (会话卡片)              │
│       ├── PermissionApprovalView (权限审批)        │
│       ├── QuestionAnswerView (问题回答)            │
│       └── PlanReviewView (计划审查)                │
│                                                  │
│   SessionManager ← Unix Socket ← di-bridge      │
│   AudioEngine (8-bit 音效合成)                    │
│   ZeroConfigManager (自动配置 Agent)              │
└─────────────────────────────────────────────────┘

Agent hook 触发 → di-bridge 编码消息 → Unix Socket → SessionManager
```

**核心组件：**

- **`TowerIsland`** — 主应用。SwiftUI 视图托管在 `NSPanel` 中，实现浮动灵动岛 UI
- **`DIBridge`** — 轻量 CLI 工具，由 Agent hook 调用。读取 stdin JSON，编码为 `DIMessage`，通过 Unix Socket 发送
- **`DIShared`** — 共享协议定义（`DIMessage`、Socket 配置）

## 项目结构

```
Sources/
├── DIShared/          # 共享协议与 Socket 配置
│   └── Protocol.swift
├── DIBridge/          # Bridge CLI 工具
│   └── DIBridge.swift
└── DynamicIsland/     # 主应用
    ├── TowerIslandApp.swift
    ├── AppDelegate.swift
    ├── NotchWindow.swift
    ├── Models/
    │   ├── AgentSession.swift
    │   └── AgentType.swift
    ├── Managers/
    │   ├── SessionManager.swift
    │   ├── AudioEngine.swift
    │   ├── SocketServer.swift
    │   ├── ZeroConfigManager.swift
    │   └── TerminalJumpManager.swift
    └── Views/
        ├── NotchContentView.swift
        ├── CollapsedPillView.swift
        ├── SessionListView.swift
        ├── ExpandedSessionView.swift
        ├── PermissionApprovalView.swift
        ├── QuestionAnswerView.swift
        ├── PlanReviewView.swift
        └── PreferencesView.swift

Scripts/
├── build.sh           # Release 构建 + .app 打包
└── test.sh            # 集成测试套件（100 个测试）
```

## 测试

项目包含完整的 bash 集成测试套件：

```bash
# 运行所有测试（需要 app 正在运行）
bash Scripts/test.sh

# 运行指定模块
bash Scripts/test.sh M1 M15 M17
```

测试模块覆盖：消息编码、会话生命周期、Agent 身份隔离、权限/问题/计划流程、多会话支持、完成音效去重、可配置保留时长等。

## 设置选项

所有设置可在 Tower Island 设置面板中调整：

| 设置项 | 默认值 | 说明 |
|--------|-------|------|
| 自动收起延迟 | 3 秒 | 交互完成后面板保持展开的时间 |
| 完成会话显示 | 2 分钟 | 已完成的会话保留多久（10秒–5分钟或永不消失） |
| 智能抑制 | 开启 | Agent 终端聚焦时不自动展开 |
| 音效 | 按事件 | 可单独开关每种事件的音效 |

## 工作原理

1. **零配置启动**：启动时自动扫描已安装的 Agent，在其配置文件中注入轻量 hook
2. **Hook → Bridge → Socket**：Agent 事件触发（工具调用、权限请求、任务完成）时，hook 调用 `di-bridge`，通过 Unix Socket 发送结构化消息
3. **实时 UI**：主应用通过 `SocketServer` 接收消息，更新 `SessionManager`，SwiftUI 视图即时响应
4. **交互响应**：权限和问题场景下，bridge 进程保持存活等待用户响应，然后将结果写回 stdout 供 Agent 消费

## 许可证

MIT
