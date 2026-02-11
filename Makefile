.PHONY: build scan shell clean help

build:
	docker-compose build

scan:
	@echo "Repository URL: "; \
	read repo; \
	echo "Output name (optional, press Enter to skip): "; \
	read name; \
	if [ -z "$$name" ]; then \
		docker-compose run --rm vuln-scanner scan $$repo; \
	else \
		docker-compose run --rm vuln-scanner scan $$repo $$name; \
	fi

shell:
	docker-compose run --rm vuln-scanner /bin/bash

clean:
	docker-compose down -v
	rm -rf results/*

help:
	@echo "Containerized Vulnerability Scanner - Docker Edition"
	@echo ""
	@echo "Available targets:"
	@echo "  build  - Build the Docker image"
	@echo "  scan   - Run interactive scan"
	@echo "  shell  - Open shell in container"
	@echo "  clean  - Clean up containers and results"
	@echo ""
	@echo "Manual usage:"
	@echo "  docker-compose run --rm vuln-scanner scan <repo-url> [output-name]"
