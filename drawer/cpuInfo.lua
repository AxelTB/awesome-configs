--- CpuInfo Module for Drawer
--- Last Edit 2017-10-19 by Axxx

--- Requires: lm-sensors
--- TODO:
--- 9: Fix topCpu core usage
--- 5: Close governor menu when cpuInfo closed
local setmetatable = setmetatable
local io           = io
local ipairs       = ipairs
local loadstring   = loadstring
local print        = print
local tonumber     = tonumber
local beautiful    = require( "beautiful"             )
local button       = require( "awful.button"          )
local widget2      = require( "awful.widget"          )
local config       = require( "forgotten"             )
local vicious      = require("vicious")
local menu         = require( "radical.context"       )
local util         = require( "awful.util"            )
local awful         = require( "awful"            )
local wibox        = require( "wibox"                 )
local themeutils   = require( "blind.common.drawing"  )
local radtab       = require( "radical.widgets.table" )
local embed        = require( "radical.embed"         )
local radical      = require( "radical"               )
local color        = require( "gears.color"           )
local allinone     = require( "widgets.allinone"      )
local fd_async     = require("utils.fd_async"         )

local data     = {}

--Menus
local procMenu , govMenu = nil, menu({arrow_type=radical.base.arrow_type.CENTERED})

local capi = { client = client }

local cpuInfoModule = {}

--TODO make them private again or remove
local modelWl
local cpuWidgetArrayL
local main_table

--LOCAL FUNCTIONS===============================================================
--Refresh all cpu usage widgets (Bar widget,graph and table)
--take vicious data
local function refreshCoreUsage(widget,content)
  --If menu created
  if cpuInfoModule.menu ~= nil then
    --Add current value to graph
    cpuInfoModule.volUsage:add_value(content[2])

    if cpuInfoModule.menu.visible then
      --Update table data only if visible
      for i=1, (data.coreN) do
        main_table[i][2]:set_text(string.format("%2.1f",content[i+1]))
      end
    end
  end
  --Set bar widget as global usage
  return content[1]
end

--Refreshes process list
local function refresh_process()
  local process={}
  --Load process information from script
  local topCpu=fd_async.exec.command(util.getdir("config")..'/drawer/Scripts/topCpu.sh')

  topCpu:connect_signal("new::line",function(content)

    if content ~= nil then
      table.insert(process,content:split(","))
    end
    procMenu:clear()
    if process then
      local procIcon = {}
      for k2,v2 in ipairs(capi.client.get()) do
        if v2.icon then
          procIcon[v2.class:lower()] = v2.icon
        end
      end
      for i=1,#process do
        local wdg = {}
        wdg.percent       = wibox.widget.textbox()
        wdg.percent.fit = function()
          return 42,procMenu.item_height
        end
        wdg.percent.draw = function(self, context, cr, width, height)
          cr:save()
          cr:set_source(color(procMenu.bg_alternate))
          cr:rectangle(0,0,width-height/2,height)
          cr:fill()
          cr:set_source_surface(themeutils.get_beg_arrow2({bg_color=procMenu.bg_alternate}),width-height/2,0)
          cr:paint()
          cr:restore()
          wibox.widget.textbox.draw(self, context, cr, width, height)
        end
        wdg.kill          = wibox.widget.imagebox()
        wdg.kill:set_image(config.iconPath .. "kill.png")
        wdg.kill:buttons(button({ }, 1, function (geo) awful.spawn("kill "..process[i][1]) print("kill "..process[i][1]) cpuInfoModule.toggle() end))

        --Show process and cpu load
        wdg.percent:set_text((process[i][2] or "N/A").."%")
        procMenu:add_item({text=process[i][3],suffix_widget=wdg.kill,prefix_widget=wdg.percent})
      end
    end
  end)
  topCpu:connect_signal("request::completed",function() print("TopCpu Complete") end )
end

--Save governor list to avoid recharge
local govList = nil

-- Generate governor list menu
local function generateGovernorMenu(cpuN)
  local govLabel

  if cpuN ~= nil then govLabel="Set Cpu"..cpuN.." Governor"
  else govLabel="Set global Governor" end

  if govList == nil then
    govList=radical.context{}

    fd_async.file.load('/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors'):connect_signal('request::completed',function(content)
      for i,gov in pairs(content:split(" ")) do
        print("G:",gov)
        --Generate menu list
        if gov:len() > 2 then
          govList:add_item {text=gov,button1=function(_menu,item,mods)
            for cpuI=0,data.coreN-1 do
              print('sudo cpufreq-set -c '..cpuI..' -g '..gov)
              awful.spawn('sudo cpufreq-set -c '..cpuI..' -g '..gov)
              govMenu.visible = false
            end
          end}
        end
      end
    end)
  end

  govMenu:add_item {text=govLabel,sub_menu=govList}
end


--Initialization function-------------------------------------------------------
--Executed on first menu open
local function init()
  --Load initial data
  print("Load initial data")

  --Create menu content
  local cpuModel            = wibox.widget.textbox()
  local spacer1             = wibox.widget.textbox()
  cpuInfoModule.volUsage    = wibox.widget.graph()

  --Evaluate core number------------------
  local pipe0 = io.popen("cat /proc/cpuinfo | grep processor | tail -n1 | grep -e'[0-9]*' -o")
  local coreN = pipe0:read("*all") or "0"
  pipe0:close()

  if coreN then
    data.coreN=(coreN+1)
    --print("Detected core number: ",data.coreN)
  else
    print("CpuInfo Error: Unable to load core number")
  end

  --Create CPUs Table
  topCpuW           = {}
  local emptyTable={};
  local tabHeader={};
  for i=1,data.coreN,1 do
    emptyTable[i]= {"","","",""}
    tabHeader[i]="Core "..(i-1)
  end
  local tab,widgets = radtab(emptyTable,
    {row_height=20,v_header = tabHeader,
    h_header = {"GHz","Used %","Temp","Governor"}
  })
  main_table = widgets --Needed for some unknown reason


  --Register cell table as vicious widgets
  for i=0, (data.coreN-1) do
    --Cpu Speed (Frequency in Ghz
    vicious.register(main_table[i+1][1], vicious.widgets.cpuinf,    function (widget, args)
      return string.format("%.2f", args['{cpu'..i..' ghz}'])
    end,2)
  --Governor
  vicious.register(main_table[i+1][4], vicious.widgets.cpufreq,'$5',5,"cpu"..i)
  end

  --Create menu structure
  modelWl = wibox.layout.fixed.horizontal()
  modelWl:add(cpuModel)
  cpuWidgetArrayL = wibox.container.margin()
  cpuWidgetArrayL:set_margins(3)
  cpuWidgetArrayL:set_bottom(10)
  cpuWidgetArrayL:set_widget(tab)

  --Load Cpu model
  cpuModel:set_text("Loading...")
  fd_async.exec.command(util.getdir("config")..'/drawer/Scripts/cpuName.sh'):connect_signal('request::completed',function(content)
      cpuModel:set_text(content)
      print ("CPU Name:",content)
  end)
  cpuModel.width     = 212

  cpuInfoModule.volUsage:set_width        ( 212                                  )
  cpuInfoModule.volUsage:set_height       ( 30                                   )
  cpuInfoModule.volUsage:set_scale        ( true                                 )
  cpuInfoModule.volUsage:set_border_color ( beautiful.fg_normal                  )
  cpuInfoModule.volUsage:set_color        ( beautiful.fg_normal                  )
  vicious.register( cpuInfoModule.volUsage, vicious.widgets.cpu,refreshCoreUsage,1 )
  --Generate governor list
  generateGovernorMenu()
  print("Init Ended")
end

-- Constructor==================================================================
local function new(args)
  --Functions-----------------------------------------------------------------
  --"Public" (Accessible from outside)
  --Toggle visibility (Return visibility)----

  --------------------------------------------------------------------------
  --Widget definition---------------------------------------------------------
  local rpb = wibox.widget.base.make_widget_declarative {
    {
      {
        icon    = config.iconPath .. "brain.png",
        vicious = {vicious.widgets.cpu,'$1',1},
        widget  = allinone,
      },
      bg     = beautiful.systray_bg or beautiful.bg_alternate or beautiful.bg_normal,
      widget = wibox.container.background
    },
    menu          = cpuInfoModule.toggle,
    vicious       = {vicious.widgets.cpu,'$1',1},
    border_color  = beautiful.bg_allinone or beautiful.bg_highlight,
    color         = beautiful.fg_allinone or beautiful.icon_grad or beautiful.fg_normal,
    widget        = wibox.container.radialprogressbar,
  }

  return rpb
end

--Metodi pubblici===============================================================
cpuInfoModule.refresh=function()
  --Update core(s) temperature
  local pipe0 = io.popen('sensors | grep "Core" | grep -e ": *+[0-9]*" -o| grep -e "[0-9]*" -o')
  local i=0
  for line in pipe0:lines() do
    main_table[i+1][3]:set_text(line.." °C")
    i=i+1
  end
  pipe0:close()

  refresh_process()
end

cpuInfoModule.toggle=function(parent_widget)

  print("Toggle")

  --Create menu at first load===================================================
  if not cpuInfoModule.menu then
    procMenu = embed({max_items=6})
    init()

    local imb = wibox.widget.imagebox()
    imb:set_image(beautiful.path .. "Icon/reload.png")
    imb:buttons(button({ }, 1, function (geo) cpuInfoModule.refresh() end))

    cpuInfoModule.menu = menu({item_width=198,width=200,arrow_type=radical.base.arrow_type.CENTERED})
    cpuInfoModule.menu:add_embeded_menu(govMenu)
    cpuInfoModule.menu:add_widget(radical.widgets.header(cpuInfoModule.menu,"INFO")  , {height = 20  , width = 200})
    cpuInfoModule.menu:add_widget(modelWl         , {height = 40  , width = 200})
    cpuInfoModule.menu:add_widget(radical.widgets.header(cpuInfoModule.menu,"USAGE")   , {height = 20  , width = 200})
    cpuInfoModule.menu:add_widget(cpuInfoModule.volUsage        , {height = 30  , width = 200})
    cpuInfoModule.menu:add_widget(cpuWidgetArrayL         , {width = 200})
    cpuInfoModule.menu:add_widget(radical.widgets.header(cpuInfoModule.menu,"PROCESS",{suffix_widget=imb}) , {height = 20  , width = 200})
    cpuInfoModule.menu:add_embeded_menu(procMenu)
  end

  --If opening refresh
  if not cpuInfoModule.menu.visible then
    cpuInfoModule.refresh()
    print("CPUInfo: open")
  end
  --         cpuInfoModule.menu.visible = visibility or (not cpuInfoModule.menu.visible)
  return cpuInfoModule.menu
end

return setmetatable(cpuInfoModule, { __call = function(_, ...) return new(...) end })
-- kate: space-indent on; indent-width 4; replace-tabs on;
