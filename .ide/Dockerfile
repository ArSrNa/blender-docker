FROM docker.cnb.cool/arsrna/blender-docker/blender:3.6.14

# 安装 code-server 和 vscode 常用插件
RUN curl -fsSL https://code-server.dev/install.sh | sh \
	&& code-server --install-extension redhat.vscode-yaml \
	&& code-server --install-extension dbaeumer.vscode-eslint \
	&& code-server --install-extension eamodio.gitlens \
	&& code-server --install-extension tencent-cloud.coding-copilot \
	&& code-server --install-extension cnbcool.cnb-welcome \
	&& code-server --install-extension ms-azuretools.vscode-docker \