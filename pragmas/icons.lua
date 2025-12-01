-- receives 'compilation' and 'values'

-- values[1] is the path where the Heroicon .svg files should be

-- the plugin will create an inlined asset for each file
-- arrow-path.svg becomes icon_arrow_path
-- whose content attribute is the SVG source

function printTable(t, indent)
    indent = indent or 0
    for k, v in pairs(t) do
        local prefix = string.rep("  ", indent) .. tostring(k) .. ": "
        if type(v) == "table" then
            print(prefix)
            printTable(v, indent + 1)
        else
            print(prefix .. tostring(v))
        end
    end
end

function clean_filename(filename)
  filename = filename:gsub("-", "_")
  filename = filename:gsub("%.svg$", "")
  return filename
end

function make_icon_asset(id, path)
  local asset = rez.asset.make(id, path)
  asset = rez.node.set_attr_value(asset, "$inline", "boolean", true)
  return asset;
end

do
  local icons_path = values[1]

  local files, err = rez.plugin.ls(icons_path)
  if files then
    for i, icon_file in ipairs(files) do
      local icon_name = clean_filename(icon_file)
      local asset_id = "icon_" .. icon_name
      local icon_path = icons_path .. "/" .. icon_file
      local icon_asset = make_icon_asset(asset_id, icon_path)
      --rez.node.inspect(icon_asset)

      compilation = rez.compilation.add_content(compilation, icon_asset)
    end
  end

  return compilation
end