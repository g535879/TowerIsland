[中文](README_zh.md) | English

# Tower Island

A macOS menu bar app that gives you a **Dynamic Island-style control tower** for all your AI coding agents. Monitor Claude Code, Cursor, Codex, OpenCode, Gemini CLI and more — all from a single floating panel at the top of your screen.

## What It Does

Tower Island sits at the top of your screen as a compact pill. When your AI agents are working, it shows their status at a glance. Hover to expand and see all active sessions with full details.

**Core features:**

- **Unified dashboard** — See all AI coding agents in one place, regardless of which terminal or IDE they run in
- **Real-time status** — Live status dots (blue = working, green = done, orange = needs input, red = error)
- **Permission approval** — Approve or deny file/command permissions directly from the island, no need to switch windows
- **Question answering** — Answer agent questions from the island UI
- **Plan review** — Review and approve agent plans inline
- **Smart notifications** — 8-bit sound effects for session events (configurable per event)
- **Multi-session support** — Multiple conversations per agent, each tracked independently
- **Window jumping** — Click a session to jump to the exact terminal tab or IDE window (iTerm2 tab-level precision)
- **Horizontal dragging** — Drag the island left/right along the top edge
- **Session titles** — Shows first user prompt as title, workspace folder as subtitle

**Supported agents:**

| Agent | Hook System | Status |
|-------|------------|--------|
| Claude Code | Native hooks (settings.json) | Full support |
| Cursor | Hooks API (hooks.json) | Full support |
| Codex (OpenAI) | Native hooks | Full support |
| OpenCode | JS plugin | Full support |
| Gemini CLI | Config hook | Basic support |
| Copilot (VS Code) | Config hook | Basic support |

## Quick Start

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Swift 5.9+
- At least one supported AI coding agent installed

### Build & Run

```bash
git clone https://github.com/g535879/TowerIsland.git
cd TowerIsland
bash Scripts/build.sh
open ".build/Tower Island.app"
```

### Agent Configuration

Tower Island **auto-configures** hooks for all detected agents on first launch. No manual setup needed.

To verify or manually trigger configuration:
- Open Tower Island Settings (gear icon or menu bar)
- Go to the **Agents** tab
- Toggle agents on/off as needed

Under the hood, it installs a lightweight bridge binary (`di-bridge`) at `~/.tower-island/bin/` and registers hooks in each agent's config file.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Tower Island App                │
│                                                  │
│   NotchWindow (NSPanel)                          │
│   ├── CollapsedPillView (status dots)            │
│   └── Expanded View                              │
│       ├── SessionListView (session cards)        │
│       ├── PermissionApprovalView                 │
│       ├── QuestionAnswerView                     │
│       └── PlanReviewView                         │
│                                                  │
│   SessionManager ← Unix Socket ← di-bridge      │
│   AudioEngine (8-bit sound synthesis)            │
│   ZeroConfigManager (auto-configures agents)     │
└─────────────────────────────────────────────────┘

Agent hooks fire → di-bridge encodes message → socket → SessionManager
```

**Key components:**

- **`TowerIsland`** — Main app. SwiftUI views hosted in an `NSPanel` for the floating island UI
- **`DIBridge`** — Lightweight CLI binary invoked by agent hooks. Reads stdin JSON, encodes it as a `DIMessage`, sends via Unix socket
- **`DIShared`** — Shared protocol definitions (`DIMessage`, socket config)

## Project Structure

```
Sources/
├── DIShared/          # Shared protocol & socket config
│   └── Protocol.swift
├── DIBridge/          # Bridge CLI binary
│   └── DIBridge.swift
└── DynamicIsland/     # Main app
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
├── build.sh           # Release build + .app bundle
└── test.sh            # Integration test suite (100 tests)
```

## Testing

The project includes a comprehensive bash integration test suite:

```bash
# Run all tests (requires app to be running)
bash Scripts/test.sh

# Run specific modules
bash Scripts/test.sh M1 M15 M17
```

Test modules cover: message encoding, session lifecycle, agent identity, permission/question/plan flows, multi-session support, completion sound dedup, configurable linger, and more.

## Configuration

All settings are accessible from the Tower Island Settings panel:

| Setting | Default | Description |
|---------|---------|-------------|
| Auto-collapse delay | 3s | How long the panel stays open after interaction |
| Completed session display | 2 min | How long completed sessions remain visible (10s–5min or Never) |
| Smart suppression | On | Don't auto-expand when agent terminal is focused |
| Sound effects | Per-event | Toggle individual sound events on/off |

## How It Works

1. **Zero-config setup**: On launch, Tower Island scans for installed agents and injects lightweight hooks into their config files
2. **Hook → Bridge → Socket**: When an agent event fires (tool use, permission request, completion), the hook invokes `di-bridge` which sends a structured message over a Unix socket
3. **Real-time UI**: The main app receives messages via `SocketServer`, updates `SessionManager`, and the SwiftUI views react immediately
4. **Interactive responses**: For permissions and questions, the bridge process stays alive waiting for the user's response, then writes it back to stdout for the agent to consume

## License

MIT
