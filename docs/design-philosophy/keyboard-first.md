# Keyboard-First Interaction

## The Core Philosophy

**Every single interaction in vulpes is keyboard-accessible.** Not as an afterthought. Not as an accessibility feature. As the *primary* interface.

The mouse exists. You can use it. But the moment your fingers leave the keyboard, you've lost time. Vulpes is built for people who live in nvim, who navigate terminals with muscle memory, who think in keystrokes.

## Why Keyboard-First?

### Speed
```
Mouse: Move hand → Find cursor → Position → Click
Keys:  Think → Type

The difference is 500ms+ per interaction.
In a browsing session, that's minutes.
```

### Flow State
Context-switching kills focus. Every time you reach for the mouse, you break flow. Keyboard navigation keeps you in the zone.

### Density
Keyboard UI can be denser because you don't need giant click targets. More content, less chrome.

### Muscle Memory
After a week, your fingers know where to go. No visual scanning required.

## Interaction Modes

### Normal Mode (Default)

Navigation and reading. Like vim's normal mode.

```
Movement:
  j / ↓        Scroll down
  k / ↑        Scroll up
  h / ←        Scroll left (if wider than viewport)
  l / →        Scroll right

  d / Ctrl-d   Scroll down half page
  u / Ctrl-u   Scroll up half page

  gg           Jump to top
  G            Jump to bottom

  Ctrl-f       Page down
  Ctrl-b       Page up

Links:
  f            Enter link hint mode
  F            Open link in new card

  [[           Previous page (if detected)
  ]]           Next page (if detected)

History:
  H / Backspace    Go back
  L                Go forward

Cards/Tabs:
  gt / Tab         Next card
  gT / Shift-Tab   Previous card
  {number}gt       Go to card N

  Ctrl-w c         Close current card
  Ctrl-w o         Close other cards

  Space            Toggle card zoom (spatial mode)

Search:
  /            Start search forward
  ?            Start search backward
  n            Next search result
  N            Previous search result

Actions:
  r            Reload page
  y            Copy current URL
  p            Open URL from clipboard
  o            Open URL (command mode)
  O            Open URL in new card

  :            Enter command mode
  Esc          Return to normal mode
```

### Link Hint Mode

Press `f` to enter. Type hint characters to follow link.

```
Page displays:
  ┌──────────────────────────────────────────┐
  │ Welcome to Example                        │
  │                                           │
  │ Check out our [a]documentation[/a] and   │
  │ [s]tutorials[/s] to get started.         │
  │                                           │
  │ Visit [d]GitHub[/d] for source code.     │
  └──────────────────────────────────────────┘

Type 'a' → follows "documentation" link
Type 's' → follows "tutorials" link
Type 'd' → follows "GitHub" link
Type Esc → cancel, return to normal mode
```

**Hint character generation:**
- Home row first: `a s d f j k l ;`
- Then: `g h` (near home row)
- Then top row: `q w e r u i o p`
- Two-character hints for many links: `aa as ad...`

### Command Mode

Press `:` to enter. Like vim's ex mode.

```
:open https://example.com     Open URL
:open example.com             Open with https://
:o example.com                Shorthand

:card new                     New empty card
:card close                   Close current
:card list                    Show all cards

:history                      Show browsing history
:bookmarks                    Show bookmarks
:bookmark add                 Bookmark current page
:bookmark add "name"          Bookmark with name

:set dark                     Dark mode
:set light                    Light mode
:set font-size 18             Set font size

:help                         Show help
:help navigation              Topic-specific help

:quit / :q                    Quit vulpes
:qa                           Quit all (close all cards)
```

**Command completion:**
- Tab completes commands and URLs
- History-aware URL completion
- Fuzzy matching

### Search Mode

Press `/` to search forward, `?` to search backward.

```
/search term<Enter>    Find "search term"
n                      Next match
N                      Previous match
Esc                    Clear search highlighting

Search features:
- Case-insensitive by default
- /Search (capital) for case-sensitive
- Highlights all matches
- Scrolls to first match
- Shows match count
```

### Insert Mode

For URL bar and forms (when we support them).

```
i           Enter insert mode (when in URL bar area)
Esc         Exit insert mode
Ctrl-[      Exit insert mode (vim style)

In insert mode:
  Standard text editing
  Ctrl-w      Delete word backward
  Ctrl-u      Delete to beginning
  Ctrl-a      Move to beginning
  Ctrl-e      Move to end
```

## Key Binding Principles

### 1. Vim Compatibility Where Sensible

Users of vim should feel at home. But we're not vim—we don't need 100% compatibility, just intuitive overlap.

### 2. Home Row Preference

The most common actions use home row keys:
- `f` for follow (most common)
- `j/k` for scroll (constant use)
- `h/l` for card switching

### 3. Mnemonic When Possible

- `f` = follow
- `r` = reload
- `y` = yank (copy)
- `p` = paste
- `o` = open
- `H` = history back
- `L` = history forward (or think "forward-L")

### 4. Modifier Consistency

- `Shift` = "do it bigger" or "opposite direction"
  - `f` = follow, `F` = follow in new card
  - `n` = next match, `N` = previous match
  - `gt` = next tab, `gT` = previous tab
- `Ctrl` = "system-level" actions
  - `Ctrl-f/b` = full page scroll
  - `Ctrl-w` = window/card operations

### 5. No Hidden Features

Every keybinding is documented and discoverable:
- `:help` shows all bindings
- `?` in help shows keybinding help
- Status bar shows current mode

## Configuration

Users can remap keys:

```
# ~/.config/vulpes/keys.toml

[normal]
# Use space for card overview (like tmux)
"<Space>" = "cards.overview"

# Emacs-style scrolling
"<Ctrl-n>" = "scroll.down"
"<Ctrl-p>" = "scroll.up"

[hints]
# Use different hint characters
chars = "aoeuidhtns"  # Dvorak home row

[command]
# Custom commands
aliases = [
  { "gh" = "open https://github.com" },
  { "hn" = "open https://news.ycombinator.com" },
]
```

## Visual Feedback

### Mode Indicator

Always visible, always clear:

```
┌─────────────────────────────────────────────────────────┐
│ NORMAL │ example.com/page                               │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ HINT   │ example.com/page                         [3]   │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ SEARCH │ /search term                             [2/7] │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ COMMAND │ :open https://                                │
└─────────────────────────────────────────────────────────┘
```

### Key Echo (Optional)

Show recently pressed keys (like vim's showcmd):

```
Pressed: g → waiting for second key
Pressed: gt → switched to next card
```

### Command Palette (Future)

`Cmd-Shift-P` or `Ctrl-Shift-P` for fuzzy command search:

```
┌─────────────────────────────────────────────┐
│ > reload                                    │
├─────────────────────────────────────────────┤
│ ▶ Reload Page                          r   │
│   Reload (bypass cache)           Shift-r   │
│   Reload all cards                          │
└─────────────────────────────────────────────┘
```

## Discoverability

### Help System

```
:help              Full help
:help keys         All keybindings
:help navigation   Navigation help
:help cards        Card management help

Press ? in any mode for contextual help
```

### Onboarding

First launch shows essential keys:

```
┌─────────────────────────────────────────────────────────┐
│                    Welcome to vulpes                    │
│                                                         │
│   Essential keys:                                       │
│                                                         │
│   j/k         Scroll down/up                           │
│   f           Follow a link                            │
│   H           Go back                                  │
│   o           Open URL                                 │
│   /           Search page                              │
│   :help       Full help                                │
│                                                         │
│   Press any key to dismiss                             │
└─────────────────────────────────────────────────────────┘
```

## Mouse Support (Secondary)

The mouse works, but it's not optimized for:

- Click links
- Scroll (trackpad/wheel)
- Select text
- Resize windows

But no mouse-only features. Everything has a keyboard path.

## Implementation Notes

### Key Event Handling

```zig
const KeyEvent = struct {
    key: Key,
    modifiers: Modifiers,

    const Modifiers = packed struct {
        shift: bool,
        ctrl: bool,
        alt: bool,
        cmd: bool,  // macOS
    };
};

fn handleKey(mode: Mode, event: KeyEvent) Action {
    const binding = keybindings.get(mode, event);
    return binding orelse .none;
}
```

### Mode State Machine

```zig
const Mode = enum {
    normal,
    hint,
    search,
    command,
    insert,
};

const ModeTransition = struct {
    from: Mode,
    trigger: KeyEvent,
    to: Mode,
};

const transitions = [_]ModeTransition{
    .{ .from = .normal, .trigger = key('f'), .to = .hint },
    .{ .from = .normal, .trigger = key('/'), .to = .search },
    .{ .from = .normal, .trigger = key(':'), .to = .command },
    .{ .from = .hint, .trigger = key_esc, .to = .normal },
    // ...
};
```

## See Also

- [spatial-cards.md](spatial-cards.md) - Card navigation concept
- [principles.md](principles.md) - Design principles
- [../roadmap/phase-2-actually-useful.md](../roadmap/phase-2-actually-useful.md) - Implementation plan
