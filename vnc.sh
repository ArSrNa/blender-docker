#!/bin/bash
set -e
#虚拟屏幕
Xvfb :0 -screen 0 1280x720 -listen tcp -ac +extension GLX +extension RENDER > /dev/null 2>&1 &
#vnc服务器
x11vnc -display :0 -forever -shared -rfbport 5900 -passwd cnb666 > /dev/null 2>&1 &
#novnc
websockify --web /usr/share/novnc 8080 localhost:5900 > /dev/null 2>&1 &