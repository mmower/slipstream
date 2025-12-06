
do
  local github_binary = values[1]
  local build_num, err = rez.plugin.run("git", {"rev-list", "--count", "HEAD"})
  if build_num then
    build_num = math.tointeger(tonumber(build_num))
    compilation = rez.compilation.add_numeric_const(compilation, "BUILD_NUM", build_num)
  else
    print("Error in get_build_number plugin. Exit code: " .. err)
  end

  return compilation
end