# FRPC Manager

一个功能强大的 FRPC（Fast Reverse Proxy Client）安装和管理脚本，支持主流 Linux 系统，提供自动安装、更新、监控等功能。

## 📋 功能特性

- **自动安装**：支持 Debian/Ubuntu、CentOS/RHEL/Fedora、Arch Linux 等主流 Linux 系统
- **智能更新**：自动检测并更新到最新版本的 FRPC
- **多服务管理**：支持管理多个 FRPC 服务实例（frpc1 到 frpc10）
- **配置文件支持**：支持 ini、json、yaml、toml 格式的配置文件
- **自动转换**：将 ini 格式配置文件自动转换为 toml 格式
- **服务监控**：内置日志监控脚本，定期检查服务状态并自动重启
- **定时任务**：配置 crontab 定时任务，每 5 分钟检查一次服务状态
- **日志管理**：详细的安装日志和监控日志，便于排查问题
- **临时目录处理**：使用临时目录处理文件提取，避免目录冲突

## 🚀 快速开始

### 环境要求

- Linux 系统（Debian/Ubuntu、CentOS/RHEL/Fedora、Arch Linux）
- root 用户权限
- 网络连接（用于下载 FRPC 程序）

### 安装步骤

1. **下载脚本**

```bash
git clone https://github.com/yourusername/frpc-installer.git
cd frpc-installer
```

2. **准备配置文件**

在脚本目录中创建配置文件，支持以下格式：
- `frpc1.ini`、`frpc1.json`、`frpc1.yaml`、`frpc1.toml`
- `frpc2.ini`、`frpc2.json`、`frpc2.yaml`、`frpc2.toml`
- ...
- `frpc10.ini`、`frpc10.json`、`frpc10.yaml`、`frpc10.toml`

3. **运行脚本**

```bash
chmod +x install_frpc.sh
./install_frpc.sh
```

4. **自动安装流程**

脚本会自动执行以下操作：
- 检查系统环境和包管理器
- 安装必要依赖（curl、git、systemd）
- 创建安装目录
- 检测系统架构
- 检查并更新 FRPC 版本
- 复制配置文件和二进制文件
- 创建 systemd 服务
- 启动并启用服务
- 创建监控脚本
- 配置定时任务

## 📁 目录结构

```
/usr/local/frpc/
├── bin/           # FRPC 可执行文件
├── config/        # 配置文件目录
└── monitor_frpc.sh # 监控脚本

/var/log/frpc/     # 日志目录
├── install.log    # 安装日志
├── frpc1.log      # frpc1 监控日志
├── frpc2.log      # frpc2 监控日志
└── ...

/etc/systemd/system/
├── frpc1.service  # frpc1 服务文件
├── frpc2.service  # frpc2 服务文件
└── ...
```

## 🎯 使用方法

### 主菜单功能

运行脚本后，会进入主菜单，提供以下功能：

1. **安装/更新 FRPC 服务**：执行完整的安装流程
2. **查看所有服务运行状态**：显示所有 FRPC 服务的运行状态
3. **管理单个服务**：管理指定的 FRPC 服务（启动、停止、重启、查看状态、查看日志）
4. **管理所有服务**：批量管理所有 FRPC 服务
5. **查看服务日志**：查看指定服务的系统日志
6. **检测并更新 FRPC 版本**：检查并更新 FRPC 到最新版本
7. **查看监控脚本日志**：查看监控脚本的运行日志
8. **查看安装日志**：查看安装过程的详细日志

### 服务管理命令

```bash
# 启动服务
systemctl start frpc1

# 停止服务
systemctl stop frpc1

# 重启服务
systemctl restart frpc1

# 查看服务状态
systemctl status frpc1

# 查看服务日志
journalctl -u frpc1 -n 50

# 手动运行监控脚本
/usr/local/frpc/monitor_frpc.sh
```

## ⚙️ 配置文件说明

### 支持的配置格式

- **INI 格式**：传统的 INI 格式，脚本会自动转换为 TOML 格式
- **JSON 格式**：标准的 JSON 格式
- **YAML 格式**：简洁的 YAML 格式
- **TOML 格式**：现代的 TOML 格式（推荐）

### 配置示例（TOML 格式）

```toml
# frpc1.toml
type = "tcp"
localIP = "127.0.0.1"
localPort = 80
remotePort = 8080

[common]
serverAddr = "frp.example.com"
serverPort = 7000
auth.method = "token"
auth.token = "your_token_here"
transport.tls.enable = true
```

### 配置示例（INI 格式）

```ini
# frpc1.ini
[common]
server_addr = frp.example.com
server_port = 7000
token = your_token_here
tls_enable = true

[web]
type = tcp
local_ip = 127.0.0.1
local_port = 80
remote_port = 8080
```

## 🔍 监控系统

### 监控脚本功能

- 检查 FRPC 服务是否正在运行
- 检查服务日志中是否有 "login to server success" 记录
- 检查最近 24 小时内是否有登录成功记录
- 检测到问题时自动重启服务
- 限制监控日志文件大小，避免占用过多磁盘空间

### 定时任务

脚本会自动配置 crontab 定时任务，每 5 分钟执行一次监控脚本：

```
*/5 * * * * /usr/local/frpc/monitor_frpc.sh
```

## 📊 日志管理

### 安装日志

- 路径：`/var/log/frpc/install.log`
- 内容：详细的安装过程日志，包括时间戳、操作内容和结果
- 日志轮转：当日志文件超过 5MB 时，会保留最后 1000 行记录

### 监控日志

- 路径：`/var/log/frpc/frpc*.log`
- 内容：监控脚本的运行日志，包括服务状态检查和重启记录
- 日志轮转：当日志文件超过 10MB 时，会保留最后 500 行记录

## ❓ 常见问题

### 1. 安装失败，提示 "cp: cannot overwrite directory './frpc' with non-directory"

**解决方案**：脚本已经修复了这个问题，使用临时目录处理文件提取，避免与现有 frpc 目录冲突。

### 2. 服务启动失败，提示 "Unit frpc1.service not found"

**解决方案**：请确保在脚本目录中创建了对应的配置文件（如 frpc1.ini 或 frpc1.toml），脚本会根据配置文件创建服务。

### 3. 无法连接到 GitHub 下载 FRPC

**解决方案**：脚本内置了多个 GitHub 代理地址，会自动尝试使用代理下载。如果所有代理都失败，会尝试使用 git 克隆并编译 FRPC。

### 4. 监控脚本没有自动重启服务

**解决方案**：请检查监控日志文件（/var/log/frpc/frpc*.log），查看具体的错误信息。确保 crontab 定时任务已正确配置。

## 🤝 贡献指南

1. **Fork 本仓库**
2. **创建功能分支**：`git checkout -b feature/AmazingFeature`
3. **提交更改**：`git commit -m 'Add some AmazingFeature'`
4. **推送到分支**：`git push origin feature/AmazingFeature`
5. **创建 Pull Request**

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🙏 致谢

- [FRP](https://github.com/fatedier/frp) - 一个高性能的反向代理应用
- 所有为该项目做出贡献的开发者

---

**注意**：本脚本仅用于学习和个人使用，生产环境请谨慎使用。如有任何问题或建议，欢迎提交 Issue 或 Pull Request。