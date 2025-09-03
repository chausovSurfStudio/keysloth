### Чек‑лист релиза

Краткий, практичный список шагов для публикации и релиза `KeySloth`.

#### 1) Подготовка версии
- [ ] Обновить версию в `lib/keysloth/version.rb` (SemVer)
- [ ] Обновить `CHANGELOG.md` (секция для новой версии)
- [ ] Проверить `keysloth.gemspec`: `summary`, `description`, `authors`, `email`, `license`, `required_ruby_version`, `homepage`
- [ ] Добавить/актуализировать `metadata` (включая требование MFA):
```ruby
spec.metadata = {
  "homepage_uri" => "https://github.com/chausovSurfStudio/keysloth",
  "source_code_uri" => "https://github.com/chausovSurfStudio/keysloth",
  "changelog_uri" => "https://github.com/chausovSurfStudio/keysloth/blob/main/CHANGELOG.md",
  "documentation_uri" => "https://chausovSurfStudio.github.io/keysloth/",
  "rubygems_mfa_required" => "true"
}
```

#### 2) Публикация на RubyGems.org
- [ ] Создать аккаунт/включить 2FA (MFA) на RubyGems
- [ ] Сгенерировать API‑ключ и экспортировать его в окружение
```bash
export GEM_HOST_API_KEY=rg_********************************
```
- [ ] Собрать и проверить пакет
```bash
gem build keysloth.gemspec
gem check keysloth-<VERSION>.gem
```
- [ ] Отправить пакет
```bash
gem push keysloth-<VERSION>.gem
```
- [ ] Проверить страницу gem’a: `https://rubygems.org/gems/keysloth`
- [ ] (Опционально) Добавить совладельцев
```bash
gem owner keysloth --add teammate@example.com
```
- [ ] (Опционально) Отозвать версию (rollback)
```bash
gem yank keysloth -v <VERSION>
```

#### 3) Git‑тег и GitHub Release
- [ ] Создать и запушить тег
```bash
git tag -a v<VERSION> -m "Release v<VERSION>"
git push origin v<VERSION>
```
- [ ] Создать релиз (через GitHub UI)

#### 4) Валидация после релиза
- [ ] Проверить, что страница на RubyGems отображает новую версию
- [ ] Проверить установку:
```bash
gem install keysloth -v <VERSION>
keysloth version
keysloth help
```
- [ ] Прогнать быстрый сценарий использования (минимальный pull в тестовый каталог)

#### 5) Rollback (при необходимости)
- [ ] Отозвать версию gem’a:
```bash
gem yank keysloth -v <VERSION>
```
- [ ] Удалить GitHub Release и тег (или выпустить hotfix)

#### 6) Мини‑чек‑лист
- [ ] Обновить версию и changelog
- [ ] Собрать и запушить gem в RubyGems
- [ ] Создать git‑тег и GitHub Release
- [ ] Обновить/опубликовать документацию
- [ ] Обновить/добавить примеры CI/CD


