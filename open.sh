#!/bin/sh
# Herdr link handler: open a Ctrl-clicked file link in the configured editor.
#
# Herdr passes the click through the environment, not argv:
#   HERDR_PLUGIN_CLICKED_URL   herdr-open://file/abs/path:12:3 (osc8wrap) or file:///abs/path
#   HERDR_PLUGIN_CONFIG_DIR    holds config.toml (editor_command, open_in_pane)
#   HERDR_PLUGIN_CONTEXT_JSON  full context, incl. focused_pane_id
set -eu

# Herdr captures stdout into the plugin log, so every exit path states its decision.
say() { printf '%s\n' "$*"; }

is_num() { case $1 in '' | *[!0-9]*) return 1 ;; esac; }

# replace <text> <from> <to>: literal, so paths need no sed escaping.
replace() {
  s=$1 out=
  while :; do
    case $s in
      *"$2"*) out=$out${s%%"$2"*}$3 s=${s#*"$2"} ;;
      *) break ;;
    esac
  done
  printf '%s' "$out$s"
}

# cfg_get <key>: last `key = "value"` (or a bare value like true) in config.toml.
cfg_get() {
  cfg="${HERDR_PLUGIN_CONFIG_DIR:-}/config.toml"
  [ -f "$cfg" ] || return 0
  v=$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$cfg" | tail -n 1)
  case $v in
    \"*) v=${v#\"} v=${v%\"*} ;;
    *) v=${v%%[[:space:]#]*} ;;
  esac
  printf '%s' "$v"
}

url="${HERDR_PLUGIN_CLICKED_URL:-}"
[ -n "$url" ] || { say "skip: no clicked url"; exit 0; }

case $url in
  herdr-open://*) rest=${url#herdr-open://} ;;
  file://*) rest=${url#file://} ;;
  *) say "skip: not a file link: $url"; exit 0 ;;
esac

# file:///abs has no host; herdr-open://file/abs and file://localhost/abs do.
case $rest in /*) ;; *) rest=/${rest#*/} ;; esac

# Percent-decode byte by byte in awk: dash's printf %b has no \xHH, and the C
# locale keeps %c from re-encoding bytes of a UTF-8 name.
p=$(printf '%s' "$rest" | LC_ALL=C awk '
  function hex(h) {
    h = tolower(h)
    return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
  }
  {
    s = $0
    while (match(s, /%[0-9A-Fa-f][0-9A-Fa-f]/)) {
      printf "%s%c", substr(s, 1, RSTART - 1), hex(substr(s, RSTART + 1, 2))
      s = substr(s, RSTART + 3)
    }
    printf "%s", s
  }')

# Peel :line[:col] only when the literal path is missing, so a name with a colon still works.
line=1 col=1
if [ ! -e "$p" ] && is_num "${p##*:}"; then
  line=${p##*:} p=${p%:*}
  if [ ! -e "$p" ] && is_num "${p##*:}"; then
    col=$line line=${p##*:} p=${p%:*}
  fi
fi

# Any program can print a link, so only an existing local path goes further.
[ -e "$p" ] || { say "skip: no such path: $p"; exit 0; }

editor=$(cfg_get editor_command)
editor=${editor:-'zed {file}:{line}:{col}'}

quoted="'$(printf '%s' "$p" | sed "s/'/'\\\\''/g")'"
cmd=$(replace "$editor" '{file}' "$quoted")
cmd=$(replace "$cmd" '{line}' "$line")
cmd=$(replace "$cmd" '{col}' "$col")

if [ "$(cfg_get open_in_pane)" != true ]; then
  say "open: $cmd"
  exec sh -c "$cmd"
fi

# Terminal editor: run it in a split beside the pane that was clicked.
ctx=${HERDR_PLUGIN_CONTEXT_JSON:-}
pane=$(printf '%s' "$ctx" | sed -n 's/.*"focused_pane_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
dir=$(dirname "$p")
[ -d "$p" ] && dir=$p
# Separate statements, so set -e stops on a failed split (a pipeline would hide it).
split=$(herdr pane split ${pane:+"$pane"} --direction right --cwd "$dir" --focus)
new=$(printf '%s' "$split" | python3 -c 'import json, sys; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$new" "$cmd" >/dev/null
say "open in pane $new: $cmd"
