local radical  = require("radical")
local fd_async = require("utils.fd_async")
local util     = require("awful.util")
local spawn    = require("awful.spawn")
local module = {}

local function spawn_location(location)
  spawn("xdg-open "..location)
end

local function load_folder(parent,path,args,item_args)
  fd_async.directory.scan(path,{attributes={"FILE_ATTRIBUTE_STANDARD_NAME","FILE_ATTRIBUTE_STANDARD_TYPE","FILE_ATTRIBUTE_STANDARD_IS_HIDDEN"}}):connect_signal("request::completed",function(list)
    for k,v in ipairs(list) do
      local ftype,name,m = v["FILE_ATTRIBUTE_STANDARD_TYPE"],v["FILE_ATTRIBUTE_STANDARD_NAME"],nil
      if v["FILE_ATTRIBUTE_STANDARD_IS_HIDDEN"] ~= "TRUE" then
        if ftype == "2" then
          m = radical.context( util.table.join({},args) )
          parent:add_item(util.table.join({text=name,sub_menu= m and (function() load_folder(m,path.."/"..name,args,item_args);return m end) or nil, button1=function() spawn_location(path.."/"..name) end},item_args))
        else
          parent:add_item(util.table.join({text=name,button1=function() spawn_location(path.."/"..name) end, item_args}))
        end

      end
      --parent:add_item(util.table.join({text=name,sub_menu= m and (function() load_folder(m,path.."/"..name,args,item_args);return m end) or nil},item_args))
    end
  end)
end

function module.path(path,args,item_args)
  local m = radical.context( util.table.join({},args) )
  load_folder(m,path,args,item_args)
  return m
end

return module
-- kate: space-indent on; indent-width 2; replace-tabs on;
