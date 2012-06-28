----------------------------------------------------------------------------
-- @author koniu &lt;gkusnierz@gmail.com&gt;
-- @copyright 2008 koniu
-- @release v3.4-rc3
----------------------------------------------------------------------------

-- Package environment
local pairs = pairs
local ipairs = ipairs
local print = print
local setmetatable = setmetatable
local table = table
local type = type
local string = string
local capi = { screen = screen,
               awesome = awesome,
               dbus = dbus,
               widget = widget,
               wibox = wibox,
               image = image,
               timer = timer }
local button = require("awful.button")
local util = require("awful.util")
local tools = require("utils.tools")
local tag = require("awful.tag")
local bt = require("beautiful")
local layout = require("awful.widget.layout")

--- Notification library
module("naughty")

local commonTimer = capi.timer({ timeout = 0.0333 })
local timerEvent = {}
local loopCounter =0
commonTimer:add_signal("timeout", function () 
    print("loop")
    if type(timerEvent[1]) == "function" then
        if timerEvent[1]() == false then
            timerEvent[1] = nil
            loopCounter = 0
        end
    end
    loopCounter = loopCounter + 1
    
    --Prevent infinite loop due to pango error or something like that
    if loopCounter > 40 then
        timerEvent[1] = nil
        loopCounter = 0
    end
    if #timerEvent == 0 then
        commonTimer:stop()
    end
end)

function addTimerEvent(func)
    table.insert(timerEvent,func)
    if not commonTimer.started then
        commonTimer:start()
    end
end

--- Naughty configuration - a table containing common popup settings.
-- @name config
-- @field padding Space between popups and edge of the workarea. Default: 4
-- @field spacing Spacing between popups. Default: 1
-- @field icon_dirs List of directories that will be checked by getIcon()
--   Default: { "/usr/share/pixmaps/", }
-- @field icon_formats List of formats that will be checked by getIcon()
--   Default: { "png", "gif" }
-- @field default_preset Preset to be used by default.
--   Default: config.presets.normal
-- @class table

config = {}
widgets = {} --List of wibox widgets, if any (popups -not- included)
config.init = false --Is the dbus connection open?
config.padding = 4
config.spacing = 1
config.icon_dirs = { "/usr/share/pixmaps/", }
config.icon_formats = { "png", "gif" }


--- Notification Presets - a table containing presets for different purposes
-- Preset is a table of any parameters available to notify()
-- You have to pass a reference of a preset in your notify() call to use the preset
-- At least the default preset named "normal" has to be defined
-- The presets "low", "normal" and "critical" are used for notifications over DBUS
-- @name config.presets
-- @field low The preset for notifications with low urgency level
-- @field normal The default preset for every notification without a preset that will also be used for normal urgency level
-- @field critical The preset for notifications with a critical urgency level
-- @class table

config.presets = {
    normal = {},
    low = {
        timeout = 5
    },
    critical = {
        bg = "#ff0000",
        fg = "#ffffff",
        timeout = 0,
    }
}

config.default_preset = config.presets.normal

-- DBUS Notification constants
urgency = {
    low = "\0",
    normal = "\1",
    critical = "\2"
}

--- DBUS notification to preset mapping
-- @name config.mapping
-- The first element is an object containing the filter
-- If the rules in the filter matches the associated preset will be applied
-- The rules object can contain: urgency, category, appname
-- The second element is the preset

config.mapping = {
    {{urgency = urgency.low}, config.presets.low},
    {{urgency = urgency.normal}, config.presets.normal},
    {{urgency = urgency.critical}, config.presets.critical}
}

-- Counter for the notifications
-- Required for later access via DBUS
local counter = 1

--- Index of notifications. See config table for valid 'position' values.
-- Each element is a table consisting of:
-- @field box Wibox object containing the popup
-- @field height Popup height
-- @field width Popup width
-- @field die Function to be executed on timeout
-- @field id Unique notification id based on a counter
-- @name notifications[screen][position]
-- @class table

notifications = {}
for s = 1, capi.screen.count() do
    notifications[s] = {
        top_left = {},
        top_right = {},
        bottom_left = {},
        bottom_right = {},
    }
end

function new(args)
  local w = {}
  w.widget = capi.widget({ type = "textbox", align = "right" })
  w.widget.width = 400
  table.insert(widgets, w)
  return w.widget
end

-- Evaluate desired position of the notification by index - internal
-- @param idx Index of the notification
-- @param position top_right | top_left | bottom_right | bottom_left
-- @param height Popup height
-- @param width Popup width (optional)
-- @return Absolute position and index in { x = X, y = Y, idx = I } table
local function get_offset(screen, position, idx, width, height)
    local ws = capi.screen[screen].workarea
    local v = {}
    local idx = idx or #notifications[screen][position] + 1
    local width = width or notifications[screen][position][idx].width

    -- calculate x
    if position:match("left") then
        v.x = ws.x + config.padding
    else
        v.x = ws.x + ws.width - (width + config.padding)
    end

    -- calculate existing popups' height
    local existing = 0
    for i = 1, idx-1, 1 do
        existing = existing + notifications[screen][position][i].height + config.spacing
    end

    -- calculate y
    if position:match("top") then
        v.y = ws.y + config.padding + existing
    else
        v.y = ws.y + ws.height - (config.padding + height + existing)
    end

    -- if positioned outside workarea, destroy oldest popup and recalculate
    if v.y + height > ws.y + ws.height or v.y < ws.y then
        idx = idx - 1
        destroy(notifications[screen][position][1])
        v = get_offset(screen, position, idx, width, height)
    end
    if not v.idx then v.idx = idx end

    return v
end

-- Re-arrange notifications according to their position and index - internal
-- @return None
local function arrange(screen)
    for p,pos in pairs(notifications[screen]) do
        for i,notification in pairs(notifications[screen][p]) do
            local offset = get_offset(screen, p, i, notification.width, notification.height)
            notification.box:geometry({ x = offset.x, y = offset.y })
            notification.idx = offset.idx
        end
    end
end

--- Destroy notification by index
-- @param notification Notification object to be destroyed
-- @return True if the popup was successfully destroyed, nil otherwise
function destroy(notification)
    if not notification or not notification.box then
      return 
    end
    
    if notification and notification.box and notification.box.screen then
        local scr = notification.box.screen
        table.remove(notifications[notification.box.screen][notification.position], notification.idx)
        if notification.timer then
            notification.timer:stop()
        end
        notification.box.screen = nil
        arrange(scr)
        return true
    end
end

-- Get notification by ID
-- @param id ID of the notification
-- @return notification object if it was found, nil otherwise
local function getById(id)
    -- iterate the notifications to get the notfications with the correct ID
    for s = 1, capi.screen.count() do
        for p,pos in pairs(notifications[s]) do
            for i,notification in pairs(notifications[s][p]) do
                if notification.id == id then
                    return notification
                 end
            end
        end
    end
end

-- Search for an icon in specified directories with a specified format
-- @param icon Name of the icon
-- @return full path of the icon, or nil of no icon was found
local function getIcon(name)
    for d, dir in pairs(config.icon_dirs) do
        for f, format in pairs(config.icon_formats) do
            local icon = dir .. name .. "." .. format
            if util.file_readable(icon) then
                return icon
            end
        end
    end
end

function notify_hidden(pid,title,text)
  local found = false
  for s =1,capi.screen.count() do
    for k,c in pairs(tag.selected(s):clients()) do
      if c.pid == pid then
        return
      end
    end
  end
  
  notify({text=text,title=title})
end

--- Create notification. args is a dictionary of (optional) arguments.
-- @param text Text of the notification. Default: ''
-- @param title Title of the notification. Default: nil
-- @param timeout Time in seconds after which popup expires.
--   Set 0 for no timeout. Default: 5
-- @param hover_timeout Delay in seconds after which hovered popup disappears.
--   Default: nil
-- @param screen Target screen for the notification. Default: 1
-- @param position Corner of the workarea displaying the popups.
--   Values: "top_right" (default), "top_left", "bottom_left", "bottom_right".
-- @param ontop Boolean forcing popups to display on top. Default: true
-- @param height Popup height. Default: nil (auto)
-- @param width Popup width. Default: nil (auto)
-- @param font Notification font. Default: beautiful.font or awesome.font
-- @param icon Path to icon. Default: nil
-- @param icon_size Desired icon size in px. Default: nil
-- @param fg Foreground color. Default: beautiful.fg_focus or '#ffffff'
-- @param bg Background color. Default: beautiful.bg_focus or '#535d6c'
-- @param border_width Border width. Default: 1
-- @param border_color Border color.
--   Default: beautiful.border_focus or '#535d6c'
-- @param run Function to run on left click. Default: nil
-- @param preset Table with any of the above parameters. Note: Any parameters
--   specified directly in args will override ones defined in the preset.
-- @param replaces_id Replace the notification with the given ID
-- @param callback function that will be called with all arguments
--  the notification will only be displayed if the function returns true
--  note: this function is only relevant to notifications sent via dbus
-- @usage naughty.notify({ title = "Achtung!", text = "You're idling", timeout = 0 })
-- @return The notification object
function notify(args)
    -- gather variables together
    local preset = args.preset or config.default_preset or {}
    local timeout = args.timeout or preset.timeout or 5
    local icon = args.icon or preset.icon
    local icon_size = args.icon_size or preset.icon_size
    local text = args.text or preset.text or ""
    local title = args.title or preset.title
    local screen = args.screen or preset.screen or 1
    local ontop = args.ontop or preset.ontop or true
    local width = args.width or preset.width
    local height = args.height or preset.height
    local hover_timeout = args.hover_timeout or preset.hover_timeout
    local opacity = args.opacity or preset.opacity
    local margin = args.margin or preset.margin or "5"
    local border_width = args.border_width or preset.border_width or "1"
    local position = args.position or preset.position or "top_right"

    -- beautiful
    local beautiful = bt.get()
    local font = args.font or preset.font or beautiful.font or capi.awesome.font
    local fg = args.fg or preset.fg or beautiful.fg_normal or '#ffffff'
    local bg = args.bg or preset.bg or beautiful.bg_normal or '#535d6c'
    local border_color = args.border_color or preset.border_color or beautiful.bg_focus or '#535d6c'
    local notification = {}

    -- replace notification if needed
    if args.replaces_id then
        obj = getById(args.replaces_id)
        if obj then
            -- destroy this and ...
            destroy(obj)
        end
        -- ... may use its ID
        if args.replaces_id < counter then
            notification.id = args.replaces_id
        else
            counter = counter + 1
            notification.id = counter
        end
    else
        -- get a brand new ID
        counter = counter + 1
        notification.id = counter
    end

    notification.position = position

    if title then title = title .. "\n" else title = "" end

    -- hook destroy
    local newTitle = tools.stripHtml(string.gsub(title, "\n", " - "))
    local newText = tools.stripHtml(string.gsub(text, "\n", " - "))
    local die = function (timer) 
        destroy(notification) 
        if #widgets > 0 then
            if args.noslider ~= true then
                addTimerEvent(function () 
                    --for k, w in ipairs(widgets) do
                    if widgets[1] then
                        local w = widgets[1]
                        if (w.opacity < 110 and w.opacity ~= nil) then
                            w.widget.text = string.format('<span rise="%s" font_desc="%s"><b>%s</b>%s</span>', 0-(w.opacity*100), font, newTitle, newText)
                            w.opacity = w.opacity + 3
                        else
                            w.widget.text = ""
                            return false
                        end
                    end
                end)
            end
        end
        if timer and timer.started then
            timer:stop()
        end
    end
    if timeout > 0 then
        if notification.timer and notification.timer.started then
            notification.timer:stop()
        end
        local timer_die = capi.timer { timeout = timeout }
        timer_die:add_signal("timeout", function() die(timer_die) end)
        timer_die:start()
        notification.timer = timer_die
    end
    notification.die = die

    local run = function ()
        if args.run then
            args.run(notification)
        else
            die()
        end
    end

    local hover_destroy = function ()
        if hover_timeout == 0 then
            die()
        else
            if notification.timer then notification.timer:stop() end
            notification.timer = capi.timer { timeout = hover_timeout }
            notification.timer:add_signal("timeout", die)
            notification.timer:start()
        end
    end
    
    -- show in existing widgets
    if args.noslider ~= true and #widgets > 0 then
        addTimerEvent(function () 
--             for k, w in ipairs(widgets) do
            if widgets[1] then
                local w = widgets[1]
                if w.opacity == nil then
                    w.text_real = text
                    w.opacity = 100
                end
                    
                if w.opacity > 0 then
                    w.widget.text = string.format('<span rise="%s" font_desc="%s"><b>%s</b>%s</span>', (w.opacity*100), font, newTitle, newText)
                    w.opacity = w.opacity - 3
                else
                    return false
                end
            end
        end)
    end
    -- create textbox
    local textbox = capi.widget({ type = "textbox", align = "flex" })
    textbox:buttons(util.table.join(button({ }, 1, run), button({ }, 3, die)))
    layout.margins[textbox] = { right = margin, left = margin, bottom = margin, top = margin }
    textbox.text = string.format('<span font_desc="%s"><b>%s</b>%s</span>', font, newTitle, newText)
    textbox.valign = "middle"

    -- create iconbox
    local iconbox = nil
    if icon then
        -- try to guess icon if the provided one is non-existent/readable
        if type(icon) == "string" and not util.file_readable(icon) then
            icon = getIcon(icon)
        end

        -- if we have an icon, use it
        if icon then
            iconbox = capi.widget({ type = "imagebox", align = "left" })
            layout.margins[iconbox] = { right = margin, left = margin, bottom = margin, top = margin }
            iconbox:buttons(util.table.join(button({ }, 1, run), button({ }, 3, die)))
            local img
            if type(icon) == "string" then
                img = capi.image(icon)
            else
                img = icon
            end
            if icon_size then
                img = img:crop_and_scale(0,0,img.height,img.width,icon_size,icon_size)
            end
            iconbox.resize = false
            iconbox.image = img
        end
    end

    -- create container wibox
    notification.box = capi.wibox({ fg = fg,
                                    bg = bg,
                                    border_color = border_color,
                                    border_width = border_width })

    if hover_timeout then notification.box:add_signal("mouse::enter", hover_destroy) end

    -- calculate the height
    if not height then
        if iconbox and iconbox:extents().height + 2 * margin > textbox:extents().height + 2 * margin then
            height = iconbox:extents().height + 2 * margin
        else
            height = textbox:extents().height + 2 * margin
        end
    end

    -- calculate the width
    if not width then
        width = textbox:extents().width + (iconbox and iconbox:extents().width + 2 * margin or 0) + 2 * margin
    end

    -- crop to workarea size if too big
    local workarea = capi.screen[screen].workarea
    if width > workarea.width - 2 * (border_width or 0) - 2 * (config.padding or 0) then
        width = workarea.width - 2 * (border_width or 0) - 2 * (config.padding or 0)
    end
    if height > workarea.height - 2 * (border_width or 0) - 2 * (config.padding or 0) then
        height = workarea.height - 2 * (border_width or 0) - 2 * (config.padding or 0)
    end

    -- set size in notification object
    notification.height = height + 2 * (border_width or 0)
    notification.width = width + 2 * (border_width or 0)

    -- position the wibox
    local offset = get_offset(screen, notification.position, nil, notification.width, notification.height)
    notification.box.ontop = ontop
    notification.box:geometry({ width = width,
                                height = height,
                                x = offset.x,
                                y = offset.y })
    notification.box.opacity = opacity
    notification.box.screen = screen
    notification.idx = offset.idx

    -- populate widgets
    if not notification.box.widgets or #notification.box.widgets == 0 then
        notification.box.widgets = { iconbox, textbox, ["layout"] = layout.horizontal.leftright }
    end

    -- insert the notification to the table
    table.insert(notifications[screen][notification.position], notification)

    -- return the notification
    return notification
end

-- DBUS/Notification support
-- Notify
if capi.dbus then
    capi.dbus.add_signal("org.freedesktop.Notifications", function (data, appname, replaces_id, icon, title, text, actions, hints, expire)
    args = { preset = { } }
    if data.member == "Notify" then
        if text ~= "" then
            args.text = text
            if title ~= "" then
                args.title = title
            end
        else
            if title ~= "" then
                args.text = title
            else
                return nil
            end
        end
        local score = 0
        for i, obj in pairs(config.mapping) do
            local filter, preset, s = obj[1], obj[2], 0
            if (not filter.urgency or filter.urgency == hints.urgency) and
               (not filter.category or filter.category == hints.category) and
               (not filter.appname or filter.appname == appname) then
                for j, el in pairs(filter) do s = s + 1 end
                if s > score then
                    score = s
                    args.preset = preset
                end
            end
        end
        if not args.preset.callback or (type(args.preset.callback) == "function" and
            args.preset.callback(data, appname, replaces_id, icon, title, text, actions, hints, expire)) then
            if icon ~= "" then
                args.icon = icon
            elseif hints.icon_data then
                -- icon_data is an array:
                -- 1 -> width, 2 -> height, 3 -> rowstride, 4 -> has alpha
                -- 5 -> bits per sample, 6 -> channels, 7 -> data

                local imgdata
                -- If has alpha (ARGB32)
                if hints.icon_data[6] == 4 then
                    imgdata = hints.icon_data[7]
                -- If has not alpha (RGB24)
                elseif hints.icon_data[6] == 3 then
                    imgdata = ""
                    for i = 1, #hints.icon_data[7], 3 do
                        imgdata = imgdata .. hints.icon_data[7]:sub(i , i + 2):reverse()
                        imgdata = imgdata .. string.format("%c", 255) -- alpha is 255
                    end
                end
                if imgdata then
                    args.icon = capi.image.argb32(hints.icon_data[1], hints.icon_data[2], imgdata)
                end
            end
            if replaces_id and replaces_id ~= "" and replaces_id ~= 0 then
                args.replaces_id = replaces_id
            end
            if expire and expire > -1 then
                args.timeout = expire / 1000
            end
            local id = notify(args).id
            return "u", id
        end
        return "u", "0"
    elseif data.member == "CloseNotification" then
        local obj = getById(arg1)
        if obj then
           destroy(obj)
        end
    elseif data.member == "GetServerInfo" or data.member == "GetServerInformation" then
        -- name of notification app, name of vender, version
        return "s", "naughty", "s", "awesome", "s", capi.awesome.version:match("%d.%d"), "s", "1.0"
    end
    end)

    capi.dbus.add_signal("org.freedesktop.DBus.Introspectable",
    function (data, text)
    if data.member == "Introspect" then
        local xml = [=[<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object
    Introspection 1.0//EN"
    "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    <node>
      <interface name="org.freedesktop.DBus.Introspectable">
        <method name="Introspect">
          <arg name="data" direction="out" type="s"/>
        </method>
      </interface>
      <interface name="org.freedesktop.Notifications">
        <method name="CloseNotification">
          <arg name="id" type="u" direction="in"/>
        </method>
        <method name="Notify">
          <arg name="app_name" type="s" direction="in"/>
          <arg name="id" type="u" direction="in"/>
          <arg name="icon" type="s" direction="in"/>
          <arg name="summary" type="s" direction="in"/>
          <arg name="body" type="s" direction="in"/>
          <arg name="actions" type="as" direction="in"/>
          <arg name="hints" type="a{sv}" direction="in"/>
          <arg name="timeout" type="i" direction="in"/>
          <arg name="return_id" type="u" direction="out"/>
        </method>
        <method name="GetServerInformation">
          <arg name="return_name" type="s" direction="out"/>
          <arg name="return_vendor" type="s" direction="out"/>
          <arg name="return_version" type="s" direction="out"/>
          <arg name="return_spec_version" type="s" direction="out"/>
        </method>
        <method name="GetServerInfo">
          <arg name="return_name" type="s" direction="out"/>
          <arg name="return_vendor" type="s" direction="out"/>
          <arg name="return_version" type="s" direction="out"/>
       </method>
      </interface>
    </node>]=]
        return "s", xml
    end
    end)

    -- listen for dbus notification requests
    capi.dbus.request_name("session", "org.freedesktop.Notifications")
end

setmetatable(_M, { __call = function(_, ...) return new(...) end })

-- vim: filetype=lua:expandtab:shiftwidth=4:tabstop=8:softtabstop=4:encoding=utf-8:textwidth=80
