#!/bin/bash

# FRPC 安装脚本 - 适配主流 Linux 系统
# 功能：安装、管理和监控 frpc 服务

# 安装日志配置
INSTALL_LOG_DIR="/var/log/frpc"
INSTALL_LOG_FILE="$INSTALL_LOG_DIR/install.log"
MAX_INSTALL_LOG_SIZE=5242880  # 5MB

# 日志记录函数
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 确保日志目录存在
    mkdir -p "$INSTALL_LOG_DIR"
    
    # 记录到日志文件
    echo "[$timestamp] [$level] $message" >> "$INSTALL_LOG_FILE"
    
    # 同时输出到终端（保持原有用户体验）
    case "$level" in
        "ERROR")
            echo "❌ $message"
            ;;
        "WARN")
            echo "⚠️  $message"
            ;;
        "SUCCESS")
            echo "✓ $message"
            ;;
        "INFO")
            echo "$message"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# 清理安装日志（防止文件过大）
cleanup_install_log() {
    if [ -f "$INSTALL_LOG_FILE" ]; then
        local file_size=$(stat -c%s "$INSTALL_LOG_FILE" 2>/dev/null || echo 0)
        if [ "$file_size" -gt "$MAX_INSTALL_LOG_SIZE" ]; then
            # 保留最后1000行
            tail -n 1000 "$INSTALL_LOG_FILE" > "${INSTALL_LOG_FILE}.tmp"
            mv "${INSTALL_LOG_FILE}.tmp" "$INSTALL_LOG_FILE"
            log_message "INFO" "安装日志已轮转，保留最新1000行记录"
        fi
    fi
}

# 清屏函数
clear_screen() {
    clear
}

# 显示标题
display_title() {
    echo "========================================"
    echo "FRPC Manager"
    echo "========================================"
}

# 检查是否为 root 用户
if [ "$(id -u)" != "0" ]; then
    echo "错误：请以 root 用户身份运行此脚本"
    exit 1
fi

# 检查系统类型和包管理器
check_system() {
    if [ -f /etc/debian_version ]; then
        echo "检测到 Debian/Ubuntu 系统"
        PM="apt"
        UPDATE_CMD="apt update"
        INSTALL_CMD="apt install -y"
    elif [ -f /etc/redhat-release ]; then
        echo "检测到 RedHat/CentOS/Fedora 系统"
        PM="yum"
        UPDATE_CMD="yum check-update"
        INSTALL_CMD="yum install -y"
        # 检查是否是Fedora系统
        if grep -i "fedora" /etc/redhat-release > /dev/null; then
            PM="dnf"
            UPDATE_CMD="dnf check-update"
            INSTALL_CMD="dnf install -y"
        fi
    elif [ -f /etc/arch-release ]; then
        echo "检测到 Arch Linux 系统"
        PM="pacman"
        UPDATE_CMD="pacman -Sy"
        INSTALL_CMD="pacman -S --noconfirm"
    else
        echo "错误：不支持的系统类型"
        exit 1
    fi
    echo "使用包管理器: $PM"
}

# 安装必要依赖（不更新系统）
install_dependencies() {
    echo "安装必要依赖..."
    
    case $PM in
        "apt")
            # 使用apt命令安装依赖，不更新包列表，--no-install-recommends避免安装不必要的推荐包
            DEBIAN_FRONTEND=noninteractive apt install -y -qq curl git systemd --no-install-recommends --no-upgrade 2>&1 | grep -v "WARNING: apt does not have a stable CLI interface"
            ;;
        "yum")
            # 使用yum安装依赖，不更新系统，--assumeno避免任何交互式确认
            yum install -y --assumeno curl git systemd
            ;;
        "dnf")
            # 使用dnf安装依赖，不更新系统，--assumeno避免任何交互式确认
            dnf install -y --assumeno curl git systemd
            ;;
        "pacman")
            # 使用pacman安装依赖，-S仅安装指定包，不更新系统
            pacman -S --noconfirm curl git systemd
            ;;
        *)
            echo "错误：不支持的包管理器"
            exit 1
            ;;
    esac
}

# 检查配置文件是否存在（支持ini、json、yaml、toml格式）
check_config_exists() {
    local service_num=$1
    local exists=false
    
    for ext in toml json yaml yml ini; do
        if [ -f /usr/local/frpc/config/frpc$service_num.$ext ]; then
            exists=true
            break
        fi
    done
    
    echo "$exists"
}

# 检测系统架构
detect_architecture() {
    echo "检测系统架构..."
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            FRP_ARCH="amd64"
            ;;
        aarch64|arm64)
            FRP_ARCH="arm64"
            ;;
        armv7*)
            FRP_ARCH="arm"
            ;;
        i386|i686)
            FRP_ARCH="386"
            ;;
        *)
            echo "错误：不支持的系统架构: $ARCH"
            exit 1
            ;;
    esac
    echo "检测到系统架构: $ARCH -> 使用 frp 架构: $FRP_ARCH"
}

# 版本检测函数
version_check() {
    echo "正在检测FRPC版本..."
    
    # 检查当前是否已安装frpc
    FRPC_PATH="/usr/local/frpc/bin/frpc"
    if [ -f "$FRPC_PATH" ]; then
        echo "已检测到FRPC安装在: $FRPC_PATH"
        
        # 尝试多种方式提取版本号
        VERSION_OUTPUT="$($FRPC_PATH -v 2>&1)"
        echo "版本命令输出: $VERSION_OUTPUT"
        
        # 第一种提取方式：version vX.Y.Z
        CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP 'version\s+v\K[0-9.]+')
        
        # 第二种提取方式：直接找vX.Y.Z格式
        if [ -z "$CURRENT_VERSION" ]; then
            CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP 'v\K[0-9.]+')
        fi
        
        # 第三种提取方式：找数字.数字.数字格式
        if [ -z "$CURRENT_VERSION" ]; then
            CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')
        fi
        
        if [ -n "$CURRENT_VERSION" ]; then
            echo "当前安装版本: v$CURRENT_VERSION"
        else
            echo "警告：无法提取当前版本号"
            CURRENT_VERSION="unknown"
        fi
    else
        echo "未检测到已安装的FRPC"
        CURRENT_VERSION=""
    fi
    
    # 获取最新版本号
    LATEST_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -oP '"tag_name": "v\K[0-9.]+')
    if [ -z "$LATEST_VERSION" ]; then
        echo "错误：无法获取最新版本号"
        return 1
    fi
    
    echo "GitHub最新版本: v$LATEST_VERSION"
    
    # 比较版本
    if [ -n "$CURRENT_VERSION" ] && [ "$CURRENT_VERSION" != "unknown" ]; then
        if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
            echo "✓ 当前版本已是最新版本"
        else
            echo "⚠️  当前版本不是最新版本，自动更新到最新版本！"
            echo ""
            echo "正在准备更新..."
            # 检测系统架构
            detect_architecture
            # 下载最新版本
            download_frpc
            # 复制文件到安装目录
            cp -f frpc /usr/local/frpc/bin/
            # 设置执行权限
            chmod +x /usr/local/frpc/bin/frpc
            echo ""
            echo "✓ 更新完成！当前版本: v$LATEST_VERSION"
            # 更新监控脚本
            create_monitor_script
            # 配置定时任务
            setup_crontab
            # 自动重启服务以应用更新
            restart_frpc_services
        fi
    elif [ "$CURRENT_VERSION" = "unknown" ]; then
        echo ""
        echo "已安装FRPC，但无法识别版本号"
        echo "自动重新安装最新版本以确保兼容性..."
        echo ""
        echo "正在准备重新安装..."
        # 检测系统架构
        detect_architecture
        # 下载最新版本
        download_frpc
        # 复制文件到安装目录
        cp -f frpc /usr/local/frpc/bin/
        # 设置执行权限
        chmod +x /usr/local/frpc/bin/frpc
        echo ""
        echo "✓ 重新安装完成！当前版本: v$LATEST_VERSION"
        # 更新监控脚本
        create_monitor_script
        # 配置定时任务
        setup_crontab
        # 自动重启服务以应用更新
        restart_frpc_services
    else
        echo ""
        echo "未安装FRPC，建议先进行安装"
    fi
}

# 测试URL是否可访问
test_url() {
    local url="$1"
    local timeout="${2:-5}"
    
    # 使用curl测试URL是否可访问
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" "$url" -L > /dev/null
    return $?
}

# 下载并提取最新版本的frpc
download_frpc() {
    log_message "INFO" "开始下载最新版本的frpc..."
    
    # GitHub代理列表
    GITHUB_PROXIES=(
        "https://ghfast.top/"
        "https://hk.gh-proxy.org/"
        "https://cdn.gh-proxy.org/"
        "https://gh-proxy.org/"
        "https://edgeone.gh-proxy.org/"
    )
    
    # 原始GitHub API URL
    ORIGINAL_API_URL="https://api.github.com/repos/fatedier/frp/releases/latest"
    API_URL="$ORIGINAL_API_URL"
    
    # 获取最新版本号
    LATEST_VERSION=$(curl -s "$API_URL" | grep -oP '"tag_name": "v\K[0-9.]+')
    
    # 如果原始URL失败，尝试使用代理
    if [ -z "$LATEST_VERSION" ]; then
        echo "尝试使用GitHub代理获取版本信息..."
        for proxy in "${GITHUB_PROXIES[@]}"; do
            API_URL="${proxy}${ORIGINAL_API_URL}"
            echo "尝试代理: $proxy"
            LATEST_VERSION=$(curl -s "$API_URL" | grep -oP '"tag_name": "v\K[0-9.]+')
            if [ -n "$LATEST_VERSION" ]; then
                break
            fi
        done
    fi
    
    if [ -z "$LATEST_VERSION" ]; then
        log_message "ERROR" "无法获取最新版本号"
        exit 1
    fi
    
    log_message "SUCCESS" "发现最新版本: v$LATEST_VERSION"
    
    # 构建原始下载URL
    ORIGINAL_DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v$LATEST_VERSION/frp_${LATEST_VERSION}_linux_${FRP_ARCH}.tar.gz"
    DOWNLOAD_URL="$ORIGINAL_DOWNLOAD_URL"
    
    # 测试原始下载URL
    echo "正在测试下载地址..."
    if ! test_url "$DOWNLOAD_URL"; then
        echo "原始下载地址无法访问，尝试使用GitHub代理..."
        
        # 尝试使用代理
        for proxy in "${GITHUB_PROXIES[@]}"; do
            DOWNLOAD_URL="${proxy}${ORIGINAL_DOWNLOAD_URL}"
            echo "尝试代理: $proxy"
            if test_url "$DOWNLOAD_URL"; then
                echo "找到可用代理: $proxy"
                break
            fi
            DOWNLOAD_URL=""
        done
    fi
    
    if [ -z "$DOWNLOAD_URL" ]; then
        log_message "INFO" "所有curl下载地址都无法访问，尝试使用git下载..."
        
        # 尝试使用git下载
        GIT_REPO_URL="https://github.com/fatedier/frp.git"
        
        # 尝试直接git clone
        if git clone --depth 1 "$GIT_REPO_URL" frp_repo; then
            cd frp_repo || exit 1
            
            # 检出最新标签
            git checkout "v$LATEST_VERSION" || log_message "WARNING" "无法检出指定版本，使用最新提交"
            
            # 编译frpc
            make frpc
            
            if [ -f "bin/frpc" ]; then
                cp -f "bin/frpc" ../
                cd ..
                chmod +x frpc
                log_message "SUCCESS" "使用git成功编译frpc程序 (版本: v$LATEST_VERSION)"
                rm -rf frp_repo
            else
                cd ..
                rm -rf frp_repo
                log_message "ERROR" "git编译frpc失败"
                exit 1
            fi
        else
            # 尝试使用代理git clone
            for proxy in "${GITHUB_PROXIES[@]}"; do
                GIT_PROXY_URL="${proxy}${GIT_REPO_URL}"
                echo "尝试代理git: $proxy"
                
                if git clone --depth 1 "$GIT_PROXY_URL" frp_repo; then
                    cd frp_repo || exit 1
                    
                    # 检出最新标签
                    git checkout "v$LATEST_VERSION" || log_message "WARNING" "无法检出指定版本，使用最新提交"
                    
                    # 编译frpc
                    make frpc
                    
                    if [ -f "bin/frpc" ]; then
                        cp -f "bin/frpc" ../
                        cd ..
                        chmod +x frpc
                        log_message "SUCCESS" "使用代理git成功编译frpc程序 (版本: v$LATEST_VERSION)"
                        rm -rf frp_repo
                        break
                    else
                        cd ..
                        rm -rf frp_repo
                        log_message "WARNING" "代理git编译frpc失败，尝试下一个代理"
                    fi
                fi
            done
            
            # 如果所有git尝试都失败
            if [ ! -f "frpc" ]; then
                log_message "ERROR" "所有下载方式都失败"
                exit 1
            fi
        fi
    else
        log_message "INFO" "使用下载地址: $DOWNLOAD_URL"
        
        # 下载压缩包
        log_message "INFO" "正在下载 frpc 压缩包..."
        curl -sL "$DOWNLOAD_URL" -o frp_latest.tar.gz
        
        if [ $? -ne 0 ]; then
            log_message "INFO" "curl下载失败，尝试使用git下载..."
            
            # 清理临时文件
            rm -f frp_latest.tar.gz
            
            # 尝试使用git下载
            GIT_REPO_URL="https://github.com/fatedier/frp.git"
            
            # 尝试直接git clone
            if git clone --depth 1 "$GIT_REPO_URL" frp_repo; then
                cd frp_repo || exit 1
                
                # 检出最新标签
                git checkout "v$LATEST_VERSION" || log_message "WARNING" "无法检出指定版本，使用最新提交"
                
                # 编译frpc
                make frpc
                
                if [ -f "bin/frpc" ]; then
                    cp -f "bin/frpc" ../
                    cd ..
                    chmod +x frpc
                    log_message "SUCCESS" "使用git成功编译frpc程序 (版本: v$LATEST_VERSION)"
                    rm -rf frp_repo
                else
                    cd ..
                    rm -rf frp_repo
                    log_message "ERROR" "git编译frpc失败"
                    exit 1
                fi
            else
                # 尝试使用代理git clone
                for proxy in "${GITHUB_PROXIES[@]}"; do
                    GIT_PROXY_URL="${proxy}${GIT_REPO_URL}"
                    echo "尝试代理git: $proxy"
                    
                    if git clone --depth 1 "$GIT_PROXY_URL" frp_repo; then
                        cd frp_repo || exit 1
                        
                        # 检出最新标签
                        git checkout "v$LATEST_VERSION" || log_message "WARNING" "无法检出指定版本，使用最新提交"
                        
                        # 编译frpc
                        make frpc
                        
                        if [ -f "bin/frpc" ]; then
                            cp -f "bin/frpc" ../
                            cd ..
                            chmod +x frpc
                            log_message "SUCCESS" "使用代理git成功编译frpc程序 (版本: v$LATEST_VERSION)"
                            rm -rf frp_repo
                            break
                        else
                            cd ..
                            rm -rf frp_repo
                            log_message "WARNING" "代理git编译frpc失败，尝试下一个代理"
                        fi
                    fi
                done
                
                # 如果所有git尝试都失败
                if [ ! -f "frpc" ]; then
                    log_message "ERROR" "所有下载方式都失败"
                    exit 1
                fi
            fi
        else
            log_message "SUCCESS" "下载完成，正在解压..."
            
            # 创建临时目录
            TEMP_DIR=$(mktemp -d)
            if [ ! -d "$TEMP_DIR" ]; then
                echo "错误：无法创建临时目录"
                rm -f frp_latest.tar.gz
                exit 1
            fi
            
            # 解压文件到临时目录
            tar -xzf frp_latest.tar.gz -C "$TEMP_DIR"
            
            # 提取frpc程序
            FRP_DIR="$TEMP_DIR/frp_${LATEST_VERSION}_linux_${FRP_ARCH}"
            if [ ! -d "$FRP_DIR" ]; then
                echo "错误：解压失败，未找到预期的目录结构"
                rm -f frp_latest.tar.gz
                rm -rf "$TEMP_DIR"
                exit 1
            fi
            
            # 复制frpc可执行文件到当前目录
            cp -f "$FRP_DIR/frpc" .
            
            if [ ! -f "frpc" ]; then
                echo "错误：无法提取frpc程序"
                rm -rf "$TEMP_DIR" frp_latest.tar.gz
                exit 1
            fi
            
            # 设置执行权限
            chmod +x frpc
            
            echo "✓ 成功提取frpc程序 (版本: v$LATEST_VERSION)"
            
            # 清理临时文件和目录
            rm -rf "$TEMP_DIR" frp_latest.tar.gz
        fi
    fi
}

# 创建安装目录
create_directories() {
    echo "创建安装目录..."
    mkdir -p /usr/local/frpc/bin
    mkdir -p /usr/local/frpc/config
}




# 将ini配置文件转换为toml格式
convert_ini_to_toml() {
    local ini_file="$1"
    local toml_file="$2"
    
    echo "正在将 $ini_file 转换为 $toml_file..."
    
    # 清空目标文件
    > "$toml_file"
    
    # 读取ini文件并转换为toml格式
    local section=""
    while IFS= read -r line || [ -n "$line" ]; do
        # 去除行首和行尾的空格
        line="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        
        # 跳过空行和注释行
        if [ -z "$line" ] || [[ "$line" == "#"* ]]; then
            continue
        fi
        
        # 检查是否是section行
        if [[ "$line" == "["*"]" ]]; then
            # 提取section名称
            section="$(echo "$line" | sed -e 's/^\[//' -e 's/\]$//')"
            
            # 处理不同的section
            if [ "$section" = "common" ]; then
                # common部分不需要section头
                :
            else
                # 代理部分使用[[proxies]]格式
                echo "" >> "$toml_file"
                echo "[[proxies]]" >> "$toml_file"
                echo "name = \"$section\"" >> "$toml_file"
            fi
        else
            # 检查是否是key=value行
            if [[ "$line" == *"="* ]]; then
                # 提取key和value
                key="$(echo "$line" | cut -d'=' -f1 | sed 's/[[:space:]]*$//')"
                value="$(echo "$line" | cut -d'=' -f2- | sed 's/^[[:space:]]*//')"
                
                # 处理特殊字段
                case "$key" in
                    server_addr) 
                        key="serverAddr" 
                        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "$key = $value" >> "$toml_file"
                        else
                            echo "$key = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                    server_port) 
                        key="serverPort" 
                        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "$key = $value" >> "$toml_file"
                        else
                            echo "$key = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                    tls_enable) 
                        # tls_enable转换为transport.tls.enable
                        if [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "transport.tls.enable = $value" >> "$toml_file"
                        else
                            echo "transport.tls.enable = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                    token) 
                        # token转换为auth.method和auth.token
                        echo "auth.method = \"token\"" >> "$toml_file"
                        echo "auth.token = \"$value\"" >> "$toml_file"
                        ;;
                    user) 
                        # user字段保持不变
                        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "$key = $value" >> "$toml_file"
                        else
                            echo "$key = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                    local_ip) 
                        key="localIP" 
                        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "$key = $value" >> "$toml_file"
                        else
                            echo "$key = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                    local_port) 
                        key="localPort" 
                        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "$key = $value" >> "$toml_file"
                        else
                            echo "$key = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                    remote_port) 
                        key="remotePort" 
                        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "$key = $value" >> "$toml_file"
                        else
                            echo "$key = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                    type) 
                        # type字段保持不变
                        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "$key = $value" >> "$toml_file"
                        else
                            echo "$key = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                    *) 
                        # 其他字段保持不变
                        if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+\.[0-9]+$ ]] || [[ "$value" == "true" ]] || [[ "$value" == "false" ]]; then
                            echo "$key = $value" >> "$toml_file"
                        else
                            echo "$key = \"$value\"" >> "$toml_file"
                        fi
                        ;;
                esac
            fi
        fi
    done < "$ini_file"
    
    echo "✓ 转换完成: $toml_file"
}

# 复制二进制文件和配置文件
copy_files() {
    # 创建目标目录
    mkdir -p /usr/local/frpc/bin
    mkdir -p /usr/local/frpc/config
    
    # 复制二进制文件
    cp -f frpc /usr/local/frpc/bin/
    
    # 确保配置目录存在
    mkdir -p /usr/local/frpc/config
    
    # 在复制配置文件之前先停止所有frpc服务，避免文件被占用
    echo "正在停止所有frpc服务..."
    for i in {1..10}; do
        systemctl stop frpc$i 2>/dev/null || echo "frpc$i服务未运行"
    done
    
    # 清空目标目录中的所有配置文件，确保与源目录一致
    echo "正在清空目标配置目录..."
    rm -f /usr/local/frpc/config/frpc*.* 2>/dev/null
    
    # 处理frpc1到frpc10配置文件
    for i in {1..10}; do
        echo "处理 frpc$i 配置文件..."
        
        # 检查是否存在配置文件（支持ini、json、yaml、toml格式）
        local found=false
        local config_file=""
        local config_ext=""
        
        # 按优先级检查不同格式的配置文件
        for ext in ini json yaml yml toml; do
            if [ -f "frpc$i.$ext" ]; then
                config_file="frpc$i.$ext"
                config_ext="$ext"
                found=true
                break
            fi
        done
        
        if [ "$found" = true ]; then
            echo "使用 $config_file 文件..."
            
            # 复制配置文件到配置目录
            cp -f "$config_file" /usr/local/frpc/config/
            
            # 验证配置文件是否成功复制
            if diff -q "$config_file" "/usr/local/frpc/config/$config_file" > /dev/null 2>&1; then
                echo "✓ $config_file 成功复制到 /usr/local/frpc/config/"
            else
                echo "✗ 警告：$config_file 复制失败或未成功覆盖"
                # 尝试使用更强制的方法复制
                echo "正在尝试使用强制覆盖..."
                rm -f "/usr/local/frpc/config/$config_file" 2>/dev/null
                cp "$config_file" /usr/local/frpc/config/
                if [ -f "/usr/local/frpc/config/$config_file" ]; then
                    echo "✓ $config_file 强制覆盖成功"
                else
                    echo "✗ 错误：$config_file 强制覆盖也失败了"
                fi
            fi
            
            # 如果是ini格式，转换为toml格式
            if [ "$config_ext" = "ini" ]; then
                convert_ini_to_toml "$config_file" "/usr/local/frpc/config/frpc$i.toml"
            fi
        else
            echo "警告：未找到 frpc$i 的配置文件（支持ini、json、yaml、toml格式）"
        fi
    done
    
    # 设置执行权限
    chmod +x /usr/local/frpc/bin/frpc
    

    
    # 列出配置文件
    echo "配置文件："
    ls -la /usr/local/frpc/config/
}

# 创建单个 frpc systemd 服务
create_frpc_service() {
    local i=$1
    echo "创建 frpc$i systemd 服务..."
    
    # 查找实际的配置文件格式
    local config_file=""
    for ext in toml json yaml yml ini; do
        if [ -f /usr/local/frpc/config/frpc$i.$ext ]; then
            config_file="/usr/local/frpc/config/frpc$i.$ext"
            break
        fi
    done
    
    # 如果没有找到配置文件，跳过创建服务
    if [ -z "$config_file" ]; then
        echo "✗ 错误：未找到 frpc$i 的配置文件"
        return 1
    fi
    
    # 确保日志目录存在
    mkdir -p /var/log/frpc
    
    # 确保日志文件存在
    touch /var/log/frpc/frpc$i.log
    
    cat > /etc/systemd/system/frpc$i.service << EOF
[Unit]
Description=FRPC Client $i
After=network.target

[Service]
Type=simple
# 将 stdout 和 stderr 重定向到日志文件
ExecStart=/usr/local/frpc/bin/frpc -c $config_file
StandardOutput=append:/var/log/frpc/frpc$i.log
StandardError=append:/var/log/frpc/frpc$i.log
Restart=always
RestartSec=5
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
}





# 设置服务文件权限并启动服务
start_services() {
    echo "设置 systemd 服务文件权限..."
    for i in {1..10}; do
        if [ -f /etc/systemd/system/frpc$i.service ]; then
            chmod 644 /etc/systemd/system/frpc$i.service
        fi
    done
    
    echo "重新加载 systemd 配置..."
    systemctl daemon-reload
    
    # 停止现有服务（如果存在），避免进程冲突
    echo "停止现有 frpc 服务..."
    for i in {1..10}; do
        systemctl stop frpc$i 2>/dev/null || true
    done
    
    # 启动并启用服务（只启动存在配置文件的服务）
    for i in {1..10}; do
        # 检查是否存在配置文件（支持ini、json、yaml、toml格式）
        local config_exists=false
        for ext in toml json yaml yml ini; do
            if [ -f /usr/local/frpc/config/frpc$i.$ext ]; then
                config_exists=true
                break
            fi
        done
        
        if [ "$config_exists" = true ]; then
            echo "启动 frpc$i 服务..."
            if systemctl start frpc$i; then
                echo "frpc$i 服务启动成功"
            else
                echo "警告：frpc$i 服务启动失败，请检查日志获取详细信息"
                journalctl -u frpc$i -n 20 --no-pager
            fi
            
            echo "启用 frpc$i 开机自启..."
            systemctl enable frpc$i
        fi
    done
}

# 显示服务状态
show_status() {
    echo ""
    echo "========================================"
    echo "服务状态检查"
    echo "========================================"
    
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            echo ""
            echo "frpc$i 服务状态:"
            systemctl status frpc$i --no-pager
        fi
    done
}

# 创建日志监控脚本
create_monitor_script() {
    echo "创建 frpc 日志监控脚本..."
    cat > /usr/local/frpc/monitor_frpc.sh << 'EOF'
#!/bin/bash

# FRPC 日志监控脚本
# 功能：检查 frpc 服务状态，如果异常则重启，并将监控日志存储在单独的文件中

LOG_DIR="/var/log/frpc"
MAX_LOG_SIZE=5242880  # 5MB

# 创建日志目录
mkdir -p $LOG_DIR

# 检查单个 frpc 服务
check_frpc_service() {
    local service_name="$1"
    local check_window="5 minutes ago"
    local service_log="$LOG_DIR/${service_name}.log"
    
    # 确保服务日志文件存在
    touch "$service_log"
    
    # 检查服务是否正在运行
    if systemctl is-active --quiet "$service_name"; then
        # 1. 检查最近 5 分钟内是否有成功登录记录
        local recent_success=$(journalctl -u "$service_name" --since "$check_window" --grep="login to server success" --no-pager)
        
        if [ -n "$recent_success" ]; then
            # 最近有成功登录记录，状态正常
            local log_message="[$(date)] 信息: $service_name 服务运行正常，最近有成功登录记录"
            echo "$log_message" >> "$service_log"
            return 0
        fi
        
        # 2. 检查最近 5 分钟内是否有任何活动记录
        local recent_activity=$(journalctl -u "$service_name" --since "$check_window" --no-pager | head -n 5)
        
        if [ -n "$recent_activity" ]; then
            # 有活动记录，说明服务正常运行
            local log_message="[$(date)] 信息: $service_name 服务运行正常，有活动记录"
            echo "$log_message" >> "$service_log"
            return 0
        fi
        
        # 3. 如果没有成功记录，检查最近 5 分钟内是否有连接错误记录
        local recent_error=$(journalctl -u "$service_name" --since "$check_window" --grep="connect to server error" --no-pager)
        
        if [ -n "$recent_error" ]; then
            # 最近有错误记录且没有成功记录，说明可能真的断连了
            local log_message="[$(date)] 警告: $service_name 最近 5 分钟内检测到连接错误且无成功恢复记录，正在重启服务..."
            echo "$log_message" >> "$service_log"
            systemctl restart "$service_name"
            local log_message="[$(date)] $service_name 服务已重启"
            echo "$log_message" >> "$service_log"
        else
            # 既没有成功记录也没有错误记录，可能是长时间稳定运行或 frpc 处于空闲状态，不执行重启
            local log_message="[$(date)] 信息: $service_name 服务运行正常，无近期活动记录"
            echo "$log_message" >> "$service_log"
        fi
    else
        # 服务未运行，直接启动
        local log_message="[$(date)] 警告: $service_name 服务未运行，正在启动服务..."
        echo "$log_message" >> "$service_log"
        systemctl start "$service_name"
        local log_message="[$(date)] $service_name 服务已启动"
        echo "$log_message" >> "$service_log"
    fi
    
    # 限制服务日志文件大小
    if [ -f "$service_log" ]; then
        if [ $(stat -c%s "$service_log") -gt $MAX_LOG_SIZE ]; then
            # 直接截断服务日志文件，保留最新的日志内容
            tail -n 1000 "$service_log" > "${service_log}.tmp"
            mv "${service_log}.tmp" "$service_log"
            echo "[$(date)] 服务日志已自动清理，保留最新1000行内容" >> "$service_log"
        fi
    fi
}

# 清理超过 7 天的 system 日志
cleanup_system_logs() {
    echo "清理超过 7 天的 frpc 系统日志..."
    
    # 对每个 frpc 服务，清理超过 7 天的日志
    for i in {1..10}; do
        service_name="frpc$i"
        if systemctl list-unit-files | grep -q "${service_name}.service"; then
            # 使用 journalctl 的 vacuum-time 选项清理超过 7 天的日志
            journalctl --vacuum-time=7d --unit="$service_name" --quiet
        fi
    done
    
    echo "系统日志清理完成"
}

# 检查所有 frpc 服务（1-10）
for i in {1..10}; do
    if systemctl list-unit-files | grep -q "frpc$i.service"; then
        check_frpc_service "frpc$i"
    fi
done

# 清理系统日志
cleanup_system_logs
EOF
    
    # 设置脚本执行权限
    chmod +x /usr/local/frpc/monitor_frpc.sh
    
    echo "frpc 日志监控脚本已创建：/usr/local/frpc/monitor_frpc.sh"
}

# 配置 crontab 定时任务
setup_crontab() {
    echo "配置 crontab 定时任务..."
    
    # 检查是否已经存在监控任务
    if ! crontab -l 2>/dev/null | grep -q "/usr/local/frpc/monitor_frpc.sh"; then
        # 添加每 5 分钟执行一次的监控任务
        (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/frpc/monitor_frpc.sh") | crontab -
        echo "已添加 crontab 定时任务，每 5 分钟检查一次 frpc 服务状态"
    else
        echo "crontab 定时任务已存在，跳过添加"
    fi
}

# 查看安装日志
view_install_logs() {
    clear_screen
    display_title
    echo "查看 FRPC 安装日志："
    echo "----------------------------------------"
    
    INSTALL_LOG="/var/log/frpc/install.log"
    if [ ! -f "$INSTALL_LOG" ]; then
        echo "未找到安装日志文件：$INSTALL_LOG"
        echo ""
        read -p "按 Enter 键返回主菜单..." 
        return
    fi
    
    echo "安装日志内容："
    echo "----------------------------------------"
    cat "$INSTALL_LOG"
    echo ""
    read -p "按 Enter 键返回主菜单..." 
}

# 安装流程
install() {
    # 创建日志文件目录
    mkdir -p /var/log/frpc
    
    # 确保安装日志文件存在
    touch /var/log/frpc/install.log
    
    # 确保监控日志文件存在
    touch /var/log/frpc/monitor.log
    
    # 保留旧日志，追加新的安装记录
    # 不清空旧日志，以便查看历史安装记录
    
    # 开始记录安装日志
    { 
        echo "========================================"
        echo "FRPC 安装开始: $(date)"
        echo "========================================"
        
        log_message "INFO" "=================== 开始 FRPC 安装流程 ==================="
        
        log_message "INFO" "检查系统环境和包管理器..."
        check_system
        
        log_message "INFO" "安装系统依赖..."
        install_dependencies
        
        log_message "INFO" "创建安装目录..."
        create_directories
        
        # 检测系统架构
        log_message "INFO" "检测系统架构..."
        detect_architecture
        
        # 版本检查：如果已安装且版本相同，则跳过下载
        log_message "INFO" "检查FRPC版本..."
        FRPC_PATH="/usr/local/frpc/bin/frpc"
        if [ -f "$FRPC_PATH" ]; then
            # 获取本地版本号
            VERSION_OUTPUT="$($FRPC_PATH -v 2>&1)"
            CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP 'version\s+v\K[0-9.]+' || echo "")
            if [ -z "$CURRENT_VERSION" ]; then
                CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP 'v\K[0-9.]+' || echo "")
            fi
            if [ -z "$CURRENT_VERSION" ]; then
                CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
            fi
        
        # 获取最新版本号
        LATEST_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -oP '"tag_name": "v\K[0-9.]+' || echo "")
        
        if [ -n "$CURRENT_VERSION" ] && [ -n "$LATEST_VERSION" ]; then
            log_message "INFO" "当前已安装版本: v$CURRENT_VERSION"
            log_message "INFO" "GitHub最新版本: v$LATEST_VERSION"
            
            if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
                log_message "SUCCESS" "当前版本已是最新版本，跳过下载步骤"
                # 从本地复制frpc到当前目录，以便后续复制流程使用
                cp -f "$FRPC_PATH" .
                if [ ! -f "frpc" ]; then
                    log_message "WARN" "无法从本地复制frpc文件，将重新下载"
                    download_frpc
                fi
            else
                log_message "WARN" "当前版本不是最新版本，将更新到最新版本"
                download_frpc
            fi
        else
            log_message "WARN" "无法获取完整版本信息，将重新下载frpc"
            download_frpc
        fi
    else
        log_message "INFO" "未检测到已安装的FRPC，将下载最新版本"
        download_frpc
    fi
    
    log_message "INFO" "复制配置文件和二进制文件..."
    copy_files
    # 清理不再需要的服务（配置文件不存在但服务文件存在）
    log_message "INFO" "清理不再需要的 frpc 服务..."
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "false" ] && [ -f /etc/systemd/system/frpc$i.service ]; then
            log_message "INFO" "发现不需要的服务 frpc$i（配置文件不存在），正在停止并删除..."
            systemctl stop frpc$i 2>/dev/null || true
            systemctl disable frpc$i 2>/dev/null || true
            rm -f /etc/systemd/system/frpc$i.service 2>/dev/null
            log_message "SUCCESS" "frpc$i 服务已停止并删除"
        fi
    done
    
    # 重新加载 systemd 配置以应用删除的服务
    systemctl daemon-reload 2>/dev/null || true
    
    # 创建 systemd 服务
    log_message "INFO" "创建 systemd 服务文件..."
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            create_frpc_service $i
        fi
    done
    

    
    log_message "INFO" "启动 frpc 服务..."
    start_services
    
    log_message "INFO" "显示服务状态..."
    show_status
    
    log_message "INFO" "创建监控脚本..."
    create_monitor_script
    
    log_message "INFO" "配置定时任务..."
    setup_crontab
    
    log_message "SUCCESS" "=================== FRPC 安装流程完成 ==================="
    
    echo ""
    echo "========================================"
    echo "安装完成！"
    echo "========================================"
    
    # 显示已安装的配置文件
    echo "已安装的配置文件:"
    for i in {1..10}; do
        # 检查所有支持的配置文件格式
        for ext in toml json yaml yml ini; do
            if [ -f /usr/local/frpc/config/frpc$i.$ext ]; then
                echo "frpc$i 配置文件: /usr/local/frpc/config/frpc$i.$ext"
                break
            fi
        done
    done
    
    echo "监控脚本: /usr/local/frpc/monitor_frpc.sh"
    echo "监控日志: /var/log/frpc/"
    echo "安装日志: /var/log/frpc/install.log"
    echo ""
    
    # 显示管理命令
    echo "管理命令:"
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            echo "  systemctl start/restart/stop/status frpc$i"
        fi
    done
    echo "  /usr/local/frpc/monitor_frpc.sh          # 手动运行监控脚本"
    echo "========================================"
    
    echo "========================================"
    echo "FRPC 安装结束: $(date)"
    echo "========================================"
    
    # 结束日志记录
    } 2>&1 | tee "$INSTALL_LOG_FILE"
}

# 显示所有frpc服务的运行状态
display_all_status() {
    clear_screen
    display_title
    echo "所有 FRPC 服务运行状态："
    echo "----------------------------------------"
    
    # 获取所有正在运行的frpc服务
    running_services=$(systemctl list-units --type=service --state=running | grep frpc)
    
    for i in {1..10}; do
        service_name="frpc$i"
        
        # 检查配置文件是否存在
        if [ "$(check_config_exists $i)" = "true" ]; then
            # 查找实际的配置文件
            local config_file=""
            for ext in toml json yaml yml ini; do
                if [ -f /usr/local/frpc/config/frpc$i.$ext ]; then
                    config_file="/usr/local/frpc/config/frpc$i.$ext"
                    break
                fi
            done
            echo -n "$service_name: "
            
            # 检查服务是否正在运行
            if systemctl is-active --quiet "$service_name"; then
                echo "[运行中] ✅"
                
                # 显示服务详情
                echo "   配置文件: $config_file"
                
                # 显示最近的日志条目
                echo -n "   最近状态: "
                journalctl -u "$service_name" --no-pager -n 1 | grep -o ".*:.*" | cut -d' ' -f5- 2>/dev/null || echo "无日志"
            else
                echo "[已停止] ❌"
                echo "   配置文件: $config_file"
                
                # 显示停止原因
                echo -n "   停止原因: "
                journalctl -u "$service_name" --no-pager -n 1 | grep -o ".*:.*" | cut -d' ' -f5- 2>/dev/null || echo "无日志"
            fi
            echo ""
        fi
    done
    
    # 统计已配置服务的数量
    configured_count=0
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            configured_count=$((configured_count + 1))
        fi
    done
    
    echo "----------------------------------------"
    echo "已配置服务: $configured_count/10"
    echo "可用服务: $(seq 1 10 | grep -v "$(seq -s '\|' 1 10 | grep -f <(ls /usr/local/frpc/config/frpc*.* | grep -v "\." | cut -d'c' -f3))")"
    echo ""
    
    # 显示监控状态
    echo "监控系统状态:"
    if crontab -l 2>/dev/null | grep -q "/usr/local/frpc/monitor_frpc.sh"; then
        echo "   监控脚本: 已启用 [✅]"
    else
        echo "   监控脚本: 未启用 [❌]"
    fi
    
    echo ""
    read -p "按 Enter 键返回菜单..."
}

# 管理单个服务
manage_service() {
    clear_screen
    display_title
    
    # 显示可用服务
    echo "可用的 FRPC 服务："
    echo "----------------------------------------"
    
    available_services=()
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            available_services+=($i)
            echo "$i. frpc$i"
        fi
    done
    
    if [ ${#available_services[@]} -eq 0 ]; then
        echo "没有可用的 frpc 服务"
        echo ""
        read -p "按 Enter 键返回菜单..."
        return
    fi
    
    echo ""
    read -p "请选择要管理的服务编号 (1-10，直接回车返回): " service_num
    
    # 如果直接回车，返回菜单
    if [ -z "$service_num" ]; then
        return
    fi
    
    # 验证输入
    if ! [[ "$service_num" =~ ^[0-9]+$ ]] || [ "$service_num" -lt 1 ] || [ "$service_num" -gt 10 ]; then
        echo "错误：无效的服务编号"
        read -p "按 Enter 键返回菜单..."
        return
    fi
    
    service_name="frpc$service_num"
    
    # 检查配置文件是否存在
    if [ "$(check_config_exists $service_num)" = "false" ]; then
        echo "错误：服务 frpc$service_num 不存在或未配置"
        read -p "按 Enter 键返回菜单..."
        return
    fi
    
    # 查找实际的配置文件
    local config_file=""
    for ext in toml json yaml yml ini; do
        if [ -f /usr/local/frpc/config/frpc$service_num.$ext ]; then
            config_file="/usr/local/frpc/config/frpc$service_num.$ext"
            break
        fi
    done
    
    clear_screen
    display_title
    echo "正在管理服务: $service_name"
    echo "配置文件: $config_file"
    echo "----------------------------------------"
    echo "1. 启动服务"
    echo "2. 停止服务"
    echo "3. 重启服务"
    echo "4. 查看服务状态"
    echo "5. 查看服务日志"
    echo "6. 返回主菜单"
    echo ""
    
    read -p "请选择操作 (1-6，直接回车返回): " action
    
    # 如果直接回车，返回菜单
    if [ -z "$action" ]; then
        return
    fi
    
    case "$action" in
        1)
            echo "正在启动 $service_name..."
            systemctl start "$service_name"
            if [ $? -eq 0 ]; then
                echo "✅ $service_name 启动成功"
            else
                echo "❌ $service_name 启动失败"
            fi
            ;;
        2)
            echo "正在停止 $service_name..."
            systemctl stop "$service_name"
            if [ $? -eq 0 ]; then
                echo "✅ $service_name 停止成功"
            else
                echo "❌ $service_name 停止失败"
            fi
            ;;
        3)
            echo "正在重启 $service_name..."
            systemctl restart "$service_name"
            if [ $? -eq 0 ]; then
                echo "✅ $service_name 重启成功"
            else
                echo "❌ $service_name 重启失败"
            fi
            ;;
        4)
            echo "$service_name 服务状态："
            echo "----------------------------------------"
            systemctl status "$service_name" --no-pager
            ;;
        5)
            echo "$service_name 服务日志（最近20行）："
            echo "----------------------------------------"
            # 优先显示日志文件，如果不存在则显示 journalctl
            if [ -f "/var/log/frpc/${service_name}.log" ]; then
                tail -n 20 "/var/log/frpc/${service_name}.log"
            else
                journalctl -u "$service_name" --no-pager -n 20
            fi
            ;;
        6)
            return
            ;;
        *)
            echo "错误：无效的操作"
            ;;
    esac
    
    echo ""
    read -p "按 Enter 键返回服务管理菜单..."
    manage_service
}

# 管理所有服务
manage_all_services() {
    clear_screen
    display_title
    echo "管理所有 FRPC 服务："
    echo "----------------------------------------"
    echo "1. 启动所有服务"
    echo "2. 停止所有服务"
    echo "3. 重启所有服务"
    echo "4. 返回主菜单"
    echo ""
    
    read -p "请选择操作 (1-4，直接回车返回): " action
    
    # 如果直接回车，返回菜单
    if [ -z "$action" ]; then
        return
    fi
    
    case "$action" in
        1)
            echo "正在启动所有 FRPC 服务..."
            echo "----------------------------------------"
            
            for i in {1..10}; do
                service_name="frpc$i"
                if [ "$(check_config_exists $i)" = "true" ]; then
                    echo -n "启动 $service_name: "
                    systemctl start "$service_name" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo "✅"
                    else
                        echo "❌"
                    fi
                fi
            done
            ;;
        2)
            echo "正在停止所有 FRPC 服务..."
            echo "----------------------------------------"
            
            for i in {1..10}; do
                service_name="frpc$i"
                if [ "$(check_config_exists $i)" = "true" ]; then
                    echo -n "停止 $service_name: "
                    systemctl stop "$service_name" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo "✅"
                    else
                        echo "❌"
                    fi
                fi
            done
            ;;
        3)
            echo "正在重启所有 FRPC 服务..."
            echo "----------------------------------------"
            
            for i in {1..10}; do
                service_name="frpc$i"
                if [ "$(check_config_exists $i)" = "true" ]; then
                    echo -n "重启 $service_name: "
                    systemctl restart "$service_name" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo "✅"
                    else
                        echo "❌"
                    fi
                fi
            done
            ;;
        4)
            return
            ;;
        *)
            echo "错误：无效的操作"
            ;;
    esac
    
    echo ""
    read -p "按 Enter 键返回菜单..."
}

# 查看服务日志
view_logs() {
    clear_screen
    display_title
    echo "查看 FRPC 服务日志："
    echo "----------------------------------------"
    
    # 显示可用服务
    echo "可用的 FRPC 服务："
    echo "----------------------------------------"
    
    available_services=()
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            available_services+=($i)
            echo "$i. frpc$i"
        fi
    done
    
    if [ ${#available_services[@]} -eq 0 ]; then
        echo "没有可用的 frpc 服务"
        echo ""
        read -p "按 Enter 键返回菜单..."
        return
    fi
    
    echo ""
    read -p "请选择要查看日志的服务编号 (1-10，直接回车返回): " service_num
    
    # 如果直接回车，返回菜单
    if [ -z "$service_num" ]; then
        return
    fi
    
    # 验证输入
    if ! [[ "$service_num" =~ ^[0-9]+$ ]] || [ "$service_num" -lt 1 ] || [ "$service_num" -gt 10 ]; then
        echo "错误：无效的服务编号"
        read -p "按 Enter 键返回菜单..."
        return
    fi
    
    service_name="frpc$service_num"
    
    if [ "$(check_config_exists $service_num)" = "false" ]; then
        echo "错误：服务 frpc$service_num 不存在或未配置"
        read -p "按 Enter 键返回菜单..."
        return
    fi
    
    echo ""
    echo "$service_name 服务日志（全部）："
    echo "----------------------------------------"
    journalctl -u "$service_name" --no-pager
    
    echo ""
    echo "日志文件位置：/var/log/frpc/$service_name.log"
    echo ""
    read -p "按 Enter 键返回菜单..."
}

# 查看监控脚本日志
view_monitor_logs() {
    clear_screen
    display_title
    echo "查看 FRPC 服务日志："
    echo "----------------------------------------"
    
    # 显示服务日志文件列表
    echo "可用的服务日志文件："
    echo "----------------------------------------"
    
    LOG_DIR="/var/log/frpc"
    if [ ! -d "$LOG_DIR" ]; then
        echo "未找到日志目录：$LOG_DIR"
        echo ""
        read -p "按 Enter 键返回主菜单..."
        return
    fi
    
    service_logs=()
    log_files=()
    index=1
    
    for file in "$LOG_DIR"/frpc*.log; do
        if [ -f "$file" ]; then
            service_name=$(basename "$file" .log)
            service_logs+=($service_name)
            log_files+=($file)
            echo "$index.$service_name.log"
            index=$((index + 1))
        fi
    done
    
    if [ ${#service_logs[@]} -eq 0 ]; then
        echo "没有找到服务日志文件"
        echo ""
        read -p "按 Enter 键返回主菜单..."
        return
    fi
    
    echo ""
    read -p "请输入要查看的日志编号 (1-${#service_logs[@]}，直接回车返回): " choice
    
    # 如果直接回车，返回菜单
    if [ -z "$choice" ]; then
        return
    fi
    
    # 验证输入
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#service_logs[@]} ]; then
        echo "错误：无效的日志编号"
        read -p "按 Enter 键返回菜单..."
        return
    fi
    
    # 计算数组索引（从0开始）
    index=$((choice - 1))
    service_name=${service_logs[$index]}
    log_file=${log_files[$index]}
    
    echo ""
    echo "$service_name 服务日志："
    echo "----------------------------------------"
    cat "$log_file"
    
    echo ""
    read -p "按 Enter 键返回主菜单..."
}

# 主菜单
main_menu() {
    while true; do
        clear_screen
        display_title
        echo "1. 安装/更新 FRPC 服务"
    echo "2. 查看所有服务运行状态"
    echo "3. 管理单个服务"
    echo "4. 管理所有服务"
    echo "5. 查看服务日志"
    echo "6. 检测并更新 FRPC 版本"
    echo "7. 查看监控脚本日志"
    echo "8. 查看安装日志"
    echo "9. 清除所有日志"
    echo "10. 更新管理脚本"
    echo ""
        
        read -p "请选择操作 (1-10，直接回车退出): " choice
        
        # 如果直接回车，退出程序
        if [ -z "$choice" ]; then
            echo "感谢使用 FRPC 管理工具！"
            exit 0
        fi
        
        case "$choice" in
            1)
                install
                echo ""
                read -p "按 Enter 键返回主菜单..." 
                ;;
            2)
                display_all_status
                ;;
            3)
                manage_service
                ;;
            4)
                manage_all_services
                ;;
            5)
                view_logs
                ;;
            6)
                echo ""
                version_check
                echo ""
                read -p "按 Enter 键返回主菜单..." 
                ;;
            7)
                view_monitor_logs
                ;;
            8)
                view_install_logs
                ;;
            9)
                clear_all_logs
                echo ""
                read -p "按 Enter 键返回主菜单..." 
                ;;
            10)
                update_script
                echo ""
                read -p "按 Enter 键返回主菜单..." 
                ;;
            *)
                echo "错误：无效的选择，请输入 1-10 之间的数字"
                read -p "按 Enter 键继续..." 
                ;;
        esac
    done
}

# 重启所有 frpc 服务
restart_frpc_services() {
    echo "正在重启 FRPC 服务以应用更新..."
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            echo -n "重启 frpc$i: "
            systemctl restart frpc$i 2>/dev/null
            if [ $? -eq 0 ]; then
                echo "✅"
            else
                echo "❌"
            fi
        fi
    done
    echo "✓ 服务重启完成"
}

# 更新脚本
update_script() {
    clear_screen
    display_title
    echo "更新 FRPC 管理脚本："
    echo "----------------------------------------"
    
    echo "正在从 GitHub 更新脚本..."
    
    # 尝试使用 wget 下载
    echo "尝试使用 wget 下载..."
    wget -O /tmp/frpc_manager.sh https://raw.githubusercontent.com/zhangenine/frpc_manager/refs/heads/main/frpc_manager.sh 2>/dev/null
    
    # 如果 wget 失败，尝试使用 curl 下载
    if [ $? -ne 0 ] || [ ! -f /tmp/frpc_manager.sh ]; then
        echo "wget 下载失败，尝试使用 curl 下载..."
        curl -o /tmp/frpc_manager.sh https://raw.githubusercontent.com/zhangenine/frpc_manager/refs/heads/main/frpc_manager.sh 2>/dev/null
    fi
    
    # 检查脚本是否下载成功
    if [ ! -f /tmp/frpc_manager.sh ]; then
        echo "❌ 脚本下载失败，请检查网络连接"
        return 1
    fi
    
    # 设置执行权限
    chmod +x /tmp/frpc_manager.sh
    
    # 替换当前脚本
    cp -f /tmp/frpc_manager.sh "$0"
    
    if [ $? -eq 0 ]; then
        echo "✅ 脚本更新成功！"
        echo ""
        echo "正在更新监控脚本..."
        create_monitor_script
        echo "✅ 监控脚本更新成功！"
        echo ""
        echo "脚本已自动更新，正在返回主菜单..."
        # 重新运行脚本以应用更新
        bash "$0" "$@"
        exit 0
    else
        echo "❌ 脚本更新失败"
    fi
    
    # 清理临时文件
    rm -f /tmp/frpc_manager.sh
}

# 清除所有日志
clear_all_logs() {
    clear_screen
    display_title
    echo "清除所有 FRPC 日志："
    echo "----------------------------------------"
    
    LOG_DIR="/var/log/frpc"
    
    if [ ! -d "$LOG_DIR" ]; then
        echo "未找到日志目录：$LOG_DIR"
        return
    fi
    
    # 显示当前日志文件
    echo "当前日志文件："
    echo "----------------------------------------"
    ls -la "$LOG_DIR"/
    
    echo ""
    read -p "确定要清除所有日志吗？(y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "取消清除日志"
        return
    fi
    
    # 清除所有日志文件
    echo "正在清除所有日志..."
    
    # 停止所有 frpc 服务，避免日志文件被占用
    for i in {1..10}; do
        if systemctl list-unit-files | grep -q "frpc$i.service"; then
            systemctl stop frpc$i 2>/dev/null || true
        fi
    done
    
    # 清除日志文件
    rm -f "$LOG_DIR"/*.log "$LOG_DIR"/*.log.* 2>/dev/null
    
    # 确保日志目录存在
    mkdir -p "$LOG_DIR"
    
    echo "✓ 所有日志已清除"
    echo ""
    echo "删除日志后的目录："
    echo "----------------------------------------"
    ls -la "$LOG_DIR"/
    
    # 创建空的日志文件并设置正确权限
    echo ""
    echo "创建空的日志文件..."
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            touch "$LOG_DIR/frpc$i.log"
        fi
    done
    
    # 创建监控日志文件
    for i in {1..10}; do
        if systemctl list-unit-files | grep -q "frpc$i.service"; then
            touch "$LOG_DIR/monitor_frpc$i.log"
        fi
    done
    
    # 为已配置的服务创建监控日志文件（即使服务文件不存在）
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ]; then
            touch "$LOG_DIR/monitor_frpc$i.log"
        fi
    done
    
    # 创建安装日志文件
    touch "$LOG_DIR/install.log"
    
    # 重新加载 systemd 配置
    systemctl daemon-reload 2>/dev/null || true
    
    # 重新启动服务
    for i in {1..10}; do
        if systemctl list-unit-files | grep -q "frpc$i.service"; then
            systemctl start frpc$i 2>/dev/null || true
        fi
    done
    
    # 启动已配置但服务文件不存在的服务
    for i in {1..10}; do
        if [ "$(check_config_exists $i)" = "true" ] && ! systemctl list-unit-files | grep -q "frpc$i.service"; then
            create_frpc_service $i
            systemctl start frpc$i 2>/dev/null || true
        fi
    done
    
    echo ""
    echo "创建空日志文件后的目录："
    echo "----------------------------------------"
    ls -la "$LOG_DIR"/
}

# 检查 FRPC 是否已安装
check_installation() {
    FRPC_PATH="/usr/local/frpc/bin/frpc"
    if [ -f "$FRPC_PATH" ]; then
        echo "检测到 FRPC 已安装"
        
        # 获取当前版本
        VERSION_OUTPUT="$($FRPC_PATH -v 2>&1)"
        CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP 'version\s+v\K[0-9.]+' || echo "")
        if [ -z "$CURRENT_VERSION" ]; then
            CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP 'v\K[0-9.]+' || echo "")
        fi
        if [ -z "$CURRENT_VERSION" ]; then
            CURRENT_VERSION=$(echo "$VERSION_OUTPUT" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
        fi
        
        echo "当前版本: v$CURRENT_VERSION"
        
        # 获取最新版本
        LATEST_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -oP '"tag_name": "v\K[0-9.]+' || echo "")
        if [ -n "$LATEST_VERSION" ]; then
            echo "最新版本: v$LATEST_VERSION"
            
            if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
                echo ""
                echo "发现新版本，自动更新 FRPC..."
                # 检测系统架构
                detect_architecture
                # 下载最新版本
                download_frpc
                # 复制文件到安装目录
                cp -f frpc /usr/local/frpc/bin/
                # 设置执行权限
                chmod +x /usr/local/frpc/bin/frpc
                echo ""
                echo "✓ 更新完成！当前版本: v$LATEST_VERSION"
                # 更新监控脚本
                create_monitor_script
                # 配置定时任务
                setup_crontab
                # 自动重启服务以应用更新
                restart_frpc_services
            else
                echo "✓ 当前版本已是最新版本"
            fi
        fi
        
        return 0
    else
        echo "未检测到 FRPC 安装"
        return 1
    fi
}

# 主执行逻辑
echo "========================================"
echo "FRPC 管理工具"
echo "========================================"
echo "检查 FRPC 安装状态..."

if check_installation; then
    echo ""
    echo "FRPC 已安装，进入主菜单..."
else
    echo ""
    echo "FRPC 未安装，开始安装流程..."
    install
fi

# 更新监控脚本
echo ""
echo "更新监控脚本..."
create_monitor_script
# 配置定时任务
setup_crontab

# 进入主菜单
echo ""
echo "----------------------------------------"
echo "现在进入主菜单..."
echo "----------------------------------------"
main_menu
