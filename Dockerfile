FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.local/bin:/opt/codeql/codeql:${PATH}"
ENV PIP_ROOT_USER_ACTION=ignore

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    default-jre \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN python3 -m pip install --upgrade pip

# Install Semgrep
RUN python3 -m pip install semgrep

# Install CodeQL - Use matching CLI and query versions
RUN echo "Installing CodeQL..." && \
    CODEQL_VERSION=$(curl -s https://api.github.com/repos/github/codeql-cli-binaries/releases/latest | grep tag_name | cut -d '"' -f 4) && \
    wget -q https://github.com/github/codeql-cli-binaries/releases/download/${CODEQL_VERSION}/codeql-linux64.zip && \
    unzip -q codeql-linux64.zip -d /opt/ && \
    rm codeql-linux64.zip && \
    echo "Downloading CodeQL standard libraries..." && \
    git clone --depth 1 https://github.com/github/codeql.git /opt/codeql/codeql-repo

ENV PATH="/opt/codeql:${PATH}"

# Install Gitleaks
RUN curl -L https://github.com/gitleaks/gitleaks/releases/download/v8.18.4/gitleaks_8.18.4_linux_x64.tar.gz -o /tmp/gitleaks.tar.gz && \
    tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin && \
    chmod +x /usr/local/bin/gitleaks && \
    rm /tmp/gitleaks.tar.gz

# Install Bandit and Safety
RUN pip3 install bandit safety

# Verify all installations
RUN echo "=== Verifying tool installations ===" && \
    echo "Semgrep:" && semgrep --version && \
    echo "" && \
    echo "CodeQL:" && codeql --version && \
    echo "" && \
    echo "CodeQL Queries:" && ls -la /opt/codeql/qlpacks/ | head -20 && \
    echo "" && \
    echo "Gitleaks:" && gitleaks version && \
    echo "" && \
    echo "Bandit:" && bandit --version && \
    echo "" && \
    echo "Safety:" && safety --version && \
    echo "" && \
    echo "=== All tools installed successfully ==="

# Create working directories
RUN mkdir -p /scan/repo /scan/results

# Copy scan scripts
COPY scripts/docker-scan.sh /usr/local/bin/scan
COPY scripts/scan-all-branches.sh /usr/local/bin/scan-all-branches
COPY scripts/generate-report.py /usr/local/bin/generate-report

# Make executable
RUN chmod +x /usr/local/bin/scan && \
    chmod +x /usr/local/bin/scan-all-branches && \
    chmod +x /usr/local/bin/generate-report

WORKDIR /scan

CMD ["/bin/bash"]
