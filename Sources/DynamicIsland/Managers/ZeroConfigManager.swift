import Foundation
import DIShared

enum HookInstallStatus {
    case active
    case inactive
}

enum ZeroConfigManager {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path
    private static let autoConfigKeyPrefix = "autoConfigure."

    static func configureAllAgents() {
        for agent in AgentType.allCases where isAutoConfigEnabled(for: agent) {
            configure(agent)
        }
        print("[ZeroConfig] Agent hooks configured")
    }

    static func configure(_ agent: AgentType) {
        switch agent {
        case .claudeCode: configureClaudeCode()
        case .codex: configureCodex()
        case .geminiCli: configureGeminiCli()
        case .cursor: configureCursor()
        case .openCode: configureOpenCode()
        case .droid: configureDroid()
        case .qoder: configureQoder()
        case .copilot: configureCopilot()
        case .codeBuddy: configureCodeBuddy()
        }
    }

    static func isAutoConfigEnabled(for agent: AgentType) -> Bool {
        let defaults = UserDefaults.standard
        let key = autoConfigKey(for: agent)
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }

    static func setAutoConfigEnabled(_ enabled: Bool, for agent: AgentType) {
        UserDefaults.standard.set(enabled, forKey: autoConfigKey(for: agent))
        if enabled {
            configure(agent)
        } else {
            removeConfiguration(for: agent)
        }
    }

    static func hookStatus(for agent: AgentType) -> HookInstallStatus {
        hasConfiguration(for: agent) ? .active : .inactive
    }

    static func repairHooksIfNeeded() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Check Claude Code hooks
        let claudeSettings = "\(home)/.claude/settings.json"
        if isAutoConfigEnabled(for: .claudeCode), FileManager.default.fileExists(atPath: claudeSettings) {
            if let settings = readJSON(claudeSettings),
               let hooks = settings["hooks"] as? [String: Any] {
                let hasDIBridge = hooks.values.contains { hookList in
                    guard let list = hookList as? [[String: Any]] else { return false }
                    return list.contains { entry in
                        let cmds = entry["hooks"] as? [[String: Any]] ?? []
                        return cmds.contains { ($0["command"] as? String)?.contains("di-bridge") == true }
                    }
                }
                if !hasDIBridge {
                    configureClaudeCode()
                    print("[ZeroConfig] Repaired Claude Code hooks")
                }
            }
        }

        // Check Cursor hooks
        let cursorHooks = "\(home)/.cursor/hooks.json"
        if isAutoConfigEnabled(for: .cursor), FileManager.default.fileExists(atPath: cursorHooks) {
            if let config = readJSON(cursorHooks),
               let hooks = config["hooks"] as? [String: Any] {
                let hasDIBridge = hooks.values.contains { entries in
                    guard let list = entries as? [[String: Any]] else { return false }
                    return list.contains { ($0["command"] as? String)?.contains("di-bridge") == true }
                }
                if !hasDIBridge {
                    configureCursor()
                    print("[ZeroConfig] Repaired Cursor hooks")
                }
            }
        }
    }

    private static var bridgePath: String {
        let stable = "\(home)/.tower-island/bin/di-bridge"
        let bundled = Bundle.main.bundlePath + "/Contents/MacOS/di-bridge"
        let fm = FileManager.default

        guard fm.fileExists(atPath: bundled) else {
            return stable
        }

        ensureDir("\(home)/.tower-island/bin")

        let stableIsOutdated: Bool
        if fm.fileExists(atPath: stable),
           let stableAttr = try? fm.attributesOfItem(atPath: stable),
           let bundledAttr = try? fm.attributesOfItem(atPath: bundled),
           let stableMod = stableAttr[.modificationDate] as? Date,
           let bundledMod = bundledAttr[.modificationDate] as? Date {
            stableIsOutdated = bundledMod > stableMod
        } else {
            stableIsOutdated = true
        }

        if stableIsOutdated {
            try? fm.removeItem(atPath: stable)
            try? fm.copyItem(atPath: bundled, toPath: stable)
        }

        if fm.fileExists(atPath: stable),
           let stableAttr = try? fm.attributesOfItem(atPath: stable),
           let bundledAttr = try? fm.attributesOfItem(atPath: bundled),
           let stableMod = stableAttr[.modificationDate] as? Date,
           let bundledMod = bundledAttr[.modificationDate] as? Date,
           bundledMod > stableMod {
            return bundled
        }

        return stable
    }

    // MARK: - Claude Code

    private static func configureClaudeCode() {
        let configDir = "\(home)/.claude"
        let settingsPath = "\(configDir)/settings.json"
        ensureDir(configDir)

        var settings = readJSON(settingsPath) ?? [String: Any]()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let hookMapping: [(String, String, Int)] = [
            ("PreToolUse", "PreToolUse", 5),
            ("PostToolUse", "PostToolUse", 5),
            ("PreCompact", "compact", 5),
            ("Notification", "Notification", 5),
            ("PermissionRequest", "PermissionRequest", 300),
            ("Stop", "Stop", 5),
            ("SessionStart", "session_start", 5),
            ("SessionEnd", "session_end", 5),
            ("SubagentStart", "subagent_start", 5),
            ("SubagentStop", "subagent_end", 5),
            ("UserPromptSubmit", "session_start", 5),
        ]

        for (hookType, hookArg, timeout) in hookMapping {
            var hookList = hooks[hookType] as? [[String: Any]] ?? []

            // Remove stale entries (wrong guard pattern or missing guard)
            hookList.removeAll { entry in
                let cmds = entry["hooks"] as? [[String: Any]] ?? []
                return cmds.contains {
                    guard let cmd = $0["command"] as? String else { return false }
                    return cmd.contains("di-bridge") && (
                        !cmd.contains("VSCODE_PID")
                        || (hookArg == "PermissionRequest" && cmd.contains("|| true"))
                    )
                }
            }

            let alreadyConfigured = hookList.contains { entry in
                let cmds = entry["hooks"] as? [[String: Any]] ?? []
                return cmds.contains { ($0["command"] as? String)?.contains("di-bridge") == true }
            }
            if !alreadyConfigured {
                // PermissionRequest must preserve di-bridge exit code so deny works;
                // other hooks are fire-and-forget so || true is safe.
                let guardedCmd: String
                if hookArg == "PermissionRequest" {
                    guardedCmd = "[ -n \"$VSCODE_PID\" ] || \(bridgePath) --agent claude_code --hook \(hookArg)"
                } else {
                    guardedCmd = "[ -z \"$VSCODE_PID\" ] && \(bridgePath) --agent claude_code --hook \(hookArg) || true"
                }
                hookList.append([
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": guardedCmd,
                            "timeout": timeout
                        ] as [String: Any]
                    ]
                ] as [String: Any])
                hooks[hookType] = hookList
            }
        }

        settings["hooks"] = hooks
        writeJSON(settingsPath, settings)
    }

    // MARK: - Codex

    private static func configureCodex() {
        let configDir = "\(home)/.codex"
        ensureDir(configDir)

        let hooksPath = "\(configDir)/hooks.json"
        var config = readJSON(hooksPath) ?? [String: Any]()
        var hooks = config["hooks"] as? [String: Any] ?? [:]

        // Remove stale di-bridge entries with wrong event names
        for staleKey in ["ToolUse", "PatchApply"] {
            if var hookList = hooks[staleKey] as? [[String: Any]] {
                hookList.removeAll { entry in
                    let cmds = entry["hooks"] as? [[String: Any]] ?? []
                    return cmds.contains { ($0["command"] as? String)?.contains("di-bridge") == true }
                }
                if hookList.isEmpty {
                    hooks.removeValue(forKey: staleKey)
                } else {
                    hooks[staleKey] = hookList
                }
            }
        }

        // Codex fires Stop after every agent response (not just session end),
        // so we map it to notification instead of session_end to capture assistant replies.
        let hookMapping: [(String, String, Int)] = [
            ("SessionStart", "session_start", 5),
            ("PreToolUse", "PreToolUse", 5),
            ("PostToolUse", "PostToolUse", 5),
            ("UserPromptSubmit", "session_start", 5),
            ("PermissionRequest", "PermissionRequest", 300),
            ("Stop", "notification", 5),
        ]

        for (hookType, hookArg, timeout) in hookMapping {
            var hookList = hooks[hookType] as? [[String: Any]] ?? []
            let alreadyConfigured = hookList.contains { entry in
                let cmds = entry["hooks"] as? [[String: Any]] ?? []
                return cmds.contains { ($0["command"] as? String)?.contains("di-bridge") == true }
            }
            if !alreadyConfigured {
                hookList.append([
                    "matcher": "*",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "\(bridgePath) --agent codex --hook \(hookArg)",
                            "timeout": timeout
                        ] as [String: Any]
                    ]
                ] as [String: Any])
                hooks[hookType] = hookList
            }
        }

        config["hooks"] = hooks
        writeJSON(hooksPath, config)
    }

    // MARK: - Gemini CLI

    private static func configureGeminiCli() {
        let configDir = "\(home)/.gemini"
        let settingsPath = "\(configDir)/settings.json"
        ensureDir(configDir)

        var settings = readJSON(settingsPath) ?? [String: Any]()
        if (settings["tower_island_hook"] as? String)?.contains("di-bridge") != true {
            settings["tower_island_hook"] = "\(bridgePath) --agent gemini_cli"
            writeJSON(settingsPath, settings)
        }
    }

    // MARK: - Cursor

    private static func configureCursor() {
        let configDir = "\(home)/.cursor"
        let hooksPath = "\(configDir)/hooks.json"
        ensureDir(configDir)

        var config = readJSON(hooksPath) ?? [String: Any]()
        var hooks = config["hooks"] as? [String: Any] ?? [:]

        let hookMapping: [(String, String)] = [
            ("beforeSubmitPrompt", "--hook session_start"),
            ("afterAgentResponse", "--hook notification"),
            ("afterAgentThought", "--hook notification"),
            ("beforeReadFile", "--hook PreToolUse --tool Read"),
            ("afterFileEdit", "--hook PostToolUse --tool FileEdit"),
            ("beforeShellExecution", "--hook PreToolUse --tool Shell"),
            ("afterShellExecution", "--hook PostToolUse --tool Shell"),
            ("beforeMCPExecution", "--hook PreToolUse --tool MCP"),
            ("afterMCPExecution", "--hook PostToolUse --tool MCP"),
            ("stop", "--hook session_end"),
        ]

        for (event, hookArgs) in hookMapping {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { ($0["command"] as? String)?.contains("di-bridge") == true }
            entries.append(["command": "\(bridgePath) --agent cursor \(hookArgs)"])
            hooks[event] = entries
        }

        if let oldEntries = hooks["preToolUse"] as? [[String: Any]] {
            let cleaned = oldEntries.filter {
                !( ($0["command"] as? String)?.contains("di-bridge") == true
                   && $0["matcher"] != nil )
            }
            if cleaned.count != oldEntries.count {
                hooks["preToolUse"] = cleaned
            }
        }

        config["hooks"] = hooks
        if config["version"] == nil { config["version"] = 1 }
        writeJSON(hooksPath, config)
    }

    // MARK: - OpenCode
    // OpenCode uses a JS plugin system. The plugin uses di-bridge for fire-and-forget events,
    // and async spawn + internalFetch for bidirectional permission/question interaction
    // (reference: vibe-island plugin architecture).
    private static func configureOpenCode() {
        let pluginDir = "\(home)/.config/opencode/plugins"
        let pluginPath = "\(pluginDir)/tower-island.js"
        ensureDir(pluginDir)

        let pluginSource = #"""
        const { spawn, execSync } = require("child_process");
        const os = require("os");
        const BRIDGE = os.homedir() + "/.tower-island/bin/di-bridge";
        function sendViaBridge(hookType, sessionId, data) {
          try {
            const stdin = JSON.stringify({ ...data, session_id: sessionId });
            execSync(`${BRIDGE} --agent opencode --hook ${hookType} --session ${sessionId}`, {
              input: stdin, timeout: 5000, stdio: ["pipe", "pipe", "pipe"],
            });
          } catch {}
        }
        function sendInteractive(hookType, sessionId, data) {
          return new Promise((resolve) => {
            try {
              const child = spawn(BRIDGE, ["--agent","opencode","--hook",hookType,"--session",sessionId],
                { stdio: ["pipe","pipe","pipe"] });
              child.stdin.write(JSON.stringify(data)); child.stdin.end();
              let stdout = "";
              child.stdout.on("data", (d) => { stdout += d.toString(); });
              child.on("close", (code) => resolve({ exitCode: code, output: stdout.trim() }));
              child.on("error", () => resolve(null));
              setTimeout(() => { child.kill(); resolve(null); }, 300000);
            } catch { resolve(null); }
          });
        }
        export default async ({ client, serverUrl }) => {
          const serverPort = serverUrl ? parseInt(serverUrl.port) || 4096 : 4096;
          const internalFetch = client?._client?.getConfig?.()?.fetch || null;
          const msgRoles = new Map(), sessions = new Map(), sessionCwd = new Map();
          function getSession(sid) {
            if (!sessions.has(sid)) sessions.set(sid, { lastUserText: "", lastAssistantText: "" });
            return sessions.get(sid);
          }
          function handleEvent(ev) {
            const t = ev.type, p = ev.properties || {};
            if (t === "session.created" && p.info) {
              sessionCwd.set(p.info.id, p.info.directory || "");
              sendViaBridge("session_start", `opencode-${p.info.id}`, { cwd: p.info.directory || "", terminal: process.env.TERM_PROGRAM || "Terminal" });
              return;
            }
            if (t === "session.deleted" && p.info) { sessions.delete(p.info.id); sessionCwd.delete(p.info.id); sendViaBridge("session_end", `opencode-${p.info.id}`, {}); return; }
            if (t === "session.updated" && p.info) {
              if (p.info.directory) sessionCwd.set(p.info.id, p.info.directory);
              if (p.info.time?.archived) { sessions.delete(p.info.id); sessionCwd.delete(p.info.id); sendViaBridge("session_end", `opencode-${p.info.id}`, {}); }
              return;
            }
            if (t === "permission.asked" && p.id && p.sessionID) {
              const rid = p.id, sid = `opencode-${p.sessionID}`;
              const tn = (p.permission||"unknown").charAt(0).toUpperCase()+(p.permission||"unknown").slice(1);
              const pts = p.patterns||[];
              let desc = tn;
              if (p.permission==="bash"&&pts.length) desc = "Run: "+pts.join(" && ");
              else if ((p.permission==="edit"||p.permission==="write")&&pts.length) desc = tn+": "+pts[0];
              else if (pts.length) desc = tn+": "+pts.join(", ");
              if (internalFetch) {
                sendInteractive("PermissionRequest", sid, { tool_name:tn, description:desc, file_path:pts[0]||"" })
                  .then(async (r)=>{ if(!r)return; try{ await internalFetch(new Request(`http://localhost:${serverPort}/permission/${rid}/reply`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({reply:r.exitCode===0?"once":"reject"})}));}catch{} });
              } else { sendViaBridge("PermissionRequest", sid, { tool_name:tn, description:desc, file_path:pts[0]||"" }); }
              return;
            }
            if (t === "permission.replied" && p.sessionID) { sendViaBridge("PostToolUse",`opencode-${p.sessionID}`,{tool_name:"Permission"}); return; }
            if (t === "question.asked" && p.id && p.sessionID) {
              const rid = p.id, sid = `opencode-${p.sessionID}`;
              const qs = p.questions||[];
              const qt = qs.map(q=>q.question||q.header||"").filter(Boolean).join("\n");
              const opts = qs.flatMap(q=>(q.options||[]).map(o=>o.label||o.description||"")).filter(Boolean);
              if (internalFetch) {
                sendInteractive("question", sid, { question:qt, options:opts })
                  .then(async (r)=>{ if(!r||!r.output)return; try{ await internalFetch(new Request(`http://localhost:${serverPort}/question/${rid}/reply`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({answers:qs.map(()=>[r.output])})}));}catch{} });
              } else { sendViaBridge("question", sid, { question:qt, options:opts }); }
              return;
            }
            if ((t==="question.replied"||t==="question.rejected") && p.sessionID) { sendViaBridge("notification",`opencode-${p.sessionID}`,{status:t==="question.replied"?"Question answered":"Question dismissed"}); return; }
            if (t === "message.updated" && p.info?.id && p.info?.sessionID) { msgRoles.set(p.info.id, { role: p.info.role, sessionID: p.info.sessionID }); if (msgRoles.size > 200) msgRoles.delete(msgRoles.keys().next().value); return; }
            if (t === "message.part.updated" && p.part?.type === "text" && p.part?.messageID) {
              const meta = msgRoles.get(p.part.messageID); if (!meta) return;
              const s = getSession(meta.sessionID), text = p.part.text || "";
              if (meta.role === "user" && text) { s.lastUserText = text; sendViaBridge("session_start", `opencode-${meta.sessionID}`, { prompt: text, cwd: sessionCwd.get(meta.sessionID) || "", terminal: process.env.TERM_PROGRAM || "Terminal" }); }
              else if (meta.role === "assistant" && text) { s.lastAssistantText = text; sendViaBridge("notification", `opencode-${meta.sessionID}`, { status: text }); }
              return;
            }
            if (t === "message.part.updated" && p.part?.type === "tool" && p.part?.sessionID) {
              const st = p.part.state?.status, toolName = (p.part.tool || "unknown").charAt(0).toUpperCase() + (p.part.tool || "unknown").slice(1);
              if (st === "running" || st === "pending") sendViaBridge("PreToolUse", `opencode-${p.part.sessionID}`, { tool_name: toolName, tool_input: p.part.state?.input || {} });
              else if (st === "completed" || st === "error") sendViaBridge("PostToolUse", `opencode-${p.part.sessionID}`, { tool_name: toolName });
              return;
            }
            if (t === "session.status" && p.sessionID && p.status?.type === "idle") {
              const s = getSession(p.sessionID);
              sendViaBridge("notification", `opencode-${p.sessionID}`, { status: "idle", message: s.lastAssistantText || "idle" });
            }
          }
          return { "event": async ({ event }) => { try { handleEvent(event); } catch {} } };
        };
        """#

        try? pluginSource.write(toFile: pluginPath, atomically: true, encoding: String.Encoding.utf8)
    }

    // MARK: - Droid

    private static func configureDroid() {
        let configDir = "\(home)/.droid"
        let configPath = "\(configDir)/config.json"
        ensureDir(configDir)

        var config = readJSON(configPath) ?? [String: Any]()
        if (config["tower_island_hook"] as? String)?.contains("di-bridge") != true {
            config["tower_island_hook"] = "\(bridgePath) --agent droid"
            writeJSON(configPath, config)
        }
    }

    // MARK: - Qoder

    private static func configureQoder() {
        let configDir = "\(home)/.qoder"
        let configPath = "\(configDir)/config.json"
        ensureDir(configDir)

        var config = readJSON(configPath) ?? [String: Any]()
        if (config["tower_island_hook"] as? String)?.contains("di-bridge") != true {
            config["tower_island_hook"] = "\(bridgePath) --agent qoder"
            writeJSON(configPath, config)
        }
    }

    // MARK: - Copilot

    private static func configureCopilot() {
        let configDir = "\(home)/.copilot"
        let configPath = "\(configDir)/config.json"
        ensureDir(configDir)

        var config = readJSON(configPath) ?? [String: Any]()
        if (config["tower_island_hook"] as? String)?.contains("di-bridge") != true {
            config["tower_island_hook"] = "\(bridgePath) --agent copilot"
            writeJSON(configPath, config)
        }
    }

    // MARK: - CodeBuddy

    private static func configureCodeBuddy() {
        let configDir = "\(home)/.codebuddy"
        let configPath = "\(configDir)/config.json"
        ensureDir(configDir)

        var config = readJSON(configPath) ?? [String: Any]()
        if (config["tower_island_hook"] as? String)?.contains("di-bridge") != true {
            config["tower_island_hook"] = "\(bridgePath) --agent code_buddy"
            writeJSON(configPath, config)
        }
    }

    // MARK: - Helpers

    private static func ensureDir(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func writeJSON(_ path: String, _ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private static func autoConfigKey(for agent: AgentType) -> String {
        autoConfigKeyPrefix + agent.rawValue
    }

    private static func hasConfiguration(for agent: AgentType) -> Bool {
        switch agent {
        case .claudeCode:
            let path = "\(home)/.claude/settings.json"
            guard let settings = readJSON(path),
                  let hooks = settings["hooks"] as? [String: Any] else { return false }
            return hooksContainBridge(hooks)
        case .codex:
            let path = "\(home)/.codex/hooks.json"
            guard let config = readJSON(path),
                  let hooks = config["hooks"] as? [String: Any] else { return false }
            return hooksContainBridge(hooks)
        case .cursor:
            let path = "\(home)/.cursor/hooks.json"
            guard let config = readJSON(path),
                  let hooks = config["hooks"] as? [String: Any] else { return false }
            return hooksContainBridge(hooks)
        case .openCode:
            let path = "\(home)/.config/opencode/plugins/tower-island.js"
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
            return text.contains("di-bridge")
        case .geminiCli:
            let path = "\(home)/.gemini/settings.json"
            return configContainsBridge(path: path, key: "tower_island_hook")
        case .droid:
            let path = "\(home)/.droid/config.json"
            return configContainsBridge(path: path, key: "tower_island_hook")
        case .qoder:
            let path = "\(home)/.qoder/config.json"
            return configContainsBridge(path: path, key: "tower_island_hook")
        case .copilot:
            let path = "\(home)/.copilot/config.json"
            return configContainsBridge(path: path, key: "tower_island_hook")
        case .codeBuddy:
            let path = "\(home)/.codebuddy/config.json"
            return configContainsBridge(path: path, key: "tower_island_hook")
        }
    }

    private static func removeConfiguration(for agent: AgentType) {
        switch agent {
        case .claudeCode:
            removeBridgeHooks(at: "\(home)/.claude/settings.json")
        case .codex:
            removeBridgeHooks(at: "\(home)/.codex/hooks.json")
        case .cursor:
            removeCursorBridgeHooks(at: "\(home)/.cursor/hooks.json")
        case .openCode:
            try? FileManager.default.removeItem(atPath: "\(home)/.config/opencode/plugins/tower-island.js")
        case .geminiCli:
            removeBridgeConfigValue(at: "\(home)/.gemini/settings.json", key: "tower_island_hook")
        case .droid:
            removeBridgeConfigValue(at: "\(home)/.droid/config.json", key: "tower_island_hook")
        case .qoder:
            removeBridgeConfigValue(at: "\(home)/.qoder/config.json", key: "tower_island_hook")
        case .copilot:
            removeBridgeConfigValue(at: "\(home)/.copilot/config.json", key: "tower_island_hook")
        case .codeBuddy:
            removeBridgeConfigValue(at: "\(home)/.codebuddy/config.json", key: "tower_island_hook")
        }
    }

    private static func hooksContainBridge(_ hooks: [String: Any]) -> Bool {
        hooks.values.contains { hookList in
            guard let list = hookList as? [[String: Any]] else { return false }
            return list.contains { entry in
                let cmds = entry["hooks"] as? [[String: Any]] ?? []
                if cmds.contains(where: { ($0["command"] as? String)?.contains("di-bridge") == true }) {
                    return true
                }
                return (entry["command"] as? String)?.contains("di-bridge") == true
            }
        }
    }

    private static func configContainsBridge(path: String, key: String) -> Bool {
        guard let config = readJSON(path) else { return false }
        return (config[key] as? String)?.contains("di-bridge") == true
    }

    private static func removeBridgeHooks(at path: String) {
        guard var config = readJSON(path),
              var hooks = config["hooks"] as? [String: Any] else { return }
        for key in hooks.keys {
            guard var hookList = hooks[key] as? [[String: Any]] else { continue }
            hookList.removeAll { entry in
                let cmds = entry["hooks"] as? [[String: Any]] ?? []
                return cmds.contains { ($0["command"] as? String)?.contains("di-bridge") == true }
                    || (entry["command"] as? String)?.contains("di-bridge") == true
            }
            if hookList.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = hookList
            }
        }
        config["hooks"] = hooks
        writeJSON(path, config)
    }

    private static func removeCursorBridgeHooks(at path: String) {
        guard var config = readJSON(path),
              var hooks = config["hooks"] as? [String: Any] else { return }
        for key in hooks.keys {
            guard var entries = hooks[key] as? [[String: Any]] else { continue }
            entries.removeAll { ($0["command"] as? String)?.contains("di-bridge") == true }
            if entries.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = entries
            }
        }
        config["hooks"] = hooks
        writeJSON(path, config)
    }

    private static func removeBridgeConfigValue(at path: String, key: String) {
        guard var config = readJSON(path) else { return }
        if (config[key] as? String)?.contains("di-bridge") == true {
            config.removeValue(forKey: key)
            writeJSON(path, config)
        }
    }
}
