-- sessionizer: pick a project, go to its workspace, or make one there.
--
-- Needs ranma 0.2.2 or newer, the first with workspace names and
-- ranma.layouts() in Lua.
--
-- ThePrimeagen's tmux-sessionizer for ranma. leader F (shift+f; or
-- `sessionizer` in the palette) lists the directories under the roots
-- (sessionizer.roots, sessionizer.depth levels down, hidden ones skipped)
-- and the extra directories (sessionizer.extra), found with `find`, the
-- listing reused for sessionizer.cache seconds. Picking one:
--   open      go there: the workspace named after it (this session's
--             first, else a pane of one in another session), else a pane
--             whose shell is in the directory; with sessionizer.target =
--             "session", the session named after it
--   not open  an empty, unnamed workspace, a shell in the directory,
--             the workspace named after it; with target "session",
--             moved to a new session of that name. With
--             sessionizer.layout on (the default), a layout named after
--             the project, declared in init.lua or saved with
--             `save_layout`, is loaded instead of the shell when there
--             is one.
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
  type = "bool", default = true,
  name = "Layout",
  desc = "A new project's workspace loads the layout named after it, declared in init.lua or saved with save_layout, when there is one.",
})
ranma.option("sessionizer.cache", {
  type = "int", min = 0, max = 600, step = 10, default = 30, slider = false,
  name = "Reuse the listing",
  desc = "Seconds a listing of the roots is reused before find runs again; 0 lists every time.",
})

-- Prints `home` and the projects, one tab-separated record a line.
-- Arguments: depth, the roots, `--`, the extra directories.
local LIST = [=[
tab=$(printf '\t')
depth=$1; shift
printf 'home%s%s\n' "$tab" "$HOME"
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

-- The listing in use: { projects = { {name, path, short} } }, or nil once it
-- is older than sessionizer.cache. `generation` lets a timer set for an old
-- listing leave a newer one alone.
local listing, generation, listing_job = nil, 0, nil
local waiting = {}   -- what to do with the listing a running `find` brings

local function parse(stdout)
  local home, projects, seen = nil, {}, {}
  for line in stdout:gmatch("[^\n]+") do
    local kind, value = line:match("^(%a+)\t(.*)$")
    if kind == "home" then
      home = value
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
  return { projects = projects }
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

-- Where each open project is, by its path: { workspace = N } for a workspace
-- of the shown session named after it (empty or not), else { panes = ... }:
-- those of a workspace named after it in another session, else those whose
-- shell is in its directory (the deepest project wins, for depth > 1).
local function places(projects)
  local st = ranma.state()
  local here = {}   -- name -> the lowest workspace of the shown session with it
  for n, name in pairs(st.names or {}) do
    if not here[name] or n < here[name] then here[name] = n end
  end
  local paths, elsewhere, inside = {}, {}, {}
  for _, pr in ipairs(projects) do paths[pr.path] = true end
  for _, p in ipairs(ranma.panes()) do
    local wn = p.workspace_name
    if wn and p.session ~= st.session then
      elsewhere[wn] = elsewhere[wn] or {}
      table.insert(elsewhere[wn], p)
    end
    local ok, cwd = pcall(p.cwd, p)
    local dir = ok and cwd and cwd:gsub("/+$", "") or nil
    while dir and dir ~= "" do
      if paths[dir] then
        inside[dir] = inside[dir] or {}
        table.insert(inside[dir], p)
        break
      end
      dir = dir:match("^(.*)/[^/]*$")
    end
  end
  local by = {}
  for _, pr in ipairs(projects) do
    if here[pr.name] then
      by[pr.path] = { workspace = here[pr.name] }
    elseif elsewhere[pr.name] or inside[pr.path] then
      by[pr.path] = { panes = elsewhere[pr.name] or inside[pr.path] }
    end
  end
  return by
end

-- The pane to go to: one in the shown session, then the focused one of its
-- workspace.
local function best(panes, session)
  local function score(p)
    return (p.session == session and 2 or 0) + (p.focused and 1 or 0)
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

local function has_layout(name)
  for _, l in ipairs(ranma.layouts()) do
    if l.name == name then return true end
  end
  return false
end

local function shell_in(path)
  local ok, shell = pcall(ranma.get, "shell")
  if not (ok and type(shell) == "string" and shell ~= "") then shell = nil end
  ranma.action("exec cd -- " .. quote(path) .. " && exec " .. (shell and quote(shell) or '"${SHELL:-/bin/sh}"'))
end

-- The first workspace with no panes and no name. `workspace empty` would take
-- an empty named one, and the rename would take that name from its project.
local function free_workspace()
  local st = ranma.state()
  local taken = {}
  for _, n in ipairs(st.workspaces or {}) do taken[n] = true end
  for n in pairs(st.names or {}) do taken[n] = true end
  for _, n in ipairs(st.hidden or {}) do taken[n] = true end
  for n = 1, 99 do
    if not taken[n] then return tostring(n) end
  end
  return "empty"
end

local function create(pr)
  ranma.action("workspace " .. free_workspace())
  if ranma.get("sessionizer.layout") and has_layout(pr.name) then
    ranma.action("load_layout " .. pr.name)
  else
    shell_in(pr.path)
  end
  ranma.action("rename_workspace " .. pr.name)
  if ranma.get("sessionizer.target") == "session" then
    ranma.action("move_workspace_to_session " .. pr.name)
  end
end

local function go(pr, by)
  if ranma.get("sessionizer.target") == "session" then
    if has_session(pr.name) then return ranma.action("session " .. pr.name) end
    return create(pr)
  end
  local place = by[pr.path]
  if place and place.workspace then
    return ranma.action("workspace " .. place.workspace)
  elseif place then
    return best(place.panes, ranma.state().session):focus()
  end
  create(pr)
end

local function pick(l)
  if #l.projects == 0 then
    return ranma.notify("sessionizer: no projects under " .. ranma.get("sessionizer.roots"))
  end
  local by = places(l.projects)
  local session = ranma.state().session
  local sessions = ranma.get("sessionizer.target") == "session"
  local open, closed = {}, {}
  for _, pr in ipairs(l.projects) do
    local where
    local place = by[pr.path]
    if sessions then
      where = has_session(pr.name) and "session"
    elseif place and place.workspace then
      where = session .. ":" .. place.workspace
    elseif place then
      local p = best(place.panes, session)
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
      if item and item.project then go(item.project, places(l.projects)) end
    end,
  }
end

local function open(name)
  with_listing(function(l)
    if not name or name == "" then return pick(l) end
    for _, pr in ipairs(l.projects) do
      if pr.name == name then return go(pr, places(l.projects)) end
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
