# # Makefile for Go Application

# APP_NAME := demo
# DOCKER_TAG := latest
# # Use a version that works with Go 1.18
# GOLANGCI_LINT_VERSION := v1.54.2
# GOLANGCI_LINT := $(shell go env GOPATH)/bin/golangci-lint

# .PHONY: install lint gitleaks semgrep test all

# install:
# 	@echo "Tidying Go modules..."
# 	go mod tidy

# lint:
# 	@echo "Running golangci-lint..."
# 	@if [ ! -x "$(GOLANGCI_LINT)" ]; then \
# 		echo "golangci-lint not found, installing $(GOLANGCI_LINT_VERSION)..."; \
# 		go install github.com/golangci/golangci-lint/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION); \
# 	fi
# 	PATH="$(shell go env GOPATH)/bin:$$PATH" $(GOLANGCI_LINT) run ./...

# gitleaks:
# 	@echo "Installing Gitleaks..."
# 	VERSION=$$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep tag_name | cut -d '"' -f 4); \
# 	echo "Latest Gitleaks version: $$VERSION"; \
# 	curl -sSL https://github.com/gitleaks/gitleaks/releases/download/$$VERSION/gitleaks_$${VERSION#v}_linux_x64.tar.gz -o gitleaks.tar.gz; \
# 	tar -xvzf gitleaks.tar.gz; \
# 	sudo mv gitleaks /usr/local/bin/; \
# 	rm -f gitleaks.tar.gz
# 	@echo "Running Gitleaks scan..."
# 	gitleaks detect --source . --verbose --redact

# semgrep:
# 	@echo "Installing Semgrep..."
# 	pip install semgrep --quiet
# 	@echo "Running Semgrep scan..."
# 	semgrep --config p/ci --config p/golang .

# test:
# 	@echo "Running Go tests..."
# 	go test ./... -v

# all: install lint gitleaks semgrep test

#####################################################################################

APP_NAME := demo
DOCKER_TAG := latest
# Use a version that works with Go 1.18
GOLANGCI_LINT_VERSION := v1.54.2
GOLANGCI_LINT := $(shell go env GOPATH)/bin/golangci-lint
CODEQL_VERSION := v2.23.0
CODEQL_DIR := $(CURDIR)/codeql
CODEQL := $(CODEQL_DIR)/codeql/codeql
CODEQL_URL := https://github.com/github/codeql-cli-binaries/releases/download/$(CODEQL_VERSION)/codeql-linux64.zip
CODEQL_DB := $(CURDIR)/codeql-db
CODEQL_REPORT := $(CURDIR)/codeql-report.sarif

.PHONY: install lint gitleaks semgrep test terrascan codeql codeql-init codeql-analyze all


codeql: codeql-init codeql-analyze
	@echo "CodeQL scan completed. Report: $(CODEQL_REPORT)"

codeql-init: $(CODEQL)
	@echo "Creating CodeQL database..."
	@rm -rf $(CODEQL_DB)
	$(CODEQL) database create $(CODEQL_DB) \
		--language=go \
		--source-root=$(CURDIR)

codeql-analyze: $(CODEQL)
	@echo "Analyzing CodeQL database..."
	$(CODEQL) database analyze $(CODEQL_DB) \
		--format=sarif-latest \
		--output=$(CODEQL_REPORT)

$(CODEQL):
	@echo "Installing CodeQL CLI..."
	@rm -rf $(CODEQL_DIR)
	@mkdir -p $(CODEQL_DIR)
	curl -L -o codeql-linux64.zip $(CODEQL_URL)
	curl -L -o codeql-linux64.zip.checksum.txt $(CODEQL_URL).checksum.txt
	sha256sum -c codeql-linux64.zip.checksum.txt
	unzip -q codeql-linux64.zip -d $(CODEQL_DIR)
	rm -f codeql-linux64.zip codeql-linux64.zip.checksum.txt
	chmod +x $(CODEQL)

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

test:
	@echo "Running Go tests..."
	go test ./... -v

all: install lint gitleaks semgrep terrascan codeql test
