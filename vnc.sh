#!/bin/bash
set -e
#虚拟屏幕
Xvfb :0 -screen 0 1920x1080x24 -listen tcp -ac +extension GLX +extension RENDER > /dev/null 2>&1 &
#vnc服务器
x11vnc -forever -shared -noipv6 -passwd tsjsdbd > /dev/null 2>&1 &
#novnc
websockify --web /usr/share/novnc 8080 localhost:5900 > /dev/null 2>&1 &