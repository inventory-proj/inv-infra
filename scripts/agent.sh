#!/bin/bash
# ==========================================
# Server Inventory Agent Installer (Promtail)
# ==========================================
set -e

# 1. Проверка прав root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Пожалуйста, запустите скрипт от имени root (sudo)"
  exit 1
fi

# 2. Парсинг аргументов (ищем --token)
TOKEN=""
for arg in "$@"; do
  case $arg in
    --token=*)
      TOKEN="${arg#*=}"
      shift
      ;;
  esac
done

if [ -z "$TOKEN" ]; then
  echo "❌ Ошибка: Не указан токен. Используйте: sudo bash agent.sh --token=ВАШ_ТОКЕН"
  exit 1
fi

echo "🚀 Установка Server Inventory Agent для токена: $TOKEN..."

# 3. Скачивание Promtail (Логи)
PROMTAIL_VERSION="2.9.3"
echo "⬇️  Скачивание Promtail v$PROMTAIL_VERSION..."
curl -sLO "https://github.com/grafana/loki/releases/download/v${PROMTAIL_VERSION}/promtail-linux-amd64.zip"
unzip -q promtail-linux-amd64.zip
mv promtail-linux-amd64 /usr/local/bin/promtail
chmod +x /usr/local/bin/promtail
rm promtail-linux-amd64.zip

# 4. Создание пользователя для безопасности
if ! id -u promtail > /dev/null 2>&1; then
    useradd --system --no-create-home --shell /bin/false promtail
fi
# Даем права на чтение системных логов
usermod -a -G adm promtail

# 5. Создание конфигурации Promtail (с подстановкой ТОКЕНА)
mkdir -p /etc/promtail
cat <<EOF > /etc/promtail/config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  # ЗДЕСЬ БУДЕТ АДРЕС ТВОЕГО LOKI СЕРВЕРА
  - url: https://logs.inv.e-laba52.ru/loki/api/v1/push
    tenant_id: "${TOKEN}" # Подстановка токена для авторизации

scrape_configs:
  - job_name: system
    static_configs:
    - targets:
        - localhost
      labels:
        job: varlogs
        __path__: /var/log/*log
EOF

chown -R promtail:promtail /etc/promtail

# 6. Создание службы systemd
cat <<EOF > /etc/systemd/system/promtail.service
[Unit]
Description=Promtail agent
After=network.target

[Service]
User=promtail
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail/config.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 7. Запуск службы
systemctl daemon-reload
systemctl enable promtail
systemctl start promtail

echo "✅ Агент успешно установлен и запущен!"
echo "📊 Логи начнут поступать в панель управления через минуту."
