local ipairs       = ipairs
local pairs        = pairs
local print        = print
local wibox        = require( "awful.wibox"       )
local common       = require( "ultiLayout.common" )
local titlebar     = require( "ultiLayout.widgets.titlebar"  )

module("ultiLayout.layouts.stack")

local titlebars = {}

function titlebar_to_cg(titlebar)
    return titlebars[titlebar]
end

function new(cg)
   local cg       = cg or nil
   local data     = {}
   local nb       = 0
   local activeCg = nil
   local tb       = nil
   local tabs     = {}
   cg.swapable    = true
   
   function data:update()
       for k,v in ipairs(cg:childs()) do
           if tb and cg.width > 0 then
               tb.wibox.x       = cg.x
               tb.wibox.y       = cg.y
               tb.wibox.width   = cg.width
               tb.wibox.visible = true
           elseif tb then
               tb.wibox.visible = false
           end
           v:geometry({width  = cg.width, height = cg.height-16, x = cg.x, y = cg.y+16})
           v:repaint()
       end
   end
   
    function data:gen_edge(edge_list)
        if activeCg then
            activeCg:gen_edge(edge_list)
        end
        return edge_list
    end
   
    function data:show_splitters(show,horizontal,vertical) end
    
    function data:set_active(sub_cg)
        if activeCg ~= nil then
            tabs[activeCg].selected = false
        end
        for k,v in pairs(cg:childs()) do
            v.visible = v == sub_cg
        end
        activeCg = sub_cg
        tabs[activeCg].selected = true
        tb.tablist:update()
        --cg:emit_signal("active::changed")
    end

    function data:add_child(child_cg)
        activeCg = child_cg
        if not tb then
            tb = titlebar.create_from_cg(cg)
            common.register_wibox(tb.wibox,cg,function(new_cg) cg:attach(new_cg) end)
            tb.wibox.ontop = true
            tb.wibox.bg    = "#ff0000"
            titlebars[tb] = cg
        end
        tabs[child_cg] = tb.tablist:add_tab_cg(child_cg)
        
        local function swap(_cg,other_cg,old_parent)
            if _cg.parent ~= cg then
                _cg:remove_signal("cg::swapped",swap) --TODO name changed
                tabs[_cg].clientgroup = other_cg
                other_cg:add_signal("cg::swapped",swap)
                tabs[other_cg] = tabs[_cg]
                tabs[_cg] = nil
                tabs[other_cg]:update()
            end
        end
        child_cg:add_signal("cg::swapped",swap)
        nb = nb + 1
        local percent = 1 / nb
        return child_cg
    end
    
    local function visibility_changed(_cg,value)
       if tb then
           tb.wibox.visible = value
       end
    end
    cg:add_signal("visibility::changed",visibility_changed)
    
    cg:add_signal("destroyed",function()
        titlebars[tb]    = nil
        tb.wibox.visible = false
        tb.wibox         = nil
        tb.tablist       = nil
        tb               = nil
    end)
    
    cg:add_signal("detached",function(_cg,child)
        if tb ~= nil and tb.tablist ~= nil and tabs[child] then
            tb.tablist:remove_tab(tabs[child])
            tabs[child] = nil
            if #cg:childs() > 0 then
                data:set_active(cg:childs()[1])
            end
        else
            print("Error stack")
        end
    end)
   
    return data
end

common.add_new_layout("stack",new)