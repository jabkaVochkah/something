#!/bin/bash
#
# Скрипт для установки на своём сервере AntiZapret VPN и обычного VPN
#
# https://github.com/GubernievS/AntiZapret-VPN
#
# bash <(wget -qO- --no-hsts --inet4-only https://raw.githubusercontent.com/jabkaVochkah/something/main/setup_vpn.sh)

export LC_ALL=C

#
# Проверка прав root
if [[ "$EUID" -ne 0 ]]; then
	echo 'Error: You need to run this as root!'
	exit 2
fi

cd /root

#
# Проверка на OpenVZ и LXC
if [[ "$(systemd-detect-virt)" == "openvz" || "$(systemd-detect-virt)" == "lxc" ]]; then
	echo 'Error: OpenVZ and LXC are not supported!'
	exit 3
fi

#
# Проверка версии системы
OS="$(lsb_release -si | tr '[:upper:]' '[:lower:]')"
VERSION="$(lsb_release -rs | cut -d '.' -f1)"

if [[ "$OS" == "debian" ]]; then
	if [[ $VERSION -lt 11 ]]; then
		echo 'Error: Your Debian version is not supported!'
		exit 4
	fi
elif [[ "$OS" == "ubuntu" ]]; then
	if [[ $VERSION -lt 22 ]]; then
		echo 'Error: Your Ubuntu version is not supported!'
		exit 5
	fi
elif [[ "$OS" != "debian" ]] && [[ "$OS" != "ubuntu" ]]; then
	echo 'Error: Your Linux version is not supported!'
	exit 6
fi

#
# Проверка свободного места (минимум 2Гб)
if [[ $(df --output=avail / | tail -n 1) -lt $((2 * 1024 * 1024)) ]]; then
	echo 'Error: Low disk space! You need 2GB of free space!'
	exit 7
fi








export OPENVPN_PATCH="0"           # Strong patch
export OPENVPN_DCO="y"             # Turn on OpenVPN DCO
export ANTIZAPRET_DNS="1"          # Cloudflare+Quad9 for Antizapret
export VPN_DNS="1"                 # Cloudflare for full VPN
export BLOCK_ADS="y"               # Enable blocking ads
export ALTERNATIVE_IP="n"          # Do not use alternative IP range
export OPENVPN_80_443_TCP="n"      # NO TCP 80/443 for OpenVPN (IMPORTANT for Caddy)
export OPENVPN_80_443_UDP="n"      # NO UDP 80/443 for OpenVPN (IMPORTANT for Caddy)
export OPENVPN_DUPLICATE="y"       # Allow multiple clients
export OPENVPN_LOG="n"             # Do not enable detailed logs
export SSH_PROTECTION="y"          # Enable SSH brute-force protection
export ATTACK_PROTECTION="n"       # NO network attack and scan protection (IMPORTANT for Caddy/SillyTavern)
export TORRENT_GUARD="y"           # Enable torrent guard
export RESTRICT_FORWARD="n"        # Restrict forwarding
export OPENVPN_HOST=""             # No domain for OpenVPN (empty string)
export WIREGUARD_HOST=""           # No domain for WireGuard (empty string)
export ROUTE_ALL="n"               # Do not route all traffic
export DISCORD_INCLUDE="n"         # Include Discord IPs
export CLOUDFLARE_INCLUDE="n"      # Include Cloudflare IPs
export TELEGRAM_INCLUDE="n"        # Include Telegram IPs
export AMAZON_INCLUDE="n"          # Do not include Amazon IPs
export HETZNER_INCLUDE="n"         # Do not include Hetzner IPs
export DIGITALOCEAN_INCLUDE="n"    # Do not include DigitalOcean IPs
export OVH_INCLUDE="n"             # Do not include OVH IPs
export GOOGLE_INCLUDE="n"          # Do not include Google IPs
export AKAMAI_INCLUDE="n"          # Do not include Akamai IPs








echo 'Preparing for installation, please wait...'

#
# Ожидание пока выполняется apt-get
while pidof apt-get &>/dev/null; do
	echo 'Waiting for apt-get to finish...';
	sleep 5;
done

#
# Отключим фоновые обновления системы
systemctl stop unattended-upgrades &>/dev/null
systemctl stop apt-daily.timer &>/dev/null
systemctl stop apt-daily-upgrade.timer &>/dev/null

#
# Остановим и выключим обновляемые службы
for service in kresd@ openvpn-server@ wg-quick@; do
	systemctl list-units --type=service --no-pager | awk -v s="$service" '$1 ~ s"[^.]+\\.service" {print $1}' | xargs -r systemctl stop &>/dev/null
	systemctl list-unit-files --type=service --no-pager | awk -v s="$service" '$1 ~ s"[^.]+\\.service" {print $1}' | xargs -r systemctl disable &>/dev/null
done

systemctl stop antizapret &>/dev/null
systemctl disable antizapret &>/dev/null

systemctl stop antizapret-update &>/dev/null
systemctl disable antizapret-update &>/dev/null

systemctl stop antizapret-update.timer &>/dev/null
systemctl disable antizapret-update.timer &>/dev/null

# Остановим и выключим ненужные службы
systemctl stop firewalld &>/dev/null
ufw disable &>/dev/null

systemctl disable firewalld &>/dev/null
systemctl disable ufw &>/dev/null

#
# Удаляем старые файлы и кеш Knot Resolver
rm -rf /var/cache/knot-resolver/*
rm -rf /etc/knot-resolver/*
rm -rf /var/lib/knot-resolver/*

#
# Удаляем старые файлы OpenVPN и WireGuard
rm -rf /etc/openvpn/server/*
rm -rf /etc/openvpn/client/*
rm -rf /etc/wireguard/templates/*

#
# Удаляем скомпилированный патченный OpenVPN
make -C /usr/local/src/openvpn uninstall &>/dev/null
rm -rf /usr/local/src/openvpn

#
# Отключим IPv6
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
sysctl -w net.ipv6.conf.lo.disable_ipv6=1

#
# Завершим выполнение скрипта при ошибке
set -e

#
# Обработка ошибок
handle_error() {
	echo "$(lsb_release -ds) $(uname -r) $(date --iso-8601=seconds)"
	echo -e "\e[1;31mError at line $1: $2\e[0m"
	exit 1
}
trap 'handle_error $LINENO "$BASH_COMMAND"' ERR

#
# Обновляем систему
rm -rf /etc/apt/sources.list.d/cznic-labs-knot-resolver.list
rm -rf /etc/apt/sources.list.d/openvpn-aptrepo.list
rm -rf /etc/apt/sources.list.d/backports.list
export DEBIAN_FRONTEND=noninteractive
apt-get clean
apt-get update
dpkg --configure -a
apt-get install --fix-broken -y
apt-get dist-upgrade -y
apt-get install --reinstall -y curl gpg

#
# Папка для ключей
mkdir -p /etc/apt/keyrings

#
# Добавим репозиторий Knot Resolver
curl -fsSL https://pkg.labs.nic.cz/gpg -o /etc/apt/keyrings/cznic-labs-pkg.gpg
echo "deb [signed-by=/etc/apt/keyrings/cznic-labs-pkg.gpg] https://pkg.labs.nic.cz/knot-resolver $(lsb_release -cs) main" > /etc/apt/sources.list.d/cznic-labs-knot-resolver.list

#
# Добавим репозиторий OpenVPN
curl -fsSL https://swupdate.openvpn.net/repos/repo-public.gpg | gpg --dearmor > /etc/apt/keyrings/openvpn-repo-public.gpg
echo "deb [signed-by=/etc/apt/keyrings/openvpn-repo-public.gpg] https://build.openvpn.net/debian/openvpn/release/2.6 $(lsb_release -cs) main" > /etc/apt/sources.list.d/openvpn-aptrepo.list

#
# Добавим репозиторий Debian Backports
if [[ "$OS" == "debian" ]]; then
	if [[ "$VERSION" -ge 12 ]]; then
		echo "deb http://deb.debian.org/debian $(lsb_release -cs)-backports main" > /etc/apt/sources.list.d/backports.list
	elif [[ "$VERSION" -eq 11 ]]; then
		echo "deb http://archive.debian.org/debian $(lsb_release -cs)-backports main" > /etc/apt/sources.list.d/backports.list
	fi
fi

#
# Ставим необходимые пакеты
apt-get update
apt-get install --reinstall -y git openvpn iptables easy-rsa gawk knot-resolver idn sipcalc python3-pip wireguard diffutils socat lua-cqueues ipset irqbalance
apt-get autoremove -y
apt-get clean

#
# Клонируем репозиторий и устанавливаем dnslib
rm -rf /tmp/dnslib
git clone https://github.com/paulc/dnslib.git /tmp/dnslib
PIP_BREAK_SYSTEM_PACKAGES=1 python3 -m pip install --force-reinstall --user /tmp/dnslib

#
# Клонируем репозиторий antizapret
rm -rf /tmp/antizapret
git clone https://github.com/GubernievS/AntiZapret-VPN.git /tmp/antizapret

#
# Сохраняем пользовательские настройки и пользовательские обработчики custom*.sh
cp /root/antizapret/config/* /tmp/antizapret/setup/root/antizapret/config/ &>/dev/null || true
cp /root/antizapret/custom*.sh /tmp/antizapret/setup/root/antizapret/ &>/dev/null || true

#
# Восстанавливаем из бэкапа пользовательские настройки и пользователей OpenVPN и WireGuard
tar -xzf /root/backup*.tar.gz &>/dev/null || true
rm -f /root/backup*.tar.gz &>/dev/null || true
cp -r /root/easyrsa3/* /tmp/antizapret/setup/etc/openvpn/easyrsa3 &>/dev/null || true
cp /root/wireguard/* /tmp/antizapret/setup/etc/wireguard &>/dev/null || true
cp /root/config/* /tmp/antizapret/setup/root/antizapret/config &>/dev/null || true
rm -rf /root/easyrsa3
rm -rf /root/wireguard
rm -rf /root/config

#
# Сохраняем настройки
echo "SETUP_DATE=$(date --iso-8601=seconds)
OPENVPN_PATCH=${OPENVPN_PATCH}
OPENVPN_DCO=${OPENVPN_DCO}
ANTIZAPRET_DNS=${ANTIZAPRET_DNS}
VPN_DNS=${VPN_DNS}
BLOCK_ADS=${BLOCK_ADS}
ALTERNATIVE_IP=${ALTERNATIVE_IP}
OPENVPN_80_443_TCP=${OPENVPN_80_443_TCP}
OPENVPN_80_443_UDP=${OPENVPN_80_443_UDP}
OPENVPN_DUPLICATE=${OPENVPN_DUPLICATE}
OPENVPN_LOG=${OPENVPN_LOG}
SSH_PROTECTION=${SSH_PROTECTION}
ATTACK_PROTECTION=${ATTACK_PROTECTION}
TORRENT_GUARD=${TORRENT_GUARD}
RESTRICT_FORWARD=${RESTRICT_FORWARD}
OPENVPN_HOST=${OPENVPN_HOST}
WIREGUARD_HOST=${WIREGUARD_HOST}
ROUTE_ALL=${ROUTE_ALL}
DISCORD_INCLUDE=${DISCORD_INCLUDE}
CLOUDFLARE_INCLUDE=${CLOUDFLARE_INCLUDE}
TELEGRAM_INCLUDE=${TELEGRAM_INCLUDE}
AMAZON_INCLUDE=${AMAZON_INCLUDE}
HETZNER_INCLUDE=${HETZNER_INCLUDE}
DIGITALOCEAN_INCLUDE=${DIGITALOCEAN_INCLUDE}
OVH_INCLUDE=${OVH_INCLUDE}
GOOGLE_INCLUDE=${GOOGLE_INCLUDE}
AKAMAI_INCLUDE=${AKAMAI_INCLUDE}
DEFAULT_INTERFACE=
DEFAULT_IP=
CLEAR_HOSTS=y" > /tmp/antizapret/setup/root/antizapret/setup

#
# Выставляем разрешения
find /tmp/antizapret -type f -exec chmod 644 {} +
find /tmp/antizapret -type d -exec chmod 755 {} +
find /tmp/antizapret -type f \( -name '*.sh' -o -name '*.py' \) -execdir chmod +x {} +

# Копируем нужное, удаляем не нужное
find /tmp/antizapret -name '.gitkeep' -delete
rm -rf /root/antizapret
cp -r /tmp/antizapret/setup/* /
rm -rf /tmp/dnslib
rm -rf /tmp/antizapret

#
# Настраиваем DNS в AntiZapret VPN
if [[ "$ANTIZAPRET_DNS" == "2" ]]; then
	# Cloudflare+Quad9
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'1.1.1.1', '1.0.0.1', '9.9.9.10', '149.112.112.10'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == "3" ]]; then
	# Comss
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'83.220.169.155', '212.109.195.93'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'83.220.169.155', '212.109.195.93'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == "4" ]]; then
	# Xbox
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'176.99.11.77', '80.78.247.254'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'176.99.11.77', '80.78.247.254'/" /etc/knot-resolver/kresd.conf
elif [[ "$ANTIZAPRET_DNS" == "5" ]]; then
	# Malw
	sed -i "s/'62\.76\.76\.62', '62\.76\.62\.76', '195\.208\.4\.1', '195\.208\.5\.1'/'46.226.165.53', '64.188.98.242'/" /etc/knot-resolver/kresd.conf
	sed -i "s/'1\.1\.1\.1', '1\.0\.0\.1', '9\.9\.9\.10', '149\.112\.112\.10'/'46.226.165.53', '64.188.98.242'/" /etc/knot-resolver/kresd.conf
fi

#
# Настраиваем DNS в обычном VPN
if [[ "$VPN_DNS" == "2" ]]; then
	# Quad9
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 9.9.9.10"\npush "dhcp-option DNS 149.112.112.10"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/9.9.9.10, 149.112.112.10/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "3" ]]; then
	# Google
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 8.8.8.8"\npush "dhcp-option DNS 8.8.4.4"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/8.8.8.8, 8.8.4.4/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "4" ]]; then
	# AdGuard
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 94.140.14.14"\npush "dhcp-option DNS 94.140.15.15"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/94.140.14.14, 94.140.15.15/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "5" ]]; then
	# Comss
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 83.220.169.155"\npush "dhcp-option DNS 212.109.195.93"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/83.220.169.155, 212.109.195.93/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "6" ]]; then
	# Xbox
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 176.99.11.77"\npush "dhcp-option DNS 80.78.247.254"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/176.99.11.77, 80.78.247.254/' /etc/wireguard/templates/vpn-client*.conf
elif [[ "$VPN_DNS" == "7" ]]; then
	# Malw
	sed -i '/push "dhcp-option DNS 1\.1\.1\.1"/,+1c push "dhcp-option DNS 46.226.165.53"\npush "dhcp-option DNS 64.188.98.242"' /etc/openvpn/server/vpn*.conf
	sed -i 's/1\.1\.1\.1, 1\.0\.0\.1/46.226.165.53, 64.188.98.242/' /etc/wireguard/templates/vpn-client*.conf
fi

#
# Используем альтернативные диапазоны ip-адресов
# 10.28.0.0/14 => 172.28.0.0/14
if [[ "$ALTERNATIVE_IP" == "y" ]]; then
	sed -i 's/10\.30\./172\.30\./g' /root/antizapret/proxy.py
	sed -i 's/10\.29\./172\.29\./g' /etc/knot-resolver/kresd.conf
	sed -i 's/10\./172\./g' /etc/openvpn/server/*.conf
	sed -i 's/10\./172\./g' /etc/wireguard/templates/*.conf
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 10\./s = 172\./g' {} +
else
	find /etc/wireguard -name '*.conf' -exec sed -i 's/s = 172\./s = 10\./g' {} +
fi

#
# Запрещаем несколько одновременных подключений к OpenVPN для одного клиента
if [[ "$OPENVPN_DUPLICATE" == "n" ]]; then
	sed -i '/^duplicate-cn/s/^/#/' /etc/openvpn/server/*.conf
fi

#
# Включим подробные логи в OpenVPN
if [[ "$OPENVPN_LOG" == "y" ]]; then
	sed -i '/^#\(verb\|log\)/s/^#//' /etc/openvpn/server/*.conf
fi

#
# Загружаем и создаем списки исключений IP-адресов
/root/antizapret/doall.sh ip

#
# Настраиваем сервера OpenVPN и WireGuard/AmneziaWG для первого запуска
# Пересоздаем для всех существующих пользователей файлы подключений
# Если пользователей нет, то создаем новых пользователей 'antizapret-client' для OpenVPN и WireGuard/AmneziaWG
/root/antizapret/client.sh 7

#
# Включим обновляемые службы
systemctl enable kresd@1
systemctl enable kresd@2
systemctl enable antizapret
systemctl enable antizapret-update
systemctl enable antizapret-update.timer
systemctl enable openvpn-server@antizapret-udp
systemctl enable openvpn-server@antizapret-tcp
systemctl enable openvpn-server@vpn-udp
systemctl enable openvpn-server@vpn-tcp
systemctl enable wg-quick@antizapret
systemctl enable wg-quick@vpn

ERRORS=""

if [[ "$OPENVPN_PATCH" != "0" ]]; then
	if ! /root/antizapret/patch-openvpn.sh "$OPENVPN_PATCH"; then
		ERRORS+="\n\e[1;31mAnti-censorship patch for OpenVPN has not installed!\e[0m Please run '/root/antizapret/patch-openvpn.sh' after rebooting\n"
	fi
fi

if [[ "$OPENVPN_DCO" == "y" ]]; then
	if ! /root/antizapret/openvpn-dco.sh y; then
		ERRORS+="\n\e[1;31mOpenVPN DCO has not turn on!\e[0m Please run '/root/antizapret/openvpn-dco.sh y' after rebooting\n"
	fi
fi

#
# Если есть ошибки, выводим их
if [[ -n "$ERRORS" ]]; then
	echo -e "$ERRORS"
fi

#
# Создадим файл подкачки размером 1 Гб если его нет
if [[ -z "$(swapon --show)" ]]; then
	set +e
	SWAPFILE="/swapfile"
	SWAPSIZE=1024
	dd if=/dev/zero of=$SWAPFILE bs=1M count=$SWAPSIZE
	chmod 600 "$SWAPFILE"
	mkswap "$SWAPFILE"
	swapon "$SWAPFILE"
	echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

echo
echo -e '\e[1;32mAntiZapret VPN + full VPN installed successfully!\e[0m'
echo 'Rebooting...'

#
# Перезагружаем
reboot
