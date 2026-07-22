.PHONY: setup deploy build up down clean ssl bucket-init logs status uninstall

SHELL := /bin/bash
NAMESPACE := minio
KUBECTL := kubectl
CONTEXT :=

ifdef CONTEXT
KUBECTL := kubectl --context $(CONTEXT)
endif

# ──────────────────────────────────────────────
# setup: install prerequisites (nginx-ingress + cert-manager)
# ──────────────────────────────────────────────
setup:
	@echo "==> Installing NGINX Ingress Controller..."
	$(KUBECTL) apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/cloud/deploy.yaml
	@echo "==> Waiting for ingress-nginx controller pod..."
	@sleep 10
	$(KUBECTL) wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=180s
	@echo "==> Waiting for ingress-nginx admission webhook..."
	@until $(KUBECTL) get endpoints ingress-nginx-controller-admission -n ingress-nginx -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | grep -q "ip"; do \
		echo "    Waiting for admission webhook endpoint..."; \
		sleep 5; \
	done
	@echo "==> NGINX Ingress Controller ready."
	@echo "==> Installing cert-manager..."
	$(KUBECTL) apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml
	@echo "==> Waiting for cert-manager pods..."
	@sleep 10
	$(KUBECTL) wait --namespace cert-manager \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=webhook \
		--timeout=180s
	$(KUBECTL) wait --namespace cert-manager \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=180s
	@echo "==> Setup complete."

# ──────────────────────────────────────────────
# ssl: apply cert-manager ClusterIssuer
# ──────────────────────────────────────────────
ssl:
	@echo "==> Applying Let's Encrypt ClusterIssuer..."
	$(KUBECTL) apply -f cert-manager-issuer.yaml
	@echo "==> ClusterIssuer created. Certificates will be issued automatically via Ingress."

# ──────────────────────────────────────────────
# build: pull minio image (optional, k8s pulls on deploy)
# ──────────────────────────────────────────────
build:
	@echo "==> Kubernetes pulls images automatically on deploy."
	@echo "    To pre-pull: docker pull minio/minio:latest && docker pull minio/mc:latest"

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
	$(KUBECTL) apply -f ingress.yaml
	@echo "==> Waiting for MinIO pod to be ready..."
	$(KUBECTL) -n $(NAMESPACE) wait --for=condition=ready pod -l app=minio --timeout=120s
	@echo "==> MinIO deployed."

# ──────────────────────────────────────────────
# down: scale MinIO to 0 (keep data)
# ──────────────────────────────────────────────
down:
	@echo "==> Scaling MinIO to 0..."
	$(KUBECTL) -n $(NAMESPACE) scale deployment minio --replicas=0 2>/dev/null || true
	@echo "==> MinIO scaled down."

# ──────────────────────────────────────────────
# deploy: full deployment (setup + ssl + up + buckets)
# ──────────────────────────────────────────────
deploy: setup ssl up
	@sleep 10
	@$(MAKE) bucket-init
	@echo "==> Deployment complete!"
	@echo "    S3 API:  https://s3.v2.selys.app"
	@echo "    Console: https://minio.v2.selys.app"

# ──────────────────────────────────────────────
# bucket-init: run the bucket initialization job
# ──────────────────────────────────────────────
bucket-init:
	@echo "==> Initializing buckets..."
	$(KUBECTL) delete job minio-bucket-init -n $(NAMESPACE) 2>/dev/null || true
	$(KUBECTL) delete configmap bucket-init-script -n $(NAMESPACE) 2>/dev/null || true
	$(KUBECTL) create configmap bucket-init-script --from-file=bucket-init.sh=scripts/bucket-init.sh -n $(NAMESPACE)
	$(KUBECTL) apply -f job-bucket-init.yaml
	@echo "==> Waiting for bucket-init job to complete..."
	$(KUBECTL) -n $(NAMESPACE) wait --for=condition=complete job/minio-bucket-init --timeout=120s
	$(KUBECTL) -n $(NAMESPACE) logs job/minio-bucket-init

# ──────────────────────────────────────────────
# clean: remove all MinIO resources (keeps PVC data)
# ──────────────────────────────────────────────
clean:
	@echo "==> Removing MinIO resources..."
	$(KUBECTL) delete -f job-bucket-init.yaml 2>/dev/null || true
	$(KUBECTL) delete -f ingress.yaml 2>/dev/null || true
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
	$(KUBECTL) delete -f cert-manager-issuer.yaml 2>/dev/null || true
	@echo "==> MinIO uninstalled."
	@echo "    NGINX Ingress and cert-manager were kept (shared resources)."
	@echo "    To remove them:"
	@echo "      $(KUBECTL) delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/cloud/deploy.yaml"
	@echo "      $(KUBECTL) delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.2/cert-manager.yaml"

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
	@echo "=== Ingress ==="
	@$(KUBECTL) -n $(NAMESPACE) get ingress
	@echo ""
	@echo "=== Certificates ==="
	@$(KUBECTL) -n $(NAMESPACE) get certificates 2>/dev/null || echo "    (no certificates found)"
	@echo ""
	@echo "=== PVC ==="
	@$(KUBECTL) -n $(NAMESPACE) get pvc
