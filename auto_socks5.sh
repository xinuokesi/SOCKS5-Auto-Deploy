#!/bin/bash

# ==============================================================================
#
# V2Ray SOCKS5 全功能管理脚本 
#
# ==============================================================================

# --- 全局变量和配置 ---

SCRIPT_VERSION="3.0.1"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

V2RAY_CONFIG_PATH="/usr/local/etc/v2ray/config.json"
V2RAY_SERVICE_PATH="/etc/systemd/system/v2ray.service"
V2RAY_AUTOSTART_LINK="/etc/systemd/system/multi-user.target.wants/v2ray.service"
V2RAY_LOG_DIR="/var/log/v2ray"

# --- 辅助功能函数 ---

check_root() {
    if [ "$(id -u)" -ne 0 ]; then echo -e "${RED}错误：此脚本必须以 root 权限运行。${NC}"; exit 1; fi
}

check_dependencies() {
    echo -e "${BLUE}正在检查系统依赖...${NC}"
    local deps="curl unzip jq lsof"
    local missing=""
    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing="$missing $dep"
        fi
    done
    if [ -n "$missing" ]; then
        echo -e "${YELLOW}检测到依赖缺失:${missing}。正在尝试安装...${NC}"
        apt-get update && apt-get install -y $missing
        if [ $? -ne 0 ]; then echo -e "${RED}依赖安装失败。${NC}"; exit 1; fi
    fi
    echo -e "${GREEN}所有依赖项均已安装。${NC}"
}

is_v2ray_installed() {
    [ -f "$V2RAY_SERVICE_PATH" ] && command -v v2ray >/dev/null 2>&1
}

check_service_status() {
    if ! systemctl is-active --quiet v2ray; then
        echo -e "${RED}--------------------------------------------------${NC}"
        echo -e "${RED}错误：V2Ray 服务未能成功运行！${NC}"
        echo -e "${YELLOW}请使用菜单中的“查看日志”功能来诊断问题。${NC}"
        echo -e "${RED}--------------------------------------------------${NC}"
        return 1
    fi
    return 0
}

restart_v2ray_and_check() {
    echo -e "${BLUE}正在重启 V2Ray 服务...${NC}"
    systemctl restart v2ray
    sleep 2
    check_service_status
}

# --- 核心功能函数 ---

install_v2ray() {
    if is_v2ray_installed; then echo -e "${YELLOW}V2Ray 已安装，无需重复安装。${NC}"; return; fi
    
    echo -e "${BLUE}正在从官方源安装 V2Ray 核心文件...${NC}"
    bash <(curl -L -s https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    if [ $? -ne 0 ]; then echo -e "${RED}V2Ray 核心安装失败。${NC}"; exit 1; fi

    echo -e "${BLUE}强制创建并设置日志目录权限...${NC}"
    mkdir -p "$V2RAY_LOG_DIR"
    touch "$V2RAY_LOG_DIR/access.log" "$V2RAY_LOG_DIR/error.log"
    chown -R root:root "$V2RAY_LOG_DIR"
    chmod 755 "$V2RAY_LOG_DIR"
    chmod 644 "$V2RAY_LOG_DIR"/*.log

    echo -e "${BLUE}正在创建 SOCKS5 配置文件...${NC}"
    mkdir -p "$(dirname "$V2RAY_CONFIG_PATH")"
    cat > "$V2RAY_CONFIG_PATH" <<EOF
{
  "log": { "access": "/var/log/v2ray/access.log", "error": "/var/log/v2ray/error.log", "loglevel": "warning" },
  "inbounds": [ { "port": 10800, "listen": "0.0.0.0", "protocol": "socks", "settings": { "auth": "password", "accounts": [], "udp": true } } ],
  "outbounds": [ { "protocol": "freedom", "settings": {} } ]
}
EOF

    echo -e "${YELLOW}正在创建与 Debian/Ubuntu 兼容的 systemd 服务文件...${NC}"
    cat > "$V2RAY_SERVICE_PATH" <<EOF
[Unit]
Description=V2Ray Service
Documentation=https://www.v2fly.org/
After=network.target nss-lookup.target

[Service]
User=root
ExecStart=/usr/local/bin/v2ray run -config ${V2RAY_CONFIG_PATH}
Restart=on-failure
RestartSec=5s
LimitNPROC=infinity
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${BLUE}正在重载 systemd 并启动服务...${NC}"
    systemctl daemon-reload
    systemctl start v2ray
    if ! check_service_status; then return; fi
    
    echo -e "${YELLOW}正在手动创建开机自启链接 (绕过 systemctl enable)...${NC}"
    ln -sf "$V2RAY_SERVICE_PATH" "$V2RAY_AUTOSTART_LINK"
    
    echo -e "${GREEN}V2Ray 安装并初始化成功！${NC}"
    if [ -L "$V2RAY_AUTOSTART_LINK" ]; then
        echo -e "${GREEN}开机自启已成功设置！${NC}"
    else
        echo -e "${RED}错误：开机自启设置失败！${NC}"
    fi
    echo -e "${GREEN}服务自带保活功能，如果意外崩溃将在5秒后自动重启。${NC}"
}

uninstall_v2ray() {
    if ! is_v2ray_installed; then echo -e "${YELLOW}V2Ray 未安装。${NC}"; return; fi
    read -p "确定要完全移除 V2Ray 及其所有配置吗？ (y/n): " confirm
    if [ "$confirm" != "y" ]; then echo "操作已取消。"; return; fi
    
    systemctl stop v2ray
    echo -e "${BLUE}正在移除开机自启链接...${NC}"
    rm -f "$V2RAY_AUTOSTART_LINK"
    systemctl disable v2ray &> /dev/null
    
    echo -e "${BLUE}正在清理文件...${NC}"
    rm -rf "$(dirname "$V2RAY_CONFIG_PATH")" "$V2RAY_LOG_DIR"
    rm -f "$V2RAY_SERVICE_PATH"
    
    systemctl daemon-reload
    echo -e "${GREEN}V2Ray 已成功卸载。官方核心文件可能保留，可忽略。${NC}"
}

toggle_autostart() {
    if ! is_v2ray_installed; then echo -e "${RED}请先安装 V2Ray。${NC}"; return; fi
    
    if [ -L "$V2RAY_AUTOSTART_LINK" ]; then
        echo -e "${YELLOW}当前开机自启为“已启用”状态，正在禁用...${NC}"
        rm -f "$V2RAY_AUTOSTART_LINK"
        if [ ! -L "$V2RAY_AUTOSTART_LINK" ]; then
            echo -e "${GREEN}开机自启已成功禁用。${NC}"
        else
            echo -e "${RED}操作失败！${NC}"
        fi
    else
        echo -e "${YELLOW}当前开机自启为“已禁用”状态，正在启用...${NC}"
        ln -sf "$V2RAY_SERVICE_PATH" "$V2RAY_AUTOSTART_LINK"
        if [ -L "$V2RAY_AUTOSTART_LINK" ]; then
            echo -e "${GREEN}开机自启已成功启用。${NC}"
        else
            echo -e "${RED}操作失败！${NC}"
        fi
    fi
    systemctl daemon-reload
}

configure_port() {
    if ! is_v2ray_installed; then echo -e "${RED}请先安装 V2Ray。${NC}"; return; fi
    local current_port=$(jq -r '.inbounds[0].port' "$V2RAY_CONFIG_PATH")
    read -p "当前端口为 ${current_port}。请输入新端口 (1024-65535): " new_port
    case "$new_port" in
        ''|*[!0-9]*) echo -e "${RED}输入无效，请输入纯数字。${NC}"; return ;;
        *)
            if [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
                echo -e "${RED}端口号必须在 1024-65535 之间。${NC}"; return;
            fi ;;
    esac
    local tmp_config=$(mktemp)
    jq --argjson p "$new_port" '.inbounds[0].port = $p' "$V2RAY_CONFIG_PATH" > "$tmp_config" && mv "$tmp_config" "$V2RAY_CONFIG_PATH"
    if restart_v2ray_and_check; then echo -e "${GREEN}端口已成功设置为 ${new_port}。${NC}"; fi
}

add_custom_user(){
    if ! is_v2ray_installed; then echo -e "${RED}请先安装 V2Ray。${NC}"; return; fi
    read -p "请输入自定义用户名: " user
    if [ -z "$user" ]; then echo -e "${RED}用户名不能为空。${NC}"; return; fi
    read -p "请输入自定义密码: " pass
    if [ -z "$pass" ]; then echo -e "${RED}密码不能为空。${NC}"; return; fi
    local tmp_config=$(mktemp)
    jq --arg u "$user" --arg p "$pass" '.inbounds[0].settings.accounts += [{"user": $u, "pass": $p}]' "$V2RAY_CONFIG_PATH" > "$tmp_config" && mv "$tmp_config" "$V2RAY_CONFIG_PATH"
    if restart_v2ray_and_check; then echo -e "${GREEN}自定义用户 '${user}' 添加成功！${NC}"; fi
}

add_random_user(){
    if ! is_v2ray_installed; then echo -e "${RED}请先安装 V2Ray。${NC}"; return; fi
    local user=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 8 | head -n 1)
    local pass=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 16 | head -n 1)
    local tmp_config=$(mktemp)
    jq --arg u "$user" --arg p "$pass" '.inbounds[0].settings.accounts += [{"user": $u, "pass": $p}]' "$V2RAY_CONFIG_PATH" > "$tmp_config" && mv "$tmp_config" "$V2RAY_CONFIG_PATH"
    if restart_v2ray_and_check; then
        echo -e "${GREEN}随机用户添加成功！${NC}"
        echo -e "用户名: ${YELLOW}${user}${NC}"
        echo -e "密  码: ${YELLOW}${pass}${NC}"
    fi
}

list_users() {
    if ! is_v2ray_installed; then echo -e "${RED}请先安装 V2Ray。${NC}"; return; fi
    local user_count=$(jq '.inbounds[0].settings.accounts | length' "$V2RAY_CONFIG_PATH")
    if [ "$user_count" -eq 0 ]; then
        echo -e "${YELLOW}当前没有配置任何用户。${NC}"
    else
        echo -e "${BLUE}--- 用户列表 (共 ${user_count} 个) ---${NC}"
        jq -r '.inbounds[0].settings.accounts[] | "  - 用户名: \u001b[33m" + .user + "\u001b[0m, 密码: \u001b[33m" + .pass + "\u001b[0m"' "$V2RAY_CONFIG_PATH"
    fi
}

remove_user() {
    if ! is_v2ray_installed; then echo -e "${RED}请先安装 V2Ray。${NC}"; return; fi
    local users_list=$(jq -r '.inbounds[0].settings.accounts[].user' "$V2RAY_CONFIG_PATH")
    if [ -z "$users_list" ]; then echo -e "${YELLOW}当前没有用户可供移除。${NC}"; return; fi
    echo -e "${YELLOW}请选择要移除的用户:${NC}"
    local i=1
    for user in $users_list; do echo "  ${GREEN}${i})${NC} ${user}"; i=$((i + 1)); done
    local user_count=$(echo "$users_list" | wc -l)
    local choice
    read -p "请输入选项 [1-${user_count}]: " choice
    if ! [ "$choice" -ge 1 ] 2>/dev/null || ! [ "$choice" -le "$user_count" ] 2>/dev/null; then
        echo -e "${RED}无效输入。${NC}"; return;
    fi
    local user_to_remove=$(echo "$users_list" | sed -n "${choice}p")
    read -p "确定要移除用户 '${user_to_remove}' 吗？ (y/n): " confirm
    if [ "$confirm" = "y" ]; then
        local tmp_config=$(mktemp)
        jq --arg u "$user_to_remove" '.inbounds[0].settings.accounts |= map(select(.user != $u))' "$V2RAY_CONFIG_PATH" > "$tmp_config" && mv "$tmp_config" "$V2RAY_CONFIG_PATH"
        if restart_v2ray_and_check; then echo -e "${GREEN}用户 '${user_to_remove}' 已被移除。${NC}"; fi
    else
        echo "操作已取消。"
    fi
}

view_logs() {
    if ! is_v2ray_installed; then echo -e "${RED}请先安装 V2Ray。${NC}"; return; fi
    clear
    echo -e "${GREEN}--- 日志查看菜单 ---${NC}"
    echo -e "${YELLOW}===================================================${NC}"
    echo -e "  ${GREEN}1)${NC} 查看 V2Ray 实时日志 (按 Ctrl+C 退出)"
    echo -e "  ${GREEN}2)${NC} 查看 V2Ray 最近100行日志"
    echo -e "  ${GREEN}3)${NC} 返回主菜单"
    echo -e "${YELLOW}===================================================${NC}"
    echo
    read -p "请输入选项 [1-3]: " choice
    case "$choice" in
        1) journalctl -u v2ray -f --no-pager ;;
        2) journalctl -u v2ray -n 100 --no-pager ;;
        3) return ;;
        *) echo -e "${RED}无效输入。${NC}" ;;
    esac
}

show_status() {
    clear
    if ! is_v2ray_installed; then echo -e "${YELLOW}V2Ray 未安装。${NC}"; return; fi
    local service_status autostart_status public_ip port
    if systemctl is-active --quiet v2ray; then service_status="${GREEN}运行中 (Active)${NC}"; else service_status="${RED}未运行 (Inactive)${NC}"; fi
    if [ -L "$V2RAY_AUTOSTART_LINK" ]; then autostart_status="${GREEN}已启用${NC}"; else autostart_status="${RED}已禁用${NC}"; fi
    public_ip=$(curl -s --connect-timeout 5 https://ifconfig.me)
    port=$(jq -r '.inbounds[0].port' "$V2RAY_CONFIG_PATH")
    echo -e "\n${BLUE}================ V2Ray SOCKS5 状态面板 ================${NC}"
    printf "%-25s: %b\n" "V2Ray 服务状态" "$service_status"
    printf "%-25s: %b\n" "开机自启 (手动链接)" "$autostart_status"
    printf "%-25s: %b\n" "服务保活 (自动重启)" "${GREEN}已集成${NC}" # <-- 修正点
    printf "%-25s: %b\n" "服务器公网 IP" "${YELLOW}${public_ip:-无法获取}${NC}"
    printf "%-25s: %b\n" "SOCKS5 端口" "${YELLOW}${port}${NC}"
    echo -e "${BLUE}=======================================================${NC}"
    list_users
    echo
}

main_menu() {
    while true; do
        clear
        echo -e "${GREEN}欢迎使用 V2Ray SOCKS5 管理脚本 v${SCRIPT_VERSION} (最终版)${NC}"
        echo -e "${YELLOW}===================================================${NC}"
        echo -e "  ${GREEN}1)${NC} 安装 V2Ray"
        echo -e "  ${GREEN}2)${NC} 卸载 V2Ray"
        echo -e "  ${GREEN}3)${NC} 管理用户"
        echo -e "  ${GREEN}4)${NC} 配置 SOCKS5 端口"
        echo -e "  ${GREEN}5)${NC} 查看日志"
        echo -e "  ${GREEN}6)${NC} 管理开机自启"
        echo -e "  ${GREEN}7)${NC} 查看状态和连接信息"
        echo -e "  ${GREEN}8)${NC} 退出脚本"
        echo -e "${YELLOW}===================================================${NC}"
        echo
        read -p "请输入选项 [1-8]: " choice
        case "$choice" in
            1) install_v2ray ;;
            2) uninstall_v2ray ;;
            3) manage_users_menu ;;
            4) configure_port ;;
            5) view_logs ;;
            6) toggle_autostart ;;
            7) show_status ;;
            8) echo -e "${GREEN}感谢使用！再见。${NC}"; exit 0 ;;
            *) echo -e "${RED}无效输入，请重试。${NC}" ;;
        esac
        echo -e "\n${BLUE}按 Enter 键返回主菜单...${NC}"
        read -r
    done
}

manage_users_menu() {
    while true; do
        clear
        echo -e "${GREEN}--- 用户管理菜单 ---${NC}"
        echo
        list_users
        echo
        echo -e "${YELLOW}===================================================${NC}"
        echo -e "  ${GREEN}1)${NC} 添加随机用户"
        echo -e "  ${GREEN}2)${NC} 添加自定义用户"
        echo -e "  ${GREEN}3)${NC} 移除用户"
        echo -e "  ${GREEN}4)${NC} 返回主菜单"
        echo -e "${YELLOW}===================================================${NC}"
        echo
        read -p "请输入选项 [1-4]: " choice
        case "$choice" in
            1) add_random_user ;;
            2) add_custom_user ;;
            3) remove_user ;;
            4) return ;;
            *) echo -e "${RED}无效输入，请重试。${NC}" ;;
        esac
        if [ "$choice" != "4" ]; then
            echo -e "\n${BLUE}按 Enter 键返回用户管理菜单...${NC}"
            read -r
        fi
    done
}

# --- 脚本执行入口 ---
check_root
check_dependencies
main_menu
