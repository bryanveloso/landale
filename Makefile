# Landale Docker Management

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: up
up: ## Start all services in detached mode
	docker compose up -d

.PHONY: down
down: ## Stop all services
	docker compose down

.PHONY: restart
restart: down up ## Restart all services

.PHONY: build
build: ## Build Docker images
	docker compose build

.PHONY: rebuild
rebuild: ## Rebuild Docker images without cache
	docker compose build --no-cache

.PHONY: logs
logs: ## Show logs from all services
	docker compose logs -f

.PHONY: logs-server
logs-server: ## Show logs from server only
	docker compose logs -f server

.PHONY: logs-overlays
logs-overlays: ## Show logs from overlays only
	docker compose logs -f overlays

.PHONY: shell-server
shell-server: ## Open shell in server container
	docker compose exec server sh

.PHONY: shell-db
shell-db: ## Open PostgreSQL shell
	docker compose exec db psql -U landale landale

.PHONY: migrate
migrate: ## Run database migrations
	docker compose exec server bun --cwd packages/database db:migrate:dev

.PHONY: studio
studio: ## Open Prisma Studio
	docker compose exec server bun --cwd packages/database studio

.PHONY: cache-emotes
cache-emotes: ## Cache Twitch emotes
	docker compose exec server bun run cache-emotes

.PHONY: backup-db
backup-db: ## Backup database
	@mkdir -p backups
	docker compose exec -T db pg_dump -U landale landale > backups/landale_backup_$$(date +%Y%m%d_%H%M%S).sql
	@echo "Database backed up to backups/landale_backup_$$(date +%Y%m%d_%H%M%S).sql"

.PHONY: clean
clean: ## Remove containers, volumes, and images
	docker compose down -v --remove-orphans
	docker image rm landale-server landale-overlays 2>/dev/null || true