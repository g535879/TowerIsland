# Demo screenshots & screen recording (README assets)

Use this when updating `Assets/demo.gif` and `Assets/screenshots/*.png` after UI changes (e.g. notch-style black island).

## Prerequisites

1. **Build & bridge**

   ```bash
   bash Scripts/build.sh
   ```

2. **Run the app** so the Unix socket exists: `~/.tower-island/di.sock`

3. **Hardware**

   - **Notch MacBook**: island is top-center → collapsed UI shows **left icon (last messaged session) + active count** when the bar sits in the camera housing region.
   - **External display** (or island dragged sideways): collapsed UI shows **all session icons centered** — good to show that layout variant if you add a second screenshot row later.

## Test data (deterministic sessions)

From the repo root:

```bash
bash Scripts/demo-media.sh seed
```

This creates three active sessions:

| Session ID           | Agent        | Prompt (first line)                    |
|----------------------|--------------|----------------------------------------|
| `readme-demo-claude` | Claude Code  | Refactor authentication and session…   |
| `readme-demo-cursor` | Cursor       | Fix TypeScript errors in the API…      |
| `readme-demo-codex`  | Codex        | Add unit tests for the markdown parser |

Order in the **expanded list** matches `SessionManager` insertion order (same three as above). **Collapsed / unobstructed** row uses the same **order and count** as the expanded list.

## Capturing static screenshots

README shows **two rows**: notch MacBook + non-notch (external display). Recommended target widths: ~220px in README table (crop to panel + small wallpaper margin at 2× Retina).

### Notch MacBook (`notch-*.png`)

| Asset | Steps |
|-------|--------|
| `Assets/screenshots/notch-collapsed.png` | Run `seed`, collapse island (move mouse away). Capture the top bar only, cropping to just the menu-bar height. Island shows **left icon + active count** straddling the camera housing. |
| `Assets/screenshots/notch-expanded.png` | Click island to expand, capture the session-list panel. |
| `Assets/screenshots/notch-question.png` | Run `seed`, then `bash Scripts/demo-media.sh question`. **While the question is visible**, capture. Then kill the bridge process. |

### External / Non-notch display (`external-*.png`)

Run `bash Scripts/demo-media.sh seed` on the non-notch screen, then capture:

| Asset | Steps |
|-------|--------|
| `Assets/screenshots/external-collapsed.png` | Collapsed island — shows **all session icons centered** (no notch obstructs). |
| `Assets/screenshots/external-expanded.png` | Expanded session list. |
| `Assets/screenshots/external-question.png` | Question UI (same `question` subcommand). |

## Recording `Assets/demo.gif`

The checked-in GIF is a **real screen recording** (not a stitched static loop). Regenerate it with **`bash Scripts/record-demo-gif.sh`** after `seed`, or follow the manual steps below.

### Option A — `ffmpeg` one-shot (recommended)

1. Run `bash Scripts/demo-media.sh seed`.
2. With Tower Island in front, run from the repo root:

   ```bash
   bash Scripts/record-demo-gif.sh
   ```

   This captures the main display for ~20s (cursor visible) to `/tmp/ti_screen_record.mov`, then writes `Assets/demo.gif` (~560px wide, top-of-screen crop, palette-optimized).

3. If AVFoundation fails to open the screen device, list inputs and set `SCREEN_INPUT` (often `1:none` on a single-display Mac):

   ```bash
   ffmpeg -f avfoundation -list_devices true -i ""
   SCREEN_INPUT="1:none" bash Scripts/record-demo-gif.sh
   ```

4. To **re-encode only** (you already have a `.mov`):

   ```bash
   bash Scripts/record-demo-gif.sh --from-mov /path/to/recording.mov
   ```

   Tunables: `RECORD_SECONDS`, `CROP_HEIGHT` (source pixels from the top; larger = taller GIF after scale), `GIF_FPS`, `GIF_WIDTH`.

### Option B — QuickTime + `ffmpeg` encode

1. Run `bash Scripts/demo-media.sh seed`.
2. **QuickTime Player → File → New Screen Recording**, capture the menu-bar / island region or full screen.
3. Flow (~15–25s): collapsed → hover expand → slight scroll → collapse (move pointer away).
4. Export or save as `.mov`, then: `bash Scripts/record-demo-gif.sh --from-mov ~/Movies/your-recording.mov`.

## One-shot refresh (maintainers, local Mac)

Typical flow used when regenerating all four assets:

1. `bash Scripts/build.sh` then `open ".build/Tower Island.app"` and wait until `~/.tower-island/di.sock` exists.
2. `bash Scripts/demo-media.sh seed`
3. **Screenshots:** `screencapture -x /path/to/_full.png` → crop the top-center band for **collapsed**; activate Tower Island and `osascript` **click** near the top-center to expand → second full capture → crop for **expanded**.
4. **Question:** run the `AskUserQuestion` JSON through `di-bridge` in the background (or `demo-media.sh question` in another terminal), wait ~2s, `screencapture`, then answer in the island or end the bridge process; crop for **question.png**.
5. **GIF:** `bash Scripts/record-demo-gif.sh` (or `--from-mov` if you captured with QuickTime). Optionally automate clicks with AppleScript during capture so expand/collapse happens without hand-waving the cursor.

Requires **Screen Recording** / **Accessibility** permissions for Terminal or your IDE if `screencapture` / `osascript` prompts appear. Delete large intermediate `_full*.png` files before committing.

## Reset demo sessions

```bash
bash Scripts/demo-media.sh cleanup
```

This sends `session_end` for the three `readme-demo-*` IDs (best-effort).

## Files to update in README

After capture, replace/add:

- `Assets/demo.gif` — re-encode from the notch screen recording
- `Assets/screenshots/notch-collapsed.png`
- `Assets/screenshots/notch-expanded.png`
- `Assets/screenshots/notch-question.png`
- `Assets/screenshots/external-collapsed.png`
- `Assets/screenshots/external-expanded.png`
- `Assets/screenshots/external-question.png`

Optionally sync copy in `README_zh.md` if the Chinese README references the same assets.
