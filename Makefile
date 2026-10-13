# Image URL to use all building/pushing image targets
IMG ?= ${ACC}.dkr.ecr.eu-west-1.amazonaws.com/monzo/egress-operator:manager-$(shell git rev-parse --short HEAD)

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Local directory for tool binaries (controller-gen, setup-envtest, envtest assets)
LOCALBIN ?= $(shell pwd)/bin

# Tool versions. SETUP_ENVTEST_VERSION tracks the controller-runtime minor version in go.mod.
SETUP_ENVTEST_VERSION ?= release-0.19
# Kubernetes version of the etcd/kube-apiserver binaries used by envtest
ENVTEST_K8S_VERSION ?= 1.31.x

CONTROLLER_TOOLS_VERSION ?= v0.17.0

ENVTEST ?= $(LOCALBIN)/setup-envtest
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen

# Minimum statement coverage (percent) of the controllers package enforced by coverage-check
COVERAGE_MIN ?= 70

all: manager

# Run tests. envtest binaries (etcd, kube-apiserver) are downloaded into ./bin automatically;
# set KUBEBUILDER_ASSETS yourself to use binaries from elsewhere.
test: generate fmt vet manifests envtest
	KUBEBUILDER_ASSETS="$${KUBEBUILDER_ASSETS:-$$($(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)}" \
		go test ./... -coverprofile cover.out

# Fail if controllers coverage in cover.out is below COVERAGE_MIN. Run after `make test`.
coverage-check:
	@grep -E '^(mode:|github.com/monzo/egress-operator/controllers/)' cover.out > cover.controllers.out
	@pct=$$(go tool cover -func cover.controllers.out | awk '/^total:/ {sub("%","",$$3); print $$3}'); \
	echo "controllers coverage: $${pct}% (minimum $(COVERAGE_MIN)%)"; \
	awk -v p="$$pct" -v m="$(COVERAGE_MIN)" 'BEGIN { exit (p+0 < m+0) }' || { echo "coverage below minimum"; exit 1; }

# Default gateway Envoy image, read from controllers/deployment.go so there is a single source of truth
ENVOY_IMAGE ?= $(shell sed -n 's/.*img := "\(envoyproxy\/envoy:[^"]*\)".*/\1/p' controllers/deployment.go)

# Validate the Envoy configs the operator generates against the real Envoy binary (needs Docker)
validate-envoy-config:
	rm -rf $(LOCALBIN)/envoy-configs && mkdir -p $(LOCALBIN)/envoy-configs
	ENVOY_CONFIG_DUMP_DIR=$(LOCALBIN)/envoy-configs go test ./controllers/ -run Test_envoyConfig -count=1
	for f in $(LOCALBIN)/envoy-configs/*.yaml; do \
		echo "validating $$(basename $$f) with $(ENVOY_IMAGE)"; \
		docker run --rm -v $(LOCALBIN)/envoy-configs:/cfg $(ENVOY_IMAGE) --mode validate -c /cfg/$$(basename $$f) || exit 1; \
	done

# Build every Dockerfile / compose file in the repo and scan the images with `snyk container test`
# (see hack/snyk-container-scan.sh --help). SNYK_CONTAINER_ARGS="--base-only" skips the builds.
SNYK_CONTAINER_ARGS ?=
snyk-container:
	hack/snyk-container-scan.sh $(SNYK_CONTAINER_ARGS)

# Run the Robot Framework acceptance suites in test/ (one per fixed issue).
# Pass ROBOT_ARGS, e.g. ROBOT_ARGS="--include issue-50" or ROBOT_ARGS="--exclude slow".
ROBOT_ARGS ?=
robot:
	uv run --with-requirements test/requirements.txt robot --outputdir test/results $(ROBOT_ARGS) test/

# Build manager binary
manager: generate fmt vet
	go build -o bin/manager main.go

# Run against the configured Kubernetes cluster in ~/.kube/config
run: generate fmt vet manifests
	go run ./main.go

# Install CRDs into a cluster
install: manifests
	kustomize build config/crd | kubectl apply -f -

# Uninstall CRDs from a cluster
uninstall: manifests
	kustomize build config/crd | kubectl delete -f -

# Deploy controller in the configured Kubernetes cluster in ~/.kube/config
deploy: manifests
	cd ./config/manager && kustomize edit set image controller=${IMG}
	kustomize build config/default | kubectl apply -f -

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	CGO_ENABLED=0 $(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

# Run go fmt against code
fmt:
	go fmt ./...

# Run go vet against code
vet:
	go vet ./...

# Generate code
generate: controller-gen
	CGO_ENABLED=0 $(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths="./..."

# Build the docker image
docker-build: test
	docker buildx build . -t ${IMG} --platform=linux/amd64

# Push the docker image
docker-push:
	docker push ${IMG}

# Download setup-envtest into ./bin if necessary
envtest: $(ENVTEST)
$(ENVTEST):
	mkdir -p $(LOCALBIN)
	GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@$(SETUP_ENVTEST_VERSION)

# Download the pinned controller-gen into ./bin if necessary. A controller-gen already on $PATH is
# deliberately ignored: other versions generate different output, and old ones (installed via
# `go get` with cgo) are what broke issue #17. CGO_ENABLED=0 means no C compiler is needed.
controller-gen: $(CONTROLLER_GEN)
# The stamp file makes a CONTROLLER_TOOLS_VERSION change trigger a reinstall.
$(CONTROLLER_GEN): $(LOCALBIN)/.controller-gen-$(CONTROLLER_TOOLS_VERSION)
	CGO_ENABLED=0 GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)
$(LOCALBIN)/.controller-gen-$(CONTROLLER_TOOLS_VERSION):
	mkdir -p $(LOCALBIN)
	rm -f $(LOCALBIN)/.controller-gen-* && touch $@

# Fail if generated code or manifests are out of date (e.g. api/ changed without `make generate manifests`)
verify-generated: generate manifests
	git diff --exit-code -- api config || { echo "Generated files are stale: run 'make generate manifests' and commit the result"; exit 1; }
