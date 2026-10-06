# space-roster

OpenCode skill that inventories the local [Herdr](https://github.com/) workspace:
pane + tab + workspace + agent kind + model + status for every coding agent
running in the current space.

The skill description triggers when you ask which models, agents, or panes
are present, who is working on what, or what the current Herdr roster looks
like. Agents inside Herdr should also load it at session start so the roster
is in context before any work begins.

## Install

No official installer - skill files are picked up by file placement.

```bash
git clone https://github.com/overlag/space-roster ~/.config/opencode/skills/space-roster
```

Or, if you keep skills as a worktree:

```bash
git clone https://github.com/overlag/space-roster ~/code/space-roster
ln -s ~/code/space-roster ~/.config/opencode/skills/space-roster
```

OpenCode reads `~/.config/opencode/skills/<name>/SKILL.md` at session start
and exposes the description in `<available_skills>`. See
<https://opencode.ai/docs/skills/> for the full discovery rules.

## Requirements

- `herdr` CLI in `PATH`
- `jq`
- `HERDR_ENV=1` (set automatically inside a Herdr pane)
- Bash 4+

## Usage

Inside any Herdr pane, ask:

```
what models are in this space?
who is idle?
list the agents
```

The agent will load `space-roster` and run:

```bash
~/.config/opencode/skills/space-roster/scripts/inventory.sh
```

Direct CLI usage:

```bash
scripts/inventory.sh           # human-readable table
scripts/inventory.sh --json    # raw JSON
scripts/inventory.sh --refresh # bypass the 60s cache
```

## Output

Human-readable:

```
PANE    TAB      KIND      MODEL                    STATUS
w5:p1   w5:t1    opencode  MiniMax-M3               working
w5:p2   w5:t2    opencode  MiniMax-M3               working
w5:p3   w5:t3    opencode  GPT-6 Luna GitHub Copilot  idle

workspace: w5  generated: 2026-10-06T12:34:56Z
```

JSON cache at `/tmp/space-roster-<workspace>.json`:

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

## How it works

1. `herdr agent list` returns the live pane inventory.
2. For every pane, `herdr pane read <pane> --source recent-unwrapped --lines 200`
   pulls the recent unwrapped output.
3. Model extraction prefers the bottom-most `▣  OpenAgent · <MODEL>` marker
   - the live input box at the bottom of the TUI. Anything higher up in
   the buffer is conversation scrollback that may quote the marker.
4. If no compact marker is found, the shortest `OpenAgent · ...` match
   wins (the wide status footer is hundreds of chars and would otherwise
   swallow the model in plan/branch text).
5. Stops at the next `·` to drop duration suffixes like `· 1m 23s`.
6. Rejects matches containing `<` or backticks to keep script-comment
   placeholders from leaking into the result.
7. Caches the roster per workspace at `/tmp/space-roster-<workspace>.json`
   for 60 seconds; pass `--refresh` to force a re-read.

## Limits

- Model extraction depends on the `OpenAgent · <MODEL>` marker in the OpenCode
  TUI. New agent kinds without that marker will report `model: unknown` until
  the script learns the new pattern.
- Herdr must be the agent that owns the pane; do not target focused panes
  belonging to another client.

## Publishing checklist (when you are ready)

```bash
cd ~/Dev/Perso/space-roster
git init
git add .
git commit -m "feat: initial space-roster skill"
gh repo create overlag/space-roster --public --source=. --remote=origin --push
```

## License

MIT. See `LICENSE`.