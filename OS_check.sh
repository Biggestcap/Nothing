#!/bin/bash

# 定义颜色变量
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 打印欢迎信息
welcome() {
    echo -e "${GREEN}
============================================
            CentOS 7.9 系统管理工具
============================================
${NC}"
}

# 检查系统信息
check_system_info() {
    echo -e "${BLUE}\n[1] 检查系统信息${NC}"
    echo -e "操作系统: $(cat /etc/redhat-release)"
    echo -e "内核版本: $(uname -r)"
    echo -e "CPU 信息: $(grep 'model name' /proc/cpuinfo | uniq | cut -d ':' -f 2 | xargs)"
    echo -e "内存信息: $(free -h | grep Mem | awk '{print $2}')"
    echo -e "主机名: $(hostname)"
    echo -e "IP 地址: $(hostname -I | awk '{print $1}')"
}

# 检查磁盘使用情况
check_disk_usage() {
    echo -e "${BLUE}\n[2] 检查磁盘使用情况${NC}"
    df -h
}

# 检查网络连接状态
check_network_status() {
    echo -e "${BLUE}\n[3] 检查网络连接状态${NC}"
    ping -c 4 baidu.com &> /dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}网络连接正常${NC}"
    else
        echo -e "${RED}网络连接失败${NC}"
    fi
}

# 清理临时文件和缓存
clean_system() {
    echo -e "${BLUE}\n[4] 清理临时文件和缓存${NC}"
    echo -e "${YELLOW}正在清理临时文件和缓存...${NC}"
    sudo yum clean all
    sudo rm -rf /tmp/*
    sudo rm -rf /var/cache/yum
    echo -e "${GREEN}清理完成！${NC}"
}

# 更新系统
update_system() {
    echo -e "${BLUE}\n[5] 更新系统${NC}"
    echo -e "${YELLOW}正在更新系统...${NC}"
    sudo yum update -y
    echo -e "${GREEN}系统更新完成！${NC}"
}

# 重启或关闭系统
system_control() {
    echo -e "${BLUE}\n[6] 系统控制${NC}"
    echo -e "1) 重启系统"
    echo -e "2) 关闭系统"
    echo -e "3) 返回主菜单"
    read -p "请选择操作 (1/2/3): " choice

    case $choice in
        1)
            echo -e "${YELLOW}正在重启系统...${NC}"
            sudo reboot
            ;;
        2)
            echo -e "${YELLOW}正在关闭系统...${NC}"
            sudo shutdown -h now
            ;;
        3)
            return
            ;;
        *)
            echo -e "${RED}无效选项，请重试！${NC}"
            system_control
            ;;
    esac
}

# 主菜单
main_menu() {
    while true; do
        echo -e "${BLUE}\n请选择操作：${NC}"
        echo -e "1) 检查系统信息"
        echo -e "2) 检查磁盘使用情况"
        echo -e "3) 检查网络连接状态"
        echo -e "4) 清理临时文件和缓存"
        echo -e "5) 更新系统"
        echo -e "6) 系统控制"
        echo -e "7) 退出"
        read -p "请输入选项 (1-7): " option

        case $option in
            1) check_system_info ;;
            2) check_disk_usage ;;
            3) check_network_status ;;
            4) clean_system ;;
            5) update_system ;;
            6) system_control ;;
            7)
                echo -e "${GREEN}退出脚本。${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重试！${NC}"
                ;;
        esac
    done
}

# 脚本入口
welcome
main_menu
