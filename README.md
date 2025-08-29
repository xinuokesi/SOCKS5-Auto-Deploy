# V2Ray SOCKS5 代理一键管理脚本

这是一个用于在 Debian/Ubuntu 系统上快速部署和管理 V2Ray SOCKS5 代理的脚本，支持用户管理、端口配置、开机自启和故障修复功能。

## 安装

```bash
wget https://raw.githubusercontent.com/xinuokesi/SOCKS5-Auto-Deploy/main/auto_socks5.sh
```

### 提权

```bash
chmod +x auto_socks5.sh
```

### 运行

```bash
sudo ./auto_socks5.sh
```

## 使用说明

脚本提供 9 个主要功能：
1. 安装 V2Ray
2. 卸载 V2Ray
3. 管理用户（添加/删除用户）
4. 配置 SOCKS5 端口
5. 查看日志
6. 管理开机自启
7. 查看状态和连接信息

安装完成后，默认端口为 10800，可通过脚本进行修改。
