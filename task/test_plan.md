# Test plan: Проверка работы gem KeySloth (шаг за шагом для новичка)

## Цели
- Подтвердить, что все основные команды работают: `init`, `pull`, `push`, `status`, `validate`, `restore`, `version`, `help`.
- Проверить успешные и ошибочные сценарии.
- Пройти путь «с нуля»: установка Ruby/gem, подготовка SSH, тестовый репозиторий, локальная установка и запуск.

## 0. Предпосылки и требования
- macOS/Linux с установленными:
  - Git: `git --version`
  - OpenSSL: `openssl version`
  - Ruby 2.7+: `ruby -v` (если нет — установите через rbenv/asdf/Homebrew)
  - Bundler/Rake: `gem install bundler rake`
- SSH доступ к Git-хостингу (GitHub/GitLab). Убедитесь, что ключи работают:
  ```bash
  ssh -T git@github.com       # или git@gitlab.com
  ```

## 1. Клонирование проекта и установка зависимостей
```bash
git clone https://github.com/keysloth/keysloth.git  # если локально — просто перейдите в папку проекта
cd keysloth
bundle install
```

## 2. Запуск локальных проверок (по желанию)
```bash
# Тесты
bundle exec rake spec

# Линтинг
bundle exec rake rubocop
```

## 3. Сборка и локальная установка gem
```bash
gem build keysloth.gemspec
gem install ./keysloth-0.1.0.gem

# Проверка установки и базовых команд
keysloth version
keysloth help
```

### Важно про Rugged (доступ к Git через libgit2)
В текущей версии используется API `Rugged` в `git_manager`. Чтобы избежать ошибки `uninitialized constant Rugged`, добавьте предзагрузку:
```bash
gem install rugged
export RUBYOPT="-r rugged"
```
(Это временная предзагрузка библиотеки без изменения кода.)

## 4. Подготовка тестового удалённого репозитория (SSH)
Вариант A (GitHub через веб-интерфейс):
- Создайте приватный репозиторий, например `keysloth-secrets-test`.
- Выберите «Add a README» при создании, чтобы в репозитории сразу была ветка `main`.

Вариант B (через локальный git и push):
```bash
mkdir -p ~/tmp/keysloth-secrets-remote
cd ~/tmp/keysloth-secrets-remote
git init
echo "# secrets" > README.md
git add README.md
git commit -m "init"
git branch -M main
git remote add origin git@github.com:<YOUR_USER>/keysloth-secrets-test.git
git push -u origin main
```

Проверьте доступ по SSH:
```bash
ssh -T git@github.com
```

## 5. Подготовка рабочего каталога и начальной конфигурации
```bash
mkdir -p ~/tmp/keysloth-playground
cd ~/tmp/keysloth-playground

# Инициализация проекта под KeySloth (создаст .keyslothrc, директорию секретов, обновит .gitignore)
keysloth init -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git -b main -d ./secrets

# Проверим, что создалось
cat .keyslothrc
cat .gitignore
```

Ожидаемо: `.keyslothrc` содержит `repo_url`, `branch`, `local_path`; в `.gitignore` добавлены `secrets/` и `.keyslothrc`.

## 6. Подготовка тестовых «секретов»
Создадим набор файлов разных типов, поддерживаемых инструментом:
```bash
mkdir -p secrets/certificates secrets/config

# JSON
cat > secrets/config/app.json << 'JSON'
{
  "apiKey": "demo-123",
  "endpoint": "https://api.example.com",
  "featureFlags": {"newUI": true}
}
JSON

# CER (PEM)
cat > secrets/certificates/dev.cer << 'CER'
-----BEGIN CERTIFICATE-----
MIIBkTCB+wI...FAKE...FOR...TEST...
-----END CERTIFICATE-----
CER

# P12 (минимальный валидный заголовок: первый байт 0x30)
printf "\x30\x82\x05\x10\x02\x01\x03\x30" > secrets/certificates/dev.p12

# Mobile provisioning (XML/plist признак)
echo '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"></plist>' > secrets/dev.mobileprovisioning
```

## 7. Первая отправка секретов (push)
```bash
export SECRET_PASSWORD="SOME_STRONG_PASSWORD_16+"

keysloth push \
  -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git \
  -p "$SECRET_PASSWORD" \
  -b main \
  -d ./secrets \
  -m "init secrets"
```

Ожидаемо: в удалённом репозитории появятся зашифрованные файлы с расширением `.enc`, структура директорий сохранится.

Проверьте на хостинге (GitHub/GitLab) наличие `*.enc`.

## 8. Получение секретов (pull)
Очистим локальные файлы и попробуем скачать и расшифровать:
```bash
rm -rf ./secrets

keysloth pull \
  -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git \
  -p "$SECRET_PASSWORD" \
  -b main \
  -d ./secrets

# Проверим содержимое
ls -la ./secrets ./secrets/certificates
cat ./secrets/config/app.json
```

Ожидаемо: файлы восстановлены и читаемы.

## 9. Проверка status
```bash
keysloth status -d ./secrets
```
Ожидаемо: отображается список найденных файлов, размеры, список доступных бэкапов (если есть).

## 10. Проверка validate (целостность)
```bash
keysloth validate -d ./secrets
```
Ожидаемо: все файлы «валидны»; завершение с кодом 0.

## 11. Проверка backup и restore
1) Сымитируем порчу файла и увидим ошибку в validate:
```bash
truncate -s 0 ./secrets/config/app.json
keysloth validate -d ./secrets || echo "validate failed (как и ожидалось)"
```

2) Посмотрим доступные бэкапы и восстановим:
```bash
keysloth status -d ./secrets   # именa бэкапов вида secrets_backup_YYYYMMDD_HHMMSS

# Пример восстановления (подставьте своё имя каталога бэкапа из вывода status)
keysloth restore ./secrets_backup_YYYYMMDD_HHMMSS -d ./secrets

keysloth validate -d ./secrets
```

## 12. Негативные сценарии (проверка ошибок)
- Неверный пароль при pull:
  ```bash
  keysloth pull -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git -p WRONGPASS -b main -d ./secrets
  # Ожидаемо: ошибка дешифровки, ненулевой код выхода
  ```
- Несуществующая ветка:
  ```bash
  keysloth pull -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git -p "$SECRET_PASSWORD" -b no_such_branch -d ./secrets
  # Ожидаемо: ошибка «ветка не найдена»/«не синхронизирована»
  ```
- Пустая/отсутствующая директория при push:
  ```bash
  keysloth push -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git -p "$SECRET_PASSWORD" -d ./nope
  # Ожидаемо: ошибка файловой системы
  ```
- Проблемы SSH (нет доступа):
  ```bash
  keysloth pull -r git@github.com:<YOUR_USER>/private_no_access.git -p "$SECRET_PASSWORD"
  # Ожидаемо: ошибка аутентификации/доступа
  ```

## 13. Глобальные флаги логирования
```bash
# Подробный вывод
keysloth pull -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git -p "$SECRET_PASSWORD" --verbose

# Тихий режим (только ошибки)
keysloth pull -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git -p "$SECRET_PASSWORD" --quiet
```

## 14. Работа через .keyslothrc (минимум аргументов)
После `keysloth init` можно опускать `--repo`, `--branch`, `--path`:
```bash
keysloth pull -p "$SECRET_PASSWORD"
keysloth push -p "$SECRET_PASSWORD" -m "update via rc"
```

## 15. Минимальная проверка в CI/CD (GitHub Actions пример)
Создайте секреты репозитория: `SSH_PRIVATE_KEY`, `SECRET_PASSWORD`. Затем workflow:
```yaml
name: KeySloth smoke
on: [workflow_dispatch]
jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2'
      - name: Setup SSH key
        env:
          SSH_PRIVATE_KEY: ${{ secrets.SSH_PRIVATE_KEY }}
        run: |
          mkdir -p ~/.ssh
          echo "$SSH_PRIVATE_KEY" > ~/.ssh/id_rsa
          chmod 600 ~/.ssh/id_rsa
          ssh-keyscan github.com >> ~/.ssh/known_hosts
      - name: Install KeySloth
        run: gem install keysloth rugged
      - name: Preload rugged
        run: echo "RUBYOPT=-r rugged" >> $GITHUB_ENV
      - name: Pull secrets
        env:
          SECRET_PASSWORD: ${{ secrets.SECRET_PASSWORD }}
        run: |
          keysloth pull -r git@github.com:<YOUR_USER>/keysloth-secrets-test.git -p "$SECRET_PASSWORD"
```

## 16. Завершение и очистка
```bash
# Опционально удалить установленный gem локально
gem uninstall keysloth -aIx

# Удалить рабочие каталоги
rm -rf ~/tmp/keysloth-playground ~/tmp/keysloth-secrets-remote
```

## Чек-лист «что должно сработать»
- `gem build` и `gem install` проходят без ошибок; `keysloth version`/`help` работают.
- `push` создаёт `*.enc` в удалённом репозитории; `pull` восстанавливает исходные файлы.
- `status` показывает файлы и бэкапы; `validate` подтверждает целостность.
- `restore` возвращает корректные файлы из бэкапа.
- Негативные сценарии приводят к понятным ошибкам и ненулевому коду выхода.


