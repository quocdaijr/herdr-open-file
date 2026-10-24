# herdr-open-file

Ctrl-click a file path in a Herdr pane to open it in your editor, at the line and column when the link has them. Zed is the default.

## Why a plugin

Herdr only makes OSC 8 hyperlinks and `http(s)://` URLs clickable. A path printed as plain text is not a link, and Herdr opens no link scheme but `http(s)` by itself ("Other links need a matching plugin"). So two pieces are needed:

1. Something that turns paths into OSC 8 links.
2. This plugin, which opens the clicked link.

For (1):

- **Claude Code** emits `file://` links for paths in tool output, but not inside Herdr, which sets `TERM_PROGRAM=herdr` ([herdr#4748](https://github.com/herdrdev/herdr/issues/4748)). Turn them back on with `FORCE_HYPERLINK=1`.
- **[osc8wrap](https://github.com/mash/osc8wrap)** wraps any program and links every path in its output that exists on disk, including the bare paths in `Bash(...)` lines and compiler errors.

## Install

```sh
herdr plugin link /path/to/herdr-open-file
go install github.com/mash/osc8wrap@latest   # needs ~/go/bin on PATH
```

In `~/.zshrc`:

```sh
[ "$TERM_PROGRAM" = herdr ] && export FORCE_HYPERLINK=1
alias claude='osc8wrap --scheme=herdr-open claude'
```

`--scheme=herdr-open` keeps the links editor-neutral: they look like `herdr-open://file/abs/path:12:3`, and the editor is chosen here, not in the alias.

Ctrl-click needs `ui.mouse_capture = true`, which is Herdr's default.

## Configure

The plugin works without a config file. To pick another editor:

```sh
mkdir -p "$(herdr plugin config-dir open-file)"
cp config.example.toml "$(herdr plugin config-dir open-file)/config.toml"
```

- `editor_command` is a shell command with `{file}`, `{line}` and `{col}`. `{file}` is quoted for you. The default is `zed {file}:{line}:{col}`.
- `open_in_pane = true` runs the command in a new pane split to the right of the clicked one. Use it for terminal editors, e.g. `nvim +{line} {file}`.

## Limits

- Paths that do not exist are never opened. This is also the safety check: any program can print a link.
- Cmd-click is not available; Herdr only passes Ctrl-click.
- Other tools can emit their own links: `rg --hyperlink-format='herdr-open://file{path}:{line}:{column}'`, delta `hyperlinks-file-link-format`, `eza --hyperlink`, `fd --hyperlink`.

## Test

```sh
sh test.sh
```

The `file://` decoding is adapted from [klukacin/herdr-finder-reveal](https://github.com/klukacin/herdr-finder-reveal).
