.PHONY: setup deploy build up down clean ssl bucket-init logs status uninstall install-mc

SHELL := /bin/bash
ENV_FILE := ../.env
NAMESPACE := minio
KUBECTL := kubectl
NGINX_CONF_DIR := /etc/nginx/sites-enabled
NGINX_SITES_AVAILABLE := /etc/nginx/sites-available
CERTBOT_WEBROOT := /var/www/certbot
CERTBOT_EMAIL := dev@selys-africa.com

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
# ssl: obtain SSL certificates with certbot
# ──────────────────────────────────────────────
ssl:
	@echo "==> Obtaining SSL certificates..."
	sudo certbot certonly --webroot -w $(CERTBOT_WEBROOT) \
		-d minio.v2.selys.app -d s3.v2.selys.app \
		--non-interactive --agree-tos -m $(CERTBOT_EMAIL)
	@echo "==> SSL certificates obtained."

# ──────────────────────────────────────────────
# build: pull minio image (optional, k8s pulls on deploy)
# ──────────────────────────────────────────────
build:
	@echo "==> Kubernetes pulls images automatically on deploy."
	@echo "    To pre-pull: docker pull minio/minio:latest"

# ──────────────────────────────────────────────
# up: deploy MinIO to the cluster
# ──────────────────────────────────────────────
up:
	@echo "==> Deploying MinIO..."
	$(KUBECTL) apply -f namespace.yaml
	$(KUBECTL) apply -f secret.yaml
	$(KUBECTL) apply -f pvc.yaml
	$(KUBECTL) apply -f deployment.yaml
	$(KUBECTL) apply -f service.yaml
	@echo "==> Waiting for MinIO pod to be ready..."
	$(KUBECTL) -n $(NAMESPACE) wait --for=condition=ready pod -l app=minio --timeout=120s
	@echo "==> MinIO deployed on NodePort 30900 (API) and 30901 (Console)."

# ──────────────────────────────────────────────
# down: scale MinIO to 0 (keep data)
# ──────────────────────────────────────────────
down:
	@echo "==> Scaling MinIO to 0..."
	$(KUBECTL) -n $(NAMESPACE) scale deployment minio --replicas=0 2>/dev/null || true
	@echo "==> MinIO scaled down."

# ──────────────────────────────────────────────
# deploy: full deployment (up + nginx + ssl + buckets)
# ──────────────────────────────────────────────
deploy: setup up
	@echo "==> Checking if certificates exist..."
	@if [ ! -f /etc/letsencrypt/live/minio.v2.selys.app/fullchain.pem ]; then \
		echo "    Certificates missing, installing temporary HTTP-only config..."; \
		echo 'server { listen 80; server_name s3.v2.selys.app minio.v2.selys.app; location /.well-known/acme-challenge/ { root /var/www/certbot; } location / { return 301 https://$$host$$request_uri; } }' | sudo tee $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf > /dev/null; \
		sudo ln -sf $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf $(NGINX_CONF_DIR)/minio.v2.selys.app.conf; \
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
	sudo cp nginx/minio.v2.selys.app.conf $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf
	sudo ln -sf $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf $(NGINX_CONF_DIR)/minio.v2.selys.app.conf
	sudo nginx -t
	sudo systemctl reload nginx
	@sleep 5
	@$(MAKE) bucket-init
	@echo "==> Deployment complete!"
	@echo "    S3 API:  https://s3.v2.selys.app"
	@echo "    Console: https://minio.v2.selys.app"

# ──────────────────────────────────────────────
# bucket-init: initialize buckets via mc on host
# ──────────────────────────────────────────────
bucket-init: install-mc
	@echo "==> Initializing buckets..."
	@bash scripts/bucket-init.sh

# ──────────────────────────────────────────────
# clean: remove all MinIO resources (keeps PVC data)
# ──────────────────────────────────────────────
clean:
	@echo "==> Removing MinIO resources..."
	$(KUBECTL) delete -f service.yaml 2>/dev/null || true
	$(KUBECTL) delete -f deployment.yaml 2>/dev/null || true
	$(KUBECTL) delete -f secret.yaml 2>/dev/null || true
	@echo "==> MinIO resources removed. PVC kept."
	@echo "    To also delete data: $(KUBECTL) delete -f pvc.yaml"

# ──────────────────────────────────────────────
# uninstall: remove everything including namespace and data
# ──────────────────────────────────────────────
uninstall:
	@echo "==> Uninstalling MinIO completely..."
	$(KUBECTL) delete namespace $(NAMESPACE) 2>/dev/null || true
	@echo "==> Removing Nginx configuration..."
	sudo rm -f $(NGINX_CONF_DIR)/minio.v2.selys.app.conf
	sudo rm -f $(NGINX_SITES_AVAILABLE)/minio.v2.selys.app.conf
	sudo nginx -t 2>/dev/null && sudo systemctl reload nginx || true
	@echo "==> MinIO uninstalled."
	@echo "    SSL certificates kept in /etc/letsencrypt/"
	@echo "    To remove: sudo certbot delete --cert-name minio.v2.selys.app"

# ──────────────────────────────────────────────
# remove-k8s-ingress: remove nginx-ingress controller from cluster
# ──────────────────────────────────────────────
remove-k8s-ingress:
	@echo "==> Removing nginx-ingress controller from K8s (restoring system nginx)..."
	$(KUBECTL) delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/cloud/deploy.yaml 2>/dev/null || true
	@echo "==> nginx-ingress controller removed."
	@echo "==> Restarting system nginx..."
	sudo systemctl restart nginx
	@echo "==> System nginx restored. All *.selys.app sites should work again."

# ──────────────────────────────────────────────
# logs: show MinIO pod logs
# ──────────────────────────────────────────────
logs:
	$(KUBECTL) -n $(NAMESPACE) logs -f deployment/minio

# ──────────────────────────────────────────────
# status: show MinIO resources status
# ──────────────────────────────────────────────
status:
	@echo "=== Pods ==="
	@$(KUBECTL) -n $(NAMESPACE) get pods -o wide
	@echo ""
	@echo "=== Services ==="
	@$(KUBECTL) -n $(NAMESPACE) get svc
	@echo ""
	@echo "=== PVC ==="
	@$(KUBECTL) -n $(NAMESPACE) get pvc
