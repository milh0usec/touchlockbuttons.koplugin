-- SPDX-License-Identifier: AGPL-3.0-or-later

if #arg == 0 then
    io.stderr:write("Usage: check_lua_syntax.lua FILE...\n")
    os.exit(2)
end

for index = 1, #arg do
    local path = arg[index]
    local chunk, err = loadfile(path)
    if not chunk then
        io.stderr:write(path, ": ", tostring(err), "\n")
        os.exit(1)
    end
    io.stdout:write(path, ": syntax OK\n")
end
