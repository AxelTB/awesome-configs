local module = {}

-- This code lifed straight from: http://awesome.naquadah.org/wiki/Autostart
-- It requires the liblua5.1-filesystem0 deb.
require("lfs")
local awful = require("awful")
-- {{{ Run programm once
local function processwalker()
  local function yieldprocess()
    for dir in lfs.dir("/proc") do
      -- All directories in /proc containing a number, represent a process
      if tonumber(dir) ~= nil then
        local f, err = io.open("/proc/"..dir.."/cmdline")
        if f then
          local cmdline = f:read("*all")
          f:close()
          if cmdline ~= "" then
            coroutine.yield(cmdline)
          end
        end
      end
    end
  end
  return coroutine.wrap(yieldprocess)
end


function run_once(process, cmd)
  assert(type(process) == "string")
  local regex_killer = {
    ["+"]  = "%+", ["-"] = "%-",
    ["*"]  = "%*", ["?"]  = "%?"
  }

  for p in processwalker() do
    if p:find(process:gsub("[-+?*]", regex_killer)) then
      return
    end
  end
  return awful.spawn(cmd or process)
end

return setmetatable(module, { __call = function(_, ...) return run_once(...) end })
