.PHONY: setup deploy build install-minio up down clean ssl bucket-init logs status uninstall

SHELL := /bin/bash
ENV_FILE := ../.env
NGINX_CONF_DIR := /etc/nginx/sites-enabled
NGINX_SITES_AVAILABLE := /etc/nginx/sites-available
CERTBOT_WEBROOT := /var/www/certbot
CERTBOT_EMAIL := dev@selys-africa.com
MINIO_DATA_DIR := /var/lib/minio
MINIO_SERVICE := minio
MINIO_USER := minio
MINIO_GROUP := minio
MINIO_API_PORT := 9005
MINIO_CONSOLE_PORT := 9006

# ──────────────────────────────────────────────
# setup: prepare the environment
# ──────────────────────────────────────────────
setup:
	@echo "==> Setting up environment..."
	@if [ ! -f $(ENV_FILE) ]; then \
		cp ../.env.example $(ENV_FILE); \
		echo "    Created .env from .env.example — edit it with your credentials."; \
	else \
		echo "    .env already exists, skipping."; \
	fi
	@mkdir -p $(CERTBOT_WEBROOT)
	@chmod +x scripts/bucket-init.sh
	@echo "==> Setup complete."

# ──────────────────────────────────────────────
# install-mc: download and install MinIO Client (mc)
# ──────────────────────────────────────────────
install-mc:
	@echo "==> Installing MinIO Client (mc)..."
	@if command -v mc >/dev/null 2>&1 && file /usr/local/bin/mc | grep -q "ELF"; then \
		echo "    mc already installed: $$(mc --version | head -1)"; \
	else \
		echo "    Downloading mc binary..."; \
		sudo rm -f /usr/local/bin/mc; \
		cd /tmp && \
		wget -q https://dl.min.io/client/mc/release/linux-amd64/mc && \
		sudo mv mc /usr/local/bin/ && \
		sudo chmod +x /usr/local/bin/mc && \
		echo "    mc installed successfully."; \
	fi
	@mc --version

# ──────────────────────────────────────────────
# install-minio: download and install MinIO binary
# ──────────────────────────────────────────────
install-minio: install-mc
	@echo "==> Installing MinIO Community Edition..."
	@if command -v minio >/dev/null 2>&1 && file /usr/local/bin/minio | grep -q "ELF"; then \
		echo "    MinIO already installed: $$(minio --version)"; \
	else \
		echo "    Downloading MinIO binary..."; \
		sudo rm -f /usr/local/bin/minio /usr/bin/minio; \
		cd /tmp && \
 		# wget -q https://dl.min.io/server/minio/release/linux-amd64/minio && \

		curl --progress-bar -L dl.min.io/aistor/minio/release/linux-amd64/minio.deb -o minio.deb
		sudo dpkg -i minio.deb
		minio --version

		sudo mkdir /opt/minio
		sudo touch /opt/minio/minio.license
		sudo chown -R minio-user:minio-user /opt/minio
		
		sudo mv minio /usr/local/bin/ && \
		sudo chmod +x /usr/local/bin/minio && \
		echo "    MinIO installed successfully."; \
	fi
	@if ! command -v minio >/dev/null 2>&1; then \
		echo "==> ERROR: MinIO binary not found after installation."; \
		echo "    Try: which minio"; \
		echo "    Or:  find /usr -name minio"; \
		exit 1; \
	fi
	@echo "==> Creating minio user and directories..."
	@sudo useradd -rU $(MINIO_USER) 2>/dev/null || true
	@sudo mkdir -p $(MINIO_DATA_DIR)
	@sudo chown $(MINIO_USER):$(MINIO_GROUP) $(MINIO_DATA_DIR)
	@sudo chmod 700 $(MINIO_DATA_DIR)
	@echo "==> MinIO version: $$(minio --version)"

# ──────────────────────────────────────────────
# build: no-op for compatibility (minio already installed)
# ──────────────────────────────────────────────
build:
	@echo "==> MinIO binary ready."

# ──────────────────────────────────────────────
# configure-env: generate /etc/default/minio from .env
# ──────────────────────────────────────────────
configure-env:
	@echo "==> Creating /etc/default/minio from .env..."
	@if [ ! -f $(ENV_FILE) ]; then \
		echo "ERROR: $(ENV_FILE) not found. Run 'make setup' first."; \
		exit 1; \
	fi
	@bash -c ' \
		source $(ENV_FILE); \
		{ \
			echo "# MinIO Environment Variables"; \
			echo "# Generated from .env"; \
			echo ""; \
			echo "MINIO_ROOT_USER=\"$$MINIO_ROOT_USER\""; \
			echo "MINIO_ROOT_PASSWORD=\"$$MINIO_ROOT_PASSWORD\""; \
			echo "MINIO_SERVER_URL=\"$$MINIO_SERVER_URL\""; \
			echo "MINIO_BROWSER_REDIRECT_URL=\"$$MINIO_BROWSER_REDIRECT_URL\""; \
		} | sudo tee /etc/default/minio > /dev/null \
	'
	@sudo chmod 600 /etc/default/minio
	@echo "==> /etc/default/minio created successfully."

# ──────────────────────────────────────────────
# up: start MinIO service
# ──────────────────────────────────────────────
up: configure-env
	@echo "==> Updating MinIO service unit..."
	@sudo cp minio.service /etc/systemd/system/minio.service
	@sudo systemctl daemon-reload
	@echo "==> Starting MinIO service..."
	@sudo systemctl enable $(MINIO_SERVICE)
	@sudo systemctl restart $(MINIO_SERVICE)
	@echo "==> MinIO service started."
	@sleep 2
	@sudo systemctl status $(MINIO_SERVICE) --no-pager

# ──────────────────────────────────────────────
# down: stop MinIO service
# ──────────────────────────────────────────────
down:
	@echo "==> Stopping MinIO service..."
	@sudo systemctl stop $(MINIO_SERVICE) 2>/dev/null || true
	@echo "==> MinIO service stopped."

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
# deploy: full deployment (nginx + ssl + minio + buckets)
# ──────────────────────────────────────────────
deploy: setup install-minio build
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
	@echo "==> Installing Nginx configuration..."
	@sudo cp nginx/minio.v2.selys.app.conf $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf
	@sudo ln -sf $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf $(NGINX_CONF_DIR)/minio.v2.selys.app.conf
	@sudo nginx -t
	@sudo systemctl reload nginx
	@$(MAKE) up
	@sleep 5
	@$(MAKE) bucket-init
	@echo "==> Deployment complete!"
	@echo "    S3 API:  https://s3.v2.selys.app"
	@echo "    Console: https://minio.v2.selys.app"


# ──────────────────────────────────────────────
# bucket-init: initialize buckets
# ──────────────────────────────────────────────
bucket-init: install-mc
	@echo "==> Initializing buckets..."
	@bash scripts/bucket-init.sh

# ──────────────────────────────────────────────
# clean: remove MinIO service and data
# ──────────────────────────────────────────────
clean: down
	@echo "==> Cleaning up..."
	@sudo rm -f /etc/systemd/system/minio.service
	@sudo systemctl daemon-reload
	@sudo rm -rf $(MINIO_DATA_DIR)
	@echo "==> MinIO service and data removed."

# ──────────────────────────────────────────────
# logs: show MinIO service logs
# ──────────────────────────────────────────────
logs:
	@sudo journalctl -u $(MINIO_SERVICE) -f --no-pager

# ──────────────────────────────────────────────
# status: show MinIO service status
# ──────────────────────────────────────────────
status:
	@sudo systemctl status $(MINIO_SERVICE) --no-pager

# ──────────────────────────────────────────────
# uninstall: completely remove MinIO from the system
# ──────────────────────────────────────────────
uninstall: down
	@echo "==> Uninstalling MinIO..."
	@sudo systemctl disable $(MINIO_SERVICE) 2>/dev/null || true
	@sudo rm -f /etc/systemd/system/minio.service
	@sudo systemctl daemon-reload
	@sudo rm -f /etc/default/minio
	@echo "==> Removing MinIO binaries..."
	@sudo rm -f /usr/local/bin/minio /usr/bin/minio
	@sudo dpkg -r minio 2>/dev/null || true
	@echo "==> Removing mc binary..."
	@sudo rm -f /usr/local/bin/mc
	@echo "==> Removing MinIO user and group..."
	@sudo userdel $(MINIO_USER) 2>/dev/null || true
	@sudo groupdel $(MINIO_GROUP) 2>/dev/null || true
	@sudo userdel minio-user 2>/dev/null || true
	@echo "==> Removing Nginx configuration..."
	@sudo rm -f $(NGINX_CONF_DIR)/minio.v2.selys.app.conf
	@sudo rm -f $(NGINX_CONF_DIR)/s3.v2.selys.app.conf
	@sudo rm -f $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf
	@sudo rm -f $(NGINX_SITES_AVAILABLE)/s3.v2.selys.app.conf
	@sudo nginx -t 2>/dev/null && sudo systemctl reload nginx || true
	@echo "==> Removing data and license..."
	@sudo rm -rf $(MINIO_DATA_DIR)
	@sudo rm -rf /opt/minio
	@echo "==> MinIO completely uninstalled."
	@echo "    Note: SSL certificates kept in /etc/letsencrypt/"
	@echo "    To remove them: sudo certbot delete --cert-name minio.v2.selys.app"
