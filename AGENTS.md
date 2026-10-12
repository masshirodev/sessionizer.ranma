# AGENTS.md

sessionizer.ranma is a ranma plugin in Lua: `plugin/sessionizer.lua` is all of
it, and its header comment is the reference that `README.md` repeats. ranma's
API is https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md (`ranma --dump-types` prints it as LuaLS annotations).

- Push to `main`.
- A change to what it does changes the header comment and `README.md` in the
  same commit, and an option goes in the README's table.
- It needs ranma 0.2.2 or newer, and uses only the API the latest release
  has (the README says which version). Open projects are found by workspace
  name (`ranma.state().names`, a pane's `workspace_name`), then by pane
  directory; layouts by `ranma.layouts()`. New workspaces are built from
  actions rather than a `ranma open` job: actions run at once, need no
  `ranma` on the job's PATH, and the layout path needs them anyway.
- Check it loads: `ranma --check-config` lists every plugin and why one failed;
  `ranma lua` runs code in the live server.
  CI (`.github/workflows/ci.yml`) loads it into the latest ranma release on
  every push and fails if it does not.
- Try behaviour in a private server (its own `RANMA_CONFIG_DIR`, `XDG_*` dirs
  and tmux, with `RANMA_SOCKET`, `RANMA`, `RANMA_PANE` and `TMUX` unset), not
  in the terminal you work in: saving a file in a packadded checkout reloads
  the ranma that loads it.
- `AGENTS.local.md` (gitignored) carries what is true of one checkout on one
  machine. Never commit it.
