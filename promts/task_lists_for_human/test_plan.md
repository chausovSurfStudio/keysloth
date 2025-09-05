# Test plan: Проверка работы gem KeySloth (шаг за шагом, как для новичка)

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
# перейдите в папку проекта
cd keysloth
bundle install
```

## 2. Запуск локальных проверок (по желанию)
```bash
# Тесты
bundle exec rake spec

## 3. Сборка и локальная установка gem
```bash
gem build keysloth.gemspec
gem install ./keysloth-0.2.0.gem  # подставить текущую версию вместо 0.2.0

# Проверка установки и базовых команд
keysloth version
keysloth help
```

### Требования к Git/SSH
Инструмент использует системный Git и SSH. Убедитесь, что установлены и доступны из PATH:
```bash
git --version
ssh -V
```

## 4. Подготовка тестового удалённого репозитория (SSH)
- Создайте приватный репозиторий, например `keysloth-secrets-test`.
- Выберите «Add a README» при создании, чтобы в репозитории сразу была ветка `main`

## 5. Подготовка рабочего каталога и начальной конфигурации
```bash
mkdir -p ~/tmp/keysloth-playground
cd ~/tmp/keysloth-playground

# Инициализация проекта под KeySloth (создаст .keyslothrc, директорию секретов, обновит .gitignore)
# Этот и остальные шаги этого пункта ниже - делать только если репозиторий в пункте 4 до этого ни разу не создавался
keysloth init -r git@github.com:chausovSurfStudio/keysloth-secrets-test.git -b main -d ./secrets

# Проверим, что создалось
cat .keyslothrc
cat .gitignore
```

Ожидаемо: `.keyslothrc` содержит `repo_url`, `branch`, `local_path`; в `.gitignore` добавлены `secrets/` и `.keyslothrc`.

## 6. Подготовка тестовых «секретов»
Создать/скопировать в заранее подготовленную папку набор необходимых "серкретов"

## 7. Первая отправка секретов (push)
```bash
export SECRET_PASSWORD="SOME_STRONG_PASSWORD_16+"

keysloth push -v \
  -r git@github.com:chausovSurfStudio/keysloth-secrets-test.git \
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
  -r git@github.com:chausovSurfStudio/keysloth-secrets-test.git \
  -p "$SECRET_PASSWORD" \
  -b main \
  -d ./secrets
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
  keysloth pull -r git@github.com:chausovSurfStudio/keysloth-secrets-test.git -p WRONGPASS -b main -d ./secrets
  # Ожидаемо: ошибка дешифровки, ненулевой код выхода
  ```
- Несуществующая ветка:
  ```bash
  keysloth pull -r git@github.com:chausovSurfStudio/keysloth-secrets-test.git -p "$SECRET_PASSWORD" -b no_such_branch -d ./secrets
  # Ожидаемо: ошибка «ветка не найдена»/«не синхронизирована»
  ```
- Пустая/отсутствующая директория при push:
  ```bash
  keysloth push -r git@github.com:chausovSurfStudio/keysloth-secrets-test.git -p "$SECRET_PASSWORD" -d ./nope
  # Ожидаемо: ошибка файловой системы
  ```
- Проблемы SSH (нет доступа):
  ```bash
  keysloth pull -r git@github.com:chausovSurfStudio/private_no_access.git -p "$SECRET_PASSWORD"
  # Ожидаемо: ошибка аутентификации/доступа
  ```

## 13. Глобальные флаги логирования
```bash
# Подробный вывод
keysloth pull -r git@github.com:chausovSurfStudio/keysloth-secrets-test.git -p "$SECRET_PASSWORD" --verbose

# Тихий режим (только ошибки)
keysloth pull -r git@github.com:chausovSurfStudio/keysloth-secrets-test.git -p "$SECRET_PASSWORD" --quiet
```

## 14. Работа через .keyslothrc (минимум аргументов)
После `keysloth init` можно опускать `--repo`, `--branch`, `--path`:
```bash
keysloth pull -p "$SECRET_PASSWORD"
keysloth push -p "$SECRET_PASSWORD" -m "update via rc"
```

## 15. Завершение и очистка
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


