.PHONY: setup deploy build up down clean ssl bucket-init logs status

SHELL := /bin/bash
ENV_FILE := .env
NGINX_CONF_DIR := /etc/nginx/sites-enabled
CERTBOT_WEBROOT := /var/www/certbot

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
		-d s3.v2.selys.app \
		--non-interactive --agree-tos -m $${CERTBOT_EMAIL} || true
	@source $(ENV_FILE) && \
	sudo certbot certonly --webroot -w $(CERTBOT_WEBROOT) \
		-d minio.v2.selys.app \
		--non-interactive --agree-tos -m $${CERTBOT_EMAIL} || true
	@echo "==> SSL certificates obtained."

# ──────────────────────────────────────────────
# build: build/pull docker images
# ──────────────────────────────────────────────
build:
	@echo "==> Pulling MinIO image..."
	docker compose pull

# ──────────────────────────────────────────────
# up: start containers
# ──────────────────────────────────────────────
up:
	@echo "==> Starting MinIO..."
	docker compose up -d
	@echo "==> MinIO started."

# ──────────────────────────────────────────────
# down: stop containers
# ──────────────────────────────────────────────
down:
	docker compose down

# ──────────────────────────────────────────────
# deploy: full deployment (nginx + ssl + build + up + buckets)
# ──────────────────────────────────────────────
deploy: setup build
	@echo "==> Installing Nginx configurations..."
	sudo cp nginx/s3.v2.selys.app.conf $(NGINX_CONF_DIR)/s3.v2.selys.app.conf
	sudo cp nginx/minio.v2.selys.app.conf $(NGINX_CONF_DIR)/minio.v2.selys.app.conf
	sudo nginx -t
	sudo systemctl reload nginx
	@$(MAKE) ssl
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
# clean: remove containers, volumes, and data
# ──────────────────────────────────────────────
clean:
	@echo "==> Cleaning up..."
	docker compose down -v
	@echo "==> WARNING: To also remove data, run: rm -rf data"
	@echo "==> Clean complete."

# ──────────────────────────────────────────────
# logs: show container logs
# ──────────────────────────────────────────────
logs:
	docker compose logs -f minio

# ──────────────────────────────────────────────
# status: show container status
# ──────────────────────────────────────────────
status:
	docker compose ps
