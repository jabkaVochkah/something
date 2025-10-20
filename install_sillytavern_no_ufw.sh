#!/bin/bash
#
# Скрипт для автоматической установки SillyTavern с Caddy на Ubuntu 24.04.
# Подходит для серверов, где уже ЕСТЬ другой фаервол (например, от скрипта VPN).
# UFW НЕ АКТИВИРУЕТСЯ И НЕ НАСТРАИВАЕТСЯ ЭТИМ СКРИПТОМ.
#
# Использование: sudo bash <(wget -qO- https://raw.githubusercontent.com/jabkaVochkah/something/main/install_sillytavern_no_ufw.sh)
#
set -euo pipefail # Выход при ошибке, undef var, failure in pipe
export LC_ALL=C

# --- НАСТРАИВАЕМЫЕ ПЕРЕМЕННЫЕ ---
# URL вашего преднастроенного config.yaml для SillyTavern
USER_CONFIG_YAML_URL="https://raw.githubusercontent.com/jabkaVochkah/something/refs/heads/main/config.yaml"
# ---------------------------------

echo -e "\n--- Важно: Скрипт должен быть запущен с правами root. ---"
if [[ "$EUID" -ne 0 ]]; then
	echo "Error: Запустите скрипт от имени root. Пример: sudo bash <(wget -qO- URL_СКРИПТА)"
	exit 1
fi

CADDY_DOMAIN=""
while true; do
  read -rp "Введите субдомен (например, client1.sillytavern.help) для SillyTavern (ОБЯЗАТЕЛЬНО должен быть настроен в Cloudflare): " CADDY_DOMAIN
  if [[ -z "$CADDY_DOMAIN" ]]; then
    echo "Субдомен не может быть пустым. Пожалуйста, введите его."
  elif [[ ! "$CADDY_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "Некорректный формат субдомена. Введите полный домен, например, example.com"
  else
    break
  fi
done

echo -e "\n--- Проверка и обновление системы ---"
apt update
apt upgrade -y
apt install -y curl git nano

echo -e "\n--- Установка NVM и Node.js ---"
# Проверка, установлен ли NVM. Если нет, устанавливаем.
if [ -z "$NVM_DIR" ]; then
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        . "$NVM_DIR/nvm.sh"
    fi
fi
if ! command -v nvm &> /dev/null; then
    echo "NVM не найден, устанавливаем..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # Загружаем NVM в текущую сессию
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
else
    echo "NVM уже установлен."
fi
nvm install --lts # Установка последней LTS-версии Node.js
nvm use --lts     # Использование последней LTS-версии
nvm alias default lts/* # Установка LTS-версии по умолчанию

echo -e "\n--- Установка Caddy ---"
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install caddy -y

echo -e "\n--- Фаервол будет управляться внешним скриптом (например, VPN) ---"
echo "UFW НЕ АКТИВИРУЕТСЯ И НЕ НАСТРАИВАЕТСЯ ЭТИМ СКРИПТОМ."
echo "Убедитесь, что порты 22, 80 и 443 открыты вашей существующей конфигурацией фаервола (например, скриптом VPN)."

echo -e "\n--- Клонирование и установка SillyTavern ---"
cd ~
git clone https://github.com/SillyTavern/SillyTavern.git
cd ~/SillyTavern
echo "Установка NPM зависимостей для SillyTavern. Это может занять некоторое время..."
npm install

echo -e "\n--- Загрузка вашего преднастроенного config.yaml ---"
rm -f ~/SillyTavern/config.yaml # Удаляем любой существующий config.yaml
wget -qO ~/SillyTavern/config.yaml "$USER_CONFIG_YAML_URL"
echo "Ваш преднастроенный config.yaml загружен."

echo -e "\n--- Установка и запуск SillyTavern с PM2 ---"
sudo -E env PATH="$PATH" npm install -g pm2
pm2 start ~/SillyTavern/server.js --name "sillytavern"
pm2 save
pm2 startup systemd # PM2 сам выполнит команду для systemd

echo -e "\n--- Настройка Caddyfile ---"
sudo sh -c "echo \"
$CADDY_DOMAIN {
  reverse_proxy 127.0.0.1:8000
}
\" > /etc/caddy/Caddyfile"

echo -e "\n--- Перезапуск Caddy ---"
sudo systemctl restart caddy
sudo systemctl enable caddy

echo -e "\n--- Установка завершена! ---"
echo "SillyTavern должна быть доступна по адресу: https://$CADDY_DOMAIN"
echo "Первый вход потребует создания аккаунта."
echo "Проверьте логи Caddy: sudo journalctl -u caddy -f"
echo "Проверьте логи SillyTavern: pm2 logs sillytavern"
echo "Удачи!"
