#!/bin/bash
# OpenSSH安全升级脚本 for 生产环境
# 版本: 2.1 （更新最后认证功能）
# 日期: 2025-10-13
# 脚本执行成功最后请source一下环境profile文件

# 全局变量
BACKUP_DIR="/home/ssh-old-bak-$(date +%Y%m%d_%H%M%S)"
LOG_FILE="/var/log/ssh_upgrade_$(date +%Y%m%d_%H%M%S).log"
TAR_URL="https://string-file.oss-cn-shanghai.aliyuncs.com/202509openssh.tar"
TAR_FILE="/tmp/openssh.tar"
TARGET_DIR="/usr"
NEW_SSH_SERVICE="sshd10.service"
OLD_SSH_SERVICE="sshd.service"

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
    
    # 停止新的ssh服务
    if systemctl is-active --quiet "$NEW_SSH_SERVICE"; then
        log "停止新的SSH服务: $NEW_SSH_SERVICE"
        systemctl stop "$NEW_SSH_SERVICE" || log "警告: 停止新服务失败"
    fi
    
    # 恢复旧的ssh服务
    if [ -d "$BACKUP_DIR" ]; then
        log "恢复旧的SSH配置文件..."
        
        # 恢复sshd二进制文件
        if [ -f "$BACKUP_DIR/sshd" ]; then
            # 如果目标文件存在，先备份
            if [ -f "/usr/sbin/sshd" ]; then
                mv -f "/usr/sbin/sshd" "/usr/sbin/sshd.new" || log "警告: 备份新sshd文件失败"
            fi
            mv -f "$BACKUP_DIR/sshd" "/usr/sbin/sshd" || log "警告: 恢复sshd二进制文件失败"
        fi
        
        # 恢复配置目录
        if [ -d "$BACKUP_DIR/ssh" ]; then
            # 如果目标目录存在，先备份
            if [ -d "/etc/ssh" ]; then
                mv -f "/etc/ssh" "/etc/ssh.new" || log "警告: 备份新ssh配置目录失败"
            fi
            mv -f "$BACKUP_DIR/ssh" "/etc/ssh" || log "警告: 恢复/etc/ssh目录失败"
        fi
        
        # 恢复systemd服务文件
        for service_file in sshd-keygen.service sshd.service sshd@.service sshd.socket; do
            if [ -f "$BACKUP_DIR/$service_file" ]; then
                # 如果目标文件存在，先备份
                if [ -f "/usr/lib/systemd/system/$service_file" ]; then
                    mv -f "/usr/lib/systemd/system/$service_file" "/usr/lib/systemd/system/${service_file}.new" || log "警告: 备份新$service_file失败"
                fi
                mv -f "$BACKUP_DIR/$service_file" "/usr/lib/systemd/system/$service_file" || log "警告: 恢复$service_file失败"
            fi
        done
        
        # 重新加载systemd配置
        systemctl daemon-reload
        
        # 启动旧的ssh服务
        if systemctl is-enabled --quiet "$OLD_SSH_SERVICE"; then
            systemctl start "$OLD_SSH_SERVICE" || log "警告: 启动旧SSH服务失败"
        fi
    fi
    
    # 清理临时文件
    if [ -f "$TAR_FILE" ]; then
        rm -f "$TAR_FILE"
    fi
    
    log "${YELLOW}回滚操作完成，请检查系统状态${NC}"
}

# 预检查函数
pre_check() {
    log "${GREEN}开始预检查...${NC}"
    
    # 检查是否以root用户运行
    if [ "$(id -u)" -ne 0 ]; then
        error_exit "必须以root用户运行此脚本"
    fi
    
    # 检查网络连接
    if ! ping -c 1 -W 5 string-file.oss-cn-shanghai.aliyuncs.com > /dev/null 2>&1; then
        error_exit "无法连接到下载服务器，请检查网络连接"
    fi
    
    # 检查wget是否安装
    if ! command -v wget &> /dev/null; then
        error_exit "wget未安装，请先安装wget"
    fi
    
    # 检查tar是否安装
    if ! command -v tar &> /dev/null; then
        error_exit "tar未安装，请先安装tar"
    fi
    
    # 检查当前ssh服务状态
    if ! systemctl is-active --quiet "$OLD_SSH_SERVICE"; then
        error_exit "当前SSH服务未运行，无法继续升级"
    fi
    
    # 检查是否有正在进行的ssh连接
    SSH_CONNECTIONS=$(who | grep -c pts)
    if [ "$SSH_CONNECTIONS" -gt 1 ]; then
        log "${YELLOW}警告: 检测到$SSH_CONNECTIONS个活跃的SSH连接${NC}"
        read -p "是否继续升级? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            error_exit "用户取消了升级操作"
        fi
    fi
    
    log "${GREEN}预检查完成，开始升级操作${NC}"
}

# 下载和解压函数
download_and_extract() {
    log "${GREEN}开始下载OpenSSH安装包...${NC}"
    
    # 下载tar包
    if ! wget --no-check-certificate -O "$TAR_FILE" "$TAR_URL"; then
        error_exit "下载OpenSSH安装包失败"
    fi
    
    # 验证文件是否下载成功
    if [ ! -f "$TAR_FILE" ] || [ ! -s "$TAR_FILE" ]; then
        error_exit "下载的文件为空或不存在"
    fi
    
    log "下载完成，开始解压..."
    
    # 解压到/usr目录
    if ! tar -xf "$TAR_FILE" -C "$TARGET_DIR"; then
        error_exit "解压安装包失败"
    fi
    
    # 验证解压结果
    if [ ! -d "$TARGET_DIR/openssh" ]; then
        error_exit "解压后未找到openssh目录"
    fi
    
    log "${GREEN}下载和解压完成${NC}"
}

# 配置环境变量函数
configure_environment() {
    log "${GREEN}开始配置环境变量...${NC}"
    
    # 备份profile文件
    cp -p /etc/profile "/etc/profile.bak.$(date +%Y%m%d_%H%M%S)" || error_exit "备份/etc/profile失败"
    
    # 检查环境变量是否已存在，如果存在则更新
    if grep -q "OpenSSH 10.2p1 Environment Variables" /etc/profile; then
        log "${YELLOW}环境变量配置已存在，更新配置...${NC}"
        # 删除旧的配置
        sed -i '/# OpenSSH 10.2p1 Environment Variables/,+4d' /etc/profile
    fi
    
    # 添加环境变量配置
    cat >> /etc/profile << 'EOF'

# OpenSSH 10.2p1 Environment Variables
export LD_LIBRARY_PATH=/usr/openssh/openssl-3.6.0-beta1/lib64:$LD_LIBRARY_PATH
export PATH=/usr/openssh/openssh-10.2p1/bin:/usr/openssh/openssh-10.2p1/sbin:/usr/openssh/openssl-3.6.0-beta1/bin:$PATH
export CFLAGS="-I/usr/openssh/openssl-3.6.0-beta1/include"
export LDFLAGS="-L/usr/openssh/openssl-3.6.0-beta1/lib64"
EOF
    
    # 验证配置是否添加成功
    if ! grep -q "OpenSSH 10.2p1 Environment Variables" /etc/profile; then
        error_exit "添加环境变量配置失败"
    fi
    
    # 立即生效环境变量
    source /etc/profile
    
    log "${GREEN}环境变量配置完成${NC}"
}

# 创建systemd服务文件函数
create_systemd_service() {
    log "${GREEN}开始创建systemd服务文件...${NC}"
    
    # 备份现有服务文件（如果存在）
    if [ -f "/usr/lib/systemd/system/$NEW_SSH_SERVICE" ]; then
        cp -p "/usr/lib/systemd/system/$NEW_SSH_SERVICE" "/usr/lib/systemd/system/${NEW_SSH_SERVICE}.bak.$(date +%Y%m%d_%H%M%S)"
        log "${YELLOW}已备份现有$NEW_SSH_SERVICE服务文件${NC}"
    fi
    
    # 创建sshd10.service文件
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
    
    # 设置文件权限
    chmod 644 "/usr/lib/systemd/system/$NEW_SSH_SERVICE"
    
    # 验证服务文件是否创建成功
    if [ ! -f "/usr/lib/systemd/system/$NEW_SSH_SERVICE" ]; then
        error_exit "创建$NEW_SSH_SERVICE服务文件失败"
    fi
    
    log "${GREEN}systemd服务文件创建完成${NC}"
}

# 备份旧配置函数 - 改进版
backup_old_config() {
    log "${GREEN}开始备份旧的SSH配置...${NC}"
    
    # 创建备份目录
    if ! mkdir -p "$BACKUP_DIR"; then
        error_exit "创建备份目录失败"
    fi
    
    # 备份配置目录 - 先检查是否存在
    if [ -d "/etc/ssh" ]; then
        log "备份/etc/ssh目录..."
        # 使用cp而不是mv，确保源文件保持不变
        if ! cp -rp /etc/ssh "$BACKUP_DIR/"; then
            error_exit "备份/etc/ssh失败"
        fi
        log "成功备份/etc/ssh到$BACKUP_DIR/"
    else
        log "${YELLOW}警告: /etc/ssh目录不存在，跳过备份${NC}"
    fi
    
    # 备份sshd二进制文件
    if [ -f "/usr/sbin/sshd" ]; then
        log "备份sshd二进制文件..."
        if ! cp -p /usr/sbin/sshd "$BACKUP_DIR/"; then
            error_exit "备份sshd二进制文件失败"
        fi
        log "成功备份sshd到$BACKUP_DIR/"
    else
        log "${YELLOW}警告: /usr/sbin/sshd文件不存在，跳过备份${NC}"
    fi
    
    # 备份systemd服务文件
    for service_file in sshd-keygen.service sshd.service sshd@.service sshd.socket; do
        if [ -f "/usr/lib/systemd/system/$service_file" ]; then
            log "备份$service_file服务文件..."
            if ! cp -p "/usr/lib/systemd/system/$service_file" "$BACKUP_DIR/"; then
                log "${YELLOW}警告: 备份$service_file失败${NC}"
            else
                log "成功备份$service_file到$BACKUP_DIR/"
            fi
        else
            log "${YELLOW}警告: $service_file文件不存在，跳过备份${NC}"
        fi
    done
    
    log "${GREEN}旧配置备份完成，备份目录: $BACKUP_DIR${NC}"
}

# 停止旧服务函数
stop_old_service() {
    log "${GREEN}开始停止旧的SSH服务...${NC}"
    
    # 停止sshd服务
    if systemctl is-active --quiet "$OLD_SSH_SERVICE"; then
        log "停止$OLD_SSH_SERVICE服务..."
        if ! systemctl stop "$OLD_SSH_SERVICE"; then
            error_exit "停止旧SSH服务失败"
        fi
        log "$OLD_SSH_SERVICE服务已停止"
    else
        log "${YELLOW}警告: $OLD_SSH_SERVICE服务未运行，跳过停止操作${NC}"
    fi
    
    # 禁用sshd服务
    if systemctl is-enabled --quiet "$OLD_SSH_SERVICE"; then
        log "禁用$OLD_SSH_SERVICE服务..."
        if ! systemctl disable "$OLD_SSH_SERVICE"; then
            error_exit "禁用旧SSH服务失败"
        fi
        log "$OLD_SSH_SERVICE服务已禁用"
    else
        log "${YELLOW}警告: $OLD_SSH_SERVICE服务未启用，跳过禁用操作${NC}"
    fi
    
    # 等待服务完全停止
    sleep 5
    
    # 验证服务是否已停止
    if systemctl is-active --quiet "$OLD_SSH_SERVICE"; then
        error_exit "旧SSH服务仍在运行，无法继续升级"
    fi
    
    log "${GREEN}旧SSH服务处理完成${NC}"
}

# 移动旧文件函数 - 改进版
move_old_files() {
    log "${GREEN}开始处理旧的SSH文件...${NC}"
    
    # 移动配置目录 - 先检查是否存在
    if [ -d "/etc/ssh" ]; then
        log "移动/etc/ssh目录到备份目录..."
        # 使用mv命令，先检查目标是否存在
        if [ -d "$BACKUP_DIR/ssh" ]; then
            # 如果目标存在，先删除（因为我们已经用cp备份过了）
            rm -rf "$BACKUP_DIR/ssh" || error_exit "删除旧备份目录失败"
        fi
        if ! mv /etc/ssh "$BACKUP_DIR/"; then
            error_exit "移动/etc/ssh失败"
        fi
        log "成功移动/etc/ssh到$BACKUP_DIR/"
    else
        log "${YELLOW}警告: /etc/ssh目录不存在，跳过移动操作${NC}"
    fi
    
    # 移动sshd二进制文件
    if [ -f "/usr/sbin/sshd" ]; then
        log "移动sshd二进制文件到备份目录..."
        # 使用mv命令，先检查目标是否存在
        if [ -f "$BACKUP_DIR/sshd" ]; then
            # 如果目标存在，先删除（因为我们已经用cp备份过了）
            rm -f "$BACKUP_DIR/sshd" || error_exit "删除旧备份文件失败"
        fi
        if ! mv /usr/sbin/sshd "$BACKUP_DIR/"; then
            error_exit "移动sshd二进制文件失败"
        fi
        log "成功移动sshd到$BACKUP_DIR/"
    else
        log "${YELLOW}警告: /usr/sbin/sshd文件不存在，跳过移动操作${NC}"
    fi
    
    # 移动systemd服务文件
    for service_file in sshd-keygen.service sshd.service sshd@.service sshd.socket; do
        if [ -f "/usr/lib/systemd/system/$service_file" ]; then
            log "移动$service_file服务文件到备份目录..."
            # 使用mv命令，先检查目标是否存在
            if [ -f "$BACKUP_DIR/$service_file" ]; then
                # 如果目标存在，先删除（因为我们已经用cp备份过了）
                rm -f "$BACKUP_DIR/$service_file" || error_exit "删除旧备份文件失败"
            fi
            if ! mv "/usr/lib/systemd/system/$service_file" "$BACKUP_DIR/"; then
                log "${YELLOW}警告: 移动$service_file失败${NC}"
            else
                log "成功移动$service_file到$BACKUP_DIR/"
            fi
        else
            log "${YELLOW}警告: $service_file文件不存在，跳过移动操作${NC}"
        fi
    done
    
    log "${GREEN}旧文件处理完成${NC}"
}

# 启动新服务函数
start_new_service() {
    log "${GREEN}开始启动新的SSH服务...${NC}"
    
    # 重新加载systemd配置
    log "重新加载systemd配置..."
    if ! systemctl daemon-reload; then
        error_exit "重新加载systemd配置失败"
    fi
    
    # 启动新的ssh服务
    log "启动$NEW_SSH_SERVICE服务..."
    if ! systemctl start "$NEW_SSH_SERVICE"; then
        error_exit "启动新SSH服务失败"
    fi
    
    # 等待服务启动
    log "等待服务启动..."
    sleep 10
    
    # 验证服务状态
    if ! systemctl is-active --quiet "$NEW_SSH_SERVICE"; then
        error_exit "新SSH服务启动失败，服务状态异常"
    fi
    
    # 设置开机自启
    log "设置$NEW_SSH_SERVICE服务开机自启..."
    if ! systemctl enable "$NEW_SSH_SERVICE"; then
        log "${YELLOW}警告: 设置新SSH服务开机自启失败${NC}"
    fi
    
    # 显示服务状态
    log "新SSH服务状态:"
    systemctl status "$NEW_SSH_SERVICE" --no-pager | tee -a "$LOG_FILE"
    
    log "${GREEN}新SSH服务启动完成${NC}"
}

# 验证升级结果函数
verify_upgrade() {
    log "${GREEN}开始验证升级结果...${NC}"
    
    # 验证ssh版本
    log "验证SSH版本:"
    SSH_VERSION=$(/usr/openssh/openssh-10.2p1/bin/ssh -V 2>&1)
    log "$SSH_VERSION"
    
    if ! echo "$SSH_VERSION" | grep -q "OpenSSH_10.2p1"; then
        error_exit "SSH版本验证失败，未检测到OpenSSH_10.2p1"
    fi
    
    if ! echo "$SSH_VERSION" | grep -q "OpenSSL 3.6.0-beta1"; then
        error_exit "OpenSSL版本验证失败，未检测到OpenSSL 3.6.0-beta1"
    fi
    
    # 验证环境变量
    log "验证环境变量:"
    if [ -z "$LD_LIBRARY_PATH" ] || [[ "$LD_LIBRARY_PATH" != "/usr/openssh/openssl-3.6.0-beta1/lib64:"* ]]; then
        log "${YELLOW}警告: LD_LIBRARY_PATH环境变量设置不正确${NC}"
    else
        log "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
    fi
    
    if [ -z "$PATH" ] || [[ "$PATH" != "/usr/openssh/openssh-10.2p1/bin:"* ]]; then
        log "${YELLOW}警告: PATH环境变量设置不正确${NC}"
    else
        log "PATH包含新的SSH路径"
    fi
    
    # 验证服务端口
    log "验证SSH端口状态:"
    if ! netstat -tlnp | grep -q ":22"; then
        error_exit "SSH端口22未监听，服务启动异常"
    fi
    
    log "${GREEN}升级结果验证完成${NC}"
}

# 测试SSH连接函数 - 修复版
test_ssh_connection() {
    log "${GREEN}开始测试SSH连接...${NC}"
    
    # 获取本地IP地址
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    
    if [ -z "$LOCAL_IP" ]; then
        log "${YELLOW}警告: 无法获取本地IP地址，跳过连接测试${NC}"
        return
    fi
    
    log "测试连接到本地IP: $LOCAL_IP"
    
    # 创建测试用户（如果不存在）
    TEST_USER="ssh_test_user_$(date +%s)"
    TEST_PASSWORD=$(openssl rand -base64 12)
    
    log "创建测试用户: $TEST_USER"
    if ! useradd -m "$TEST_USER" &> /dev/null; then
        log "${YELLOW}警告: 创建测试用户失败，跳过连接测试${NC}"
        return
    fi
    
    # 设置测试用户密码
    echo "$TEST_USER:$TEST_PASSWORD" | chpasswd &> /dev/null
    
    # 等待密码生效
    sleep 2
    
    # 使用密码认证测试SSH连接
    log "使用密码认证测试SSH连接..."
    SSH_TEST_OUTPUT=$(sshpass -p "$TEST_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TEST_USER@$LOCAL_IP" "echo SSH_TEST_SUCCESS" 2>&1)
    
    if echo "$SSH_TEST_OUTPUT" | grep -q "SSH_TEST_SUCCESS"; then
        log "${GREEN}SSH连接测试成功${NC}"
    else
        # 如果密码认证失败，尝试密钥认证
        log "${YELLOW}密码认证失败，尝试密钥认证...${NC}"
        
        # 生成测试密钥
        ssh-keygen -t rsa -b 2048 -f "/tmp/ssh_test_key" -N "" &> /dev/null
        mkdir -p "/home/$TEST_USER/.ssh"
        cp "/tmp/ssh_test_key.pub" "/home/$TEST_USER/.ssh/authorized_keys"
        chown -R "$TEST_USER:$TEST_USER" "/home/$TEST_USER/.ssh"
        chmod 700 "/home/$TEST_USER/.ssh"
        chmod 600 "/home/$TEST_USER/.ssh/authorized_keys"
        
        # 修复SELinux上下文（如果启用）
        if command -v restorecon &> /dev/null; then
            restorecon -R "/home/$TEST_USER/.ssh" &> /dev/null
        fi
        
        # 使用密钥认证测试
        SSH_TEST_OUTPUT=$(ssh -i "/tmp/ssh_test_key" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TEST_USER@$LOCAL_IP" "echo SSH_TEST_SUCCESS" 2>&1)
        
        if echo "$SSH_TEST_OUTPUT" | grep -q "SSH_TEST_SUCCESS"; then
            log "${GREEN}SSH密钥认证测试成功${NC}"
        else
            log "${YELLOW}警告: SSH连接测试失败: $SSH_TEST_OUTPUT${NC}"
            # 不中断升级，只记录警告
        fi
        
        # 清理密钥文件
        rm -f "/tmp/ssh_test_key" "/tmp/ssh_test_key.pub"
    fi
    
    # 清理测试环境
    log "清理测试用户: $TEST_USER"
    userdel -r "$TEST_USER" &> /dev/null
    
    log "${GREEN}SSH连接测试完成${NC}"
}

# 主函数
main() {
    log "${GREEN}=============================================${NC}"
    log "${GREEN}开始OpenSSH安全升级流程 (版本2.1)${NC}"
    log "${GREEN}=============================================${NC}"
    
    # 记录系统信息
    log "系统信息:"
    uname -a | tee -a "$LOG_FILE"
    cat /etc/os-release | grep PRETTY_NAME | tee -a "$LOG_FILE"
    
    # 执行各个步骤
    pre_check
    download_and_extract
    configure_environment
    create_systemd_service
    backup_old_config
    stop_old_service
    move_old_files
    start_new_service
    verify_upgrade
    test_ssh_connection
    
    log "${GREEN}=============================================${NC}"
    log "${GREEN}OpenSSH安全升级完成！${NC}"
    log "${GREEN}新SSH服务: $NEW_SSH_SERVICE${NC}"
    log "${GREEN}备份目录: $BACKUP_DIR${NC}"
    log "${GREEN}升级日志: $LOG_FILE${NC}"
    log "${YELLOW}提示: 请不要断开连接，执行'source /etc/profile'刷新环境变量！${NC}"
    log "${GREEN}=============================================${NC}"
    
    # 清理临时文件
    if [ -f "$TAR_FILE" ]; then
        rm -f "$TAR_FILE"
    fi
    
    exit 0
}

# 启动主函数
main
