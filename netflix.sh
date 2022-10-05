#!/bin/bash

export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}

green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

[[ -z $SYSTEM ]] && red "目前你的VPS的操作系统暂未支持！" && exit 1

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "不支持的CPU架构!" && exit 1 ;;
    esac
}

if [[ ! -f /usr/local/bin/nf ]]; then
    wget https://cdn.jsdelivr.net/gh/taffychan/warp/netflix/verify/nf_linux_$(archAffix) -O /usr/local/bin/nf
    chmod +x /usr/local/bin/nf
fi

wgcfnf4(){
    wgcfv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ ! $wgcfv4 =~ on|plus ]]; then
        red "Wgcf-WARP的IPv4未正常配置，请在脚本中安装Wgcf-WARP全局模式！"
        exit 1
    fi
    nfv4result=$(nf | sed -n 3p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    if [[ $nfv4result == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WgcfWARPIP=$(curl -s4m8 api64.ipify.org -k)
        green "当前Wgcf-WARP的IP：$WgcfWARPIP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        wgcfnf4
    fi
    if [[ $nfv4result =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WgcfWARPIP=$(curl -s4m8 api64.ipify.org -k)
        red "当前Wgcf-WARP的IP：$WgcfWARPIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        wgcfnf4
    fi
    if [[ $nfv4result == "您的网络可能没有正常配置IPv4，或者没有IPv4网络接入" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        wgcfnf4
    fi
}

wgcfnf6(){
    wgcfv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ ! $wgcfv6 =~ on|plus ]]; then
        red "Wgcf-WARP的IPv6未正常配置，请在脚本中安装Wgcf-WARP全局模式！"
        exit 1
    fi
    nfv6result=$(nf | sed -n 7p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    if [[ $nfv6result == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WgcfWARPIP=$(curl -s6m8 api64.ipify.org -k)
        green "当前Wgcf-WARP的IP：$WgcfWARPIP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        wgcfnf6
    fi
    if [[ $nfv6result =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WgcfWARPIP=$(curl -s6m8 api64.ipify.org -k)
        red "当前Wgcf-WARP的IP：$WgcfWARPIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        wgcfnf6
    fi
    if [[ $nfv6result == "您的网络可能没有正常配置IPv6，或者没有IPv6网络接入" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        wgcfnf6
    fi
}

wgcfnfd(){
    wgcfv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ ! $wgcfv4 =~ on|plus || ! $wgcfv6 =~ on|plus ]]; then
        red "Wgcf-WARP的IPv4和IPv6未正常配置，请在脚本中安装Wgcf-WARP全局模式！"
        exit 1
    fi
    nfv4result=$(nf | sed -n 3p)
    nfv6result=$(nf | sed -n 7p)
    if [[ $nfv4result == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]] && [[ $nfv6result == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WgcfWARPV4IP=$(curl -s4m8 api64.ipify.org -k)
        WgcfWARPV6IP=$(curl -s6m8 api64.ipify.org -k)
        green "当前Wgcf-WARP的IPv4 IP：$WgcfWARPV4IP 已解锁Netfilx"
        green "当前Wgcf-WARP的IPv6 IP：$WgcfWARPV6IP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        wgcfnfd
    fi
    if [[ $nfv4result =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]] && [[ $nfv6result =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WgcfWARPV4IP=$(curl -s4m8 api64.ipify.org -k)
        WgcfWARPV6IP=$(curl -s6m8 api64.ipify.org -k)
        red "当前Wgcf-WARP的IPv4 IP：$WgcfWARPIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        red "当前Wgcf-WARP的IPv6 IP：$WgcfWARPIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        wgcfnfd
    fi
    if [[ $nfv4result == "您的网络可能没有正常配置IPv4，或者没有IPv4网络接入" ]] && [[ $nfv6result == "您的网络可能没有正常配置IPv6，或者没有IPv6网络接入" ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        wgcfnfd
    fi
}

wpgonf4(){
    wgcfv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ ! $wgcfv4 =~ on|plus ]]; then
        red "WARP-Go的IPv4未正常配置，请在脚本中安装WARP-Go全局模式！"
        exit 1
    fi
    nfv4result=$(nf | sed -n 3p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    if [[ $nfv4result == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WgcfWARPIP=$(curl -s4m8 api64.ipify.org -k)
        green "当前WARP-Go的IP：$WgcfWARPIP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        wgcfnf4
    fi
    if [[ $nfv4result =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WgcfWARPIP=$(curl -s4m8 api64.ipify.org -k)
        red "当前WARP-Go的IP：$WgcfWARPIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        systemctl stop warp-go
        systemctl start warp-go
        wgcfnf4
    fi
    if [[ $nfv4result == "您的网络可能没有正常配置IPv4，或者没有IPv4网络接入" ]]; then
        systemctl stop warp-go
        systemctl start warp-go
        wgcfnf4
    fi
}

wpgonf6(){
    wgcfv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ ! $wgcfv6 =~ on|plus ]]; then
        red "WARP-Go的IPv6未正常配置，请在脚本中安装WARP-Go全局模式！"
        exit 1
    fi
    nfv6result=$(nf | sed -n 7p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    if [[ $nfv6result == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WgcfWARPIP=$(curl -s6m8 api64.ipify.org -k)
        green "当前WARP-Go的IP：$WgcfWARPIP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        wgcfnf6
    fi
    if [[ $nfv6result =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WgcfWARPIP=$(curl -s6m8 api64.ipify.org -k)
        red "当前WARP-Go的IP：$WgcfWARPIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        systemctl stop warp-go
        systemctl start warp-go
        wgcfnf6
    fi
    if [[ $nfv6result == "您的网络可能没有正常配置IPv6，或者没有IPv6网络接入" ]]; then
        systemctl stop warp-go
        systemctl start warp-go
        wgcfnf6
    fi
}

wpgonfd(){
    wgcfv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ ! $wgcfv4 =~ on|plus || ! $wgcfv6 =~ on|plus ]]; then
        red "WARP-Go的IPv4和IPv6未正常配置，请在脚本中安装WARP-Go全局模式！"
        exit 1
    fi
    nfv4result=$(nf | sed -n 3p)
    nfv6result=$(nf | sed -n 7p)
    if [[ $nfv4result == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]] && [[ $nfv6result == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WgcfWARPV4IP=$(curl -s4m8 api64.ipify.org -k)
        WgcfWARPV6IP=$(curl -s6m8 api64.ipify.org -k)
        green "当前WARP-Go的IPv4 IP：$WgcfWARPV4IP 已解锁Netfilx"
        green "当前WARP-Go的IPv6 IP：$WgcfWARPV6IP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        wgcfnfd
    fi
    if [[ $nfv4result =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]] && [[ $nfv6result =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WgcfWARPV4IP=$(curl -s4m8 api64.ipify.org -k)
        WgcfWARPV6IP=$(curl -s6m8 api64.ipify.org -k)
        red "当前WARP-Go的IPv4 IP：$WgcfWARPIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        red "当前WARP-Go的IPv6 IP：$WgcfWARPIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        systemctl stop warp-go
        systemctl start warp-go
        wgcfnfd
    fi
    if [[ $nfv4result == "您的网络可能没有正常配置IPv4，或者没有IPv4网络接入" ]] && [[ $nfv6result == "您的网络可能没有正常配置IPv6，或者没有IPv6网络接入" ]]; then
        systemctl stop warp-go
        systemctl start warp-go
        wgcfnfd
    fi
}

cliquan(){
    warpstat=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k --interface CloudflareWARP | grep warp | cut -d= -f2)
    if [[ ! $warpstat =~ on|plus ]]; then
        red "WARP-Cli 全局模式未正常配置，请在脚本中安装WARP-Cli 全局模式！"
        exit 1
    fi
    nfresult=$(nf -address 172.16.0.2 | sed -n 3p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    if [[ $nfresult == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WARPCliIP=$(curl -s4m8 ip.p3terx.com -k --interface CloudflareWARP | sed -n 1p)
        green "当前WARP-Cli全局模式的IP：$WARPCliIP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        wgcfnf4
    fi
    if [[ $nfresult =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WARPCliIP=$(curl -s4m8 ip.p3terx.com -k --interface CloudflareWARP | sed -n 1p)
        red "当前WARP-Cli全局模式的IP：$WARPCliIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        warp-cli --accept-tos connect >/dev/null 2>&1
        wgcfnf4
    fi
    if [[ $nfresult == "您的网络可能没有正常配置IPv4，或者没有IPv4网络接入" ]]; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        warp-cli --accept-tos connect >/dev/null 2>&1
        wgcfnf4
    fi
}

clisocks(){
    cliport=$(warp-cli --accept-tos settings 2>/dev/null | grep 'WarpProxy on port' | awk -F "port " '{print $2}')
    warpstat=$(curl -sx socks5h://localhost:$cliport https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    if [[ ! $warpstat =~ on|plus ]]; then
        red "WARP-Cli 代理模式未正常配置，请在脚本中安装WARP-Cli 代理模式！"
        exit 1
    fi
    nfresult=$(nf -proxy socks5://127.0.0.1:$cliport | sed -n 3p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    if [[ $nfresult == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WARPCliIP=$(curl -sx socks5h://localhost:$cliport ip.p3terx.com -k --connect-timeout 8 | sed -n 1p)
        green "当前WARP-Cli代理模式的IP：$WARPCliIP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        clisocks
    fi
    if [[ $nfresult =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WARPCliIP=$(curl -sx socks5h://localhost:$cliport ip.p3terx.com -k --connect-timeout 8 | sed -n 1p)
        red "当前WARP-Cli代理模式的IP：$WARPCliIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        warp-cli --accept-tos connect >/dev/null 2>&1
        clisocks
    fi
    if [[ $nfresult == "您的网络可能没有正常配置IPv4，或者没有IPv4网络接入" ]]; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        warp-cli --accept-tos connect >/dev/null 2>&1
        clisocks
    fi
}

wireproxy(){
    wireport=$(grep BindAddress /etc/wireguard/proxy.conf 2>/dev/null | sed "s/BindAddress = 127.0.0.1://g")
    warpstat=$(curl -sx socks5h://localhost:$wireport https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    if [[ ! $warpstat =~ on|plus ]]; then
        red "WireProxy-WARP 代理模式未正常配置，请在脚本中安装WireProxy-WARP 代理模式！"
        exit 1
    fi
    nfresult=$(nf -proxy socks5://127.0.0.1:$wireport | sed -n 3p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    if [[ $nfresult == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]]; then
        WireProxyIP=$(curl -sx socks5h://localhost:$WireProxyPort ip.p3terx.com -k --connect-timeout 8 | sed -n 1p)
        green "当前WireProxy-WARP的IP：$WireProxyIP 已解锁Netfilx"
        yellow "等待1小时后，脚本将会自动重新检查Netfilx解锁状态"
        sleep 1h
        wireproxy
    fi
    if [[ $nfresult =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务"|"您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]]; then
        WireProxyIP=$(curl -sx socks5h://localhost:$WireProxyPort ip.p3terx.com -k --connect-timeout 8 | sed -n 1p)
        red "当前WireProxy-WARP的IP：$WireProxyIP 未解锁Netfilx，脚本将在15秒后重新测试Netfilx解锁情况"
        sleep 15
        systemctl stop wireproxy-warp
        systemctl start wireproxy-warp
        wireproxy
    fi
    if [[ $nfresult == "您的网络可能没有正常配置IPv4，或者没有IPv4网络接入" ]]; then
        systemctl stop wireproxy-warp
        systemctl start wireproxy-warp
        wireproxy
    fi
}

menu(){
    yellow "需要使用什么方式来使用WARP的Netflix IP"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Wgcf-WARP 全局单栈模式 ${YELLOW}(WARP IPv4)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Wgcf-WARP 全局单栈模式 ${YELLOW}(WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}3.${PLAIN} Wgcf-WARP 全局双栈模式 ${YELLOW}(WARP IPv4 + WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}4.${PLAIN} WARP-Go 全局单栈模式 ${YELLOW}(WARP IPv4)${PLAIN}"
    echo -e " ${GREEN}5.${PLAIN} WARP-Go 全局单栈模式 ${YELLOW}(WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}6.${PLAIN} WARP-Go 全局双栈模式 ${YELLOW}(WARP IPv4 + WARP IPv6)${PLAIN}"
    echo -e " ${GREEN}7.${PLAIN} WARP-Cli 全局模式 ${YELLOW}(WARP IPv4)${PLAIN}"
    echo -e " ${GREEN}8.${PLAIN} WARP-Cli 代理模式"
    echo -e " ${GREEN}9.${PLAIN} WireProxy-WARP 代理模式"
    echo " -------------"
    echo -e " ${GREEN}0.${PLAIN} 退出脚本"
    echo ""
    read -rp "请选择客户端 [0-6]: " clientInput
    case $clientInput in
        1 ) wgcfnf4 ;;
        2 ) wgcfnf6 ;;
        3 ) wgcfnfd ;;
        4 ) wpgonf4 ;;
        5 ) wpgonf6 ;;
        6 ) wpgonfd ;;
        7 ) cliquan ;;
        8 ) clisocks ;;
        9 ) wireproxy ;;
        * ) exit 1 ;;
    esac
}

menu
