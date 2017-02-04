local lgi  = require     'lgi'
local wirefu = require("wirefu")
local GLib = lgi.require 'GLib'

wirefu.SYSTEM.org.freedesktop.UPower("/org/freedesktop/UPower").HibernateAllowed():get(function (work)
    print("It worked:",work)
end)

wirefu.SYSTEM.org.freedesktop.UPower("/org/freedesktop/UPower").Changed:connect(function (work)
    print("STATUS CHANGED")
end)

print("async")


wirefu.SYSTEM.org.freedesktop.UPower("/org/freedesktop/UPower/devices/DisplayDevice").org.freedesktop.UPower.Device.Energy:get(function (work)
    print("ENERGY:",work)
end)
--local main_loop = GLib.MainLoop()
--main_loop:run()
