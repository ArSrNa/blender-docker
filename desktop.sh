#!/bin/bash
# Ubuntu 桌面环境 + noVNC 安装脚本
# 适用于 Docker 容器

export DEBIAN_FRONTEND=noninteractive
export TZ=Asia/Shanghai

set -e

echo "=========================================="
echo "Ubuntu Desktop + noVNC 安装脚本"
echo "=========================================="

# 1. 更新包列表
echo "[1/7] 更新包列表..."
apt update

# 2. 安装基础桌面环境（轻量级 Xfce）
echo "[2/7] 安装 Xfce 桌面环境..."
apt install -y \
    xfce4 \
    xfce4-goodies \
    xorg \
    x11vnc \
    xvfb \
    dbus-x11 \
    --no-install-recommends

# 3. 安装 noVNC
echo "[3/7] 安装 noVNC..."
apt install -y \
    git \
    wget \
    python3 \
    python3-websockify \
    python3-numpy

# 下载 noVNC
cd /opt
if [ ! -d "/opt/novnc" ]; then
    git clone https://github.com/novnc/noVNC.git /opt/novnc
    git clone https://github.com/novnc/websockify.git /opt/novnc/utils/websockify
fi

# 4. 安装中文字体（可选，避免中文乱码）
echo "[4/7] 安装中文字体..."
apt install -y \
    fonts-wqy-zenhei \
    fonts-wqy-microhei \
    fonts-noto-cjk \
    --no-install-recommends

# 5. 安装必要的图形库
echo "[5/7] 安装图形依赖..."
apt install -y \
    libgl1-mesa-glx \
    libgl1-mesa-dri \
    mesa-utils \
    x11-utils \
    xauth \
    --no-install-recommends

# 6. 配置 Xvfb 和 VNC
echo "[6/7] 配置 VNC 服务..."

# 创建启动脚本
cat > /usr/local/bin/start-desktop.sh << 'EOF'
#!/bin/bash
# 启动桌面环境脚本

export DISPLAY=:1
export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p /tmp/runtime-root
chmod 700 /tmp/runtime-root

# 清理之前的锁文件
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# 启动 Xvfb（虚拟帧缓冲）
Xvfb :1 -screen 0 1280x720x24 -ac +extension GLX +extension RANDR &

# 等待 Xvfb 启动
sleep 3

# 启动 Xfce 桌面
export DISPLAY=:1
startxfce4 &

# 等待桌面启动
sleep 3

# 启动 noVNC
cd /opt/novnc
./utils/novnc_proxy --vnc localhost:5900 --listen 8080 &

echo "=========================================="
echo "桌面环境已启动！"
echo "访问地址: http://localhost:8080/vnc.html"
echo "=========================================="

# 保持进程运行
tail -f /dev/null
EOF

chmod +x /usr/local/bin/start-desktop.sh

# 7. 创建 VNC 密码（可选，这里设置空密码）
echo "[7/7] 配置 VNC 服务..."
cat > /usr/local/bin/start-vnc.sh << 'EOF'
#!/bin/bash
export DISPLAY=:1
x11vnc -display :1 -forever -nopw -shared -nevershared -xrandr &
EOF

chmod +x /usr/local/bin/start-vnc.sh

# 清理
apt clean
rm -rf /var/lib/apt/lists/*

echo "=========================================="
echo "✅ 安装完成！"
echo ""
echo "使用方法："
echo "1. 启动桌面: /usr/local/bin/start-desktop.sh"
echo "2. 浏览器访问: http://localhost:8080/vnc.html"
echo ""
echo "如果要在后台运行:"
echo "   nohup /usr/local/bin/start-desktop.sh &"
echo "=========================================="