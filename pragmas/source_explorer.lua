-- Source Explorer
-- No values
-- All pragmas are passed a %Compilation{} under the name 'compilation'
-- and are expected to return an updated compilation.
--
-- This plugin gets all the user written source files for the game and creates
-- an HTML file that allows "exploring" the source. In the left pane is the
-- list of source files and in the right pane is the content of the source file
-- code formatted (monospace font etc…) All of the required content is packed
-- into source_explorer.html which is automatically added to the game assets

function get_asset_dist_path(compilation, asset_id)
  local asset = rez.compilation.get_content_with_id(compilation, asset_id)
  return rez.node.get_attr_value(asset, "$dist_path")
end

-- Compute relative path from a directory to a file path
function relative_path(from_dir, to_path)
  local function split_path(path)
    local parts = {}
    local start = 1
    while true do
      local pos = path:find("/", start, true)
      if pos then
        if pos > start then
          table.insert(parts, path:sub(start, pos - 1))
        end
        start = pos + 1
      else
        if start <= #path then
          table.insert(parts, path:sub(start))
        end
        break
      end
    end
    return parts
  end

  local from_parts = split_path(from_dir)
  local to_parts = split_path(to_path)

  -- Find common prefix length
  local common = 0
  for i = 1, math.min(#from_parts, #to_parts) do
    if from_parts[i] == to_parts[i] then
      common = i
    else
      break
    end
  end

  local result = {}

  -- Go up from from_dir to common ancestor
  for i = common + 1, #from_parts do
    table.insert(result, "..")
  end

  -- Go down to target
  for i = common + 1, #to_parts do
    table.insert(result, to_parts[i])
  end

  return table.concat(result, "/")
end

function read_sources(compilation)
  local sources = {}
  local source_paths = rez.compilation.source_paths(compilation)
  local cwd = rez.plugin.cwd()
  local prefix = cwd .. "/"

  for i, source_path in ipairs(source_paths) do
    local content, err = rez.plugin.read_file(source_path)

    if content then
      local source = {}
      -- Strip the project root to get relative path
      if source_path:sub(1, #prefix) == prefix then
        source["path"] = source_path:sub(#prefix + 1)
      else
        source["path"] = source_path
      end
      source["content"] = content
      sources[i] = source
    else
      print("Unable to read: " .. source_path .. " - " .. (err or "unknown error"))
    end
  end

  return sources
end

-- Generates an HTML source explorer using Bulma CSS and AlpineJS.
-- Returns a complete HTML document as a string.
function generate_source_explorer(sources, bulma_css_path, alpine_js_path, main_source_path)
  -- Escape HTML entities in code
  local function escape_html(str)
    local subst = {
      ["&"] = "&amp;",
      ["<"] = "&lt;",
      [">"] = "&gt;",
      ['"'] = "&quot;",
      ["'"] = "&#39;"
    }
    return (str:gsub("[&<>'\"]", subst))
  end

  -- Escape string for use in JavaScript string literal
  local function escape_js_string(str)
    local result = str
    result = result:gsub("\\", "\\\\")  -- backslashes first
    result = result:gsub("\n", "\\n")   -- newlines
    result = result:gsub("\r", "\\r")   -- carriage returns
    result = result:gsub("\t", "\\t")   -- tabs
    result = result:gsub('"', '\\"')    -- double quotes
    result = result:gsub("'", "\\'")    -- single quotes
    return result
  end

  -- Extract folder and filename from path
  local function get_display_name(path)
    -- Get filename
    local filename = path:match("([^/]+)$") or path
    -- Get parent folder
    local parent = path:match("([^/]+)/[^/]+$") or ""
    if parent ~= "" then
      return parent .. "/" .. filename
    end
    return filename
  end

  -- Group sources by folder
  local function get_folder(path)
    local folder = path:match("(.+)/[^/]+$") or ""
    -- Get just the last folder name
    local last_folder = folder:match("([^/]+)$") or folder
    return last_folder
  end

  -- Sort sources by folder then filename (grouping all files in same folder together)
  table.sort(sources, function(a, b)
    local folder_a = get_folder(a.path)
    local folder_b = get_folder(b.path)
    if folder_a ~= folder_b then
      return folder_a < folder_b
    end
    return a.path < b.path
  end)

  -- Build JSON object for sources
  local json_entries = {}
  for i, src in ipairs(sources) do
    local path = escape_js_string(src.path)
    local content = escape_js_string(src.content)
    json_entries[i] = string.format('"%s": "%s"', path, content)
  end
  local sources_json = "{" .. table.concat(json_entries, ",") .. "}"

  -- Build file list items grouped by folder
  local file_list_html = ""
  local current_folder = nil
  for _, src in ipairs(sources) do
    local folder = get_folder(src.path)
    local filename = src.path:match("([^/]+)$") or src.path
    local escaped_path = escape_js_string(src.path)

    -- Add folder label if folder changed
    if folder ~= current_folder then
      if current_folder ~= nil then
        file_list_html = file_list_html .. "          </ul>\n"
      end
      file_list_html = file_list_html .. string.format(
        '          <p class="menu-label">%s</p>\n          <ul class="menu-list">\n',
        escape_html(folder)
      )
      current_folder = folder
    end

    file_list_html = file_list_html .. string.format([[
            <li>
              <a href="#" @click.prevent="select('%s')"
                 :class="selected === '%s' ? 'is-active' : ''">
                %s
              </a>
            </li>
]], escaped_path, escaped_path, escape_html(filename))
  end
  if current_folder ~= nil then
    file_list_html = file_list_html .. "          </ul>\n"
  end

  -- Find the full path matching the main source path
  local initial_path = ""
  for _, src in ipairs(sources) do
    if src.path:match(main_source_path .. "$") then
      initial_path = escape_js_string(src.path)
      break
    end
  end

  -- Build HTML
  local html = [[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Source Explorer</title>
  <link rel="stylesheet" href="]] .. bulma_css_path .. [[">
  <script defer src="]] .. alpine_js_path .. [["></script>
  <style>
    html, body {
      height: 100%;
      margin: 0;
      overflow: hidden;
    }
    .explorer-container {
      display: flex;
      height: 100vh;
    }
    .file-sidebar {
      width: 280px;
      min-width: 280px;
      height: 100vh;
      overflow-y: auto;
      background-color: #f5f5f5;
      border-right: 1px solid #dbdbdb;
      padding: 1rem;
    }
    .file-sidebar .menu-label {
      color: #7a7a7a;
      font-size: 0.75rem;
      letter-spacing: 0.1em;
      text-transform: uppercase;
      margin-top: 1em;
    }
    .file-sidebar .menu-label:first-child {
      margin-top: 0;
    }
    .file-sidebar .menu-list a {
      padding: 0.5em 0.75em;
      margin-bottom: 0.25em;
      border-radius: 4px;
      background-color: #2d2d2d;
      color: #e0e0e0;
      font-size: 0.9rem;
    }
    .file-sidebar .menu-list a:hover {
      background-color: #404040;
      color: #ffffff;
    }
    .file-sidebar .menu-list a.is-active {
      background-color: #3273dc;
      color: #fff;
    }
    .code-panel {
      flex: 1;
      height: 100vh;
      overflow-y: auto;
      padding: 1.5rem;
      background-color: #fff;
    }
    .code-container {
      background-color: #282c34;
      border-radius: 6px;
      padding: 1rem;
      overflow-x: auto;
    }
    .code-container pre {
      margin: 0;
      padding: 0;
      background: transparent;
    }
    .code-container code {
      font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Fira Code', 'Droid Sans Mono', 'Source Code Pro', monospace;
      font-size: 0.875rem;
      line-height: 1.6;
      color: #abb2bf;
      white-space: pre;
      tab-size: 2;
    }
    .explorer-title {
      font-size: 1.25rem;
      font-weight: 600;
      color: #363636;
      padding-bottom: 1rem;
      margin-bottom: 0.5rem;
      border-bottom: 1px solid #dbdbdb;
    }
  </style>
</head>

<body x-data="sourceExplorer()">

<div class="explorer-container">
  <!-- LEFT: File list sidebar -->
  <aside class="file-sidebar">
    <h1 class="explorer-title">Source Explorer</h1>
    <nav class="menu">
]] .. file_list_html .. [[
    </nav>
  </aside>

  <!-- RIGHT: Code viewer -->
  <main class="code-panel">
    <div class="code-container">
      <pre><code x-text="sources[selected]"></code></pre>
    </div>
  </main>
</div>

<script>
function sourceExplorer() {
  return {
    sources: ]] .. sources_json .. [[,
    selected: "]] .. initial_path .. [[",
    select(path) {
      this.selected = path;
    }
  }
}
</script>

</body>
</html>
]]

  return html
end

do
  local source_explorer_folder = "assets/source_explorer"

  -- Get asset dist paths and compute relative paths from source_explorer folder
  local bulma_dist_path = get_asset_dist_path(compilation, "_BULMA_CSS")
  local alpine_dist_path = get_asset_dist_path(compilation, "_ALPINE_JS")
  local bulma_rel_path = relative_path(source_explorer_folder, bulma_dist_path)
  local alpine_rel_path = relative_path(source_explorer_folder, alpine_dist_path)

  -- Read each source file into a string
  local sources = read_sources(compilation)
  local main_source_path = rez.compilation.main_source_path(compilation)

  rez.plugin.mkdir(source_explorer_folder)

  local source_explorer_path = source_explorer_folder .. "/source_explorer.html"
  local html = generate_source_explorer(sources, bulma_rel_path, alpine_rel_path, main_source_path)

  rez.plugin.write_file(source_explorer_path, html)

  local asset = rez.asset.make(source_explorer_path)
  compilation = rez.compilation.add_content(compilation, asset)
end

return compilation
