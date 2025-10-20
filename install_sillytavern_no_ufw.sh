#!/bin/bash
#
# Скрипт для автоматической установки SillyTavern с Caddy на Ubuntu 24.04.
# Подходит для серверов, где уже ЕСТЬ другой фаервол (например, от скрипта VPN).
# UFW НЕ АКТИВИРУЕТСЯ И НЕ НАСТРАИВАЕТСЯ ЭТИМ СКРИПТОМ.
#
# Использование: wget -qO- https://raw.githubusercontent.com/jabkaVochkah/something/main/install_sillytavern_no_ufw.sh | sudo bash -s your.subdomain.help
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
if [ -n "$1" ]; then # Проверяем, был ли передан аргумент
    CADDY_DOMAIN="$1"
    echo "Используем субдомен из аргументов: $CADDY_DOMAIN"
else # Если аргумент не передан, запрашиваем интерактивно
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
fi

# Добавляем проверку валидности субдомена, даже если он был передан как аргумент
if [[ -z "$CADDY_DOMAIN" || ! "$CADDY_DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "Ошибка: Некорректный или отсутствующий субдомен. Пожалуйста, укажите валидный субдомен."
    exit 1
fi

echo -e "\n--- Проверка и обновление системы ---"
apt update
apt upgrade -y
apt install -y curl git nano

echo -e "\n--- Установка NVM и Node.js ---"

# Определяем NVM_DIR, если он еще не определен (что вероятно для root в скрипте)
export NVM_DIR="$HOME/.nvm"

# Загружаем NVM, если он установлен
if [ -s "$NVM_DIR/nvm.sh" ]; then
    echo "NVM уже установлен, загружаем..."
    \. "$NVM_DIR/nvm.sh" # This loads nvm
    # Проверяем, что nvm теперь доступен
    if ! command -v nvm &> /dev/null; then
        echo "Ошибка: NVM не загрузился корректно, перезапускаем оболочку."
        # Если NVM все равно не доступен, это серьезная проблема,
        # тогда нужно перепробовать установку nvm
        # Для простоты скрипта, если nvm не загрузился, мы будем считать его не установленным.
    fi
fi

# Устанавливаем NVM, если он не был установлен или не загрузился корректно
if ! command -v nvm &> /dev/null; then
    echo "NVM не найден или не загрузился корректно, устанавливаем..."
    wget -qO- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # NVM устанавливается, но не загружается автоматически в текущую *неинтерактивную* оболочку
    # Поэтому загружаем его явно
    export NVM_DIR="$HOME/.nvm" # Повторно убеждаемся, что NVM_DIR определен
    \. "$NVM_DIR/nvm.sh"  # This loads nvm scripts required for the current session
    # Проверяем, что nvm теперь доступен после установки
    if ! command -v nvm &> /dev/null; then
        echo "Критическая ошибка: NVM так и не стал доступен после установки. Проверьте установку NVM вручную."
        exit 1
    fi
else
    echo "NVM уже установлен."
fi

# Теперь nvm точно должен быть доступен

# Временно отключаем 'nounset' (set -u) для команд nvm, которые могут быть чувствительны
set +u
nvm install --lts # Установка последней LTS-версии Node.js
nvm use --lts     # Использование последней LTS-версии
nvm alias default lts/* # Установка LTS-версии по умолчанию
set -u # Включаем 'nounset' обратно для остальной части скрипта

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
# Удаляем любой существующий config.yaml, если он есть
rm -f ~/SillyTavern/config.yaml

# Скачиваем config.yaml с вашего GitHub
wget -qO ~/SillyTavern/config.yaml "$USER_CONFIG_YAML_URL"

# --- Проверка успешности загрузки config.yaml ---
if [ $? -ne 0 ]; then
    echo "Error: Не удалось скачать config.yaml с $USER_CONFIG_YAML_URL. Проверьте URL и доступ к файлу." >&2
    exit 1
fi
# --- Конец проверки ---

echo "Ваш преднастроенный config.yaml загружен."

echo -e "\n--- Установка и запуск SillyTavern с PM2 ---"
sudo -E env PATH="$PATH" npm install -g pm2

# Удаляем любой существующий PM2-процесс SillyTavern, чтобы обеспечить чистый старт с новым config.yaml
pm2 delete sillytavern || true # '|| true' предотвращает выход скрипта, если процесс не найден

# Запускаем SillyTavern с PM2
pm2 start ~/SillyTavern/server.js --name "sillytavern"
pm2 save
pm2 startup systemd # PM2 сам выполнит команду для systemd

# --- Добавляем небольшую задержку, чтобы Node.js и PM2 успели полностью запуститься ---
echo "Ожидаем 10 секунд для полной инициализации SillyTavern. Пожалуйста, подождите..."
sleep 10


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
