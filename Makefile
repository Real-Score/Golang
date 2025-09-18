APP_NAME := demo
DOCKER_TAG := latest
# Use a version that works with Go 1.18
GOLANGCI_LINT_VERSION := v1.54.2
GOLANGCI_LINT := $(shell go env GOPATH)/bin/golangci-lint
CODEQL_VERSION := v2.23.0
CODEQL_DIR := $(PWD)/codeql
CODEQL_BIN := $(CODEQL_DIR)/codeql
CODEQL_DB := $(PWD)/codeql-db
CODEQL_RESULTS := $(PWD)/codeql-results.sarif
CONFTEST_VERSION := 0.41.0   # specify a stable version
OPA_VERSION := 0.80.0
POLICY_DIR := policies
MANIFEST_DIR := k8s-manifests

.PHONY: install lint gitleaks semgrep test terrascan codeql synk conftest all

install:
	@echo "Tidying Go modules..."
	go mod tidy

lint:
	@echo "Running golangci-lint..."
	@if [ ! -x "$(GOLANGCI_LINT)" ]; then \
		echo "golangci-lint not found, installing $(GOLANGCI_LINT_VERSION)..."; \
		go install github.com/golangci/golangci-lint/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION); \
	fi
	PATH="$(shell go env GOPATH)/bin:$$PATH" $(GOLANGCI_LINT) run ./...

gitleaks:
	@echo "Installing Gitleaks..."
	VERSION=$$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep tag_name | cut -d '"' -f 4); \
	echo "Latest Gitleaks version: $$VERSION"; \
	curl -sSL https://github.com/gitleaks/gitleaks/releases/download/$$VERSION/gitleaks_$${VERSION#v}_linux_x64.tar.gz -o gitleaks.tar.gz; \
	tar -xvzf gitleaks.tar.gz; \
	sudo mv gitleaks /usr/local/bin/; \
	rm -f gitleaks.tar.gz
	@echo "Running Gitleaks scan..."
	gitleaks detect --source . --verbose --redact --config .gitleaks.toml

semgrep:
	@echo "Installing Semgrep..."
	pip install semgrep --quiet
	@echo "Running Semgrep scan..."
	semgrep --config p/ci --config p/golang .

terrascan:
	@echo "Installing Terrascan..."
	@ASSET_URL=$$(curl -s https://api.github.com/repos/tenable/terrascan/releases/latest \
		| jq -r '.assets[].browser_download_url' \
		| grep 'Linux_x86_64.tar.gz'); \
	echo "Downloading Terrascan from: $$ASSET_URL"; \
	curl -L $$ASSET_URL -o terrascan.tar.gz; \
	tar -xvzf terrascan.tar.gz terrascan; \
	rm terrascan.tar.gz; \
	sudo mv terrascan /usr/local/bin/; \
	echo "Terrascan installed."; \
	echo "Running Terrascan scans..."; \
	terrascan scan -t terraform -d ./terraform || true; \
	terrascan scan -t k8s -d ./k8s || true; \
	terrascan scan -t helm -d ./helm || true; \
	terrascan scan -t kustomize -d ./kustomize || true

codeql:
	@echo "Checking CodeQL installation..."
	@if [ ! -x "$(CODEQL_BIN)" ]; then \
		echo "Downloading CodeQL CLI $(CODEQL_VERSION)..."; \
		curl -sSL -o codeql.zip https://github.com/github/codeql-cli-binaries/releases/download/$(CODEQL_VERSION)/codeql-linux64.zip; \
		unzip -q codeql.zip; \
		rm -f codeql.zip; \
	fi
	@echo "Ensuring Go query pack is available..."
	$(CODEQL_BIN) pack download codeql/go-queries
	@echo "Removing old database (if any)..."
	rm -rf $(CODEQL_DB)
	@echo "Creating new CodeQL database..."
	$(CODEQL_BIN) database create $(CODEQL_DB) --language=go --source-root=.
	@echo "Running CodeQL analysis..."
	$(CODEQL_BIN) database analyze $(CODEQL_DB) \
		codeql/go-queries \
		--format=sarifv2.1.0 \
		--output=$(CODEQL_RESULTS)
	@echo "CodeQL analysis completed. Results saved to $(CODEQL_RESULTS)"

synk:
	@echo "Installing latest Snyk CLI..."
	curl -sL https://static.snyk.io/cli/latest/snyk-linux -o snyk
	chmod +x snyk
	@echo "Running Snyk scan..."
	SNYK_TOKEN="3b94176d-d733-448a-8c30-ef3c88a64299" ./snyk test --all-projects --severity-threshold=medium

# conftest:
# 	@echo "Installing Conftest CLI..."
# 	curl -sSL -o conftest.tar.gz https://github.com/open-policy-agent/conftest/releases/download/v0.41.0/conftest_0.41.0_linux_amd64.tar.gz
# 	tar -xzf conftest.tar.gz
# 	chmod +x conftest
# 	sudo mv conftest /usr/local/bin/conftest || true
# 	rm -f conftest.tar.gz
# 	@echo "Running Conftest security checks..."
# 	conftest test $(MANIFEST_DIR) -p $(POLICY_DIR)

opa:
	@echo "Installing OPA CLI..."
	curl -sSL -o opa https://openpolicyagent.org/downloads/v$(OPA_VERSION)/opa_linux_amd64
	chmod +x opa
	sudo mv opa /usr/local/bin/opa || true
	@echo "Running OPA security checks..."
	opa eval --input $(MANIFEST_DIR) --data $(POLICY_DIR) "data.main.deny" --fail-defined

test:
	@echo "Running Go tests..."
	go test ./... -v

all: install lint gitleaks semgrep terrascan codeql synk conftest test
