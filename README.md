# KeySloth

![SwiftObfuscator](keysloth.png)

Ruby gem для безопасного управления зашифрованными секретами в Git репозиториях.

## Описание

KeySloth решает проблему безопасного хранения и распространения секретов (сертификаты, ключи, конфигурационные файлы) в команде разработки. Вместо хранения секретов напрямую в репозитории, KeySloth шифрует их с использованием AES-256-GCM и позволяет безопасно синхронизировать между участниками команды и CI/CD системами.

### Основные возможности

- 🔐 **Надежное шифрование**: AES-256-GCM с защитой целостности данных
- 🚀 **Простота использования**: Одна команда для получения/отправки секретов
- 🔄 **Git интеграция**: Работает с любыми Git репозиториями через SSH
- 🛡️ **Безопасность**: Многоуровневая защита с SSH ключами и шифрованием
- 📦 **Backup'ы**: Автоматическое создание резервных копий
- 🎯 **CI/CD готовность**: Поддержка переменных окружения для автоматизации

### Типы файлов

Поддерживаются любые типы файлов (сертификаты, конфиги, изображения, бинарные и т.д.).

По умолчанию игнорируются при сборе и шифровании:
- `*.enc` (зашифрованные артефакты в репозитории)
- содержимое `.git/`
- `.DS_Store`, `Thumbs.db`
- локальный `README.md` в директории секретов

## Зависимости

Для работы KeySloth требуются системные инструменты:

- Git CLI (должен быть доступен в PATH)
- SSH-клиент (обычно OpenSSH), используемый через переменную `GIT_SSH_COMMAND`

## Установка

```bash
gem install keysloth
```

Или добавьте в Gemfile:

```ruby
gem 'keysloth'
```

## Быстрый старт

### 1. Получение секретов

```bash
keysloth pull -r git@github.com:company/secrets.git -p your_password
```

### 2. Отправка секретов

```bash
keysloth push -r git@github.com:company/secrets.git -p your_password -m "Update certificates"
```

### 3. Проверка состояния

```bash
keysloth status
```

## Использование

### Команды

#### pull - Получение секретов

Получает зашифрованные секреты из Git репозитория и расшифровывает их локально:

```bash
keysloth pull --repo git@github.com:company/secrets.git \
              --password your_secret_password \
              --branch main \
              --path ./secrets
```

**Параметры:**
- `--repo, -r` - URL Git репозитория (обязательно)
- `--password, -p` - Пароль для расшифровки (обязательно) 
- `--branch, -b` - Ветка репозитория (по умолчанию: main)
- `--path, -d` - Локальный путь для секретов (по умолчанию: ./secrets)

#### push - Отправка секретов

Шифрует локальные секреты и отправляет их в Git репозиторий:

```bash
keysloth push --repo git@github.com:company/secrets.git \
              --password your_secret_password \
              --message "Update mobile certificates" \
              --branch main \
              --path ./secrets
```

**Параметры:**
- `--repo, -r` - URL Git репозитория (обязательно)
- `--password, -p` - Пароль для шифрования (обязательно)
- `--branch, -b` - Ветка репозитория (по умолчанию: main)
- `--path, -d` - Локальный путь с секретами (по умолчанию: ./secrets)
- `--message, -m` - Сообщение коммита (опционально)

#### status - Проверка состояния

Показывает информацию о локальных секретах и доступных backup'ах:

```bash
keysloth status --path ./secrets
# без --path возьмёт путь из .keyslothrc (или дефолт)
```

#### restore - Восстановление из backup'а

Восстанавливает секреты из резервной копии:

```bash
keysloth restore secrets_backup_20231215_143022 --path ./secrets
# без --path возьмёт путь из .keyslothrc (или дефолт)
```

### Конфигурационный файл

KeySloth поддерживает файл конфигурации `.keyslothrc` в формате YAML:

```yaml
# .keyslothrc
repo_url: "git@github.com:company/secrets.git"
branch: "main"
local_path: "./secrets"
backup_count: 3
```

Параметры командной строки имеют приоритет над конфигурационным файлом.

Дополнительно: файл конфигурации ищется автоматически, если путь не указан флагом `--config`:
- сначала в текущей директории (`./.keyslothrc`)
- затем в домашней директории (`~/.keyslothrc`)

Дефолтные значения при отсутствии флагов CLI и отсутствующих полях в конфиге:
- `branch`: `main`
- `local_path`: `./secrets`
- `backup_count`: `3`
- `repo_url`: отсутствует (должен быть указан явно через CLI или в конфиге)

### Логирование

KeySloth поддерживает три уровня логирования:

```bash
# Подробное логирование (DEBUG)
keysloth pull -r repo_url -p password --verbose

# Тихий режим (только ошибки)
keysloth pull -r repo_url -p password --quiet

# Обычное логирование (INFO) - по умолчанию
keysloth pull -r repo_url -p password
```

## Безопасность

### Архитектура безопасности

KeySloth обеспечивает многоуровневую защиту:

1. **SSH аутентификация** - доступ к репозиторию только через SSH ключи
2. **AES-256-GCM шифрование** - надежное шифрование с защитой целостности
3. **PBKDF2 деривация ключей** - безопасная генерация ключей из паролей
4. **Зашифрованное хранение** - секреты хранятся зашифрованными в репозитории

### Настройка SSH ключей

#### Локальная работа

Используйте стандартные SSH ключи:

```bash
# Генерируем SSH ключ если нет
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"   # RSA
# или современный вариант:
ssh-keygen -t ed25519 -C "your_email@example.com"       # Ed25519

# Добавляем публичный ключ в GitHub/GitLab
cat ~/.ssh/id_rsa.pub
# или
cat ~/.ssh/id_ed25519.pub
```

#### CI/CD настройка

Для автоматизации используйте переменные окружения:

```bash
# Экспортируем SSH ключ в переменную окружения
export SSH_PRIVATE_KEY="$(cat ~/.ssh/id_rsa)"            # может быть RSA или Ed25519
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"        # опционально

# Используем в CI/CD
keysloth pull -r git@github.com:company/secrets.git -p $SECRET_PASSWORD
```

#### Использование системного SSH (GIT_SSH_COMMAND)

При использовании ключей из переменных окружения в CI создаются временные файлы ключей и применяется `GIT_SSH_COMMAND`, например:

```bash
export GIT_SSH_COMMAND='ssh -i /tmp/keysloth_ssh/id_rsa -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
```

Для локальной разработки отключать проверку хостов не рекомендуется.

Также можно явно указать путь к ключу через переменную окружения `KEYSLOTH_SSH_KEY_PATH` (поддерживаются как RSA, так и Ed25519):

```bash
export KEYSLOTH_SSH_KEY_PATH="~/.ssh/id_ed25519"
```

#### Требования к автору коммита

Перед отправкой изменений должны быть настроены глобальные параметры Git:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

#### Поведение git-операций

- Клонирование по умолчанию: `git clone --depth 1` (shallow).
- Если `git pull --ff-only` требует историю, выполняется `git fetch --unshallow`, затем повтор `pull`.
- Перед записью новых файлов очищаются все `.enc` в репозитории: `**/*.enc`.

### Рекомендации по безопасности

1. **Сильные пароли**: Используйте пароли длиной минимум 16 символов
2. **Ротация ключей**: Регулярно обновляйте SSH ключи и пароли шифрования
3. **Ограниченный доступ**: Предоставляйте доступ к репозиторию только необходимым участникам
4. **Аудит**: Регулярно проверяйте логи доступа к репозиторию
5. **Backup'ы**: Используйте автоматические backup'ы для восстановления

## Интеграция с CI/CD

### GitHub Actions

```yaml
name: Deploy with Secrets
on: [push]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup SSH key
        env:
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan github.com >> ~/.ssh/known_hosts
      
      - name: Install KeySloth
        run: gem install keysloth
      
      - name: Pull secrets
        env:
          SECRET_PASSWORD: ${{ secrets.SECRET_PASSWORD }}
        run: |
          keysloth pull -r git@github.com:company/secrets.git -p "$SECRET_PASSWORD"
      
      - name: Deploy application
        run: |
          # Используем расшифрованные секреты для развертывания
          ./deploy.sh
```

### GitLab CI

```yaml
deploy:
  stage: deploy
  before_script:
    - gem install keysloth
    - mkdir -p ~/.ssh
    - echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
    - chmod 600 ~/.ssh/id_rsa
    - ssh-keyscan gitlab.com >> ~/.ssh/known_hosts
  script:
    - keysloth pull -r git@gitlab.com:company/secrets.git -p "$SECRET_PASSWORD"
    - ./deploy.sh
  variables:
    SSH_PRIVATE_KEY: $SSH_PRIVATE_KEY
    SECRET_PASSWORD: $SECRET_PASSWORD
```

## Разработка

### Установка для разработки

```bash
git clone https://github.com/keysloth/keysloth.git
cd keysloth
bundle install
```

### Запуск тестов

```bash
# Все тесты
bundle exec rake spec

# Тесты с покрытием кода
COVERAGE=true bundle exec rake spec

# Линтинг кода
bundle exec rake rubocop

# Все проверки
bundle exec rake check
```

### Структура проекта

```
keysloth/
├── lib/keysloth/           # Основная логика
│   ├── crypto.rb          # Криптографические операции
│   ├── git_manager.rb     # Работа с Git
│   ├── file_manager.rb    # Файловые операции
│   ├── cli.rb             # CLI интерфейс
│   ├── config.rb          # Конфигурация
│   ├── logger.rb          # Логирование
│   └── errors.rb          # Обработка ошибок
├── bin/keysloth           # Исполняемый файл
├── spec/                  # Тесты RSpec
└── keysloth.gemspec       # Спецификация gem'а
```

## Лицензия

MIT License. См. [LICENSE](LICENSE) для деталей.

## Поддержка

- **Документация**: [GitHub Wiki](https://github.com/keysloth/keysloth/wiki)
- **Issues**: [GitHub Issues](https://github.com/keysloth/keysloth/issues)
- **Обсуждения**: [GitHub Discussions](https://github.com/keysloth/keysloth/discussions)

## Troubleshooting

### Часто встречающиеся проблемы

#### Ошибки аутентификации Git

**Проблема**: `Permission denied (publickey)` при выполнении pull/push

**Решение**:
```bash
# Проверьте SSH ключи
ssh-add -l

# Добавьте SSH ключ если необходимо
ssh-add ~/.ssh/id_rsa
# или
ssh-add ~/.ssh/id_ed25519

# Проверьте соединение с GitHub/GitLab
ssh -T git@github.com
ssh -T git@gitlab.com
```

#### Ошибки расшифровки

**Проблема**: `Неверный пароль или поврежденные данные`

**Решение**:
1. Проверьте правильность пароля
2. Убедитесь что файлы не повреждены: `keysloth validate`
3. Попробуйте восстановить из backup'а: `keysloth restore`

#### Ошибки файловой системы

**Проблема**: `Permission denied` при создании/чтении файлов

**Решение**:
```bash
# Проверьте права доступа к директории
ls -la ./secrets

# Измените права если необходимо
chmod 755 ./secrets
chmod 644 ./secrets/*
```

#### Проблемы с Git репозиторием

**Проблема**: `Repository not found` или `Could not read from remote repository`

**Решение**:
1. Проверьте URL репозитория
2. Убедитесь что у вас есть доступ к репозиторию
3. Для приватных репозиториев проверьте SSH ключи

#### Ошибки в CI/CD

**Проблема**: Команды KeySloth не работают в CI/CD

**Решение**:
```yaml
# Настройка SSH ключей в GitHub Actions
- name: Setup SSH key
  env:
    SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
  run: |
    mkdir -p ~/.ssh
    echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
    chmod 600 ~/.ssh/id_rsa
    ssh-keyscan github.com >> ~/.ssh/known_hosts

# Установка gem'а
- name: Install KeySloth
  run: gem install keysloth

# Использование с переменными окружения
- name: Pull secrets
  env:
    SECRET_PASSWORD: ${{ secrets.SECRET_PASSWORD }}
  run: keysloth pull -r $REPO_URL -p "$SECRET_PASSWORD"
```

#### Логирование для отладки

Используйте различные уровни логирования для диагностики:

```bash
# Подробное логирование для отладки
keysloth pull -r repo_url -p password --verbose

# Тихий режим для CI/CD
keysloth pull -r repo_url -p password --quiet
```

#### Backup и восстановление

При проблемах с секретами используйте backup'ы:

```bash
# Посмотреть доступные backup'ы
keysloth status

# Восстановить из backup'а
keysloth restore secrets_backup_20231215_143022
```

### Получение помощи

Если проблема не решается:

1. **Проверьте логи** с флагом `--verbose`
2. **Создайте минимальный пример** для воспроизведения
3. **Откройте issue** в [GitHub Issues](https://github.com/keysloth/keysloth/issues) с:
   - Версией KeySloth (`keysloth version`)
   - Версией Ruby (`ruby --version`)
   - Полным текстом ошибки
   - Шагами для воспроизведения

## Changelog

См. [CHANGELOG.md](CHANGELOG.md) для истории изменений.