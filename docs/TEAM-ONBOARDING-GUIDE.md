# 🚀 Team Onboarding & Local Pipeline Setup Guide

Welcome to the **Secure DevOps Pipeline (SDOP-2025)** project! This guide is designed to help any developer or teammate set up their local environment and run the pipeline seamlessly on their laptop. 

This pipeline integrates secret scanning, SAST, SCA, IaC scanning, container vulnerability scanning, and DAST, reporting all findings to **DefectDojo** and telemetry/metrics to **Prometheus & Grafana**.

---

## 📋 Table of Contents
1. [System Requirements & Prerequisites](#1-system-requirements--prerequisites)
2. [External Accounts & API Keys](#2-external-accounts--api-keys)
3. [Local Services Setup (Docker Compose)](#3-local-services-setup-docker-compose)
4. [Setting Up Local Caching & Performance Tuning](#4-setting-up-local-caching--performance-tuning)
5. [Running the Pipeline via Self-Hosted Runner (Recommended)](#5-running-the-pipeline-via-self-hosted-runner-recommended)
6. [Running Scans Manually via CLI (Alternative)](#6-running-scans-manually-via-cli-alternative)
7. [Troubleshooting & FAQs](#7-troubleshooting--faqs)

---

## 1. System Requirements & Prerequisites

The pipeline runs a complete security orchestration and monitoring stack locally. Ensure your laptop meets these minimum specifications:

*   **RAM**: Minimum **8 GB** (16 GB highly recommended). Docker Desktop must be allocated at least **4 GB RAM** to run SonarQube, DefectDojo, Grafana, Prometheus, and databases concurrently.
*   **Disk Space**: At least **10 GB** of free space for Docker images, dependency caches, and the NVD database.
*   **Operating System**: Windows 10/11 (with WSL2 enabled), macOS, or Linux.

### Required Software Packages:
Install the following on your host machine:
*   [Docker Desktop](https://www.docker.com/products/docker-desktop/) (includes Docker Compose)
*   [Java Development Kit (JDK) 17](https://adoptium.net/temurin/releases/?version=17) (Temurin is used by the pipeline)
*   [Apache Maven 3.8+](https://maven.apache.org/download.cgi) (for Java builds and Maven plugins)
*   `curl` and `jq` CLI tools (for scripts and API querying)

---

## 2. External Accounts & API Keys

To run all pipeline stages successfully, you need the following keys and configurations:

### A. National Vulnerability Database (NVD) API Key ⚠️ CRITICAL
The OWASP Dependency Check scan queries the NVD database. Without an API key, the scan is heavily rate-limited, causing builds to fail or take hours.
1.  Go to the [NVD API Key Request Page](https://nvd.nist.gov/developers/request-an-api-key).
2.  Register and request a free API key.
3.  Store this key securely. You will use it as a GitHub Secret (`NVD_API_KEY`) or as a local environment variable.

### B. Docker Hub Account & Access Token
To build and push container images, you need a Docker Hub account.
1.  Log in to Docker Hub.
2.  Navigate to **Account Settings** → **Security** → **Access Tokens**.
3.  Create a new token with **Read & Write** permissions (do not use your primary Docker password).
4.  Save the username (`DOCKER_USERNAME`) and token (`DOCKER_PASSWORD`).

### C. SonarQube Authentication Token
SonarQube requires a token to authenticate local scans.
1.  Access your local SonarQube instance at `http://localhost:9000` (after spinning it up in Section 3).
2.  Login (Default: `admin` / `admin`).
3.  Go to **My Account** → **Security** → **Tokens** → **Generate Token**.
4.  Name the token (e.g., `local-pipeline`) and copy the generated token (`SONAR_TOKEN`).

### D. DefectDojo API Key
1.  Access DefectDojo at `http://localhost:8000`.
2.  Login (Default: `admin` / `admin123`).
3.  Click the user icon in the top right → **API v2 Key**.
4.  Click **Generate Key** if empty, and copy it (`DEFECTDOJO_API_KEY`).

---

## 3. Local Services Setup (Docker Compose)

The pipeline uploads scan reports to DefectDojo and pushes metrics to Prometheus/Grafana. All these run locally as Docker containers.

### Step 1: Start the Local Stack
Navigate to the directory containing the docker-compose file:
```bash
cd docker/monitoring
docker-compose up -d
```

### Step 2: Verify All Services are Healthy
Run the verification script provided in the repository
```bash
# Return to repository root
cd ../..
./verify-demo-setup.sh
```

All the following local endpoints should be accessible via browser:
*   ✅ **DefectDojo**: [http://localhost:8000](http://localhost:8000) (`admin` / `admin123`)
*   ✅ **SonarQube**: [http://localhost:9000](http://localhost:9000) (`admin` / `admin` - first login prompts password change)
*   ✅ **Grafana**: [http://localhost:3000](http://localhost:3000) (`admin` / `admin`)
*   ✅ **Prometheus**: [http://localhost:9090](http://localhost:9090)
*   ✅ **Prometheus Pushgateway**: [http://localhost:9091](http://localhost:9091)

---

## 4. Setting Up Local Caching & Performance Tuning

Vulnerability scans can be highly time-consuming. To make the pipeline run fast and seamlessly on a laptop, several local caching layers have been integrated:

### 4.1 OWASP Dependency Check Cache (NVD Data Cache)
*   **The Problem**: Downloading the entire NVD database takes 15+ minutes and downloads gigabytes of data on every scan.
*   **The Fix**: We configure Maven to store downloaded database files in a persistent directory: `-DdataDirectory="$HOME/odc-data"`.
*   **To configure locally**: The pipeline automatically writes to the runner's `$HOME/odc-data` folder. On subsequent runs, it only downloads updates/deltas (less than 1 minute).
*   **Requirement**: Pass the `-DnvdApiKey` Maven argument alongside it.

### 4.2 Docker Build Layer Caching
*   **The Fix**: The Docker build step uses `--cache-from type=local` in the pipeline configuration. Since the pipeline runs on a self-hosted runner on the same laptop, Docker automatically reuses cached layers from previous builds, reducing build times from minutes to seconds.

### 4.3 Maven Dependency Cache
*   **The Fix**: Maven dependencies are stored in the user's host `$HOME/.m2/repository`. The self-hosted runner shares this local directory, eliminating the need to download dependency JARs on each pipeline run.

### 4.4 Trivy DB Cache
*   **The Fix**: Trivy caches vulnerability data in its local directory (`~/.cache/trivy` on Linux/macOS, `Local/trivy` on Windows). Because the runner is self-hosted on your machine, this cache is naturally preserved, avoiding full DB updates on every scan.

---

## 5. Running the Pipeline via Self-Hosted Runner (Recommended)

To run the GitHub Actions pipeline against your local services (`localhost`), you must register a **Self-Hosted Runner** on your laptop.

### Step 1: Register the Runner in GitHub
1.  Go to your GitHub Fork repository → **Settings** → **Actions** → **Runners**.
2.  Click **New self-hosted runner** and select your Operating System (e.g., Windows or Linux).
3.  Follow the download and configuration steps provided by GitHub.

### Step 2: Configure the Runner Environment
For Windows, create a directory like `C:\github-runner`, extract the runner, and configure it:
```powershell
# Open PowerShell as Administrator
cd C:\github-runner
.\config.cmd --url https://github.com/YOUR_USERNAME/secure-devops-pipeline --token <YOUR_RUNNER_TOKEN>
```
Name your runner and give it the tag `self-hosted`.

### Step 3: Run the Runner Agent
Ensure this remains running in a dedicated shell window:
```powershell
.\run.cmd
```

### Step 4: Configure GitHub Repository Secrets
Go to your GitHub repository → **Settings** → **Secrets and variables** → **Actions** and add these secrets:

| Secret Name | Value | Description |
| :--- | :--- | :--- |
| `DEFECTDOJO_URL` | `http://localhost:8000` | Local DefectDojo Address |
| `DEFECTDOJO_API_KEY` | `[Paste DefectDojo API key]` | Obtained from DefectDojo Settings |
| `PUSHGATEWAY_URL` | `http://localhost:9091` | Local Pushgateway Address |
| `NVD_API_KEY` | `[Paste NVD API Key]` | Speed up Dependency Check |
| `DOCKER_USERNAME` | `[Your Docker Hub Username]` | Pushing Docker Image |
| `DOCKER_PASSWORD` | `[Your Docker Hub Access Token]` | Pushing Docker Image |
| `SONAR_TOKEN` | `[Paste SonarQube Token]` | SonarQube Authentication |

### Step 5: Trigger a Run
Push a commit to your branch or manually trigger the action. The pipeline will execute on your laptop, run the Docker builds, execute scans, cache outputs, and push findings/metrics to local dashboards.

---

## 6. Running Scans Manually via CLI (Alternative)

If you don't want to set up a GitHub Actions runner, you can execute individual security scan stages manually from your terminal.

Ensure your environment variables are configured in your shell first:
```bash
export NVD_API_KEY="your-nvd-api-key"
export SONAR_TOKEN="your-sonar-token"
export DEFECTDOJO_API_KEY="your-defectdojo-api-key"
export DEFECTDOJO_URL="http://localhost:8000"
```

### Run Gitleaks & TruffleHog (Secret Detection):
```bash
# Gitleaks
docker run --rm -v $(pwd):/repo zricethezav/gitleaks:latest detect --source=/repo --no-git --exit-code 1

# TruffleHog
docker run --rm -v $(pwd):/repo ghcr.io/trufflesecurity/trufflehog:latest filesystem /repo --fail --no-update
```

### Build & Run SonarQube Scan:
```bash
# Build artifact
cd app
mvn clean install -DskipTests -Dcheckstyle.skip=true -Dspring-javaformat.skip=true

# Scan
mvn org.sonarsource.scanner.maven:sonar-maven-plugin:4.0.0.4121:sonar \
  -Dsonar.projectKey=secure-devops \
  -Dsonar.host.url=http://localhost:9000 \
  -Dsonar.login=$SONAR_TOKEN
cd ..
```

### Run OWASP Dependency Check (SCA Scan with Local Cache):
```bash
cd app
mvn org.owasp:dependency-check-maven:check \
  -DnvdApiKey=$NVD_API_KEY \
  -Dformat=XML \
  -DdataDirectory="$HOME/odc-data"
cd ..
```

### Run Checkov (IaC Scan):
```bash
docker run --rm -v $(pwd):/app bridgecrewio/checkov:latest \
  --framework kubernetes,dockerfile,github_actions \
  --directory /app \
  --output json \
  --output-file-path /app/checkov-report.json
```

### Run Trivy (Container Scan):
```bash
# Build image
docker build -t anoop1605/devops-app -f docker/Dockerfile .

# Scan
trivy image \
  --format json \
  --output trivy-report.json \
  anoop1605/devops-app
```

### Upload Reports manually to DefectDojo:
```bash
./scripts/defectdojo-upload.sh \
  --url "$DEFECTDOJO_URL" \
  --api-key "$DEFECTDOJO_API_KEY" \
  --product "Secure DevOps Pipeline" \
  --engagement "Manual Scan Run"
```

---

## 7. Troubleshooting & FAQs

### Q1: The SonarQube container keeps exiting or crashing.
*   **Cause**: Elasticsearch in SonarQube requires specific virtual memory configurations.
*   **Fix**: 
    *   **Linux/WSL2**: Run `sudo sysctl -w vm.max_map_count=262144` on your host.
    *   **Docker Compose**: Ensure `SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true` is set in the `sonarqube` environment block (it is already configured in `docker-compose.yml`).
    *   **RAM**: Verify Docker Desktop has been allocated at least 4 GB RAM in its settings under *Resources*.

### Q2: OWASP Dependency Check fails with HTTP 403 Forbidden or 503 Service Unavailable.
*   **Cause**: NVD rate limit hit because the API key is missing, invalid, or the database is downloading too frequently.
*   **Fix**: Ensure `-DnvdApiKey` is passed correctly and maps to a valid key. Check your local cache directory (`~/odc-data`) to ensure permissions allow writing.

### Q3: Local scans are extremely slow.
*   **Fix**: Ensure your caches are working. The first scan of Dependency Check will *always* be slow. Allow the initial database download to complete. Subsequent runs will use the `$HOME/odc-data` cache and complete in seconds.

### Q4: Self-Hosted Runner shows as "Offline" on GitHub.
*   **Fix**: Open your terminal/shell, navigate to your runner folder, and start it again with `.\run.cmd` (Windows) or `./run.sh` (Linux/macOS).

---
