---
name: space-roaster-oc-herdr
description: "Inventory of coding agents and models currently occupying the local Herdr workspace (pane + tab + workspace + agent kind + model + status). Use when HERDR_ENV=1 and the user asks which models, agents, or panes are present in the current space, who is working on what, or wants a roster of the current Herdr session. Also use at session start to load the current roster into context."
license: MIT
compatibility: opencode
metadata:
  audience: developers
  workflow: herdr
  requires: herdr-cli
---

# Space Roster

Inventory the local Herdr workspace: enumerate panes, identify each agent's
model and status, and present the roster as a compact table.

## When to load

- User asks "what models are here", "who is in the space", "list agents", "what is working", "what's idle".
- User mentions a model name and you need to know which pane it lives in.
- Session just opened inside Herdr and the user has not yet asked anything.
  In that case the agent must call `scripts/inventory.sh` once at session
  start so the roster is in context before any work begins.

## How to use

Run the inventory script. It is the single entry point - do not reimplement
the parsing in the agent loop.

```bash
scripts/inventory.sh
```

The script:

- Bails out unless `HERDR_ENV=1`.
- Calls `herdr agent list` and parses pane IDs, tabs, workspaces, agent kind, status.
- For each pane, calls `herdr pane read <pane> --source recent-unwrapped --lines 200`
  to extract the live OpenCode TUI model marker.
- Caches the result in `/tmp/space-roaster-oc-herdr-<workspace>.json` with an mtime stamp.
- If the cache is younger than 60 seconds, returns the cached version.
- Prints the roster as `pane | tab | agent | model | status` rows.

Refresh the cache when the user reports changes (new pane, model switched,
agent closed): pass `--refresh`.

```bash
scripts/inventory.sh --refresh
```

## Model extraction strategy

The OpenCode TUI shows `OpenAgent · <MODEL>` in two places:

- The compact input box at the bottom of the screen (`▣  OpenAgent · MODEL`,
  no left border, may be followed by `· 1m 23s` duration).
- The wide status footer near the bottom (`┃  OpenAgent · MODEL ...`,
  followed by the plan name like `MiniMax Token Plan (minimax.io)` and
  the git branch).

The conversation scrollback may also quote these markers when the user
or another agent discusses the model format. The script handles that by:

1. Preferring the LAST `▣  OpenAgent · ` match - the live input box is
   the bottom-most match; anything higher up is conversation.
2. Stopping at the next `·` so `· 1m 23s` is dropped.
3. Rejecting anything with `<` or backticks to keep script-comment
   placeholders from leaking.
4. Falling back to the shortest match anywhere if no compact marker
   was found - the wide footer is hundreds of chars and would otherwise
   swallow the model in plan/branch text.

## Output format

The JSON cache shape is:

```json
{
  "workspace": "w5",
  "generated_at": "2026-10-06T12:34:56Z",
  "agents": [
    {
      "pane": "w5:p1",
      "tab": "w5:t1",
      "workspace": "w5",
      "agent_kind": "opencode",
      "model": "MiniMax-M3",
      "status": "working"
    }
  ]
}
```

## Limits

- Model parsing depends on the OpenCode TUI footer marker
  `OpenAgent · <MODEL>`. New agent kinds without that marker will show
  `model: unknown` until the script is extended.
- Read source `recent-unwrapped` may miss rows that left the alternate
  screen. For very stale state, re-run with `--refresh`.
- Herdr must be the agent that owns the pane; do not target focused panes
  belonging to another client.

## Files

- `SKILL.md` - this file
- `scripts/inventory.sh` - single entry point
- `README.md` - install and usage
- `LICENSE` - MIT