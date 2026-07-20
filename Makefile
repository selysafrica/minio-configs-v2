.PHONY: setup deploy build up down clean ssl bucket-init logs status

SHELL := /bin/bash
ENV_FILE := .env
NGINX_CONF_DIR := /etc/nginx/sites-enabled
NGINX_SITES_AVAILABLE := /etc/nginx/sites-available
CERTBOT_WEBROOT := /var/www/certbot
CERTBOT_EMAIL := dev@selys-africa.com
MINIO_CONTAINER := minio
MINIO_DATA_DIR := ~/minio/data
MINIO_HOST_API_PORT := 9000
MINIO_HOST_CONSOLE_PORT := 9001
MINIO_CONTAINER_API_PORT := 9005
MINIO_CONTAINER_CONSOLE_PORT := 9006
MINIO_IMAGE := minio/minio:latest

# ──────────────────────────────────────────────
# setup: prepare the environment
# ──────────────────────────────────────────────
setup:
	@echo "==> Setting up environment..."
	@if [ ! -f $(ENV_FILE) ]; then \
		cp .env.example $(ENV_FILE); \
		echo "    Created .env from .env.example — edit it with your credentials."; \
	else \
		echo "    .env already exists, skipping."; \
	fi
	@mkdir -p data
	@mkdir -p $(CERTBOT_WEBROOT)
	@chmod +x scripts/bucket-init.sh
	@echo "==> Setup complete. Edit .env before deploying."

# ──────────────────────────────────────────────
# ssl: obtain SSL certificates with certbot
# ──────────────────────────────────────────────
ssl:
	@echo "==> Obtaining SSL certificates..."
	@source $(ENV_FILE) && \
	sudo certbot certonly --webroot -w $(CERTBOT_WEBROOT) \
		-d minio.v2.selys.app -d s3.v2.selys.app \
		--non-interactive --agree-tos -m $(CERTBOT_EMAIL)
	@echo "==> SSL certificates obtained."

# ──────────────────────────────────────────────
# build: pull docker image
# ──────────────────────────────────────────────
build:
	@echo "==> Pulling MinIO image..."
	docker pull $(MINIO_IMAGE)

# ──────────────────────────────────────────────
# up: start MinIO container
# ──────────────────────────────────────────────
up:
	@echo "==> Starting MinIO..."
	@source $(ENV_FILE) && \
	docker run -d \
		-p $(MINIO_HOST_API_PORT):$(MINIO_CONTAINER_API_PORT) \
		-p $(MINIO_HOST_CONSOLE_PORT):$(MINIO_CONTAINER_CONSOLE_PORT) \
		--name $(MINIO_CONTAINER) \
		-v $(MINIO_DATA_DIR):/data \
		-e "MINIO_ROOT_USER=$$MINIO_ROOT_USER" \
		-e "MINIO_ROOT_PASSWORD=$$MINIO_ROOT_PASSWORD" \
		-e "MINIO_SERVER_URL=$$MINIO_SERVER_URL" \
		-e "MINIO_BROWSER_REDIRECT_URL=$$MINIO_BROWSER_REDIRECT_URL" \
		$(MINIO_IMAGE) server --address :$(MINIO_CONTAINER_API_PORT) --console-address :$(MINIO_CONTAINER_CONSOLE_PORT) /data
	@echo "==> MinIO started."

# ──────────────────────────────────────────────
# down: stop and remove MinIO container
# ──────────────────────────────────────────────
down:
	@docker stop $(MINIO_CONTAINER) 2>/dev/null || true
	@docker rm $(MINIO_CONTAINER) 2>/dev/null || true
	@echo "==> MinIO stopped and removed."

# ──────────────────────────────────────────────
# deploy: full deployment (nginx + ssl + build + up + buckets)
# ──────────────────────────────────────────────
deploy: setup build
	@echo "==> Checking if certificates exist..."
	@if [ ! -f /etc/letsencrypt/live/minio.v2.selys.app/fullchain.pem ]; then \
		echo "    Certificates missing, installing temporary HTTP-only config..."; \
		echo 'server { listen 80; server_name s3.v2.selys.app minio.v2.selys.app; location /.well-known/acme-challenge/ { root /var/www/certbot; } location / { return 301 https://$$host$$request_uri; } }' | sudo tee $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf > /dev/null; \
		sudo ln -sf $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf $(NGINX_CONF_DIR)/minio.v2.selys.app.conf; \
		sudo rm -f $(NGINX_CONF_DIR)/s3.v2.selys.app.conf $(NGINX_SITES_AVAILABLE)/s3.v2.selys.app.conf; \
		sudo nginx -t && sudo systemctl reload nginx; \
		$(MAKE) ssl; \
	fi
	@if [ ! -f /etc/letsencrypt/live/minio.v2.selys.app/fullchain.pem ]; then \
		echo "==> ERROR: SSL certificates still missing after certbot run."; \
		echo "    Ensure DNS A records for s3.v2.selys.app and minio.v2.selys.app point to this server."; \
		echo "    Then re-run: make ssl && make deploy"; \
		exit 1; \
	fi
	@echo "==> Installing full Nginx configuration..."
	sudo cp nginx/minio.v2.selys.app.conf $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf
	sudo ln -sf $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf $(NGINX_CONF_DIR)/minio.v2.selys.app.conf
	sudo nginx -t
	sudo systemctl reload nginx
	@$(MAKE) up
	@sleep 5
	@$(MAKE) bucket-init
	@echo "==> Deployment complete!"
	@echo "    S3 API:  https://s3.v2.selys.app"
	@echo "    Console: https://minio.v2.selys.app"

# ──────────────────────────────────────────────
# bucket-init: initialize buckets
# ──────────────────────────────────────────────
bucket-init:
	@echo "==> Initializing buckets..."
	@bash scripts/bucket-init.sh

# ──────────────────────────────────────────────
# clean: remove container and data
# ──────────────────────────────────────────────
clean: down
	@echo "==> Cleaning up..."
	@rm -rf $(MINIO_DATA_DIR)
	@echo "==> MinIO data removed."

# ──────────────────────────────────────────────
# logs: show MinIO container logs
# ──────────────────────────────────────────────
logs:
	docker logs -f $(MINIO_CONTAINER)

# ──────────────────────────────────────────────
# status: show MinIO container status
# ──────────────────────────────────────────────
status:
	@docker ps -a --filter "name=$(MINIO_CONTAINER)" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
