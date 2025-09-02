# Makefile для KeySloth - управление зашифрованными секретами
#
# Этот файл содержит примеры команд для работы с KeySloth в проекте.
# Настройте переменные ниже под ваш проект.

# =============================================================================
# КОНФИГУРАЦИЯ
# =============================================================================

# URL вашего репозитория с секретами (измените на свой)
SECRETS_REPO := git@github.com:company/secrets.git

# Ветка с секретами
SECRETS_BRANCH := main

# Локальная директория для секретов (добавьте в .gitignore!)
SECRETS_DIR := ./secrets

# Пароль для шифрования (установите в переменной окружения)
# Проверка будет выполняться только для команд, которые требуют пароль

# =============================================================================
# ОСНОВНЫЕ КОМАНДЫ
# =============================================================================

.PHONY: help
help: ## Показать справку по доступным командам
	@echo "KeySloth Makefile - Управление зашифрованными секретами"
	@echo ""
	@echo "НАСТРОЙКА:"
	@echo "  1. Установите SECRET_PASSWORD: export SECRET_PASSWORD=your_password"
	@echo "  2. Измените SECRETS_REPO на URL вашего репозитория"
	@echo "  3. Убедитесь что $(SECRETS_DIR) добавлен в .gitignore"
	@echo ""
	@echo "КОМАНДЫ:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: install
install: ## Установить KeySloth gem
	gem install keysloth

.PHONY: init
init: ## Инициализировать KeySloth в проекте
	keysloth init -r $(SECRETS_REPO) -b $(SECRETS_BRANCH) -d $(SECRETS_DIR)

.PHONY: pull
pull: check-password ## Получить и расшифровать секреты из репозитория
	@echo "🔽 Получаем секреты из $(SECRETS_REPO)..."
	keysloth pull -r $(SECRETS_REPO) -b $(SECRETS_BRANCH) -p "$(SECRET_PASSWORD)" -d $(SECRETS_DIR)
	@echo "✅ Секреты успешно получены в $(SECRETS_DIR)"

.PHONY: push
push: check-password ## Зашифровать и отправить секреты в репозиторий
	@echo "🔼 Отправляем секреты в $(SECRETS_REPO)..."
	@read -p "Введите сообщение коммита: " msg; \
	keysloth push -r $(SECRETS_REPO) -b $(SECRETS_BRANCH) -p "$(SECRET_PASSWORD)" -d $(SECRETS_DIR) -m "$$msg"
	@echo "✅ Секреты успешно отправлены"

.PHONY: status
status: ## Проверить состояние локальных секретов
	@echo "📊 Проверяем состояние секретов..."
	keysloth status -d $(SECRETS_DIR)

.PHONY: validate
validate: ## Проверить целостность файлов секретов
	@echo "🔍 Проверяем целостность секретов..."
	keysloth validate -d $(SECRETS_DIR)

.PHONY: backup-list
backup-list: ## Показать доступные резервные копии
	@echo "📁 Доступные резервные копии:"
	@ls -la $(SECRETS_DIR)_backup_* 2>/dev/null || echo "Резервные копии не найдены"

.PHONY: restore
restore: ## Восстановить секреты из backup'а (использование: make restore BACKUP=backup_name)
	@if [ -z "$(BACKUP)" ]; then \
		echo "❌ Укажите backup для восстановления: make restore BACKUP=secrets_backup_20231215_143022"; \
		exit 1; \
	fi
	@echo "🔄 Восстанавливаем из $(BACKUP)..."
	keysloth restore $(BACKUP) -d $(SECRETS_DIR)
	@echo "✅ Восстановление завершено"

# =============================================================================
# РАЗРАБОТКА И ОТЛАДКА
# =============================================================================

.PHONY: check-password
check-password: ## Проверить что установлен SECRET_PASSWORD
	@if [ -z "$(SECRET_PASSWORD)" ]; then \
		echo "❌ SECRET_PASSWORD не установлен. Выполните: export SECRET_PASSWORD=your_password"; \
		exit 1; \
	fi

.PHONY: pull-verbose
pull-verbose: check-password ## Получить секреты с подробным логированием
	keysloth pull -r $(SECRETS_REPO) -b $(SECRETS_BRANCH) -p "$(SECRET_PASSWORD)" -d $(SECRETS_DIR) --verbose

.PHONY: push-verbose
push-verbose: check-password ## Отправить секреты с подробным логированием
	@read -p "Введите сообщение коммита: " msg; \
	keysloth push -r $(SECRETS_REPO) -b $(SECRETS_BRANCH) -p "$(SECRET_PASSWORD)" -d $(SECRETS_DIR) -m "$$msg" --verbose

.PHONY: version
version: ## Показать версию KeySloth
	keysloth version

# =============================================================================
# CI/CD КОМАНДЫ
# =============================================================================

.PHONY: ci-setup-ssh
ci-setup-ssh: ## Настроить SSH ключи в CI/CD (требует SSH_PRIVATE_KEY)
	@if [ -z "$(SSH_PRIVATE_KEY)" ]; then \
		echo "❌ SSH_PRIVATE_KEY не установлен"; \
		exit 1; \
	fi
	@echo "🔑 Настраиваем SSH ключи для CI/CD..."
	@mkdir -p ~/.ssh
	@echo "$(SSH_PRIVATE_KEY)" > ~/.ssh/id_rsa
	@chmod 600 ~/.ssh/id_rsa
	@ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null || true
	@ssh-keyscan gitlab.com >> ~/.ssh/known_hosts 2>/dev/null || true
	@echo "✅ SSH ключи настроены"

.PHONY: ci-pull
ci-pull: ci-setup-ssh check-password ## Получить секреты в CI/CD среде
	@echo "🤖 CI/CD: Получаем секреты..."
	keysloth pull -r $(SECRETS_REPO) -b $(SECRETS_BRANCH) -p "$(SECRET_PASSWORD)" -d $(SECRETS_DIR) --quiet

.PHONY: ci-validate
ci-validate: ## Проверить секреты в CI/CD среде
	@echo "🤖 CI/CD: Проверяем секреты..."
	keysloth validate -d $(SECRETS_DIR) --quiet

# =============================================================================
# ОЧИСТКА
# =============================================================================

.PHONY: clean
clean: ## Удалить локальные секреты и backup'ы
	@echo "🧹 Очищаем локальные секреты..."
	@rm -rf $(SECRETS_DIR)
	@rm -rf $(SECRETS_DIR)_backup_*
	@echo "✅ Локальные секреты удалены"

.PHONY: clean-docs
clean-docs: ## Удалить сгенерированную документацию
	@echo "🧹 Очищаем документацию..."
	@rm -rf doc/
	@echo "✅ Документация удалена"

# =============================================================================
# ПРИМЕРЫ КОМАНД
# =============================================================================

.PHONY: example-setup
example-setup: ## Пример полной настройки проекта
	@echo "📖 Пример настройки KeySloth в проекте:"
	@echo ""
	@echo "1. Установите переменные окружения:"
	@echo "   export SECRET_PASSWORD=your_strong_password"
	@echo ""
	@echo "2. Инициализируйте проект:"
	@echo "   make init"
	@echo ""
	@echo "3. Добавьте файлы секретов в $(SECRETS_DIR)/"
	@echo ""
	@echo "4. Отправьте секреты в репозиторий:"
	@echo "   make push"
	@echo ""
	@echo "5. Другие участники команды могут получить секреты:"
	@echo "   make pull"

.PHONY: example-ci
example-ci: ## Пример использования в CI/CD
	@echo "📖 Пример настройки в CI/CD:"
	@echo ""
	@echo "GitHub Actions (.github/workflows/deploy.yml):"
	@echo "  env:"
	@echo "    SECRET_PASSWORD: \$${{ secrets.SECRET_PASSWORD }}"
	@echo "    SSH_PRIVATE_KEY: \$${{ secrets.SSH_PRIVATE_KEY }}"
	@echo "  run: |"
	@echo "    make ci-pull"
	@echo "    make ci-validate"
	@echo ""
	@echo "GitLab CI (.gitlab-ci.yml):"
	@echo "  variables:"
	@echo "    SECRET_PASSWORD: \$$SECRET_PASSWORD"
	@echo "    SSH_PRIVATE_KEY: \$$SSH_PRIVATE_KEY"
	@echo "  script:"
	@echo "    - make ci-pull"
	@echo "    - make ci-validate"