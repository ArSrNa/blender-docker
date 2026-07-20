#!/bin/bash
Xvfb :0 -screen 0 1920x960x24 -listen tcp -ac +extension GLX +extension RENDER &
x11vnc -display :0.0 -forever -shared -rfbport 5900 -passwd $VNC_PASSWORD &
websockify --web /usr/share/novnc 80 localhost:5900 &
startplasma-x11 &