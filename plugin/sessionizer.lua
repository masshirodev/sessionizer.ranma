-- sessionizer: pick a project, go to its workspace, or make one there.
--
-- ThePrimeagen's tmux-sessionizer for ranma. leader F (shift+f; or
-- `sessionizer` in the palette) lists the directories under the roots
-- (sessionizer.roots, sessionizer.depth levels down, hidden ones skipped)
-- and the extra directories (sessionizer.extra), found with `find`, the
-- listing reused for sessionizer.cache seconds. Picking one:
--   open      go there: a pane in it is focused (the one sessionizer
--             opened, else one whose shell is in the directory), or with
--             sessionizer.target = "session" the session named after it
--   not open  an empty workspace, a shell in the directory, the workspace
--             named after it; with target "session", moved to a new
--             session of that name. A layout named after the project
--             (ranma's `load_layout`) is loaded instead of the shell:
--             sessionizer.layout = "saved" when `save_layout` wrote one,
--             "always" to try it every time (layouts init.lua declares),
--             "off" never.
-- Open projects are marked ● in the picker and listed first.
-- `sessionizer NAME` in the palette goes to that project without a picker.
-- Another key: ranma.unbind("shift+f"), then
-- ranma.bind("z", function() ranma.emit("sessionizer") end, { exit = true })
-- (ranma.emit("sessionizer", "NAME") goes to a project, as the command does).
-- Names are the directory's, with anything but letters, digits, `.`, `_`
-- and `-` turned into `_`.
-- Options (settings panel, "sessionizer" group): sessionizer.roots,
-- sessionizer.depth, sessionizer.extra, sessionizer.target,
-- sessionizer.layout, sessionizer.cache.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Actions",
-- "Layouts", "Pickers and prompts", "Timers and processes", "Hooks").

ranma.option("sessionizer.roots", {
  type = "string", default = "~/projects",
  name = "Roots",
  desc = "Directories whose subdirectories are the projects, separated by commas.",
})
ranma.option("sessionizer.depth", {
  type = "int", min = 1, max = 4, default = 1, slider = false,
  name = "Depth",
  desc = "How many levels under a root are projects: 1 is its children, 2 their children too.",
})
ranma.option("sessionizer.extra", {
  type = "string", default = "",
  name = "Extra projects",
  desc = "Directories listed as projects themselves, separated by commas: ~/.config/ranma, say.",
})
ranma.option("sessionizer.target", {
  type = "enum", choices = { "workspace", "session" }, default = "workspace",
  name = "Opens a",
  desc = "What a project gets: a workspace named after it in this session, or a session of its own.",
})
ranma.option("sessionizer.layout", {
  type = "enum", choices = { "saved", "always", "off" }, default = "saved",
  name = "Layout",
  desc = "Load the layout named after a new project's workspace: when save_layout wrote one, always (for init.lua's), or never.",
})
ranma.option("sessionizer.cache", {
  type = "int", min = 0, max = 600, step = 10, default = 30, slider = false,
  name = "Reuse the listing",
  desc = "Seconds a listing of the roots is reused before find runs again; 0 lists every time.",
})

-- Prints `home`, the saved layouts and the projects, one tab-separated record
-- a line. Arguments: depth, the roots, `--`, the extra directories.
local LIST = [=[
tab=$(printf '\t')
depth=$1; shift
printf 'home%s%s\n' "$tab" "$HOME"
d=${XDG_STATE_HOME:-$HOME/.local/state}/ranma/layouts
for f in "$d"/*.toml; do
  [ -f "$f" ] || continue
  b=${f##*/}
  printf 'layout%s%s\n' "$tab" "${b%.toml}"
done
kind=root
for r in "$@"; do
  [ "$r" = "--" ] && { kind=extra; continue; }
  case $r in
    "~") r=$HOME ;;
    "~/"*) r=$HOME/${r#"~/"} ;;
  esac
  [ -d "$r" ] || continue
  if [ "$kind" = extra ]; then
    printf 'dir%s%s\n' "$tab" "$r"
  else
    find -H "$r" -mindepth 1 -maxdepth "$depth" -name '.*' -prune -o -type d -print 2>/dev/null |
      sed "s|^|dir$tab|"
  fi
done
]=]

-- A list option: comma-separated, trimmed, empty entries dropped.
local function words(s)
  local out = {}
  for w in (s or ""):gmatch("[^,]+") do
    w = w:match("^%s*(.-)%s*$")
    if w ~= "" then out[#out + 1] = w:gsub("/+$", "") end
  end
  return out
end

local function name_of(path)
  return (path:match("([^/]+)$") or path):gsub("[^%w%._%-]", "_")
end

local function quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- The listing in use: { projects = { {name, path, short} }, layouts = set },
-- or nil once it is older than sessionizer.cache. `generation` lets a timer
-- set for an old listing leave a newer one alone.
local listing, generation, listing_job = nil, 0, nil
local waiting = {}   -- what to do with the listing a running `find` brings

local function parse(stdout)
  local home, projects, layouts, seen = nil, {}, {}, {}
  for line in stdout:gmatch("[^\n]+") do
    local kind, value = line:match("^(%a+)\t(.*)$")
    if kind == "home" then
      home = value
    elseif kind == "layout" then
      layouts[value] = true
    elseif kind == "dir" then
      local path = value:gsub("/+$", "")
      if path ~= "" and not seen[path] then
        seen[path] = true
        local short = path
        if home and home ~= "" and (path == home or path:sub(1, #home + 1) == home .. "/") then
          short = "~" .. path:sub(#home + 1)
        end
        projects[#projects + 1] = { name = name_of(path), path = path, short = short }
      end
    end
  end
  table.sort(projects, function(a, b) return a.short < b.short end)
  return { projects = projects, layouts = layouts }
end

-- Call fn with the listing, running `find` if there is none in use.
local function with_listing(fn)
  if listing then return fn(listing) end
  waiting[#waiting + 1] = fn
  if listing_job then return end
  local args = { "sh", "-c", LIST, "sessionizer", tostring(ranma.get("sessionizer.depth")) }
  for _, r in ipairs(words(ranma.get("sessionizer.roots"))) do args[#args + 1] = r end
  args[#args + 1] = "--"
  for _, r in ipairs(words(ranma.get("sessionizer.extra"))) do args[#args + 1] = r end
  listing_job = ranma.spawn(args, {
    timeout = 10,
    on_exit = function(r)
      listing_job = nil
      local fns = waiting
      waiting = {}
      if r.error then return ranma.notify("sessionizer: " .. r.error) end
      local l = parse(r.stdout or "")
      local ttl = ranma.get("sessionizer.cache")
      if ttl > 0 then
        generation = generation + 1
        local mine = generation
        listing = l
        ranma.defer(ttl * 1000, function()
          if generation == mine then listing = nil end
        end)
      end
      for _, f in ipairs(fns) do f(l) end
    end,
  })
end

-- Panes sessionizer opened are marked with their project's path for as long
-- as `vars` lasts (a reload clears it; the directory test still finds them).
local opening = nil

ranma.on("pane_open", function(ev)
  if not opening then return end
  local p = ranma.pane(ev.pane)
  if p then p.vars.sessionizer = opening end
end)

-- Every pane in a project, by its path: marked ones, else those whose
-- directory is in it (the deepest project wins, for depth > 1).
local function panes_by_project(projects)
  local paths, by = {}, {}
  for _, pr in ipairs(projects) do paths[pr.path] = true end
  for _, p in ipairs(ranma.panes()) do
    local path = p.vars.sessionizer
    if not (path and paths[path]) then
      path = nil
      local ok, cwd = pcall(p.cwd, p)
      local dir = ok and cwd and cwd:gsub("/+$", "") or nil
      while dir and dir ~= "" do
        if paths[dir] then path = dir; break end
        dir = dir:match("^(.*)/[^/]*$")
      end
    end
    if path then
      by[path] = by[path] or {}
      table.insert(by[path], p)
    end
  end
  return by
end

-- The pane to go to: one sessionizer opened, then one in the shown session,
-- then the focused one of its workspace.
local function best(panes, session)
  local function score(p)
    return (p.vars.sessionizer and 4 or 0) + (p.session == session and 2 or 0) + (p.focused and 1 or 0)
  end
  table.sort(panes, function(a, b)
    local sa, sb = score(a), score(b)
    if sa ~= sb then return sa > sb end
    return a.id < b.id
  end)
  return panes[1]
end

local function has_session(name)
  for _, s in ipairs(ranma.state().sessions or {}) do
    if s == name then return true end
  end
  return false
end

local function shell_in(path)
  local ok, shell = pcall(ranma.get, "shell")
  if not (ok and type(shell) == "string" and shell ~= "") then shell = nil end
  ranma.action("exec cd -- " .. quote(path) .. " && exec " .. (shell and quote(shell) or '"${SHELL:-/bin/sh}"'))
end

local function to_session(pr)
  if ranma.get("sessionizer.target") == "session" then
    ranma.action("move_workspace_to_session " .. pr.name)
  end
end

local function create(pr, layouts)
  local mode = ranma.get("sessionizer.layout")
  opening = pr.path
  ranma.defer(1000, function() opening = nil end)
  ranma.action("workspace empty")
  if not (mode == "always" or (mode == "saved" and layouts[pr.name])) then
    shell_in(pr.path)
    ranma.action("rename_workspace " .. pr.name)
    return to_session(pr)
  end
  ranma.action("load_layout " .. pr.name)
  ranma.action("rename_workspace " .. pr.name)
  -- A name no layout has opens nothing (ranma says so in the bar), and an
  -- empty workspace cannot move to a session: a shell there, then.
  local ws = nil
  ranma.defer(0, function() ws = ranma.state().workspace end)
  ranma.defer(150, function()
    local st = ranma.state()
    if st.workspace ~= ws then return end
    local occupied = false
    for _, n in ipairs(st.workspaces or {}) do
      if n == ws then occupied = true end
    end
    if not occupied then shell_in(pr.path) end
    to_session(pr)
  end)
end

local function go(pr, l, by)
  if ranma.get("sessionizer.target") == "session" then
    if has_session(pr.name) then return ranma.action("session " .. pr.name) end
    return create(pr, l.layouts)
  end
  local panes = by and by[pr.path]
  if panes and #panes > 0 then
    return best(panes, ranma.state().session):focus()
  end
  create(pr, l.layouts)
end

local function pick(l)
  if #l.projects == 0 then
    return ranma.notify("sessionizer: no projects under " .. ranma.get("sessionizer.roots"))
  end
  local by = panes_by_project(l.projects)
  local sessions = ranma.get("sessionizer.target") == "session"
  local open, closed = {}, {}
  for _, pr in ipairs(l.projects) do
    local where
    if sessions then
      where = has_session(pr.name) and "session"
    elseif by[pr.path] then
      local p = best(by[pr.path], ranma.state().session)
      where = p.session .. ":" .. p.workspace
    end
    local item = { label = pr.name, detail = pr.short, project = pr }
    if where then
      item.label = pr.name .. " ●"
      item.detail = where .. "  " .. pr.short
      open[#open + 1] = item
    else
      closed[#closed + 1] = item
    end
  end
  for _, it in ipairs(closed) do open[#open + 1] = it end
  ranma.picker {
    title = "projects",
    items = open,
    on_select = function(item)
      if item and item.project then go(item.project, l, panes_by_project(l.projects)) end
    end,
  }
end

local function open(name)
  with_listing(function(l)
    if not name or name == "" then return pick(l) end
    for _, pr in ipairs(l.projects) do
      if pr.name == name then return go(pr, l, panes_by_project(l.projects)) end
    end
    ranma.notify("sessionizer: no project called " .. name)
  end)
end

ranma.command("sessionizer", open, {
  desc = "go to a project's workspace, or open one",
  args = "[project]",
  complete = function()
    local names = {}
    for _, pr in ipairs(listing and listing.projects or {}) do names[#names + 1] = pr.name end
    return names
  end,
})

ranma.on("user:sessionizer", function(name)
  open(type(name) == "string" and name or nil)
end)

-- WM mode ends as the picker opens: it has the keyboard from there.
ranma.bind("shift+f", function() open() end, { desc = "projects", group = "plugins", exit = true })
