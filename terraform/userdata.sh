#!/bin/bash
# userdata.sh – runs on EC2 first boot as root
# Installs Docker, pulls image from ECR, starts all containers

set -e
exec > /var/log/userdata.log 2>&1

echo "=== Starting bootstrap at $(date) ==="

###############################################################
# 1. System updates & Docker install
###############################################################
dnf update -y
dnf install -y docker git aws-cli

systemctl enable docker
systemctl start docker

# Install Docker Compose v2 plugin
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Allow ec2-user to run Docker without sudo
usermod -aG docker ec2-user

echo "=== Docker installed ==="

###############################################################
# 2. Login to ECR and pull the Node.js image
###############################################################
AWS_ACCOUNT_ID="${account_id}"
AWS_REGION="${aws_region}"
ECR_REPO="${ecr_repo_name}"
ECR_URL="$${AWS_ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region "$${AWS_REGION}" | \
    docker login --username AWS --password-stdin "$${ECR_URL}"

echo "=== ECR login successful ==="

###############################################################
# 3. Create app directory and write docker-compose.yml
###############################################################
APP_DIR="/opt/nodejs-app"
mkdir -p "$${APP_DIR}"
cd "$${APP_DIR}"

cat > docker-compose.yml <<'COMPOSE'
version: '3.8'

services:
  app:
    image: ${account_id}.dkr.ecr.${aws_region}.amazonaws.com/${ecr_repo_name}:latest
    container_name: nodejs-app
    ports:
      - "9000:9000"
    environment:
      DB_HOST: mysql
      DB_USER: root
      DB_PASSWORD: ${db_password}
      DB_NAME: loginDB
    depends_on:
      mysql:
        condition: service_healthy
    restart: always

  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${db_password}
      MYSQL_DATABASE: loginDB
    ports:
      - "3306:3306"
    volumes:
      - mysql_data:/var/lib/mysql
      - /opt/nodejs-app/init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${db_password}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: always

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    ports:
      - "9090:9090"
    volumes:
      - /opt/nodejs-app/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=7d'
    restart: always

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin123
    volumes:
      - grafana_data:/var/lib/grafana
    depends_on:
      - prometheus
    restart: always

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.ignored-mount-points=^/(sys|proc|dev|host|etc)($$|/)'
    restart: always

volumes:
  mysql_data:
  prometheus_data:
  grafana_data:
COMPOSE

###############################################################
# 4. Write Prometheus config
###############################################################
cat > prometheus.yml <<'PROM'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'nodejs-app'
    static_configs:
      - targets: ['app:9000']
    metrics_path: '/metrics'

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
PROM

###############################################################
# 5. Write init.sql
###############################################################
cat > init.sql <<'SQL'
CREATE DATABASE IF NOT EXISTS loginDB;
USE loginDB;

CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL
);
SQL

###############################################################
# 6. Start all containers
###############################################################
docker compose pull
docker compose up -d

echo "=== All containers started at $(date) ==="

###############################################################
# 7. Create a systemd service to auto-start on reboot
###############################################################
cat > /etc/systemd/system/nodejs-app.service <<'SERVICE'
[Unit]
Description=Node.js App Docker Compose
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/nodejs-app
ExecStart=/usr/local/lib/docker/cli-plugins/docker-compose up -d
ExecStop=/usr/local/lib/docker/cli-plugins/docker-compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable nodejs-app.service

echo "=== Bootstrap complete at $(date) ==="
