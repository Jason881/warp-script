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

main=$(uname -r | awk -F . '{print $1}')
minor=$(uname -r | awk -F . '{print $2}')
OSID=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
VIRT=$(systemd-detect-virt)
TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')

# Wgcf 去除IPv4/IPv6
wg1="sed -i '/0\.0\.0\.0\/0/d' /etc/wireguard/wgcf.conf"
wg2="sed -i '/\:\:\/0/d' /etc/wireguard/wgcf.conf"
# Wgcf Endpoint
wg3="sed -i 's/engage.cloudflareclient.com/162.159.193.10/g' /etc/wireguard/wgcf.conf"
wg4="sed -i 's/engage.cloudflareclient.com/[2606:4700:d0::a29f:c001]/g' /etc/wireguard/wgcf.conf"
# Wgcf DNS Servers
wg5="sed -i 's/1.1.1.1/1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,2606:4700:4700::1111,2606:4700:4700::1001,2001:4860:4860::8888,2001:4860:4860::8844/g' /etc/wireguard/wgcf.conf"
wg6="sed -i 's/1.1.1.1/2606:4700:4700::1111,2606:4700:4700::1001,2001:4860:4860::8888,2001:4860:4860::8844,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4/g' /etc/wireguard/wgcf.conf"
# Wgcf 允许外部IP地址
wg7='sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 1.1.1.1 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostDown = ip -4 rule delete from $(ip route get 1.1.1.1 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf'
wg8='sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2606:4700:4700::1111 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostDown = ip -6 rule delete from $(ip route get 2606:4700:4700::1111 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf'
wg9='sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 1.1.1.1 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostDown = ip -4 rule delete from $(ip route get 1.1.1.1 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2606:4700:4700::1111 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostDown = ip -6 rule delete from $(ip route get 2606:4700:4700::1111 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf'

if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

archAffix(){
    case "$(uname -m)" in
        x86_64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        s390x ) echo 's390x' ;;
        * ) red "不支持的CPU架构!" && exit 1 ;;
    esac
}

check_quota(){
    if [[ "$CHECK_TYPE" = 1 ]]; then
        QUOTA=$(warp-cli --accept-tos account 2>/dev/null | grep -oP 'Quota: \K\d+')
    else
        ACCESS_TOKEN=$(grep 'access_token' /etc/wireguard/wgcf-account.toml | cut -d \' -f2)
        DEVICE_ID=$(grep 'device_id' /etc/wireguard/wgcf-account.toml | cut -d \' -f2)
        API=$(curl -s "https://api.cloudflareclient.com/v0a884/reg/$DEVICE_ID" -H "User-Agent: okhttp/3.12.1" -H "Authorization: Bearer $ACCESS_TOKEN")
        QUOTA=$(grep -oP '"quota":\K\d+' <<< $API)
    fi
    [[ $QUOTA -gt 10000000000000 ]] && QUOTA="$(echo "scale=2; $QUOTA/1000000000000" | bc) TB" || QUOTA="$(echo "scale=2; $QUOTA/1000000000" | bc) GB"
}

checktun(){
    if [[ ! $TUN =~ "in bad state"|"处于错误状态"|"ist in schlechter Verfassung" ]]; then
        if [[ $VIRT == lxc ]]; then
            if [[ $main -lt 5 ]] || [[ $minor -lt 6 ]]; then
                red "检测到未开启TUN模块, 请到VPS后台控制面板处开启"
                exit 1
            else
                return 0
            fi
        elif [[ $VIRT == "openvz" ]]; then
            wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/taffychan/warp/files/tun.sh && bash tun.sh
        else
            red "检测到未开启TUN模块, 请到VPS后台控制面板处开启"
            exit 1
        fi
    fi
}

checkv4v6(){
    v6=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
    v4=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p)
}

checkStack(){
    lan4=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    lan6=$(ip route get 2606:4700:4700::1111 2>/dev/null | grep -oP 'src \K\S+')
    if [[ "$lan4" =~ ^[0-9.]+$ ]]; then
        ping -c2 -W3 162.159.193.10 >/dev/null 2>&1 && out4=1
    fi
    if [[ "$lan6" =~ ^[0-9a-z:]+$ ]]; then
        ping6 -c2 -w10 2606:4700:4700::1111 >/dev/null 2>&1 && out6=1
    fi
}

initwgcf(){
    wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/taffychan/warp/files/wgcf/wgcf-latest-linux-$(archAffix) -O /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
}

wgcfreg(){
    if [[ -f /etc/wireguard/wgcf-account.toml ]]; then
        cp -f /etc/wireguard/wgcf-account.toml /root/wgcf-account.toml
    fi

    until [[ -a wgcf-account.toml ]]; do
        yellow "正在向CloudFlare WARP注册账号, 如提示429 Too Many Requests错误请耐心等待重试注册即可"
        wgcf register --accept-tos
        sleep 5
    done
    chmod +x wgcf-account.toml

    wgcf generate
    chmod +x wgcf-profile.conf
}

wgcfv44(){
    checkwgcf
    if [[ $wgcfv4 =~ on|plus ]] || [[ $wgcfv6 =~ on|plus ]]; then
        stopwgcf
        checkStack
    else
        checkStack
    fi

    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为纯IPv4的VPS，正在切换为Wgcf-WARP全局单栈模式 (WARP IPv4)"
            stopwgcf && switchconf
            wgcf1=$wg5 && wgcf2=$wg7 && wgcf3=$wg2 && wgcf4=$wg3
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为纯IPv4的VPS，正在安装Wgcf-WARP全局单栈模式 (WARP IPv4)"
            wgcf1=$wg5 && wgcf2=$wg7 && wgcf3=$wg2 && wgcf4=$wg3
            installwgcf
        fi
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为纯IPv6的VPS，正在切换为Wgcf-WARP全局单栈模式 (WARP IPv4 + 原生 IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg6 && wgcf2=$wg2 && wgcf3=$wg4
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为纯IPv6的VPS，正在安装Wgcf-WARP全局单栈模式 (WARP IPv4 + 原生 IPv6)"
            wgcf1=$wg6 && wgcf2=$wg2 && wgcf3=$wg4
            installwgcf
        fi
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为原生双栈的VPS，正在切换为Wgcf-WARP全局单栈模式 (WARP IPv4 + 原生 IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg5 && wgcf2=$wg7 && wgcf3=$wg2
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为原生双栈的VPS，正在安装Wgcf-WARP全局单栈模式 (WARP IPv4 + 原生 IPv6)"
            wgcf1=$wg5 && wgcf2=$wg7 && wgcf3=$wg2
            installwgcf
        fi
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为NAT IPv4+原生 IPv6的VPS，正在切换为Wgcf-WARP全局单栈模式 (WARP IPv4 + 原生 IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg6 && wgcf2=$wg7 && wgcf3=$wg2 && wgcf4=$wg4
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为NAT IPv4+原生IPv6的VPS，正在安装Wgcf-WARP全局单栈模式 (WARP IPv4 + 原生 IPv6)"
            wgcf1=$wg6 && wgcf2=$wg7 && wgcf3=$wg2 && wgcf4=$wg4
            installwgcf
        fi
    fi
}

wgcfv66(){
    checkwgcf
    if [[ $wgcfv4 =~ on|plus ]] || [[ $wgcfv6 =~ on|plus ]]; then
        stopwgcf
        checkStack
    else
        checkStack
    fi

    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为纯IPv4的VPS，正在切换为Wgcf-WARP全局单栈模式 (原生IPv4 + WARP IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg5 && wgcf2=$wg1 && wgcf3=$wg3
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为纯IPv4的VPS，正在安装Wgcf-WARP全局单栈模式 (原生IPv4 + WARP IPv6)"
            wgcf1=$wg5 && wgcf2=$wg1 && wgcf3=$wg3
            installwgcf
        fi
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为纯IPv6的VPS，正在切换为Wgcf-WARP全局单栈模式 (WARP IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg6 && wgcf2=$wg8 && wgcf3=$wg1 && wgcf4=$wg4
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为纯IPv6的VPS，正在安装Wgcf-WARP全局单栈模式 (WARP IPv6)"
            wgcf1=$wg6 && wgcf2=$wg8 && wgcf3=$wg1 && wgcf4=$wg4
            installwgcf
        fi
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为原生双栈的VPS，正在切换为Wgcf-WARP全局单栈模式 (原生 IPv4 + WARP IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg5 && wgcf2=$wg8 && wgcf3=$wg1
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为原生双栈的VPS，正在安装Wgcf-WARP全局单栈模式 (原生 IPv4 + WARP IPv6)"
            wgcf1=$wg5 && wgcf2=$wg8 && wgcf3=$wg1
            installwgcf
        fi
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为NAT IPv4+原生 IPv6的VPS，正在切换为Wgcf-WARP全局单栈模式 (WARP IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg6 && wgcf2=$wg9 && wgcf3=$wg1 && wgcf4=$wg4
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为NAT IPv4+原生 IPv6的VPS，正在安装Wgcf-WARP全局单栈模式 (WARP IPv6)"
            wgcf1=$wg6 && wgcf2=$wg9 && wgcf3=$wg1 && wgcf4=$wg4
            installwgcf
        fi
    fi
}

wgcfv46(){
    checkwgcf
    if [[ $wgcfv4 =~ on|plus ]] || [[ $wgcfv6 =~ on|plus ]]; then
        stopwgcf
        checkStack
    else
        checkStack
    fi

    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为纯IPv4的VPS，正在切换为Wgcf-WARP全局双栈模式 (WARP IPv4 + WARP IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg5 && wgcf2=$wg7 && wgcf3=$wg3
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为纯IPv4的VPS，正在安装Wgcf-WARP全局双栈模式 (WARP IPv4 + WARP IPv6)"
            wgcf1=$wg5 && wgcf2=$wg7 && wgcf3=$wg3
            installwgcf
        fi
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为纯IPv6的VPS，正在切换为Wgcf-WARP全局双栈模式 (WARP IPv4 + WARP IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg6 && wgcf2=$wg8 && wgcf3=$wg4
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为纯IPv6的VPS，正在安装Wgcf-WARP全局双栈模式 (WARP IPv4 + WARP IPv6)"
            wgcf1=$wg6 && wgcf2=$wg8 && wgcf3=$wg4
            installwgcf
        fi
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为原生双栈的VPS，正在切换为Wgcf-WARP全局单栈模式 (WARP IPv4 + WARP IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg5 && wgcf2=$wg9
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为原生双栈的VPS，正在安装Wgcf-WARP全局双栈模式 (WARP IPv4 + WARP IPv6)"
            wgcf1=$wg5 && wgcf2=$wg9
            installwgcf
        fi
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            yellow "检测为NAT IPv4+原生 IPv6的VPS，正在切换为Wgcf-WARP全局双栈模式 (WARP IPv4 + WARP IPv6)"
            stopwgcf && switchconf
            wgcf1=$wg6 && wgcf2=$wg9 && wgcf3=$wg4
            wgcfconf && wgcfcheck && showIP
        else
            yellow "检测为NAT IPv4+原生 IPv6的VPS，正在安装Wgcf-WARP全局双栈模式 (WARP IPv4 + WARP IPv6)"
            wgcf1=$wg6 && wgcf2=$wg9 && wgcf3=$wg4
            installwgcf
        fi
    fi
}

installwgcf(){
    [[ $SYSTEM == "CentOS" ]] && [[ ${OSID} -lt 7 ]] && yellow "当前系统版本：${CMD} \nWgcf-WARP模式仅支持CentOS / Almalinux / Rocky / Oracle Linux 7及以上版本的系统" && exit 1
    [[ $SYSTEM == "Debian" ]] && [[ ${OSID} -lt 10 ]] && yellow "当前系统版本：${CMD} \nWgcf-WARP模式仅支持Debian 10及以上版本的系统" && exit 1
    [[ $SYSTEM == "Fedora" ]] && [[ ${OSID} -lt 29 ]] && yellow "当前系统版本：${CMD} \nWgcf-WARP模式仅支持Fedora 29及以上版本的系统" && exit 1
    [[ $SYSTEM == "Ubuntu" ]] && [[ ${OSID} -lt 18 ]] && yellow "当前系统版本：${CMD} \nWgcf-WARP模式仅支持Ubuntu 16.04及以上版本的系统" && exit 1

    checktun

    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} sudo curl wget iproute net-tools wireguard-tools iptables bc htop screen python3 iputils
        if [[ $OSID == 9 ]] && [[ -z $(type -P resolvconf) ]]; then
            wget -N https://cdn.jsdelivr.net/gh/taffychan/warp/files/resolvconf -O /usr/sbin/resolvconf
            chmod +x /usr/sbin/resolvconf
        fi
    fi
    if [[ $SYSTEM == "Fedora" ]]; then
        ${PACKAGE_INSTALL[int]} sudo curl wget iproute net-tools wireguard-tools iptables bc htop screen python3 iputils
    fi
    if [[ $SYSTEM == "Debian" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo wget curl lsb-release bc htop screen python3 inetutils-ping
        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/backports.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi
    if [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget lsb-release bc htop screen python3 inetutils-ping
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi
    
    if [[ $main -lt 5 ]] || [[ $minor -lt 6 ]] || [[ $VIRT =~ lxc|openvz ]]; then
        wget -N --no-check-certificate https://cdn.jsdelivr.net/gh/taffychan/warp/files/wireguard-go/wireguard-go-$(archAffix) -O /usr/bin/wireguard-go
        chmod +x /usr/bin/wireguard-go
    fi

    initwgcf
    wgcfreg
    checkmtu

    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi
    
    cp -f wgcf-profile.conf /etc/wireguard/wgcf.conf >/dev/null 2>&1
    mv -f wgcf-profile.conf /etc/wireguard/wgcf-profile.conf >/dev/null 2>&1
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml >/dev/null 2>&1

    wgcfconf

    systemctl enable wg-quick@wgcf >/dev/null 2>&1
    wgcfcheck
    showIP
}

switchconf(){
    rm -rf /etc/wireguard/wgcf.conf
    cp -f /etc/wireguard/wgcf-profile.conf /etc/wireguard/wgcf.conf >/dev/null 2>&1
}

wgcfconf(){
    echo $wgcf1 | sh
    echo $wgcf2 | sh
    echo $wgcf3 | sh
    echo $wgcf4 | sh
}

checkmtu(){
    yellow "正在检测并设置MTU最佳值, 请稍等..."
    checkv4v6
    MTUy=1500
    MTUc=10
    if [[ -n ${v6} && -z ${v4} ]]; then
        ping='ping6'
        IP1='2606:4700:4700::1001'
        IP2='2001:4860:4860::8888'
    else
        ping='ping'
        IP1='1.1.1.1'
        IP2='8.8.8.8'
    fi
    while true; do
        if ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP1} >/dev/null 2>&1 || ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP2} >/dev/null 2>&1; then
            MTUc=1
            MTUy=$((${MTUy} + ${MTUc}))
        else
            MTUy=$((${MTUy} - ${MTUc}))
            if [[ ${MTUc} = 1 ]]; then
                break
            fi
        fi
        if [[ ${MTUy} -le 1360 ]]; then
            MTUy='1360'
            break
        fi
    done
    MTU=$((${MTUy} - 80))
    sed -i "s/MTU.*/MTU = $MTU/g" wgcf-profile.conf
    green "MTU 最佳值=$MTU 已设置完毕"
}

checkwgcf(){
    wgcfv6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    wgcfv4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

wgcfcheck(){
    yellow "正在启动 Wgcf-WARP"
    i=0
    while [ $i -le 4 ]; do let i++
        wg-quick down wgcf >/dev/null 2>&1
        wg-quick up wgcf >/dev/null 2>&1
        checkwgcf
        if [[ $wgcfv4 =~ on|plus ]] || [[ $wgcfv6 =~ on|plus ]]; then
            green "Wgcf-WARP 已启动成功！"
            break
        else
            red "Wgcf-WARP 启动失败！"
        fi
        checkwgcf
        if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
            red "安装Wgcf-WARP失败！"
            green "建议如下："
            yellow "1. 强烈建议使用官方源升级系统及内核加速！如已使用第三方源及内核加速，请务必更新到最新版，或重置为官方源"
            yellow "2. 部分VPS系统极度精简，相关依赖需自行安装后再尝试"
            yellow "3. 查看https://www.cloudflarestatus.com/,你当前VPS就近区域可能处于黄色的【Re-routed】状态"
            exit 1
        fi
    done
}

switchwgcf(){
    checkwgcf
    if [[ $wgcfv4 =~ on|plus ]] || [[ $wgcfv6 =~ on|plus ]]; then
        startwgcf
        green "Wgcf-WARP 已启动成功！"
    fi
    if [[ ! $wgcfv4 =~ on|plus ]] || [[ ! $wgcfv6 =~ on|plus ]]; then
        stopwgcf
        green "Wgcf-WARP 已停止成功！"
    fi
}

startwgcf(){
    wg-quick up wgcf >/dev/null 2>&1
    systemctl enable wg-quick@wgcf >/dev/null 2>&1
}

stopwgcf(){
    wg-quick down wgcf >/dev/null 2>&1
    systemctl disable wg-quick@wgcf >/dev/null 2>&1
}

uninstallwgcf(){
    wg-quick down wgcf 2>/dev/null
    systemctl disable wg-quick@wgcf 2>/dev/null
    ${PACKAGE_UNINSTALL[int]} wireguard-tools wireguard-dkms
    if [[ -z $(type -P wireproxy) ]]; then
        rm -f /usr/local/bin/wgcf
        rm -f /etc/wireguard/wgcf-account.toml
    fi
    rm -f /etc/wireguard/wgcf.conf
    rm -f /usr/bin/wireguard-go
    if [[ -e /etc/gai.conf ]]; then
        sed -i '/^precedence[ ]*::ffff:0:0\/96[ ]*100/d' /etc/gai.conf
    fi
    green "Wgcf-WARP 已彻底卸载成功!"
}

installcli(){
    [[ $SYSTEM == "CentOS" ]] && [[ ! ${OSID} =~ 8 ]] && yellow "当前系统版本：${CMD} \nWARP-Cli代理模式仅支持CentOS / Almalinux / Rocky / Oracle Linux 8系统" && exit 1
    [[ $SYSTEM == "Debian" ]] && [[ ! ${OSID} =~ 9|10|11 ]] && yellow "当前系统版本：${CMD} \nWARP-Cli代理模式仅支持Debian 9-11系统" && exit 1
    [[ $SYSTEM == "Fedora" ]] && yellow "当前系统版本：${CMD} \nWARP-Cli暂时不支持Fedora系统" && exit 1
    [[ $SYSTEM == "Ubuntu" ]] && [[ ! ${OSID} =~ 16|18|20|22 ]] && yellow "当前系统版本：${CMD} \nWARP-Cli代理模式仅支持Ubuntu 16.04/18.04/20.04/22.04系统" && exit 1
    
    [[ ! $(archAffix) == "amd64" ]] && red "WARP-Cli暂时不支持目前VPS的CPU架构, 请使用CPU架构为amd64的VPS" && exit 1
    
    checktun

    checkwgcf
    if [[ $wgcfv4 =~ on|plus ]] ||[[ $wgcfv6 =~ on|plus ]]; then
        stopwgcf
        checkv4v6
        startwgcf
    else
        checkv4v6
    fi

    if [[ -z $v4 ]]; then
        red "WARP-Cli暂时不支持纯IPv6的VPS，退出安装！"
        exit 1
    fi
    
    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} sudo curl wget net-tools bc htop iputils screen python3
        rpm -ivh http://pkg.cloudflareclient.com/cloudflare-release-el8.rpm
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi
    
    if [[ $SYSTEM == "Debian" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget lsb-release bc htop inetutils-ping screen python3
        [[ -z $(type -P gpg 2>/dev/null) ]] && ${PACKAGE_INSTALL[int]} gnupg
        [[ -z $(apt list 2>/dev/null | grep apt-transport-https | grep installed) ]] && ${PACKAGE_INSTALL[int]} apt-transport-https
        curl https://pkg.cloudflareclient.com/pubkey.gpg | apt-key add -
        echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi
    
    if [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget lsb-release bc htop inetutils-ping screen python3
        curl https://pkg.cloudflareclient.com/pubkey.gpg | apt-key add -
        echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi
    
    warp-cli --accept-tos register >/dev/null 2>&1
    if [[ $warpcli == 1 ]]; then
        yellow "正在启动 WARP-Cli 全局模式"
        warp-cli --accept-tos add-excluded-route 0.0.0.0/0 >/dev/null 2>&1
        warp-cli --accept-tos add-excluded-route ::0/0 >/dev/null 2>&1
        warp-cli --accept-tos set-mode warp >/dev/null 2>&1
        warp-cli --accept-tos connect >/dev/null 2>&1
        warp-cli --accept-tos enable-always-on >/dev/null 2>&1
        sleep 5
        ip -4 rule add from 172.16.0.2 lookup 51820
        ip -4 route add default dev CloudflareWARP table 51820
        ip -4 rule add table main suppress_prefixlength 0
        IPv4=$(curl -s4m8 ip.p3terx.com/json --interface CloudflareWARP)
        retry_time=0
        until [[ -n $IPv4 ]]; do
            retry_time=$((${retry_time} + 1))
            red "启动 WARP-Cli 全局模式失败，正在尝试重启，重试次数：$retry_time"
            warp-cli --accept-tos disconnect >/dev/null 2>&1
            warp-cli --accept-tos disable-always-on >/dev/null 2>&1
            ip -4 rule delete from 172.16.0.2 lookup 51820
            ip -4 rule delete table main suppress_prefixlength 0
            sleep 2
            warp-cli --accept-tos connect >/dev/null 2>&1
            warp-cli --accept-tos enable-always-on >/dev/null 2>&1
            sleep 5
            ip -4 rule add from 172.16.0.2 lookup 51820
            ip -4 route add default dev CloudflareWARP table 51820
            ip -4 rule add table main suppress_prefixlength 0
            if [[ $retry_time == 6 ]]; then
                warp-cli --accept-tos disconnect >/dev/null 2>&1
                warp-cli --accept-tos disable-always-on >/dev/null 2>&1
                ip -4 rule delete from 172.16.0.2 lookup 51820
                ip -4 rule delete table main suppress_prefixlength 0
                red "由于WARP-Cli全局模式启动重试次数过多 ,已自动卸载WARP-Cli全局模式"
                green "建议如下："
                yellow "1. 建议使用系统官方源升级系统及内核加速！如已使用第三方源及内核加速 ,请务必更新到最新版 ,或重置为系统官方源！"
                yellow "2. 部分VPS系统过于精简 ,相关依赖需自行安装后再重试"
                yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
                exit 1
            fi
        done
        green "WARP-Cli全局模式已安装成功！"
        echo ""
        showIP
    fi

    if [[ $warpcli == 2 ]]; then
        read -rp "请输入WARP-Cli使用的代理端口 (默认随机端口): " WARPCliPort
        [[ -z $WARPCliPort ]] && WARPCliPort=$(shuf -i 1000-65535 -n 1)
        if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$WARPCliPort") ]]; then
            until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$WARPCliPort") ]]; do
                if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$WARPCliPort") ]]; then
                    yellow "你设置的端口目前已被占用，请重新输入端口"
                    read -rp "请输入WARP-Cli使用的代理端口 (默认随机端口): " WARPCliPort
                fi
            done
        fi
        yellow "正在启动 WARP-Cli 代理模式"
        warp-cli --accept-tos set-mode proxy >/dev/null 2>&1
        warp-cli --accept-tos set-proxy-port "$WARPCliPort" >/dev/null 2>&1
        warp-cli --accept-tos connect >/dev/null 2>&1
        warp-cli --accept-tos enable-always-on >/dev/null 2>&1
        sleep 2
        if [[ ! $(ss -nltp) =~ 'warp-svc' ]]; then
            red "由于WARP-Cli代理模式安装失败 ,已自动卸载WARP-Cli代理模式"
            green "建议如下："
            yellow "1. 建议使用系统官方源升级系统及内核加速！如已使用第三方源及内核加速 ,请务必更新到最新版 ,或重置为系统官方源！"
            yellow "2. 部分VPS系统过于精简 ,相关依赖需自行安装后再重试"
            yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
            exit 1
        else
            green "WARP-Cli 代理模式已启动成功!"
            echo ""
            showIP
        fi
    fi
}

warpcli_changeport() {
    if [[ $(warp-cli --accept-tos status) =~ Connected ]]; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1
    fi
    
    read -rp "请输入WARP-Cli使用的代理端口 (默认随机端口): " WARPCliPort
    [[ -z $WARPCliPort ]] && WARPCliPort=$(shuf -i 1000-65535 -n 1)
    if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$WARPCliPort") ]]; then
        until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$WARPCliPort") ]]; do
            if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$WARPCliPort") ]]; then
                yellow "你设置的端口目前已被占用，请重新输入端口"
                read -rp "请输入WARP-Cli使用的代理端口 (默认随机端口): " WARPCliPort
            fi
        done
    fi
    warp-cli --accept-tos set-proxy-port "$WARPCliPort" >/dev/null 2>&1
    
    yellow "正在启动Warp-Cli代理模式"
    warp-cli --accept-tos connect >/dev/null 2>&1
    warp-cli --accept-tos enable-always-on >/dev/null 2>&1
    
    if [[ ! $(ss -nltp) =~ 'warp-svc' ]]; then
        red "WARP-Cli代理模式启动失败！"
        uninstallCli
    else
        green "WARP-Cli代理模式已启动成功并成功修改代理端口！"
        echo ""
        showIP
    fi
}

switchcli(){
    if [[ $(warp-cli --accept-tos status) =~ Connected ]]; then
        warp-cli --accept-tos disconnect >/dev/null 2>&1
        green "WARP-Cli客户端关闭成功! "
        exit 1
    elif [[ $(warp-cli --accept-tos status) =~ Disconnected ]]; then
        yellow "正在启动Warp-Cli"
        warp-cli --accept-tos connect >/dev/null 2>&1
        warp-cli --accept-tos enable-always-on >/dev/null 2>&1
        green "WARP-Cli客户端启动成功! "
        exit 1
    fi
}

uninstallcli(){
    warp-cli --accept-tos disconnect >/dev/null 2>&1
    warp-cli --accept-tos disable-always-on >/dev/null 2>&1
    warp-cli --accept-tos delete >/dev/null 2>&1
    ${PACKAGE_UNINSTALL[int]} cloudflare-warp
    systemctl disable --now warp-svc >/dev/null 2>&1
    green "WARP-Cli客户端已彻底卸载成功!"
}

installWireProxy(){
    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} sudo curl wget bc htop iputils screen python3
    else
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget bc htop inetutils-ping screen python3
    fi
    
    wget -N https://cdn.jsdelivr.net/gh/taffychan/warp/files/wireproxy/wireproxy-$(archAffix) -O /usr/local/bin/wireproxy
    chmod +x /usr/local/bin/wireproxy
    
    initwgcf
    wgcfreg
    
    checkwgcf
    
    if [[ $wgcfv4 =~ on|plus ]] || [[ $wgcfv6 =~ on|plus ]]; then
        wg-quick down wgcf >/dev/null 2>&1
        checkmtu
        checkv4v6
        wg-quick up wgcf >/dev/null 2>&1
    else
        checkmtu
        checkv4v6
    fi
    
    read -rp "请输入WireProxy-WARP使用的代理端口 (默认随机端口): " WireProxyPort
    [[ -z $WireProxyPort ]] && WireProxyPort=$(shuf -i 1000-65535 -n 1)
    if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$WireProxyPort") ]]; then
        until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$WireProxyPort") ]]; do
            if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$WireProxyPort") ]]; then
                yellow "你设置的端口目前已被占用，请重新输入端口"
                read -rp "请输入WireProxy-WARP使用的代理端口 (默认随机端口): " WireProxyPort
            fi
        done
    fi
    
    WgcfPrivateKey=$(grep PrivateKey wgcf-profile.conf | sed "s/PrivateKey = //g")
    WgcfPublicKey=$(grep PublicKey wgcf-profile.conf | sed "s/PublicKey = //g")
    
    if [[ -z $v4 && -n $v6 ]]; then
        WireproxyEndpoint="[2606:4700:d0::a29f:c001]:2408"
    else
        WireproxyEndpoint="162.159.193.10:2408"
    fi

    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi    
    cat <<EOF > /etc/wireguard/proxy.conf
[Interface]
Address = 172.16.0.2/32
MTU = $MTU
PrivateKey = $WgcfPrivateKey
DNS = 1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844
[Peer]
PublicKey = $WgcfPublicKey
Endpoint = $WireproxyEndpoint
[Socks5]
BindAddress = 127.0.0.1:$WireProxyPort
EOF
    
    cat <<'TEXT' > /etc/systemd/system/wireproxy-warp.service
[Unit]
Description=CloudFlare WARP Socks5 proxy mode based for WireProxy, script by owo.misaka.rest
After=network.target
[Install]
WantedBy=multi-user.target
[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/usr/local/bin/wireproxy -c /etc/wireguard/proxy.conf
Restart=always
TEXT
    
    mv -f wgcf-profile.conf /etc/wireguard/wgcf-profile.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml
    
    yellow "正在启动 WireProxy-WARP 代理模式"
    systemctl start wireproxy-warp
    WireProxyStatus=$(curl -sx socks5h://localhost:$WireProxyPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    sleep 2
    retry_time=0
    until [[ $WireProxyStatus =~ on|plus ]]; do
        retry_time=$((${retry_time} + 1))
        red "启动 WireProxy-WARP 代理模式失败，正在尝试重启，重试次数：$retry_time"
        systemctl stop wireproxy-warp
        systemctl start wireproxy-warp
        WireProxyStatus=$(curl -sx socks5h://localhost:$WireProxyPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
        if [[ $retry_time == 6 ]]; then
            uninstallWireProxy
            echo ""
            red "由于 WireProxy-WARP 代理模式启动重试次数过多 ,已自动卸载WireProxy-WARP 代理模式"
            green "建议如下："
            yellow "1. 建议使用系统官方源升级系统及内核加速！如已使用第三方源及内核加速 ,请务必更新到最新版 ,或重置为系统官方源！"
            yellow "2. 部分VPS系统过于精简 ,相关依赖需自行安装后再重试"
            yellow "3. 检查 https://www.cloudflarestatus.com/ 查询VPS就近区域。如处于黄色的【Re-routed】状态则不可使用WireProxy-WARP 代理模式"
            yellow "4. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
            exit 1
        fi
        sleep 8
    done
    sleep 5
    systemctl enable wireproxy-warp >/dev/null 2>&1
    green "WireProxy-WARP 代理模式已启动成功!"
    echo ""
    showIP
}

wireproxy_changeport(){
    systemctl stop wireproxy-warp
    read -rp "请输入WireProxy-WARP使用的代理端口 (默认随机端口): " WireProxyPort
    [[ -z $WireProxyPort ]] && WireProxyPort=$(shuf -i 1000-65535 -n 1)
    if [[ -n $(netstat -ntlp | grep "$WireProxyPort") ]]; then
        until [[ -z $(netstat -ntlp | grep "$WireProxyPort") ]]; do
            if [[ -n $(netstat -ntlp | grep "$WireProxyPort") ]]; then
                yellow "你设置的端口目前已被占用，请重新输入端口"
                read -rp "请输入WireProxy-WARP使用的代理端口 (默认随机端口): " WireProxyPort
            fi
        done
    fi
    CurrentPort=$(grep BindAddress /etc/wireguard/proxy.conf)
    sed -i "s/$CurrentPort/BindAddress = 127.0.0.1:$WireProxyPort/g" /etc/wireguard/proxy.conf
    yellow "正在启动 WireProxy-WARP 代理模式"
    systemctl start wireproxy-warp
    WireProxyStatus=$(curl -sx socks5h://localhost:$WireProxyPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    retry_time=0
    until [[ $WireProxyStatus =~ on|plus ]]; do
        retry_time=$((${retry_time} + 1))
        red "启动 WireProxy-WARP 代理模式失败，正在尝试重启，重试次数：$retry_time"
        systemctl stop wireproxy-warp
        systemctl start wireproxy-warp
        WireProxyStatus=$(curl -sx socks5h://localhost:$WireProxyPort https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
        if [[ $retry_time == 6 ]]; then
            uninstallWireProxy
            echo ""
            red "由于 WireProxy-WARP 代理模式启动重试次数过多 ,已自动卸载WireProxy-WARP 代理模式"
            green "建议如下："
            yellow "1. 建议使用系统官方源升级系统及内核加速！如已使用第三方源及内核加速 ,请务必更新到最新版 ,或重置为系统官方源！"
            yellow "2. 部分VPS系统过于精简 ,相关依赖需自行安装后再重试"
            yellow "3. 检查 https://www.cloudflarestatus.com/ 查询VPS就近区域。如处于黄色的【Re-routed】状态则不可使用WireProxy-WARP 代理模式"
            yellow "4. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
            exit 1
        fi
        sleep 8
    done
    systemctl enable wireproxy-warp
    green "WireProxy-WARP 代理模式已启动成功并已修改端口！"
    echo ""
    showIP
}

switchWireproxy(){
    w5p=$(grep BindAddress /etc/wireguard/proxy.conf 2>/dev/null | sed "s/BindAddress = 127.0.0.1://g")
    w5s=$(curl -sx socks5h://localhost:$w5p https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    if [[ $w5s =~ "on"|"plus" ]]; then
        systemctl stop wireproxy-warp
        systemctl disable wireproxy-warp
        green "WireProxy-WARP代理模式关闭成功!"
    fi
    if [[ $w5s =~ "off" ]] || [[ -z $w5s ]]; then
        systemctl start wireproxy-warp
        systemctl enable wireproxy-warp
        green "WireProxy-WARP代理模式已启动成功!"
    fi
}

uninstallWireProxy(){
    systemctl stop wireproxy-warp
    systemctl disable wireproxy-warp
    rm -f /etc/systemd/system/wireproxy-warp.service /usr/local/bin/wireproxy /etc/wireguard/proxy.conf
    if [[ ! -f /etc/wireguard/wgcf.conf ]]; then
        rm -f /usr/local/bin/wgcf /etc/wireguard/wgcf-account.toml
    fi
    green "WireProxy-WARP代理模式已彻底卸载成功!"
}

warpup(){
    yellow "获取CloudFlare WARP账号信息方法: "
    green "电脑: 下载并安装CloudFlare WARP→设置→偏好设置→复制设备ID到脚本中"
    green "手机: 下载并安装1.1.1.1 APP→菜单→高级→诊断→复制设备ID到脚本中"
    echo ""
    yellow "请按照下面指示, 输入您的CloudFlare WARP账号信息:"
    read -rp "请输入您的WARP设备ID (36位字符): " license
    until [[ $license =~ ^[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}$ ]]; do
        red "设备ID输入格式输入错误，请重新输入！"
        read -rp "请输入您的WARP设备ID (36位字符): " license
    done
    wget -N --no-check-certificate https://raw.githubusercontent.com/ALIILAPRO/warp-plus-cloudflare/master/wp-plus.py
    sed -i "27 s/[(][^)]*[)]//g" wp-plus.py
    sed -i "27 s/input/'$license'/" wp-plus.py
    read -rp "请输入Screen会话名称 (默认为wp-plus): " screenname
    [[ -z $screenname ]] && screenname="wp-plus"
    screen -UdmS $screenname bash -c '/usr/bin/python3 /root/wp-plus.py'
    green "创建刷WARP+流量任务成功！ Screen会话名称为：$screenname"
}

warpsw1(){
    yellow "请选择切换的账户类型"
    green "1. WARP 免费账户"
    green "2. WARP+"
    green "3. WARP Teams"
    read -rp "请选择账户类型 [1-3]: " accountInput
    if [[ $accountInput == 1 ]]; then
        if [[ -n $(type -P wgcf) && -n $(type -P wg-quick) ]]; then
            wg-quick down wgcf >/dev/null 2>&1
            cd /etc/wireguard
            rm -f wgcf-account.toml wgcf-profile.conf
            until [[ -a wgcf-account.toml ]]; do
                wgcf register --accept-tos
                sleep 5
            done
            chmod +x wgcf-account.toml
            wgcf generate
            chmod +x wgcf-profile.conf
            warpPublicKey=$(grep PublicKey /etc/wireguard/wgcf-profile.conf | sed "s/PublicKey = //g")
            warpPrivateKey=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
            warpIPv4Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 3p | sed "s/Address = //g")
            warpIPv6Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 4p | sed "s/Address = //g")
            sed -i "s#PublicKey.*#PublicKey = $warpPublicKey#g" /etc/wireguard/wgcf.conf;
            sed -i "s#PrivateKey.*#PrivateKey = $warpPrivateKey#g" /etc/wireguard/wgcf.conf;
            sed -i "s#Address.*32#Address = $warpIPv4Address#g" /etc/wireguard/wgcf.conf;
            sed -i "s#Address.*128#Address = $warpIPv6Address#g" /etc/wireguard/wgcf.conf;
            rm -f wgcf-profile.conf
            wg-quick up wgcf >/dev/null 2>&1
            yellow "正在检查Wgcf-WARP的WARP 免费账户连通性，请稍等..." && sleep 5
            WgcfV4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            WgcfV6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
            if [[ $WgcfV4Status == "on" ]] || [[ $WgcfV6Status == "on" ]]; then
                green "Wgcf-WARP 账户类型切换为 WARP 免费账户 成功！"
            else
                wg-quick down wgcf >/dev/null 2>&1
                red "切换 Wgcf-WARP 账户类型失败，请尝试卸载后重装以重新切换账户！"
                exit 1
            fi
        fi
        if [[ -n $(type -P wireproxy) ]]; then
            systemctl stop wireproxy-warp
            cd /etc/wireguard
            rm -f wgcf-account.toml
            until [[ -a wgcf-account.toml ]]; do
                wgcf register --accept-tos
                sleep 5
            done
            chmod +x wgcf-account.toml
            wgcf generate
            chmod +x wgcf-profile.conf
            warpIPv4Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 3p | sed "s/Address = //g")
            warpPublicKey=$(grep PublicKey /etc/wireguard/wgcf-profile.conf | sed "s/PublicKey = //g")
            warpPrivateKey=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
            sed -i "s#PublicKey.*#PublicKey = $warpPublicKey#g" /etc/wireguard/proxy.conf;
            sed -i "s#PrivateKey.*#PrivateKey = $warpPrivateKey#g" /etc/wireguard/proxy.conf;
            sed -i "s#Address.*32#Address = $warpIPv4Address/32#g" /etc/wireguard/proxy.conf;
            systemctl start wireproxy-warp
            yellow "正在检查WireProxy代理模式的WARP 免费账户连通性，请稍等..." && sleep 5
            WireProxyStatus=$(curl -sx socks5h://localhost:$w5p https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
            sleep 2
            if [[ $WireProxyStatus == "on" ]]; then
                green "WireProxy-WARP 代理模式 账户类型切换为 WARP 免费账户 成功！"
            else
                systemctl stop wireproxy-warp
                red "切换 WireProxy-WARP 代理模式账户类型失败，请卸载后重新切换账户！"
                exit 1
            fi
        fi
        showIP
    fi
    if [[ $accountInput == 2 ]]; then
        cd /etc/wireguard
        if [[ ! -f wgcf-account.toml ]]; then
            until [[ -a wgcf-account.toml ]]; do
                wgcf register --accept-tos
                sleep 5
            done
        fi
        chmod +x wgcf-account.toml
        yellow "获取CloudFlare WARP账号密钥信息方法: "
        green "电脑: 下载并安装CloudFlare WARP→设置→偏好设置→账户→复制密钥到脚本中"
        green "手机: 下载并安装1.1.1.1 APP→菜单→账户→复制密钥到脚本中"
        echo ""
        yellow "重要：请确保手机或电脑的1.1.1.1 APP的账户状态为WARP+！"
        read -rp "输入WARP账户许可证密钥 (26个字符): " warpkey
        until [[ -z $warpkey || $warpkey =~ ^[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}$ ]]; do
            red "WARP账户许可证密钥格式输入错误，请重新输入！"
            read -rp "输入WARP账户许可证密钥 (26个字符): " warpkey
        done
        if [[ -n $warpkey ]]; then
            sed -i "s/license_key.*/license_key = \"$warpkey\"/g" wgcf-account.toml
            read -rp "请输入自定义设备名，如未输入则使用默认随机设备名: " devicename
            rm -f wgcf-profile.conf
            green "注册WARP+账户中, 如下方显示:400 Bad Request, 则使用WARP免费版账户"
            if [[ -n $devicename ]]; then
                wgcf update --name $(echo $devicename | sed s/[[:space:]]/_/g) > /etc/wireguard/info.log 2>&1
            else
                wgcf update > /etc/wireguard/info.log 2>&1
            fi
            wgcf generate
            chmod +x wgcf-profile.conf
            if [[ -n $(type -P wgcf) && -n $(type -P wg-quick) ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                warpPublicKey=$(grep PublicKey /etc/wireguard/wgcf-profile.conf | sed "s/PublicKey = //g")
                warpPrivateKey=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
                warpIPv4Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 3p | sed "s/Address = //g")
                warpIPv6Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 4p | sed "s/Address = //g")
                sed -i "s#PublicKey.*#PublicKey = $warpPublicKey#g" /etc/wireguard/wgcf.conf;
                sed -i "s#PrivateKey.*#PrivateKey = $warpPrivateKey#g" /etc/wireguard/wgcf.conf;
                sed -i "s#Address.*32#Address = $warpIPv4Address#g" /etc/wireguard/wgcf.conf;
                sed -i "s#Address.*128#Address = $warpIPv6Address#g" /etc/wireguard/wgcf.conf;
                wg-quick up wgcf >/dev/null 2>&1
                yellow "正在检查Wgcf-WARP的WARP+账户连通性，请稍等..." && sleep 5
                WgcfV4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
                WgcfV6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
                if [[ $WgcfV4Status == "plus" ]] || [[ $WgcfV6Status == "plus" ]]; then
                    green "Wgcf-WARP 账户类型切换为 WARP+ 成功！"
                else
                    wg-quick down wgcf >/dev/null 2>&1
                    cd /etc/wireguard
                    rm -f wgcf-account.toml wgcf-profile.conf
                    until [[ -a wgcf-account.toml ]]; do
                        wgcf register --accept-tos
                        sleep 5
                    done
                    wgcf generate
                    chmod +x wgcf-profile.conf
                    warpPublicKey=$(grep PublicKey /etc/wireguard/wgcf-profile.conf | sed "s/PublicKey = //g")
                    warpPrivateKey=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
                    warpIPv4Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 3p | sed "s/Address = //g")
                    warpIPv6Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 4p | sed "s/Address = //g")
                    sed -i "s#PublicKey.*#PublicKey = $warpPublicKey#g" /etc/wireguard/wgcf.conf;
                    sed -i "s#PrivateKey.*#PrivateKey = $warpPrivateKey#g" /etc/wireguard/wgcf.conf;
                    sed -i "s#Address.*32#Address = $warpIPv4Address#g" /etc/wireguard/wgcf.conf;
                    sed -i "s#Address.*128#Address = $warpIPv6Address#g" /etc/wireguard/wgcf.conf;
                    wg-quick up wgcf >/dev/null 2>&1
                    red "切换 Wgcf-WARP 账户类型失败，已自动切换为WARP 免费账户！"
                    green "建议如下："
                    yellow "1. 检查1.1.1.1 APP中的WARP+账户是否有足够的流量，如没有流量可以使用本脚本内的刷流量功能来获取免费的WARP+流量"
                    yellow "2. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
                    exit 1
                fi
            fi
            if [[ -n $(type -P wireproxy) ]]; then
                systemctl stop wireproxy-warp
                warpIPv4Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 3p | sed "s/Address = //g")
                warpPublicKey=$(grep PublicKey /etc/wireguard/wgcf-profile.conf | sed "s/PublicKey = //g")
                warpPrivateKey=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
                sed -i "s#PublicKey.*#PublicKey = $warpPublicKey#g" /etc/wireguard/proxy.conf;
                sed -i "s#PrivateKey.*#PrivateKey = $warpPrivateKey#g" /etc/wireguard/proxy.conf;
                sed -i "s#Address.*32#Address = $warpIPv4Address/32#g" /etc/wireguard/proxy.conf;
                systemctl start wireproxy-warp
                yellow "正在检查WireProxy的WARP+账户连通性，请稍等..." && sleep 5
                WireProxyStatus=$(curl -sx socks5h://localhost:$w5p https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
                sleep 2
                if [[ $WireProxyStatus == "plus" ]]; then
                    green "WireProxy-WARP代理模式 账户类型切换为 WARP+ 成功！"
                else
                    systemctl stop wireproxy-warp
                    cd /etc/wireguard
                    rm -f wgcf-account.toml wgcf-profile.conf
                    until [[ -a wgcf-account.toml ]]; do
                        wgcf register --accept-tos
                        sleep 5
                    done
                    wgcf generate
                    chmod +x wgcf-profile.conf
                    warpIPv4Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 3p | sed "s/Address = //g")
                    warpPublicKey=$(grep PublicKey /etc/wireguard/wgcf-profile.conf | sed "s/PublicKey = //g")
                    warpPrivateKey=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
                    sed -i "s#PublicKey.*#PublicKey = $warpPublicKey#g" /etc/wireguard/proxy.conf;
                    sed -i "s#PrivateKey.*#PrivateKey = $warpPrivateKey#g" /etc/wireguard/proxy.conf;
                    sed -i "s#Address.*32#Address = $warpIPv4Address/32#g" /etc/wireguard/proxy.conf;
                    systemctl start wireproxy-warp
                    red "切换 WireProxy-WARP 代理模式账户类型失败，已自动切换为WARP 免费账户！"
                    green "建议如下："
                    yellow "1. 检查1.1.1.1 APP中的WARP+账户是否有足够的流量，如没有流量可以使用本脚本内的刷流量功能来获取免费的WARP+流量"
                    yellow "2. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
                    exit 1
                fi
            fi
            showIP
        else
            red "未输入WARP账户许可证密钥, 无法升级！"
        fi
    fi
    if [[ $accountInput == 3 ]]; then
        read -rp "请复制粘贴WARP Teams账户配置文件链接: " teamconfigurl
        if [[ -z $teamconfigurl ]]; then
            yellow "未输入Teams账户配置文件链接，正在使用脚本公用Teams账户..."
            teamconfigurl="https://raw.githubusercontent.com/taffychan/warp/main/files/publicteam.xml"
        fi
        teamsconfig=$(curl -sSL "$teamconfigurl" | sed "s/\"/\&quot;/g")
        wpteampublickey=$(expr "$teamsconfig" : '.*public_key&quot;:&quot;\([^&]*\).*')
        wpteamprivatekey=$(expr "$teamsconfig" : '.*private_key&quot;>\([^<]*\).*')
        wpteamv6address=$(expr "$teamsconfig" : '.*v6&quot;:&quot;\([^[&]*\).*')
        wpteamv4address=$(expr "$teamsconfig" : '.*v4&quot;:&quot;\(172[^&]*\).*')
        green "你的WARP Teams配置文件信息如下:"
        yellow "PublicKey: $wpteampublickey"
        yellow "PrivateKey: $wpteamprivatekey"
        yellow "IPv4地址: $wpteamv4address"
        yellow "IPv6地址: $wpteamv6address"
        read -rp "确认以上配置信息信息正确请输入y, 其他按键退出升级过程: " wpteamconfirm
        if [[ $wpteamconfirm =~ "y"|"Y" ]]; then
            if [[ -n $(type -P wgcf) && -n $(type -P wg-quick) ]]; then
                wg-quick down wgcf >/dev/null 2>&1
                sed -i "s#PublicKey.*#PublicKey = $wpteampublickey#g" /etc/wireguard/wgcf.conf;
                sed -i "s#PrivateKey.*#PrivateKey = $wpteamprivatekey#g" /etc/wireguard/wgcf.conf;
                sed -i "s#Address.*32#Address = $wpteamv4address/32#g" /etc/wireguard/wgcf.conf;
                sed -i "s#Address.*128#Address = $wpteamv6address/128#g" /etc/wireguard/wgcf.conf;
                sed -i "s#PublicKey.*#PublicKey = $wpteampublickey#g" /etc/wireguard/wgcf-profile.conf;
                sed -i "s#PrivateKey.*#PrivateKey = $wpteamprivatekey#g" /etc/wireguard/wgcf-profile.conf;
                sed -i "s#Address.*32#Address = $wpteamv4address/32#g" /etc/wireguard/wgcf-profile.conf;
                sed -i "s#Address.*128#Address = $wpteamv6address/128#g" /etc/wireguard/wgcf-profile.conf;
                wg-quick up wgcf >/dev/null 2>&1
                yellow "正在检查Wgcf-WARP的WARP Teams账户连通性, 请稍等..."
                WgcfV4Status=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
                WgcfV6Status=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
                retry_time=1
                until [[ $WgcfV4Status =~ on|plus ]] || [[ $WgcfV6Status =~ on|plus ]]; do
                    red "无法联通WARP Teams账户, 正在尝试重启, 重试次数：$retry_time"
                    retry_time=$((${retry_time} + 1))
                    if [[ $retry_time == 4 ]]; then
                        wg-quick down wgcf >/dev/null 2>&1
                        cd /etc/wireguard
                        rm -f wgcf-profile.conf
                        wgcf generate
                        chmod +x wgcf-profile.conf
                        warpPublicKey=$(grep PublicKey /etc/wireguard/wgcf-profile.conf | sed "s/PublicKey = //g")
                        warpPrivateKey=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
                        warpIPv4Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 3p | sed "s/Address = //g")
                        warpIPv6Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 4p | sed "s/Address = //g")
                        sed -i "s#PublicKey.*#PublicKey = $warpPublicKey#g" /etc/wireguard/wgcf.conf;
                        sed -i "s#PrivateKey.*#PrivateKey = $warpPrivateKey#g" /etc/wireguard/wgcf.conf;
                        sed -i "s#Address.*32#Address = $warpIPv4Address#g" /etc/wireguard/wgcf.conf;
                        sed -i "s#Address.*128#Address = $warpIPv6Address#g" /etc/wireguard/wgcf.conf;
                        wg-quick up wgcf >/dev/null 2>&1
                        red "WARP Teams配置可能有误, 已自动降级至WARP 免费账户 / WARP+"
                        green "建议如下："
                        yellow "1. 检查提取出来的配置文件是否为从安卓5.1模拟器，1.1.1.1 APP 6.9版本的"
                        yellow "2. 你有可能修改了团队名、删除了设备"
                        yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
                        exit 1
                    fi
                done
                green "Wgcf-WARP 账户类型切换为 WARP Teams 成功！"
            fi
            if [[ -n $(type -P wireproxy) ]]; then
                systemctl stop wireproxy-warp
                sed -i "s#PublicKey.*#PublicKey = $wpteampublickey#g" /etc/wireguard/proxy.conf;
                sed -i "s#PrivateKey.*#PrivateKey = $wpteamprivatekey#g" /etc/wireguard/proxy.conf;
                sed -i "s#Address.*32#Address = $wpteamv4address/32#g" /etc/wireguard/proxy.conf;
                systemctl start wireproxy-warp
                yellow "正在检查WireProxy代理模式的WARP Teams账户连通性, 请稍等..."
                WireProxyStatus=$(curl -sx socks5h://localhost:$w5p https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
                sleep 2
                retry_time=1
                until [[ $WireProxyStatus == "plus" ]]; do
                    red "无法联通WARP Teams账户, 正在尝试重启, 重试次数：$retry_time"
                    retry_time=$((${retry_time} + 1))
                    if [[ $retry_time == 4 ]]; then
                        systemctl stop wireproxy-warp
                        cd /etc/wireguard
                        rm -f wgcf-profile.conf
                        wgcf generate
                        chmod +x wgcf-profile.conf
                        warpIPv4Address=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 3p | sed "s/Address = //g")
                        warpPublicKey=$(grep PublicKey /etc/wireguard/wgcf-profile.conf | sed "s/PublicKey = //g")
                        warpPrivateKey=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
                        sed -i "s#PublicKey.*#PublicKey = $warpPublicKey#g" /etc/wireguard/proxy.conf;
                        sed -i "s#PrivateKey.*#PrivateKey = $warpPrivateKey#g" /etc/wireguard/proxy.conf;
                        sed -i "s#Address.*32#Address = $warpIPv4Address/32#g" /etc/wireguard/proxy.conf;
                        rm -f wgcf-profile.conf
                        systemctl start wireproxy-warp
                        red "WARP Teams配置可能有误, 已自动降级至WARP 免费账户 / WARP+"
                        green "建议如下："
                        yellow "1. 检查提取出来的配置文件是否为从安卓5.1模拟器，1.1.1.1 APP 6.9版本的"
                        yellow "2. 你有可能修改了团队名、删除了设备"
                        yellow "3. 脚本可能跟不上时代, 建议截图发布到GitHub Issues、GitLab Issues、论坛或TG群询问"
                        exit 1
                    fi
                done
                green "WireProxy-WARP代理模式 账户类型切换为 WARP Teams 成功！"
            fi
            showIP
        else
            red "已退出WARP Teams账号升级过程!"
        fi
    fi
}

warpsw2(){
    warp-cli --accept-tos disconnect >/dev/null 2>&1
    warp-cli --accept-tos register >/dev/null 2>&1
    yellow "获取CloudFlare WARP账号密钥信息方法: "
    green "电脑: 下载并安装CloudFlare WARP→设置→偏好设置→账户→复制密钥到脚本中"
    green "手机: 下载并安装1.1.1.1 APP→菜单→账户→复制密钥到脚本中"
    echo ""
    yellow "重要：请确保手机或电脑的1.1.1.1 APP的账户状态为WARP+！"
    read -rp "输入WARP账户许可证密钥 (26个字符): " warpkey
    until [[ -z $warpkey || $warpkey =~ ^[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}$ ]]; do
        red "WARP账户许可证密钥输入错误，请重新输入！"
        read -rp "输入WARP账户许可证密钥 (26个字符): " warpkey
    done
    if [[ -n $warpkey ]]; then
        warp-cli --accept-tos set-license "$warpkey" >/dev/null 2>&1 && sleep 1
    fi
    warp-cli --accept-tos set-mode proxy >/dev/null 2>&1
    warp-cli --accept-tos set-proxy-port "$s5p" >/dev/null 2>&1
    warp-cli --accept-tos connect >/dev/null 2>&1
    if [[ $(warp-cli --accept-tos account) =~ Limited ]]; then
        green "WARP-Cli 账户类型切换为 WARP+ 成功！"
        showIP
    else
        red "WARP+账户启用失败, 已自动降级至WARP免费版账户"
    fi
}

warpsw(){
    yellow "请选择需要切换WARP账户的WARP客户端:"
    echo -e " ${GREEN}1.${PLAIN} Wgcf-WARP 和 WireProxy-WARP 代理模式"
    echo -e " ${GREEN}2.${PLAIN} WARP-Cli ${RED}(目前仅支持升级WARP+账户)${PLAIN}"
    read -rp "请选择客户端 [1-2]: " clientInput
    case "$clientInput" in
        1 ) warpsw1 ;;
        2 ) warpsw2 ;;
        * ) exit 1 ;;
    esac
}

warpnf(){
    yellow "请选择需要刷NetFilx IP的WARP客户端:"
    green "1. Wgcf-WARP IPv4模式"
    green "2. Wgcf-WARP IPv6模式"
    green "3. WARP-Cli 代理模式"
    green "4. WireProxy-WARP 代理模式"
    read -rp "请选择客户端 [1-4]: " clientInput
    case "$clientInput" in
        1 ) wget -N --no-check-certificate https://raw.githubusercontent.com/taffychan/warp/main/netflix/netflix4.sh && bash netflix4.sh ;;
        2 ) wget -N --no-check-certificate https://raw.githubusercontent.com/taffychan/warp/main/netflix/netflix6.sh && bash netflix6.sh ;;
        3 ) wget -N --no-check-certificate https://raw.githubusercontent.com/taffychan/warp/main/netflix/netflixcli.sh && bash netflixcli.sh ;;
        4 ) wget -N --no-check-certificate https://raw.githubusercontent.com/taffychan/warp/main/netflix/netflixwire.sh && bash netflixwire.sh ;;
    esac
}

showIP(){
    if [[ $(warp-cli --accept-tos settings 2>/dev/null | grep "Mode" | awk -F ": " '{print $2}') == "Warp" ]]; then
        INTERFACE='--interface CloudflareWARP'
    fi
    Browser_UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/80.0.3987.87 Safari/537.36"
    v4=$(curl -s4m8 ip.p3terx.com -k $INTERFACE | sed -n 1p) || v4=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p)
    v6=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
    c4=$(curl -s4m8 ip.p3terx.com $INTERFACE | sed -n 2p) || c4=$(curl -s4m8 ip.p3terx.com | sed -n 2p)
    c6=$(curl -s6m8 ip.p3terx.com | sed -n 2p)
    d4="${RED}未设置${PLAIN}"
    d6="${RED}未设置${PLAIN}"
    w4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k $INTERFACE | grep warp | cut -d= -f2) || w4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    w6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    if [[ -n $INTERFACE ]]; then
        n4=$(curl $INTERFACE --user-agent "${Browser_UA}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81215567" 2>&1) || n4=$(curl -4 --user-agent "${Browser_UA}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81215567" 2>&1)
    else
        n4=$(curl -4 --user-agent "${Browser_UA}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81215567" 2>&1)
    fi
    n6=$(curl -6 --user-agent "${Browser_UA}" -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81215567" 2>&1)
    
    s5p=$(warp-cli --accept-tos settings 2>/dev/null | grep 'WarpProxy on port' | awk -F "port " '{print $2}')
    w5p=$(grep BindAddress /etc/wireguard/proxy.conf 2>/dev/null | sed "s/BindAddress = 127.0.0.1://g")
    if [[ -n $s5p ]]; then
        s5s=$(curl -sx socks5h://localhost:$s5p https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
        s5i=$(curl -sx socks5h://localhost:$s5p ip.p3terx.com -k --connect-timeout 8 | sed -n 1p)
        s5c=$(curl -sx socks5h://localhost:$s5p ip.p3terx.com --connect-timeout 8 | sed -n 2p)
        s5n=$(curl -sx socks5h://localhost:$s5p -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81215567" 2>&1)
    fi
    if [[ -n $w5p ]]; then
        w5d="${RED}未设置${PLAIN}"
        w5s=$(curl -sx socks5h://localhost:$w5p https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
        w5i=$(curl -sx socks5h://localhost:$w5p ip.p3terx.com -k --connect-timeout 8 | sed -n 1p)
        w5c=$(curl -sx socks5h://localhost:$w5p ip.p3terx.com --connect-timeout 8 | sed -n 2p)
        w5n=$(curl -sx socks5h://localhost:$w5p -fsL --write-out %{http_code} --output /dev/null --max-time 10 "https://www.netflix.com/title/81215567" 2>&1)
    fi

    if [[ $w4 == "plus" ]]; then
        if [[ -n $(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }') ]]; then
            d4=$(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }')
            check_quota
            t4="${GREEN} $QUOTA ${PLAIN}"
            w4="${GREEN}WARP+${PLAIN}"
        else
            t4="${RED}无限制${PLAIN}"
            w4="${GREEN}WARP Teams${PLAIN}"
        fi
    elif [[ $w4 == "on" ]]; then
        t4="${RED}无限制${PLAIN}"
        w4="${YELLOW}WARP 免费账户${PLAIN}"
    else
        t4="${RED}无限制${PLAIN}"
        w4="${RED}未启用WARP${PLAIN}"
    fi
    if [[ $w6 == "plus" ]]; then
        if [[ -n $(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }') ]]; then
            d6=$(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }')
            check_quota
            t6="${GREEN} $QUOTA ${PLAIN}"
            w6="${GREEN}WARP+${PLAIN}"
        else
            t6="${RED}无限制${PLAIN}"
            w6="${GREEN}WARP Teams${PLAIN}"
        fi
    elif [[ $w6 == "on" ]]; then
        t6="${RED}无限制${PLAIN}"
        w6="${YELLOW}WARP 免费账户${PLAIN}"
    else
        t6="${RED}无限制${PLAIN}"
        w6="${RED}未启用WARP${PLAIN}"
    fi
    if [[ $w5s == "plus" ]]; then
        if [[ -n $(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }') ]]; then
            w5d=$(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }')
            check_quota
            w5t="${GREEN} $QUOTA ${PLAIN}"
            w5="${GREEN}WARP+${PLAIN}"
        else
            w5t="${RED}无限制${PLAIN}"
            w5="${GREEN}WARP Teams${PLAIN}"
        fi
    elif [[ $w5s == "on" ]]; then
        w5t="${RED}无限制${PLAIN}"
        w5="${YELLOW}WARP 免费账户${PLAIN}"
    else
        w5t="${RED}无限制${PLAIN}"
        w5="${RED}未启动${PLAIN}"
    fi
    if [[ $s5s == "plus" ]]; then
        CHECK_TYPE=1
        check_quota
        s5t="${GREEN} $QUOTA ${PLAIN}"
        s5="${GREEN}WARP+${PLAIN}"
    else
        s5t="${RED}无限制${PLAIN}"
        s5="${YELLOW}WARP 免费账户${PLAIN}"
    fi
    
    [[ -z $s5s ]] || [[ $s5s == "off" ]] && s5="${RED}未启动${PLAIN}"
    
    [[ -z $n4 ]] || [[ $n4 == "000" ]] && n4="${RED}无法检测Netflix状态${PLAIN}"
    [[ -z $n6 ]] || [[ $n6 == "000" ]] && n6="${RED}无法检测Netflix状态${PLAIN}"
    [[ $n4 == "200" ]] && n4="${GREEN}已解锁 Netflix${PLAIN}"
    [[ $n6 == "200" ]] && n6="${GREEN}已解锁 Netflix${PLAIN}"
    [[ $s5n == "200" ]] && s5n="${GREEN}已解锁 Netflix${PLAIN}"
    [[ $w5n == "200" ]] && w5n="${GREEN}已解锁 Netflix${PLAIN}"
    [[ $n4 == "403" ]] && n4="${RED}无法解锁 Netflix${PLAIN}"
    [[ $n6 == "403" ]] && n6="${RED}无法解锁 Netflix${PLAIN}"
    [[ $s5n == "403" ]]&& s5n="${RED}无法解锁 Netflix${PLAIN}"
    [[ $w5n == "403" ]]&& w5n="${RED}无法解锁 Netflix${PLAIN}"
    [[ $n4 == "404" ]] && n4="${YELLOW}Netflix 自制剧${PLAIN}"
    [[ $n6 == "404" ]] && n6="${YELLOW}Netflix 自制剧${PLAIN}"
    [[ $s5n == "404" ]] && s5n="${YELLOW}Netflix 自制剧${PLAIN}"
    [[ $w5n == "404" ]] && w5n="${YELLOW}Netflix 自制剧${PLAIN}"
    
    if [[ -n $v4 ]]; then
        echo "----------------------------------------------------------------------------"
        echo -e "IPv4 地址：$v4  地区：$c4  设备名称：$d4"
        echo -e "WARP状态：$w4  剩余流量：$t4  Netfilx解锁状态：$n4"
    fi
    if [[ -n $v6 ]]; then
        echo "----------------------------------------------------------------------------"
        echo -e "IPv6 地址：$v6  地区：$c6  设备名称：$d6"
        echo -e "WARP状态：$w6  剩余流量：$t6  Netfilx解锁状态：$n6"
    fi
    if [[ -n $s5p ]]; then
        echo "----------------------------------------------------------------------------"
        echo -e "WARP-Cli代理端口: 127.0.0.1:$s5p  状态: $s5  剩余流量：$s5t"
        if [[ -n $s5i ]]; then
            echo -e "IP: $s5i  地区: $s5c  Netfilx解锁状态：$s5n"
        fi
    fi
    if [[ -n $w5p ]]; then
        echo "----------------------------------------------------------------------------"
        echo -e "WireProxy代理端口: 127.0.0.1:$w5p  状态: $w5  设备名称：$w5d"
        if [[ -n $w5i ]]; then
            echo -e "IP: $w5i  地区: $w5c  剩余流量：$w5t  Netfilx解锁状态：$w5n"
        fi
    fi
    echo "----------------------------------------------------------------------------"
}

menu(){
    clear
    echo "#############################################################"
    echo -e "#                     ${RED}WARP  安装管理脚本${PLAIN}                    #"
    echo -e "# ${GREEN}作者${PLAIN}: MisakaNo の 小破站                                  #"
    echo -e "# ${GREEN}博客${PLAIN}: https://blog.misaka.rest                            #"
    echo -e "# ${GREEN}GitLab${PLAIN}: https://gitlab.com/misakablog                     #"
    echo "#############################################################"
    echo -e ""
    echo -e " ${GREEN}1.${PLAIN} 安装/切换 Wgcf-WARP 全局单栈模式 ${YELLOW}(WARP IPv4)${PLAIN} | ${GREEN}6.${PLAIN} 安装 WARP-Cli 全局模式 ${YELLOW}(WARP IPv4)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} 安装/切换 Wgcf-WARP 全局单栈模式 ${YELLOW}(WARP IPv6)${PLAIN} | ${GREEN}7.${PLAIN} 安装 WARP-Cli 代理模式"
    echo -e " ${GREEN}3.${PLAIN} 安装/切换 Wgcf-WARP 全局双栈模式             | ${GREEN}8.${PLAIN} 修改 WARP-Cli 代理模式连接端口"
    echo -e " ${GREEN}4.${PLAIN} 开启或关闭 Wgcf-WARP                         | ${GREEN}9.${PLAIN} 开启或关闭 WARP-Cli"
    echo -e " ${GREEN}5.${PLAIN} ${RED}卸载 Wgcf-WARP${PLAIN}                               | ${GREEN}10.${PLAIN} ${RED}卸载 WARP-Cli${PLAIN}"
    echo " ----------------------------------------------------------------------------------"
    echo -e " ${GREEN}11.${PLAIN} 安装 Wireproxy-WARP 代理模式                | ${GREEN}15.${PLAIN} 获取 WARP+ 账户流量"
    echo -e " ${GREEN}12.${PLAIN} 修改 Wireproxy-WARP 代理模式连接端口        | ${GREEN}16.${PLAIN} 切换 WARP 账户类型"
    echo -e " ${GREEN}13.${PLAIN} 开启或关闭 Wireproxy-WARP 代理模式          | ${GREEN}17.${PLAIN} 获取解锁 Netflix 的 WARP IP"
    echo -e " ${GREEN}14.${PLAIN} ${RED}卸载 Wireproxy-WARP 代理模式${PLAIN}                | ${GREEN}0.${PLAIN} 退出脚本"
    echo -e ""
    showIP
    echo -e ""
    read -rp "请输入选项 [0-17]：" menuChoice
    case $menuChoice in
        1) wgcfv44 ;;
        2) wgcfv66 ;;
        3) wgcfv46 ;;
        4) switchwgcf ;;
        5) uninstallwgcf ;;
        6) warpcli=1 && installcli ;;
        7) warpcli=2 && installcli ;;
        8) warpcli_changeport ;;
        9) switchcli ;;
        10) uninstallcli ;;
        11) installWireProxy ;;
        12) wireproxy_changeport ;;
        13) switchWireProxy ;;
        14) uninstallWireProxy ;;
        15) warpup ;;
        16) warpsw ;;
        17) warpnf ;;
        *) red "请输入正确的选项 [0-17]！" && exit 1 ;;
    esac
}

menu
