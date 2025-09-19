APP_NAME := demo
DOCKER_TAG := latest
OWASP_TARGET ?= http://175.29.21.210:30010/  # default URL of the app to scan
# Use a version that works with Go 1.18
GOLANGCI_LINT_VERSION := v1.54.2
GOLANGCI_LINT := $(shell go env GOPATH)/bin/golangci-lint
CODEQL_VERSION := v2.23.0
CODEQL_DIR := $(PWD)/codeql
CODEQL_BIN := $(CODEQL_DIR)/codeql
CODEQL_DB := $(PWD)/codeql-db
CODEQL_RESULTS := $(PWD)/codeql-results.sarif
# CONFTEST_VERSION := 0.41.0   # specify a stable version
OPA_VERSION := 0.80.0
POLICY_DIR := policies
MANIFEST_DIR := k8s-manifests
MSF_TARGET ?= 175.29.21.210

.PHONY: install lint gitleaks semgrep test terrascan codeql synk conftest owasp metasploit whitesource datameer-mask falco-monitor all

install:
	@echo "Tidying Go modules..."
	@go mod tidy
	@echo "Updating apt caches..."
	@sudo apt update
	# If msfconsole already exists, skip install
	@if command -v msfconsole >/dev/null 2>&1; then \
	  echo "msfconsole already installed, skipping metasploit install"; \
	else \
	  echo "msfconsole not found. Installing snapd (if needed) and metasploit-framework snap..."; \
	  if ! command -v snap >/dev/null 2>&1; then \
	    echo "snap not found — installing snapd..."; \
	    sudo apt install -y snapd; \
	  fi; \
	  sudo snap install metasploit-framework --classic; \
	fi

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

# opa:
#	@echo "Installing OPA CLI..."
#	curl -sSL -o opa https://github.com/open-policy-agent/opa/releases/download/v$(OPA_VERSION)/opa_linux_amd64
#	chmod +x opa
#	sudo mv opa /usr/local/bin/opa || true
#	@echo "Running OPA security checks..."
#	opa eval --input $(MANIFEST_DIR) --data $(POLICY_DIR) "data.main.deny" --fail-defined

owasp:
	@echo "Starting OWASP ZAP scan on $(OWASP_TARGET)..."
	docker run --rm -v $(PWD):/zap/wrk/:rw zaproxy/zap-stable zap-baseline.py -t $(OWASP_TARGET) -r zap-report.html
	@echo "OWASP ZAP scan completed. Report saved to zap-report.html"

metasploit:
	@echo "Running automated Metasploit scan on $(MSF_TARGET)..."
	@echo "use auxiliary/scanner/portscan/tcp" > scan.rc
	@echo "set RHOSTS $(MSF_TARGET)" >> scan.rc
	@echo "set PORTS 1-1000" >> scan.rc
	@echo "run" >> scan.rc
	@echo "use auxiliary/scanner/http/http_version" >> scan.rc
	@echo "set RHOSTS $(MSF_TARGET)" >> scan.rc
	@echo "run" >> scan.rc
	@echo "exit" >> scan.rc
	msfconsole -r scan.rc

whitesource:
	@echo "Running WhiteSource (Mend) scan for license compliance..."
	@if [ ! -f wss-unified-agent.jar ]; then \
		curl -L -o wss-unified-agent.jar https://github.com/whitesource/unified-agent-distribution/releases/latest/download/wss-unified-agent.jar; \
	fi
	java -jar wss-unified-agent.jar -c wss-unified-agent.config

# datameer-mask target — uses dummy envs if not provided
datameer-mask:
	@echo "Running Datameer masking (test mode with dummy envs)..."

	@DATAMEER_API_TOKEN="$${DATAMEER_API_TOKEN:-dmr_test_ABC123xyz_TOKEN_000}" ; \
	DATAMEER_BASE_URL="$${DATAMEER_BASE_URL:-https://demo.datameer.example.com/api}" ; \
	DATAMEER_JOB_ID="$${DATAMEER_JOB_ID:-JOB-000-TEST-1234}" ; \
	INPUT="$${DATAMEER_INPUT_TABLE:-raw_data_test.csv}" ; \
	OUTPUT="$${DATAMEER_OUTPUT_TABLE:-masked_data_test.csv}" ; \
	\
	echo "Using Datameer API URL: $$DATAMEER_BASE_URL" ; \
	echo "Using job id: $$DATAMEER_JOB_ID" ; \
	echo "Input file: $$INPUT" ; \
	echo "Output file: $$OUTPUT" ; \
	\
	echo "POST $$DATAMEER_BASE_URL/jobs/$$DATAMEER_JOB_ID/execute (simulated)" ; \
	printf '{ "jobId":"%s", "input":"%s", "output":"%s" }' "$$DATAMEER_JOB_ID" "$$INPUT" "$$OUTPUT" > datameer_trigger_payload.json ; \
	cat datameer_trigger_payload.json ; \
	\
	echo '{"status":"SUBMITTED","runId":"run-000-test","startTime":"2025-09-19T16:00:00Z"}' > datameer_response.json ; \
	cat datameer_response.json ; \
	\
	echo "Polling for job completion (simulated)..." ; \
	sleep 1 ; \
	echo '{"runId":"run-000-test","status":"COMPLETED","rowsProcessed":1000}' > datameer_run_status.json ; \
	cat datameer_run_status.json ; \
	\
	echo "Simulating download of masked output to $$OUTPUT" ; \
	printf "id,name,email\n1,XXX,masked1@masked.com\n2,YYY,masked2@masked.com\n" > "$$OUTPUT" ; \
	ls -lh "$$OUTPUT" ; \
	echo "Datameer masking simulation complete. Output: $$OUTPUT"

falco-monitor:
	@echo "Running Falco (simulation mode for CI/CD)..."
	@echo "Using ruleset: default"
	# simulate Falco alerts
	echo '{"priority":"CRITICAL","rule":"Terminal shell in container","output":"Detected shell spawn in container"}' > falco_alert.json
	cat falco_alert.json
	@echo "Falco monitoring simulation complete."

test:
	@echo "Running Go tests..."
	go test ./... -v

all: install lint gitleaks semgrep terrascan codeql synk conftest owasp metasploit whitesource datameer-mask falco-monitor test
