# Local development Makefile for nebari-rayserve-pack
#
# Creates a kind cluster with the full Nebari infrastructure stack
# (MetalLB, Envoy Gateway, cert-manager, Keycloak, nebari-operator)
# and deploys Ray Serve with NebariApp enabled.
#
# Prerequisites: docker, kind, helm, kubectl, git
#
# Usage:
#   make up             Deploy Ray Serve with NebariApp
#   make up-standalone  Deploy Ray Serve without NebariApp (no operator needed)
#   make update-hosts   Update /etc/hosts with NebariApp hostnames
#   make down           Delete the kind cluster

CHART_DIR      := ../chart
CLUSTER_NAME   := rayserve-dev
HOSTNAME       := rayserve.nebari.local
DASH_HOSTNAME  := ray-dashboard.nebari.local
CACHE_DIR      := .cache
OPERATOR_REPO  := $(CACHE_DIR)/nebari-operator

# MetalLB IP pool configuration template.
define METALLB_POOL
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kind-pool
  namespace: metallb-system
spec:
  addresses:
  - METALLB_BASE_IP.255.200-METALLB_BASE_IP.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kind-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - kind-pool
endef
export METALLB_POOL

.PHONY: up up-standalone down cluster update-hosts

# --------------------------------------------------------------------------
# cluster - create kind cluster with full Nebari infrastructure
# --------------------------------------------------------------------------
cluster:
	@if kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Cluster '$(CLUSTER_NAME)' already exists, skipping setup"; \
	else \
		$(MAKE) _cluster-create; \
	fi

_cluster-create: _clone-operator _kind-create _metallb _services _keycloak-setup _operator _label-namespace
	@echo ""
	@echo "=========================================="
	@echo "Cluster setup complete!"
	@echo "=========================================="
	@echo ""
	@echo "Run 'make up' to deploy Ray Serve with NebariApp."

OPERATOR_REF := main

_clone-operator:
	@if [ ! -d "$(OPERATOR_REPO)" ]; then \
		echo "Cloning nebari-operator ($(OPERATOR_REF)) into $(OPERATOR_REPO)..."; \
		mkdir -p $(CACHE_DIR); \
		git clone --depth 1 --branch $(OPERATOR_REF) \
			https://github.com/nebari-dev/nebari-operator.git $(OPERATOR_REPO); \
	else \
		echo "nebari-operator already cloned"; \
	fi

_kind-create:
	@echo "Creating kind cluster: $(CLUSTER_NAME)"
	kind create cluster --name $(CLUSTER_NAME)

_metallb:
	@echo "Installing MetalLB..."
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml 2>&1 | grep -v "unrecognized format"
	kubectl wait --namespace metallb-system \
		--for=condition=available deployment/controller \
		--timeout=90s
	kubectl wait --namespace metallb-system \
		--for=jsonpath='{.status.numberReady}'=1 \
		daemonset/speaker \
		--timeout=90s
	@KIND_NET_CIDR=$$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}}{{"\n"}}{{end}}' 2>/dev/null | grep '\.' | head -n1); \
	BASE_IP=$$(echo $${KIND_NET_CIDR} | awk -F. '{print $$1"."$$2}'); \
	echo "MetalLB IP pool: $${BASE_IP}.255.200-$${BASE_IP}.255.250"; \
	echo "$$METALLB_POOL" | sed "s/METALLB_BASE_IP/$${BASE_IP}/g" | kubectl apply -f -
	@echo "MetalLB installed"

_services:
	@echo "Installing foundational services (Envoy Gateway, cert-manager, Keycloak, Gateway, TLS)..."
	CLUSTER_NAME=$(CLUSTER_NAME) $(OPERATOR_REPO)/dev/scripts/services/install.sh

_keycloak-setup:
	@echo "Setting up Keycloak realm..."
	CLUSTER_NAME=$(CLUSTER_NAME) $(OPERATOR_REPO)/dev/scripts/services/keycloak/setup.sh

_operator:
	@echo "Installing nebari-operator..."
	kubectl apply -f https://github.com/nebari-dev/nebari-operator/releases/download/v0.1.0-alpha.5/install.yaml
	kubectl wait --for=condition=available deployment/nebari-operator-controller-manager \
		-n nebari-operator-system --timeout=120s
	@echo "nebari-operator is running"

_label-namespace:
	kubectl label namespace default nebari.dev/managed=true --overwrite

# --------------------------------------------------------------------------
# up - deploy Ray Serve with NebariApp enabled
# --------------------------------------------------------------------------
up: cluster
	helm dependency update $(CHART_DIR)
	helm upgrade --install rayserve $(CHART_DIR) \
		--set nebariapp.enabled=true \
		--set nebariapp.hostname=$(HOSTNAME) \
		--set nebariapp.dashboard.enabled=true \
		--set nebariapp.dashboard.hostname=$(DASH_HOSTNAME) \
		--wait --timeout 5m
	kubectl wait --for=condition=Ready nebariapp/rayserve-nebari-rayserve-pack --timeout=180s
	CLUSTER_NAME=$(CLUSTER_NAME) $(OPERATOR_REPO)/dev/scripts/networking/update-hosts.sh
	@echo ""
	@echo "Ray Serve deployed with NebariApp."
	@echo "  Ray Serve:   https://$(HOSTNAME)"
	@echo "  Dashboard:   https://$(DASH_HOSTNAME)"

# --------------------------------------------------------------------------
# up-standalone - deploy Ray Serve without NebariApp (no operator needed)
# --------------------------------------------------------------------------
up-standalone:
	@if ! kind get clusters 2>/dev/null | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Creating kind cluster: $(CLUSTER_NAME)"; \
		kind create cluster --name $(CLUSTER_NAME); \
	fi
	helm dependency update $(CHART_DIR)
	helm upgrade --install rayserve $(CHART_DIR) \
		--wait --timeout 5m
	@echo ""
	@echo "Ray Serve deployed (standalone, no NebariApp)."
	@echo ""
	@echo "Access via port-forward:"
	@echo "  kubectl port-forward svc/rayserve-nebari-rayserve-pack-serve-svc 8000:8000"
	@echo "  kubectl port-forward svc/rayserve-nebari-rayserve-pack-head-svc 8265:8265"

# --------------------------------------------------------------------------
# update-hosts - update /etc/hosts with all NebariApp hostnames
# --------------------------------------------------------------------------
update-hosts:
	CLUSTER_NAME=$(CLUSTER_NAME) $(OPERATOR_REPO)/dev/scripts/networking/update-hosts.sh

# --------------------------------------------------------------------------
# down - delete the kind cluster
# --------------------------------------------------------------------------
down:
	kind delete cluster --name $(CLUSTER_NAME)
