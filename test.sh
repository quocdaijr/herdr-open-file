#!/bin/sh
# Assert-style checks for open.sh. Run: sh test.sh
# A stub `herdr` on PATH records its calls, so no test touches a live Herdr.
set -u

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/cfg" "$tmp/cfg-last" "$tmp/cfg-pane" "$tmp/bin" "$tmp/sub"
: >"$tmp/a.txt"
: >"$tmp/with space.txt"
: >"$tmp/it's.txt"
: >"$tmp/b.txt:9"
: >"$tmp/café\\x.txt"
printf '%s\n' "editor_command = \"printf '%s|%s|%s' {file} {line} {col}\"" >"$tmp/cfg/config.toml"
cat >"$tmp/cfg-last/config.toml" <<'EOF'
editor_command = "echo first {file}"
editor_command = "printf 'last:%s' {file}"   # the last one wins
EOF
cat >"$tmp/cfg-pane/config.toml" <<'EOF'
editor_command = "nvim +{line} {file}"
open_in_pane = true # bare value
EOF

log="$tmp/herdr.log"
cat >"$tmp/bin/herdr" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$log"
if [ "\$1 \$2" = "pane split" ]; then
  [ -z "\${STUB_SPLIT_FAIL:-}" ] || exit 1
  printf '{"result":{"pane":{"pane_id":"p-new"}}}\n'
fi
EOF
printf '#!/bin/sh\nprintf "zed-stub %%s" "$*"\n' >"$tmp/bin/zed"
chmod +x "$tmp/bin/herdr" "$tmp/bin/zed"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n  %s\n' "$1" "$2"; fails=$((fails + 1)); }

# run <clicked url> [VAR=value ...]: sets $out and $status; later VAR=value wins.
# coverage.sh sets OPEN_SH_SHELL=bash: bashcov traces only scripts run by bash.
run() {
  url=$1
  shift
  : >"$log"
  out=$(env HERDR_PLUGIN_CLICKED_URL="$url" HERDR_PLUGIN_CONFIG_DIR="$tmp/cfg" \
    HERDR_PLUGIN_CONTEXT_JSON= PATH="$tmp/bin:$PATH" "$@" "${OPEN_SH_SHELL:-sh}" "$here/open.sh" 2>&1)
  status=$?
}

# expect <name> <text> <substring>
expect() {
  case $2 in
    *"$3"*) pass "$1" ;;
    *) fail "$1" "want: $3 | got: $2" ;;
  esac
}

# reject <name> <text> <substring>
reject() {
  case $2 in
    *"$3"*) fail "$1" "unwanted: $3 | got: $2" ;;
    *) pass "$1" ;;
  esac
}

run "herdr-open://file$tmp/a.txt:12:3"
expect "osc8wrap link with line and col" "$out" "$tmp/a.txt|12|3"

run "herdr-open://file$tmp/a.txt:7"
expect "osc8wrap link with line only" "$out" "$tmp/a.txt|7|1"

run "file://$tmp/with%20space.txt"
expect "percent-encoded space" "$out" "$tmp/with space.txt|1|1"

run "file://$tmp/caf%C3%A9%5Cx.txt"
expect "UTF-8 and backslash decode" "$out" "$tmp/café\\x.txt|1|1"

run "file://localhost$tmp/a.txt"
expect "file link with host" "$out" "$tmp/a.txt|1|1"

run "file://$tmp/it%27s.txt"
expect "single quote in name" "$out" "$tmp/it's.txt|1|1"

run "herdr-open://file$tmp/b.txt:9"
expect "existing name with a colon is not peeled" "$out" "$tmp/b.txt:9|1|1"

run "herdr-open://file$tmp/missing.txt:3"
expect "missing file is skipped" "$out" "skip: no such path: $tmp/missing.txt"

run "herdr-open://file$tmp/missing.txt:abc"
expect "non-numeric suffix is skipped" "$out" "skip: no such path: $tmp/missing.txt:abc"

run "https://example.com"
expect "other scheme is skipped" "$out" "skip: not a file link"

run ""
expect "no url is skipped" "$out" "skip: no clicked url"

run "herdr-open://file$tmp/a.txt:4:2" HERDR_PLUGIN_CONFIG_DIR="$tmp/no-config"
expect "default editor is zed" "$out" "zed-stub $tmp/a.txt:4:2"

run "herdr-open://file$tmp/a.txt" HERDR_PLUGIN_CONFIG_DIR="$tmp/cfg-last"
expect "last key wins, comment ignored" "$out" "last:$tmp/a.txt"

run "herdr-open://file$tmp/a.txt:12" HERDR_PLUGIN_CONFIG_DIR="$tmp/cfg-pane" \
  HERDR_PLUGIN_CONTEXT_JSON='{"focused_pane_id":"p-1","tab_id":"t"}'
expect "pane: split beside the clicked pane" "$(cat "$log")" "pane split p-1 --direction right --cwd $tmp --focus"
expect "pane: runs the editor in the new pane" "$(cat "$log")" "pane run p-new nvim +12 '$tmp/a.txt'"
expect "pane: logs its decision" "$out" "open in pane p-new: nvim +12 '$tmp/a.txt'"

run "file://$tmp/sub" HERDR_PLUGIN_CONFIG_DIR="$tmp/cfg-pane"
expect "pane: a directory is its own cwd" "$(cat "$log")" "--cwd $tmp/sub --focus"
expect "pane: no context splits the focused pane" "$(cat "$log")" "pane split --direction right"

run "herdr-open://file$tmp/a.txt" HERDR_PLUGIN_CONFIG_DIR="$tmp/cfg-pane" STUB_SPLIT_FAIL=1
if [ "$status" -ne 0 ]; then pass "pane: failed split exits non-zero"; else fail "pane: failed split exits non-zero" "status 0"; fi
reject "pane: failed split runs nothing" "$(cat "$log")" "pane run"

if [ "$fails" -ne 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all passed"
