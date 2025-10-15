#!/bin/bash
# OpenSSH 安全升级脚本 for openEuler 环境
# 版本: 2.2 （适配 openEuler 操作逻辑）
# 日期: 2025-10-15
# 脚本执行成功后请执行 `source /etc/profile` 刷新环境变量

# 全局变量
BACKUP_DIR="/home/ssh-old-bak-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/ssh_upgrade_$(date +%Y%m%d_%H%M%S).log"
TAR_URL="https://string-file.oss-cn-shanghai.aliyuncs.com/202509openssh.tar"
TAR_FILE="/tmp/openssh.tar"
TARGET_DIR="/usr"
NEW_SSH_SERVICE="ssh10.service"   # 服务名改为 ssh10.service
OLD_SSH_SERVICE="ssh.service"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 错误处理函数
error_exit() {
    log "${RED}ERROR: $1${NC}"
    log "${YELLOW}开始回滚操作...${NC}"
    rollback
    exit 1
}

# 回滚函数
rollback() {
    log "开始回滚到原始状态..."
    
    # 停止新的 SSH 服务
    if systemctl is-active --quiet "$NEW_SSH_SERVICE"; then
        log "停止新的 SSH 服务: $NEW_SSH_SERVICE"
        systemctl stop "$NEW_SSH_SERVICE" || log "警告: 停止新服务失败"
    fi
    
    # 只恢复3个核心文件（删除 /etc/ssh 相关恢复逻辑）
    if [ -d "$BACKUP_DIR" ]; then
        log "恢复旧的 SSH 核心文件..."
        
        # 恢复 sshd 二进制文件
        if [ -f "$BACKUP_DIR/sshd" ]; then
            [ -f "/usr/sbin/sshd" ] && mv -f "/usr/sbin/sshd" "/usr/sbin/sshd.new" 2>/dev/null
            mv -f "$BACKUP_DIR/sshd" "/usr/sbin/sshd" || log "警告: 恢复 sshd 二进制文件失败"
        fi
        
        # 恢复 ssh 客户端
        if [ -f "$BACKUP_DIR/ssh" ]; then
            [ -f "/usr/bin/ssh" ] && mv -f "/usr/bin/ssh" "/usr/bin/ssh.new" 2>/dev/null
            mv -f "$BACKUP_DIR/ssh" "/usr/bin/ssh" || log "警告: 恢复 ssh 客户端失败"
        fi
        
        # 恢复 ssh-keygen 工具
        if [ -f "$BACKUP_DIR/ssh-keygen" ]; then
            [ -f "/usr/bin/ssh-keygen" ] && mv -f "/usr/bin/ssh-keygen" "/usr/bin/ssh-keygen.new" 2>/dev/null
            mv -f "$BACKUP_DIR/ssh-keygen" "/usr/bin/ssh-keygen" || log "警告: 恢复 ssh-keygen 工具失败"
        fi
        
        # 恢复 systemd 服务文件（如果需要，可选保留）
        for service_file in sshd-keygen.service sshd.service sshd@.service sshd.socket; do
            if [ -f "$BACKUP_DIR/$service_file" ]; then
                [ -f "/usr/lib/systemd/system/$service_file" ] && mv -f "/usr/lib/systemd/system/$service_file" "/usr/lib/systemd/system/${service_file}.new" 2>/dev/null
                mv -f "$BACKUP_DIR/$service_file" "/usr/lib/systemd/system/$service_file" || log "警告: 恢复 $service_file 失败"
            fi
        done
        
        # 重新加载 systemd 配置
        systemctl daemon-reload
        
        # 启动旧 SSH 服务
        systemctl start "$OLD_SSH_SERVICE" || log "警告: 启动旧 SSH 服务失败"
    fi
    
    # 清理临时文件
    [ -f "$TAR_FILE" ] && rm -f "$TAR_FILE"
    
    log "${YELLOW}回滚操作完成，请检查系统状态${NC}"
}

# 预检查函数
pre_check() {
    log "${GREEN}开始预检查...${NC}"
    
    # 检查 root 权限
    [ "$(id -u)" -ne 0 ] && error_exit "必须以 root 用户运行此脚本"
    
    # 检查网络连通性
    ping -c 1 -W 5 string-file.oss-cn-shanghai.aliyuncs.com >/dev/null 2>&1 || error_exit "无法连接下载服务器，请检查网络"
    
    # 检查必备工具（wget、tar）
    command -v wget >/dev/null 2>&1 || error_exit "wget 未安装，请先安装 wget"
    command -v tar >/dev/null 2>&1 || error_exit "tar 未安装，请先安装 tar"
    
    # 检查原有 SSH 服务状态
    systemctl is-active --quiet "$OLD_SSH_SERVICE" || error_exit "当前 SSH 服务未运行，无法继续升级"
    
    # 检查活跃 SSH 连接（超过 1 个连接时提示确认）
    SSH_CONNECTIONS=$(who | grep -c pts)
    if [ "$SSH_CONNECTIONS" -gt 1 ]; then
        log "${YELLOW}警告: 检测到 $SSH_CONNECTIONS 个活跃 SSH 连接${NC}"
        read -p "是否继续升级? (y/n): " confirm
        [ "$confirm" != "y" ] && error_exit "用户取消升级"
    fi
    
    log "${GREEN}预检查完成，开始升级操作${NC}"
}

# 创建并配置 /var/empty 目录
prepare_var_empty() {
    log "${GREEN}开始创建并配置 /var/empty 目录...${NC}"
    
    # 目录不存在则创建
    [ ! -d "/var/empty" ] && mkdir -p "/var/empty" || log "/var/empty 目录已存在"
    
    # 设置所有者和权限
    chown root:root "/var/empty" || error_exit "设置 /var/empty 所有者失败"
    chmod 711 "/var/empty" || error_exit "设置 /var/empty 权限失败"
    
    log "${GREEN}/var/empty 目录配置完成${NC}"
}

# 下载并解压安装包
download_and_extract() {
    log "${GREEN}开始下载 OpenSSH 安装包...${NC}"
    
    # 下载压缩包
    wget --no-check-certificate -O "$TAR_FILE" "$TAR_URL" || error_exit "下载 OpenSSH 安装包失败"
    [ ! -f "$TAR_FILE" ] || [ ! -s "$TAR_FILE" ] && error_exit "下载的文件为空或损坏"
    
    # 解压到目标目录
    log "下载完成，开始解压..."
    tar -xf "$TAR_FILE" -C "$TARGET_DIR" || error_exit "解压安装包失败"
    [ -d "$TARGET_DIR/openssh" ] || error_exit "解压后未找到 openssh 目录"
    
    log "${GREEN}下载和解压完成${NC}"
}

# 配置环境变量
configure_environment() {
    log "${GREEN}开始配置环境变量...${NC}"
    
    # 备份 profile 文件
    cp -p /etc/profile "/etc/profile.bak.$(date +%Y%m%d_%H%M%S)" || error_exit "备份 /etc/profile 失败"
    
    # 清理旧的 OpenSSH 环境变量配置
    grep -q "OpenSSH 10.2p1 Environment Variables" /etc/profile && \
        sed -i '/# OpenSSH 10.2p1 Environment Variables/,+4d' /etc/profile
    
    # 添加新的环境变量
    cat >> /etc/profile << 'EOF'

# OpenSSH 10.2p1 Environment Variables
export LD_LIBRARY_PATH=/usr/openssh/openssl-3.6.0-beta1/lib64:$LD_LIBRARY_PATH
export PATH=/usr/openssh/openssh-10.2p1/bin:/usr/openssh/openssh-10.2p1/sbin:/usr/openssh/openssl-3.6.0-beta1/bin:$PATH
export CFLAGS="-I/usr/openssh/openssl-3.6.0-beta1/include"
export LDFLAGS="-L/usr/openssh/openssl-3.6.0-beta1/lib64"
EOF
    
    # 验证配置并生效
    grep -q "OpenSSH 10.2p1 Environment Variables" /etc/profile || error_exit "添加环境变量配置失败"
    source /etc/profile
    
    log "${GREEN}环境变量配置完成${NC}"
}

# 创建 systemd 服务文件（ssh10.service）
create_systemd_service() {
    log "${GREEN}开始创建 systemd 服务文件...${NC}"
    
    # 备份已有服务文件（若存在）
    if [ -f "/usr/lib/systemd/system/$NEW_SSH_SERVICE" ]; then
        cp -p "/usr/lib/systemd/system/$NEW_SSH_SERVICE" "/usr/lib/systemd/system/${NEW_SSH_SERVICE}.bak.$(date +%Y%m%d_%H%M%S)"
        log "${YELLOW}已备份现有 $NEW_SSH_SERVICE 服务文件${NC}"
    fi
    
    # 生成 ssh10.service
    cat > "/usr/lib/systemd/system/$NEW_SSH_SERVICE" << 'EOF'
[Unit]
Description=OpenSSH server daemon (v10.2p1)
After=network.target

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=/usr/openssh/openssl-3.6.0-beta1/lib64
ExecStart=/usr/openssh/openssh-10.2p1/sbin/sshd -D -f /usr/openssh/openssh-10.2p1/etc/sshd_config
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target
EOF
    
    # 设置服务文件权限
    chmod 644 "/usr/lib/systemd/system/$NEW_SSH_SERVICE"
    [ -f "/usr/lib/systemd/system/$NEW_SSH_SERVICE" ] || error_exit "创建 $NEW_SSH_SERVICE 服务文件失败"
    
    log "${GREEN}systemd 服务文件创建完成${NC}"
}

# 备份旧 SSH 配置（改进版：备份更多核心文件）
backup_old_config() {
    log "${GREEN}开始备份旧的 SSH 核心文件...${NC}"
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR" || error_exit "创建备份目录失败"
    
    # 只备份3个核心文件
    for file in /usr/sbin/sshd /usr/bin/ssh /usr/bin/ssh-keygen; do
        if [ -f "$file" ]; then
            cp -p "$file" "$BACKUP_DIR/" || log "${YELLOW}警告: 备份 $file 失败${NC}"
            log "成功备份 $file 到 $BACKUP_DIR/"
        else
            log "${YELLOW}警告: $file 文件不存在，跳过备份${NC}"
        fi
    done
    
    # 备份 systemd 服务文件（如果需要，可选保留）
    for service_file in sshd-keygen.service sshd.service sshd@.service sshd.socket; do
        if [ -f "/usr/lib/systemd/system/$service_file" ]; then
            cp -p "/usr/lib/systemd/system/$service_file" "$BACKUP_DIR/" || log "${YELLOW}警告: 备份 $service_file 失败${NC}"
            log "成功备份 $service_file 到 $BACKUP_DIR/"
        else
            log "${YELLOW}警告: $service_file 文件不存在，跳过备份${NC}"
        fi
    done
    
    log "${GREEN}旧文件备份完成，备份目录: $BACKUP_DIR${NC}"
}

# 停止旧 SSH 服务
stop_old_service() {
    log "${GREEN}开始停止旧的 SSH 服务...${NC}"
    
    # 停止并禁用旧服务
    if systemctl is-active --quiet "$OLD_SSH_SERVICE"; then
        systemctl stop "$OLD_SSH_SERVICE" || error_exit "停止旧 SSH 服务失败"
        log "$OLD_SSH_SERVICE 服务已停止"
    else
        log "${YELLOW}警告: $OLD_SSH_SERVICE 服务未运行，跳过停止操作${NC}"
    fi
    
    if systemctl is-enabled --quiet "$OLD_SSH_SERVICE"; then
        systemctl disable "$OLD_SSH_SERVICE" || error_exit "禁用旧 SSH 服务失败"
        log "$OLD_SSH_SERVICE 服务已禁用"
    else
        log "${YELLOW}警告: $OLD_SSH_SERVICE 服务未启用，跳过禁用操作${NC}"
    fi
    
    # 等待服务彻底停止
    sleep 5
    systemctl is-active --quiet "$OLD_SSH_SERVICE" && error_exit "旧 SSH 服务仍在运行，无法继续升级"
    
    log "${GREEN}旧 SSH 服务处理完成${NC}"
}

# 移动旧 SSH 文件到备份目录
move_old_files() {
    log "${GREEN}开始处理旧的 SSH 核心文件...${NC}"
    
    # 只移动3个核心文件（删除所有 /etc/ssh 相关操作）
    for file in /usr/sbin/sshd /usr/bin/ssh /usr/bin/ssh-keygen; do
        if [ -f "$file" ]; then
            # 检查备份目录中是否已有同名文件，有则先删除（避免移动失败）
            if [ -f "$BACKUP_DIR/$(basename $file)" ]; then
                rm -f "$BACKUP_DIR/$(basename $file)" || error_exit "删除旧备份文件 $file 失败"
            fi
            # 移动文件到备份目录
            mv "$file" "$BACKUP_DIR/" || error_exit "移动 $file 到备份目录失败"
            log "成功移动 $file 到 $BACKUP_DIR/"
        else
            log "${YELLOW}警告: $file 文件不存在，跳过移动操作${NC}"
        fi
    done
    
    # 移动 systemd 服务文件（如果需要，可选保留）
    for service_file in sshd-keygen.service sshd.service sshd@.service sshd.socket; do
        if [ -f "/usr/lib/systemd/system/$service_file" ]; then
            if [ -f "$BACKUP_DIR/$service_file" ]; then
                rm -f "$BACKUP_DIR/$service_file" || error_exit "删除旧备份文件 $service_file 失败"
            fi
            mv "/usr/lib/systemd/system/$service_file" "$BACKUP_DIR/" || log "${YELLOW}警告: 移动 $service_file 失败${NC}"
            log "成功移动 $service_file 到 $BACKUP_DIR/"
        else
            log "${YELLOW}警告: $service_file 文件不存在，跳过移动操作${NC}"
        fi
    done
    
    log "${GREEN}旧文件处理完成${NC}"
}

# 启动新 SSH 服务（ssh10.service）
start_new_service() {
    log "${GREEN}开始启动新的 SSH 服务...${NC}"
    
    # 重新加载 systemd 配置
    systemctl daemon-reload || error_exit "重新加载 systemd 配置失败"
    
    # 启动新服务
    systemctl start "$NEW_SSH_SERVICE" || error_exit "启动新 SSH 服务失败"
    
    # 等待服务启动
    sleep 10
    systemctl is-active --quiet "$NEW_SSH_SERVICE" || error_exit "新 SSH 服务启动失败，服务状态异常"
    
    # 设置开机自启
    systemctl enable "$NEW_SSH_SERVICE" || log "${YELLOW}警告: 设置新 SSH 服务开机自启失败${NC}"
    
    # 输出服务状态
    log "新 SSH 服务状态:"
    systemctl status "$NEW_SSH_SERVICE" --no-pager | tee -a "$LOG_FILE"
    
    log "${GREEN}新 SSH 服务启动完成${NC}"
}

# 验证升级结果
verify_upgrade() {
    log "${GREEN}开始验证升级结果...${NC}"
    
    # 验证 SSH 版本
    SSH_VERSION=$(/usr/openssh/openssh-10.2p1/bin/ssh -V 2>&1)
    log "SSH 版本: $SSH_VERSION"
    echo "$SSH_VERSION" | grep -q "OpenSSH_10.2p1" || error_exit "SSH 版本验证失败，未检测到 OpenSSH_10.2p1"
    echo "$SSH_VERSION" | grep -q "OpenSSL 3.6.0-beta1" || error_exit "OpenSSL 版本验证失败，未检测到 OpenSSL 3.6.0-beta1"
    
    # 验证环境变量
    log "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
    [[ "$LD_LIBRARY_PATH" != *"/usr/openssh/openssl-3.6.0-beta1/lib64"* ]] && log "${YELLOW}警告: LD_LIBRARY_PATH 配置异常${NC}"
    [[ "$PATH" != *"/usr/openssh/openssh-10.2p1/bin"* ]] && log "${YELLOW}警告: PATH 配置异常${NC}"
    
    # 验证端口监听
    netstat -tlnp | grep -q ":22" || error_exit "SSH 端口 22 未监听，服务启动异常"
    
    log "${GREEN}升级结果验证完成${NC}"
}

# 测试 SSH 连接（可选，用于验证服务可用性）
# 测试SSH连接函数 - Ubuntu适配版
test_ssh_connection() {
    log "${GREEN}开始测试SSH连接...${NC}"
    
    # 获取本地IP地址（Ubuntu兼容方式）
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP=$(hostname -i | awk '{print $1}')  # 兼容旧版Ubuntu
    fi
    
    if [ -z "$LOCAL_IP" ]; then
        log "${YELLOW}警告: 无法获取本地IP地址，跳过连接测试${NC}"
        return
    fi
    
    log "测试连接到本地IP: $LOCAL_IP"
    
    # 创建测试用户（Ubuntu需要显式指定家目录权限）
    TEST_USER="ssh_test_user_$(date +%s)"
    TEST_PASSWORD=$(openssl rand -base64 12 | tr -d '+/'  # 移除特殊字符，避免密码兼容问题
    )
    
    log "创建测试用户: $TEST_USER"
    # Ubuntu中useradd需加-m创建家目录，-s指定shell避免nologin导致无法登录
    if ! useradd -m -s /bin/bash "$TEST_USER" &> /dev/null; then
        log "${YELLOW}警告: 创建测试用户失败，跳过连接测试${NC}"
        return
    fi
    
    # Ubuntu设置密码（使用chpasswd确保非交互模式生效）
    echo "$TEST_USER:$TEST_PASSWORD" | chpasswd &> /dev/null
    # 强制密码生效（Ubuntu有时需要刷新密码数据库）
    passwd -u "$TEST_USER" &> /dev/null
    
    # 等待用户配置生效
    sleep 3
    
    # 使用密码认证测试SSH连接（Ubuntu默认允许密码认证）
    log "使用密码认证测试SSH连接..."
    # 增加StrictHostKeyChecking=no和UserKnownHostsFile=/dev/null避免首次连接交互
    SSH_TEST_OUTPUT=$(sshpass -p "$TEST_PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$TEST_USER@$LOCAL_IP" "echo SSH_TEST_SUCCESS" 2>&1)
    
    if echo "$SSH_TEST_OUTPUT" | grep -q "SSH_TEST_SUCCESS"; then
        log "${GREEN}SSH连接测试成功${NC}"
    else
        # 密码认证失败时尝试密钥认证
        log "${YELLOW}密码认证失败，尝试密钥认证...${NC}"
        
        # 生成测试密钥（Ubuntu默认ssh-keygen路径兼容）
        ssh-keygen -t rsa -b 2048 -f "/tmp/ssh_test_key" -N "" &> /dev/null
        # Ubuntu的用户家目录权限严格，需确保正确权限
        mkdir -p "/home/$TEST_USER/.ssh"
        cp "/tmp/ssh_test_key.pub" "/home/$TEST_USER/.ssh/authorized_keys"
        chown -R "$TEST_USER:$TEST_USER" "/home/$TEST_USER/.ssh"
        chmod 700 "/home/$TEST_USER/.ssh"
        chmod 600 "/home/$TEST_USER/.ssh/authorized_keys"
        
        # Ubuntu无需SELinux，跳过上下文修复
        
        # 密钥认证测试
        SSH_TEST_OUTPUT=$(ssh -i "/tmp/ssh_test_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "$TEST_USER@$LOCAL_IP" "echo SSH_TEST_SUCCESS" 2>&1)
        
        if echo "$SSH_TEST_OUTPUT" | grep -q "SSH_TEST_SUCCESS"; then
            log "${GREEN}SSH密钥认证测试成功${NC}"
        else
            log "${YELLOW}警告: SSH连接测试失败: $SSH_TEST_OUTPUT${NC}"
        fi
        
        # 清理密钥文件
        rm -f "/tmp/ssh_test_key" "/tmp/ssh_test_key.pub"
    fi
    
    # 清理测试环境（Ubuntu删除用户需加-r递归删除家目录）
    log "清理测试用户: $TEST_USER"
    userdel -r "$TEST_USER" &> /dev/null
    
    log "${GREEN}SSH连接测试完成${NC}"
}

# 主函数
main() {
    log "${GREEN}=============================================${NC}"
    log "${GREEN}开始 OpenSSH 安全升级流程 (版本 2.2)${NC}"
    log "${GREEN}=============================================${NC}"
    
    # 记录系统信息
    log "系统信息:"
    uname -a | tee -a "$LOG_FILE"
    cat /etc/os-release | grep PRETTY_NAME | tee -a "$LOG_FILE"
    
    # 执行升级流程
    pre_check
    prepare_var_empty   # 新增：创建/配置 /var/empty
    download_and_extract
    configure_environment
    create_systemd_service
    backup_old_config
    stop_old_service
    move_old_files
    start_new_service
    verify_upgrade
    test_ssh_connection  # 可选：测试连接
    
    log "${GREEN}=============================================${NC}"
    log "${GREEN}OpenSSH 安全升级完成！${NC}"
    log "${GREEN}新 SSH 服务: $NEW_SSH_SERVICE${NC}"
    log "${GREEN}备份目录: $BACKUP_DIR${NC}"
    log "${GREEN}升级日志: $LOG_FILE${NC}"
    log "${YELLOW}提示: 请执行 'source /etc/profile' 刷新环境变量，且不要断开当前 SSH 连接！${NC}"
    log "${GREEN}=============================================${NC}"
    
    # 清理临时文件
    [ -f "$TAR_FILE" ] && rm -f "$TAR_FILE"
    exit 0
}

# 启动主流程
main