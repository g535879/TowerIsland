# Agent Hook Dataset-Driven Regression Design

## Goal

Build a deterministic, dataset-driven regression system for Tower Island where product behavior is validated by replaying AI agent hook events.

This phase focuses on:

1. Maintaining a complete mock hook dataset for currently supported agents.
2. Running product automation entirely from that dataset, covering UI appearance, interaction, click flows, and functional outcomes.

## Confirmed Scope

### In Scope

- Agents: `claude_code`, `codex`, `cursor`, `opencode`
- Dataset format: `JSONL`
- Event model: standardized fields plus preserved raw payload
- Execution mode: full replay of all agent hook datasets
- Assertions: UI identifiers, interaction behavior, and diagnostics state

### Out of Scope (for this phase)

- Selective replay by capability group
- Cloud CI integration
- Visual snapshot diff tooling
- Auto-generated dataset capture from production traffic

## Design Principles

1. **Dataset first**: tests are generated and driven from hook data, not hardcoded test scripts.
2. **Compatibility preserving**: raw input is always retained to support parser evolution.
3. **Deterministic replay**: replay order and assertions are stable across runs.
4. **Agent scalability**: adding a new agent should be data-only whenever possible.
5. **Actionable failures**: every failure should identify exact agent, hook, scenario, and assertion type.

## Data Model

Each JSONL line is one replay event:

```json
{
  "id": "claude-permission-001",
  "agent": "claude_code",
  "hook": "permission",
  "timestamp": "2026-04-16T12:00:00Z",
  "scenario": "permission_basic_allow",
  "phase": "happy_path",
  "meta": {
    "version": "v1",
    "source": "mock",
    "tags": ["permission", "ui", "smoke"]
  },
  "payload": {
    "tool": "Write",
    "description": "Edit a Swift file",
    "filePath": "Sources/DynamicIsland/AppDelegate.swift"
  },
  "raw_payload": {
    "tool_name": "Write",
    "tool_input": {
      "filePath": "Sources/DynamicIsland/AppDelegate.swift"
    },
    "description": "Edit a Swift file"
  },
  "expects": {
    "ui": [
      "island.permission.panel",
      "island.permission.allow-once",
      "island.permission.deny"
    ],
    "state": {
      "pendingInteractionType": "permission"
    },
    "actions": [
      "click:island.permission.allow-once"
    ],
    "post_state": {
      "pendingInteractionType": null
    }
  }
}
```

## Dataset Layout

```text
Tests/HookDataset/
  README.md
  schema/
    hook-event.schema.json
  agents/
    claude_code/
      session.jsonl
      permission.jsonl
      question.jsonl
      plan.jsonl
    codex/
      ...
    cursor/
      ...
    opencode/
      ...
```

Optional scenario rollups can be added later if replay performance optimization is needed.

## Replay Architecture

### 1. Dataset Loader

- Reads all `Tests/HookDataset/agents/**/*.jsonl`
- Validates records against schema
- Produces ordered replay stream

### 2. Hook Adapter Layer

- Converts standardized `payload` into the bridge input shape expected by the current hook pipeline
- Keeps `raw_payload` available for debug and compatibility checks

### 3. Replay Executor

- Sends events through existing app integration path (bridge + socket)
- Applies deterministic pacing for events that require sequencing

### 4. Assertion Engine

For each event, executes:

- **UI assertions** via accessibility IDs
- **State assertions** via `~/.tower-island/test-diagnostics.json`
- **Interaction assertions** for action-driven transitions (approve, reject, option click)

### 5. Failure Reporter

Must include:

- `agent`, `hook`, `scenario`, `id`
- failed assertion type (`ui`/`state`/`action`)
- expected vs actual detail

## Test Coverage Contract (V1)

Per agent (`claude_code`, `codex`, `cursor`, `opencode`):

1. Session lifecycle path
2. Permission interaction path
3. Question interaction path
4. Plan review path
5. At least one edge case per interaction type

Minimum requirement:

- happy path + edge case for each supported hook type in this phase

## Execution Strategy

### Full Replay (required for this phase)

Run all agent datasets in one pass.

### Script Entry Points

- `Scripts/test-dataset-replay.sh` (new): full dataset replay + assertions
- `Scripts/test-all.sh` (update): include dataset replay in full gate
- `.githooks/pre-push` (update): full gate includes dataset replay

`pre-commit` remains fast and can keep partial checks; full replay is mandatory at least pre-push.

## Add-New-Agent Workflow

When a new agent is introduced:

1. Add `Tests/HookDataset/agents/<new_agent>/...jsonl`
2. Ensure records conform to schema and standard field contract
3. Run full replay
4. No core replay engine changes unless truly new hook semantics are introduced

This keeps scale cost in dataset authoring rather than framework rewrites.

## Verification and Done Criteria

The phase is complete when:

1. All four initial agents have hook datasets and schema-valid records.
2. Full dataset replay passes locally in a clean environment.
3. Failures show precise event-level diagnostics.
4. A simulated new agent can be added with data-only changes and replayed successfully.

## Risks and Mitigations

1. **Hook shape drift across agent versions**
   - Mitigation: dual payload design (`payload` + `raw_payload`) and schema versioning.

2. **Flaky replay due to runtime socket/process state**
   - Mitigation: enforce socket liveness checks and app bootstrap guards in test scripts.

3. **Dataset growth slows runtime**
   - Mitigation: keep full replay now; add capability-group replay as phase-2 optimization.

4. **Assertion brittleness due to UI structural changes**
   - Mitigation: standardize semantic accessibility IDs and avoid hierarchy-dependent selectors.

## Next Step

After approval of this design document, create an implementation plan that breaks work into:

1. Dataset schema + storage scaffolding
2. Replay loader and executor
3. UI/state/action assertion engine
4. Script + hook wiring
5. Initial four-agent dataset authoring
