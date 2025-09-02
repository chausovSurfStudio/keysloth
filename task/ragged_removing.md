# План отказа от Rugged/libgit2 и переход на системный git

## Текущая проблема
- Использование `Rugged` (libgit2) приводит к частым проблемам:
  - Нужна сборка нативного гема: `cmake`, `libgit2`, `libssh2`, `openssl`, корректный `PKG_CONFIG_PATH`.
  - Неполная сборка без SSH → ошибка `unsupported URL protocol` при `git@...`.
  - Предзагрузка `RUBYOPT=-r rugged` ломает другие ruby-команды до установки гема (`gem install` и т.п.).
- Для пользователей и CI это поднимает порог входа и вызывает нестабильность.

Вывод: переходим на системный `git` (через `Open3`), убираем зависимость от `rugged`.

## Цели
- Исключить `rugged`/`libgit2` и любые шаги по их установке.
- Сохранить поведение `pull`/`push`/ветки/коммиты/cleanup.
- Улучшить DX: всё работает там, где есть стандартный `git` и SSH.

## Таск‑лист миграции
1) Подготовка
- Убедиться, что `keysloth.gemspec` не тянет `rugged` (оставляем как есть, rugged не в зависимостях).
- Создать ветку `feat/system-git`.

2) Реализация системного Git в `KeySloth::GitManager`
- Заменить логику на вызовы системного `git`:
  - clone: `git clone --depth 1 <repo_url> <tmp>` (если ветка не `main`, затем checkout).
  - checkout: `git checkout <branch>` или `git checkout -b <branch> --track origin/<branch>`.
  - ensure up-to-date: `git fetch origin <branch>` + сравнить `git rev-parse HEAD` и `git rev-parse origin/<branch>`; при расхождении — `git pull --ff-only` или ошибка.
  - list .enc: `Dir.glob("**/*.enc", base: tmp)` + `File.read`.
  - clear .enc: `Dir.glob("**/*.enc", base: tmp)` + `File.delete`.
  - write .enc: создать директории, `File.write`.
  - add & commit: `git add -A`, `git commit -m "msg"` (автор из ENV: `GIT_AUTHOR_*`/`GIT_COMMITTER_*` или `-c user.name=... -c user.email=...`).
  - push: `git push origin <branch>`.
- Инкапсулировать выполнение команд в метод: `run_git(cmd, env: {})` с возвратом `[stdout, stderr, status]`, логированием и конвертацией ошибок в `RepositoryError`.
- Сохранить `cleanup` (удаление временной директории).

3) Аутентификация SSH
- По умолчанию использовать стандартный SSH (ssh-agent, `~/.ssh/config`).
- Если заданы `SSH_PRIVATE_KEY`/`SSH_PUBLIC_KEY` (CI):
  - создать временную директорию ключей, записать файлы, `chmod 600`.
  - выставить `GIT_SSH_COMMAND="ssh -i <path> -o StrictHostKeyChecking=no"` для всех git‑команд.
- Опционально поддержать `KEYSLOTH_SSH_KEY_PATH` (если указан — использовать его в `GIT_SSH_COMMAND`).
- Позже: можно добавить поддержку `id_ed25519` в явном виде, но системный `ssh` уже это умеет.

4) Обработка ошибок и логирование
- Для каждой git‑команды логировать: краткое описание, команду, код выхода; при ошибке показывать stderr.
- Генерировать `RepositoryError` с понятным сообщением и советом (проверить доступ/ветку/SSH).

5) Тесты
- Переписать `spec/keysloth/git_manager_spec.rb`:
  - мокать `Open3.capture3` и проверять последовательность вызовов.
  - кейсы: clone/checkout/fetch/pull ok, нет ветки, нет изменений для коммита, запись файлов, push ok, ошибка SSH/доступа, ошибка git.
  - кейсы с `GIT_SSH_COMMAND` и env‑ключами.

6) Документация и примеры
- Обновить `task/test_plan.md`:
  - удалить блок «Важно про Rugged» и шаги `gem install rugged`, `RUBYOPT=-r rugged`.
  - уточнить, что требуется установленный `git` и корректный SSH.
  - поправить пример для push: использовать `git@github.com:...`, а не `ssh@github.com:...`.
- Обновить `README.md`:
  - удалить упоминания rugged и предзагрузки.
  - добавить раздел «Зависимости»: нужен только `git`.
  - в CI‑примере убрать установку rugged и шаг с RUBYOPT, при необходимости показать `GIT_SSH_COMMAND`.
- Добавить запись в `CHANGELOG.md` (0.1.x → 0.1.(x+1)): «Переведён на системный git; удалены инструкции про rugged».

7) Релиз
- Прогнать тесты и линтинг.
- Обновить версию (`lib/keysloth/version.rb`).
- Сформировать gem, smoke‑тест: `pull/push` на чистой машине с только `git`.
- Создать GitHub release.

## Критерии готовности
- `keysloth pull/push` работают без установки rugged/libgit2.
- Все тесты зелёные; покрыт основной happy‑path и ошибки SSH.
- `README.md`/`task/test_plan.md` не содержат упоминаний rugged, примеры актуальны.
- Ошибки `git` отображаются с понятными причинами и советами.

## Согласованные решения
1) Поведение pull
- Выполняем `git fetch origin <branch>` и затем `git pull --ff-only`. При невозможности fast-forward — завершаем с ошибкой с понятным сообщением.

2) Автор коммита
- Требуются глобальные настройки Git: `user.name` и `user.email`. Перед коммитом проверяем их наличие, при отсутствии — ошибка с подсказкой настроить `git config --global`.

3) Приоритет и способ SSH-аутентификации
- Приоритет источников ключей: `KEYSLOTH_SSH_KEY_PATH` → `SSH_PRIVATE_KEY`/`SSH_PUBLIC_KEY` (создаём временные файлы, `chmod 600`) → системные ключи/агент (`~/.ssh`, `ssh-agent`).
- При использовании нестандартных ключей выставляем `GIT_SSH_COMMAND` с вызовом системного `ssh`.

4) Passphrase-ключи
- Поддержка passphrase-ключей не входит в объём. Возможна работа через `ssh-agent` или безфразные ключи.

5) Стратегия клонирования
- По умолчанию используем `git clone --depth 1` (shallow). Если для `pull --ff-only` потребуется история, выполняем однократно `git fetch --unshallow` и повторяем `pull`.
- Предусматриваем переключатель окружения `KEYSLOTH_FULL_CLONE=true` для полного клона при необходимости.

6) Очистка `.enc`
- Очищаем глобально все `**/*.enc` в рабочем дереве перед записью новых файлов. Риски (удаление «чужих» `.enc`, гонки) осознанно принимаются; перед очисткой выполняем `fetch` + `pull --ff-only` для минимизации расхождений.

7) Зависимости и SSH
- Используются стандартные системные инструменты: Git CLI и системный SSH (обычно OpenSSH). Дополнительные нативные библиотеки не требуются.
- В CI при использовании ключей из ENV формируем `GIT_SSH_COMMAND`, например: `ssh -i <path> -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`.
- В локальной разработке проверку хостов не отключаем.

8) Версионирование
- Увеличиваем patch-версию.
