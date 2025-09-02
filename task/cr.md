# Change Request: Поддержка SSH ключей id_ed25519 и улучшение UX

## Контекст проблемы
При запуске команды (например, `keysloth pull`) возникла ошибка:

```
Ошибка выполнения операции: SSH ключ не найден: /Users/<user>/.ssh/id_rsa
```

Причина: в `KeySloth::GitManager#create_ssh_credentials` по умолчанию ожидаются ключи формата RSA (`~/.ssh/id_rsa` и `~/.ssh/id_rsa.pub`). На машине пользователя используются ключи Ed25519 (`id_ed25519`, `id_ed25519.pub`).

## Временные решения (workarounds)
1. Использовать ключи из переменных окружения (подходит для локали и CI/CD):
```bash
export SSH_PRIVATE_KEY="$(cat ~/.ssh/id_ed25519)"
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_ed25519.pub)"
keysloth pull -r git@github.com:USER/REPO.git -p "PASSWORD"
```

2. Создать симлинки под ожидаемые имена (быстро, локально):
```bash
ln -s ~/.ssh/id_ed25519 ~/.ssh/id_rsa
ln -s ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub
```

3. Сгенерировать отдельный RSA‑ключ (если принципиально):
```bash
ssh-keygen -t rsa -b 4096 -C "you@example.com" -f ~/.ssh/id_rsa
# добавить ~/.ssh/id_rsa.pub в GitHub/GitLab
```

## Предложения по доработке
1. Поддержать Ed25519 «из коробки» в `create_ssh_credentials`:
   - Приоритет: переменные окружения `SSH_PRIVATE_KEY`/`SSH_PUBLIC_KEY` (как сейчас).
   - Fallback: искать пары ключей по стандартным путям в порядке:
     - `~/.ssh/id_rsa(.pub)`
     - `~/.ssh/id_ed25519(.pub)`
   - Если пара найдена — использовать; иначе выбрасывать `AuthenticationError` с подсказками.

2. Добавить конфигурируемый путь к ключу:
   - Env: `KEYSLOTH_SSH_KEY_PATH` (если задан — использовать `<path>` и `<path>.pub`).
   - Опция CLI: `--ssh-key PATH` (пробрасывать в `GitManager`).

3. Рассмотреть поддержку ssh-agent:
   - Использовать `Rugged::Credentials::SshKeyFromAgent` при отсутствии файлов и env.

4. Улучшить сообщение об ошибке:
   - Печатать проверённые пути, быстрые шаги: env, симлинк, `--ssh-key`.

## Тестирование
- Добавить тесты в `spec/keysloth/git_manager_spec.rb`:
  - только `id_rsa`
  - только `id_ed25519`
  - ключи через ENV
  - путь через `KEYSLOTH_SSH_KEY_PATH`
  - отсутствие ключей → `AuthenticationError`

## Документация
- Обновить README (раздел «Настройка SSH ключей») и `task/test_plan.md` (раздел про SSH) с примерами для Ed25519 и `--ssh-key`/env.
