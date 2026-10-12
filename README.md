# sessionizer.ranma

A plugin for [ranma](https://github.com/masshirodev/ranma), the terminal tiling window manager: ThePrimeagen's tmux-sessionizer for ranma. Pick a project directory, go to its workspace if it has one, or open one there.

## Install

With [hako](https://github.com/masshirodev/hako.ranma), in `~/.config/ranma/lua/plugins/sessionizer.lua`:

```lua
return { "masshirodev/sessionizer.ranma" }
```

Or by hand, as ranma loads any package under `pack/*/start/`:

```sh
git clone https://github.com/masshirodev/sessionizer.ranma ~/.config/ranma/pack/plugins/start/sessionizer.ranma
```

Needs: `sh` and `find`, which every Linux has.

## What it does

```text
ThePrimeagen's tmux-sessionizer for ranma. leader F (shift+f; or
`sessionizer` in the palette) lists the directories under the roots
(sessionizer.roots, sessionizer.depth levels down, hidden ones skipped)
and the extra directories (sessionizer.extra), found with `find`, the
listing reused for sessionizer.cache seconds. Picking one:
  open      go there: a pane in it is focused (the one sessionizer
            opened, else one whose shell is in the directory), or with
            sessionizer.target = "session" the session named after it
  not open  an empty workspace, a shell in the directory, the workspace
            named after it; with target "session", moved to a new
            session of that name. A layout named after the project
            (ranma's `load_layout`) is loaded instead of the shell:
            sessionizer.layout = "saved" when `save_layout` wrote one,
            "always" to try it every time (layouts init.lua declares),
            "off" never.
Open projects are marked ● in the picker and listed first.
`sessionizer NAME` in the palette goes to that project without a picker.
Another key: ranma.unbind("shift+f"), then
ranma.bind("z", function() ranma.emit("sessionizer") end, { exit = true })
(ranma.emit("sessionizer", "NAME") goes to a project, as the command does).
Names are the directory's, with anything but letters, digits, `.`, `_`
and `-` turned into `_`.
Options (settings panel, "sessionizer" group): sessionizer.roots,
sessionizer.depth, sessionizer.extra, sessionizer.target,
sessionizer.layout, sessionizer.cache.

ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Actions",
"Layouts", "Pickers and prompts", "Timers and processes", "Hooks").
```

## Keys and commands

| | |
| --- | --- |
| `leader F` (`shift+f`) | The picker of projects, under `plugins` in the which-key hint. |
| `sessionizer` | The same, from the palette (`leader :`). |
| `sessionizer NAME` | Go to that project, or open it, without a picker. The palette offers the names of the last listing. |
| `ranma.emit("sessionizer"[, NAME])` | The same from Lua, for a key of your own. |

## Options

In ranma's settings panel under `sessionizer`, or with hako's `opts` (`{ "masshirodev/sessionizer.ranma", opts = { ... } }`), or `ranma.set { sessionizer = { ... } }`.

| Option | Default | |
| --- | --- | --- |
| `sessionizer.roots` | `"~/projects"` | Directories whose subdirectories are the projects, separated by commas. |
| `sessionizer.depth` | `1` | How many levels under a root are projects: 1 is its children, 2 their children too. |
| `sessionizer.extra` | `""` | Directories listed as projects themselves, separated by commas: `~/.config/ranma`, say. |
| `sessionizer.target` | `"workspace"` | What a project gets: a workspace named after it in this session, or a `"session"` of its own. |
| `sessionizer.layout` | `"saved"` | Load the layout named after a new project: `"saved"` when `save_layout` wrote one, `"always"` (for layouts `init.lua` declares; a project with none gets a shell), or `"off"`. |
| `sessionizer.cache` | `30` | Seconds a listing of the roots is reused before `find` runs again; 0 lists every time. |

```lua
ranma.set { sessionizer = { roots = "~/projects, ~/work", depth = 2, extra = "~/.config/ranma" } }
```

## How it tells a project is open

ranma's Lua API does not say what a workspace is called, so a project is open when a pane is in it: a pane sessionizer opened there (remembered until the configuration reloads), else any pane whose shell is in the directory or below it. With `depth` above 1, a pane belongs to the deepest project it is in. With `target = "session"`, a project is open when a session has its name.

A new project's workspace is made from ranma's own actions: `workspace empty`, then a shell started in the directory with `exec` (or `load_layout NAME`), `rename_workspace NAME`, and for the session target `move_workspace_to_session NAME`.

## License

MIT or Apache-2.0, as ranma.
