#!/bin/sh
# Line coverage of open.sh with bashcov (bash xtrace + SimpleCov), in Docker so
# it needs neither Ruby nor bash 4+ on the host. Fails below FAIL_UNDER percent.
# The repo is streamed in with tar rather than mounted, so any path works.
set -eu
cd "$(dirname "$0")"

COPYFILE_DISABLE=1 tar c --exclude .git --exclude coverage . |
  docker run --rm -i -e FAIL_UNDER="${FAIL_UNDER:-99}" ruby:3.3-slim sh -c '
    set -e
    apt-get -qq update >/dev/null && apt-get -qq install -y python3 >/dev/null
    gem install -q --silent bashcov -v 4.0.0
    useradd -m tester && mkdir /src && cd /src && tar x 2>/dev/null && chown -R tester /src
    su tester -c "cd /src && OPEN_SH_SHELL=bash bashcov --root /src -- ./test.sh" | grep -v "^ok "
    ruby -rjson -e "
      lines = JSON.parse(File.read(\"coverage/.resultset.json\")).values.first[\"coverage\"][\"/src/open.sh\"][\"lines\"]
      run = lines.compact
      pct = 100.0 * run.count(&:positive?) / run.size
      missed = lines.each_index.select { |i| lines[i] == 0 }.map { |i| i + 1 }
      puts format(\"open.sh line coverage: %.2f%% (%d/%d)\", pct, run.count(&:positive?), run.size)
      puts \"missed lines: #{missed.join(\", \")}\" unless missed.empty?
      exit(pct >= ENV.fetch(\"FAIL_UNDER\").to_f ? 0 : 1)"
  '
