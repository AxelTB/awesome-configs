local awful = require("awful")

return {
  runOnce={"nm-applet","urxvtd -q -f -o","xscreensaver -nosplash","skypeforlinux","google-chrome http://172.20.1.30:3542/gui"},
  terminal="mate-terminal",
  -- Random background path
  backgroundPath = os.getenv("HOME").."/wallpapers/",
  --terminal = 'mate-terminal',
  --modkey = 'Mod4',
  editor = 'gedit',
  layouts = {
      awful.layout.suit.tile            ,
      awful.layout.suit.max             ,
      awful.layout.suit.floating        ,
      awful.layout.suit.tile.left       ,
      awful.layout.suit.tile.bottom     ,
      awful.layout.suit.tile.top        ,
      awful.layout.suit.fair            ,
      awful.layout.suit.fair.horizontal ,
      awful.layout.suit.max.fullscreen  ,
      awful.layout.suit.magnifier       ,
  --     awful.layout.suit.treesome        ,
  }
}
