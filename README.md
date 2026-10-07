# Machinist

My personal theme: one look, applied everywhere I read text.

Like [Nord](https://www.nordtheme.com), Machinist is defined once — a
palette, a set of color roles, and layout rules — and each *port* applies it
to a particular tool, so a log line, a terminal, and an editor all read the
same way.

## The theme

The look is earthy but not tired: the warm, olive-tinged neutrals of Lospec's
[2bit-demichrome](https://lospec.com/palette-list/2bit-demichrome) as the
base, with saturated greens, teals, and conventional signal colors on top so
nothing reads as faded.

### Palette

Dark only, for now. Every text color reaches at least 4.5:1 against the
background.

| Slot | Normal | Bright |
|------|--------|--------|
| black | `#3b3638` | `#85859a` |
| red | `#e0604f` | `#f27a63` |
| green | `#40985e` | `#94e344` |
| yellow | `#d9a93a` | `#f0cc5a` |
| blue | `#5b8fc9` | `#84b3ec` |
| magenta | `#d65ca6` | `#e87fc0` |
| cyan | `#5ab9a8` | `#7fd9c4` |
| white | `#a0a08b` | `#e9efec` |

| Surface | Color |
|---------|-------|
| Background | `#211e20` |
| Foreground | `#e9efec` |
| Cursor | `#94e344` |
| Selection | `#04373b` |
| Panel, such as a status bar | `#1a644e` |
| Accent, behind text only | `#6b1fb1` |

### Roles

Roles name ANSI slots rather than hex values. A terminal port fills those
slots with the palette above; everywhere else, ports inherit the terminal's
own palette and stay legible in light and dark themes. Whatever palette fills
the slots, each slot must still read as its name — red as red, yellow as
yellow — so conventional meanings survive.

| Role | Style | Used for |
|------|-------|----------|
| Furniture | dim | Timestamps, labels, sources — what frames the content |
| Content | bold | The thing you came to read, such as a log message |
| Key | cyan | Names in key-value pairs |
| Value | plain | Values and the `:`/`,` separators between them |
| Brackets | yellow → magenta → blue, repeating | `()`, `[]`, `{}` by nesting depth; a matching pair shares a color |

Severity takes its own scale:

| `trace` | `debug` | `info` | `notice` | `warning` | `error` | `critical` |
|---------|---------|--------|----------|-----------|---------|------------|
| bright black | blue | green | cyan | yellow | red | bright red |

### Rules

1. **Readability and convention first.** Text stays legible — at least
   4.5:1 against its background — and colors keep the meanings readers
   already know: red for errors, yellow for warnings, green for success.
   Custom style gives way to both, so the theme never asks anyone to learn a
   new code.
2. **Subdue the furniture.** What frames the content recedes so the content
   stands out.
3. **Color means something.** Every color marks a severity, a role, or a
   structure — never decoration.
4. **Align, never truncate.** Columns are padded so the eye scans down
   instead of across; a wide field overflows its column instead of being cut.
5. **Plain when nobody's looking.** Color appears only on a terminal, and
   never when `NO_COLOR` is set.

## Ports

| Tool | Where | Status |
|------|-------|--------|
| swift-log | `Machinist` library in this package | Shipped |
| Ghostty | [`ports/ghostty/machinist`](ports/ghostty/machinist) | Shipped |
| Starship | [`ports/starship/machinist.toml`](ports/starship/machinist.toml) | Shipped |
| Oh My Zsh | [`ports/oh-my-zsh/machinist.zsh-theme`](ports/oh-my-zsh/machinist.zsh-theme) | Shipped |
| tmux (Oh My Tmux) | [`ports/tmux/oh-my-tmux.conf`](ports/tmux/oh-my-tmux.conf) | Shipped |

A new port maps each role to its tool's styling and keeps the rules. Ports
change colors only: layout, glyphs, and behavior stay with the configuration
that adopts them, and a config that can't include another file copies the
port's values in.

Powerline-style bars — the Starship prompt and the tmux status bar — run one
gradient, bright to deep, so both read as the same object:

| Segment | Background | Text |
|---------|------------|------|
| 1 — user, session | `#94e344` | `#211e20` |
| 2 — directory, current window | `#40985e` | `#211e20` |
| 3 — git | `#1a644e` | `#e9efec` |
| 4 — toolchain | `#04373b` | `#e9efec` |
| 5 — context | `#555568` | `#e9efec` |
| 6 — clock, bar | `#3b3638` | `#e9efec` |

## Ghostty

Link the theme into Ghostty's themes directory, then select it in your
Ghostty config:

```sh
mkdir -p ~/.config/ghostty/themes
ln -s ~/code/machinist/ports/ghostty/machinist ~/.config/ghostty/themes/machinist
```

```
theme = machinist
```

With Ghostty on Machinist, anything that colors by ANSI slot — including the
swift-log port — picks up the palette.

## Oh My Zsh

The `machinist` theme draws the Starship prompt below. Link it into your
custom themes and select it in `~/.zshrc`:

```sh
ln -s ~/code/machinist/ports/oh-my-zsh/machinist.zsh-theme \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/machinist.zsh-theme
```

```sh
ZSH_THEME="machinist"
```

Link the theme rather than copying it: it finds `machinist.toml` relative to
its own location. If Starship isn't installed, the theme installs it once —
with Homebrew when available, otherwise with Starship's installer into
`~/.local/bin` — and falls back to the default prompt if neither works.
Remove any `eval "$(starship init zsh)"` line from `~/.zshrc`; the theme runs
it.

## Starship

`machinist.toml` is a complete prompt: Starship's Gruvbox Rainbow layout in
the Machinist palette. Use it through the Oh My Zsh theme, or directly with
`STARSHIP_CONFIG=~/code/machinist/ports/starship/machinist.toml`.

To recolor a different layout, copy its `[palettes.machinist]` table. It keeps
the Gruvbox Rainbow preset's key names: `color_orange` through `color_blue`
are the bar's segments 1–4, `color_bg3` and `color_bg1` segments 5 and 6.
Segments 1 and 2 are bright, so point their text at `color_bg0` instead of
`color_fg0`:

```toml
[directory]
style = "fg:color_bg0 bg:color_yellow"
```

## tmux

`oh-my-tmux.conf` sets [Oh My Tmux](https://github.com/gpakosz/.tmux)'s 17
theme colors; paste it over the `tmux_conf_theme_colour_*` lines in
`tmux.conf.local`. Status-left runs segments 1–3, status-right segments 3–5,
and the current window takes segment 2.

Status lines styled by hand use these roles on the bar background, `#3b3638`:

| Role | Color |
|------|-------|
| Muted text, inactive | `#a0a08b` |
| Label | `#f0cc5a` or `#7fd9c4` |
| Key | `#d9a93a` or `#94e344` |

## swift-log

`MachinistLogHandler` follows swift-log's `StreamLogHandler` — the same
metadata sources merged in the same order (handler metadata, then the
`MetadataProvider`, then per-statement metadata, then `error.message` and
`error.type` for statements carrying an error) — and lays each line out in
Machinist's columns: the `[LEVEL]`, `[label:source]`, and message columns are
padded so the message and its tags each start at the same column on nearly
every line, the metadata tags trail the message in parentheses, where a long
list wraps its own tail, tag keys are printed in the order they were added
rather than alphabetically, and each formatted line is delivered to a
caller-supplied `Output` instead of a `TextOutputStream`:

    2026-09-30T18:11:04-0700 [com.example.machinist:MachinistTests]   [INFO]     listening on port 9000                   (app: machinistd, request-id: A1B2C3)

Keys set on the logger one at a time keep that order in output; keys arriving
as a whole metadata dictionary (from a provider or a log statement) are
ordered alphabetically among themselves, since a dictionary's own order is
not meaningful. Reassigning an existing key keeps its original position.

Column widths default to `Justification(level: 10, label: 40, message: 40)`;
construct a handler with `justification:` to tune them, or
`justification: .none` for the most compact lines. The message is padded only
when tags follow it, so lines without tags end at the message.

### Usage

Write to standard output, with locking and a flush after every line:

```swift
import Logging
import Machinist

LoggingSystem.bootstrap { label in
    MachinistLogHandler.standardOutput(label: label)
}
```

Or supply your own destination. Each `write` receives one complete line,
including the trailing newline, from whichever thread happens to log — wrap
destinations that aren't safe for that in `Output.locked`:

```swift
LoggingSystem.bootstrap { label in
    MachinistLogHandler(label: label, output: .locked { line in
        logFile.write(line)
    })
}
```

### Color

The handler applies the theme's roles: the timestamp and label:source bracket
are furniture, the message is content, the `[LEVEL]` takes its severity
color, and in the trailing tags, keys are cyan, values plain, and brackets —
the enclosing parentheses and any pair inside a value — rainbow by depth.

The stdio factories colorize automatically when attached to a terminal and
stay plain when piped or when `NO_COLOR` is set. Pass `colorize: true` or
`false` to a factory to force a choice, or set `colorize` on a handler
created with the full initializer (off by default).

Run `swift test --filter sampleRows` to print a palette of both plain and
colorized lines in your terminal.
