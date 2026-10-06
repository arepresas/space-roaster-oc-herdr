#!/usr/bin/env bash
# space-roaster-oc-herdr inventory: enumerate Herdr workspace panes + extract model per pane.
#
# Usage: scripts/inventory.sh [--refresh] [--json]
#
# Flags:
#   --refresh  bypass the cache and re-read every pane
#   --json     print JSON instead of the human-readable table
#
# Exit codes:
#   0  roster emitted
#   1  HERDR_ENV not set, or herdr CLI missing
#   2  herdr agent list failed
#
# Cache: /tmp/space-roaster-oc-herdr-<workspace>.json (mtime tracked).
# Cache TTL: 60s; pass --refresh to bypass.

set -euo pipefail

REFRESH=0
JSON_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --refresh) REFRESH=1 ;;
    --json)    JSON_ONLY=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      echo "unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

# --- guards -----------------------------------------------------------------

if [ "${HERDR_ENV:-}" != "1" ]; then
  echo "not in herdr (HERDR_ENV!=1); nothing to inventory" >&2
  exit 1
fi

if ! command -v herdr >/dev/null 2>&1; then
  echo "herdr CLI not found in PATH" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found in PATH (required for parsing)" >&2
  exit 1
fi

# --- list agents ------------------------------------------------------------

LIST_JSON="$(herdr agent list 2>/dev/null)" || {
  echo "herdr agent list failed" >&2
  exit 2
}

# `herdr agent list` returns agents from every workspace visible to the
# server, so the roster must be scoped to the current workspace.
# HERDR_WORKSPACE_ID is set automatically inside Herdr panes.
if [ -z "${HERDR_WORKSPACE_ID:-}" ]; then
  echo "HERDR_WORKSPACE_ID not set; cannot scope roster" >&2
  exit 1
fi

LIST_JSON="$(printf '%s' "$LIST_JSON" | jq --arg ws "$HERDR_WORKSPACE_ID" '
  {result: {agents: [.result.agents[] | select(.workspace_id == $ws)]}}')"

WORKSPACE="$HERDR_WORKSPACE_ID"

CACHE_FILE="/tmp/space-roaster-oc-herdr-${WORKSPACE}.json"
NOW_EPOCH="$(date +%s)"

# Use cache when fresh.
if [ "$REFRESH" -eq 0 ] && [ -f "$CACHE_FILE" ]; then
  CACHE_MTIME="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)"
  if [ $((NOW_EPOCH - CACHE_MTIME)) -lt 60 ]; then
    if [ "$JSON_ONLY" -eq 1 ]; then
      cat "$CACHE_FILE"
    else
      jq -r '
        ["PANE","TAB","KIND","MODEL","STATUS"],
        (.agents[] | [.pane, .tab, .agent_kind, .model, .status]) | @tsv
      ' "$CACHE_FILE" | column -t -s $'\t'
      echo
      echo "workspace: $WORKSPACE  cached: $(date -d "@$CACHE_MTIME" '+%H:%M:%S')"
    fi
    exit 0
  fi
fi

# --- build roster -----------------------------------------------------------

AGENTS_JSON="$(printf '%s' "$LIST_JSON" | jq -c '
  [.result.agents[] | {
    pane: .pane_id,
    tab: .tab_id,
    workspace: .workspace_id,
    agent_kind: .agent,
    status: .agent_status,
    focused: .focused
  }]
')"

# Extract model per pane. Read recent output and grep the OpenCode TUI marker.
build_entries() {
  printf '%s' "$AGENTS_JSON" | jq -c '.[]' | while IFS= read -r row; do
    pane="$(printf '%s' "$row" | jq -r '.pane')"
    kind="$(printf '%s' "$row" | jq -r '.agent_kind')"

    pane_text="$(herdr pane read "$pane" --source recent-unwrapped --lines 200 2>/dev/null || true)"

    # Primary marker: OpenCode TUI shows `OpenAgent · <MODEL>` in the input
    # area (compact line, prefixed with `▣  `, no left border) and again
    # in the wide status footer (`┃` prefix, hundreds of chars). The
    # input box sits at the very bottom of the buffer. Strategy:
    #  1. Take the LAST `▣  OpenAgent · ` match - the live input box is
    #     the bottom-most match; anything higher up is conversation
    #     scrollback where the user/agent quoted the script.
    #  2. Stop at the next `·` so trailing tokens like `· 1m 23s` drop.
    #  3. Reject anything with `<` or backticks (placeholder leakage).
    #  4. Fallback to the shortest match anywhere if the compact line
    #     was not found.
    model="$(printf '%s' "$pane_text" \
      | grep -oE '▣  OpenAgent · [^·<`]+' \
      | tail -n1 \
      | sed -e 's/^▣  OpenAgent · //' -e 's/[[:space:]]*$//' \
      || true)"

    if [ -z "$model" ]; then
      model="$(printf '%s' "$pane_text" \
        | grep -oE 'OpenAgent · [^·<`]+' \
        | grep -v '^[[:space:]]*$' \
        | awk '{ print length, $0 }' \
        | sort -n \
        | head -n1 \
        | cut -d' ' -f2- \
        | sed -e 's/^OpenAgent · //' -e 's/[[:space:]]*$//' \
        || true)"
    fi

    if [ -z "$model" ]; then
      model="unknown"
    fi

    printf '%s' "$row" | jq -c --arg m "$model" '. + {model: $m}'
  done | jq -s --arg ws "$WORKSPACE" --arg ts "$now_iso" '
    {
      workspace: $ws,
      generated_at: $ts,
      agents: .
    }
  '
}

now_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
ROSTER="$(build_entries)"

# Persist cache atomically.
tmp_cache="${CACHE_FILE}.tmp.$$"
printf '%s\n' "$ROSTER" > "$tmp_cache"
mv "$tmp_cache" "$CACHE_FILE"

# --- emit -------------------------------------------------------------------

if [ "$JSON_ONLY" -eq 1 ]; then
  printf '%s\n' "$ROSTER"
else
  printf '%s' "$ROSTER" | jq -r '
    ["PANE","TAB","KIND","MODEL","STATUS"],
    (.agents[] | [.pane, .tab, .agent_kind, .model, .status]) | @tsv
  ' | column -t -s $'\t'
  echo
  echo "workspace: $WORKSPACE  generated: $now_iso"
fi