#!/bin/sh
# Assert-style checks for open.sh. Run: sh test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/cfg" "$tmp/bin"
: >"$tmp/a.txt"
: >"$tmp/with space.txt"
: >"$tmp/it's.txt"
printf '%s\n' "editor_command = \"printf '%s|%s|%s' {file} {line} {col}\"" >"$tmp/cfg/config.toml"

fails=0
check() { # check <name> <clicked url> <expected substring> [config dir]
  out=$(HERDR_PLUGIN_CLICKED_URL="$2" HERDR_PLUGIN_CONFIG_DIR="${4:-$tmp/cfg}" \
    PATH="$tmp/bin:$PATH" sh "$here/open.sh" 2>&1)
  case "$out" in
    *"$3"*) printf 'ok   %s\n' "$1" ;;
    *) printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "$3" "$out"; fails=$((fails + 1)) ;;
  esac
}

check "osc8wrap link with line and col" "herdr-open://file$tmp/a.txt:12:3" "$tmp/a.txt|12|3"
check "osc8wrap link with line only" "herdr-open://file$tmp/a.txt:7" "$tmp/a.txt|7|1"
check "percent-encoded space" "file://$tmp/with%20space.txt" "$tmp/with space.txt|1|1"
check "file link with host" "file://localhost$tmp/a.txt" "$tmp/a.txt|1|1"
check "single quote in name" "file://$tmp/it%27s.txt" "$tmp/it's.txt|1|1"
check "missing file is skipped" "herdr-open://file$tmp/missing.txt:3" "skip: no such path"
check "other scheme is skipped" "https://example.com" "skip: not a file link"
check "no url is skipped" "" "skip: no clicked url"

printf '#!/bin/sh\nprintf "zed-stub %%s" "$*"\n' >"$tmp/bin/zed"
chmod +x "$tmp/bin/zed"
check "default editor is zed" "herdr-open://file$tmp/a.txt:4:2" "zed-stub $tmp/a.txt:4:2" "$tmp/no-config"

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
