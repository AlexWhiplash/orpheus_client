# Git hooks (orpheus_client)

Этот репозиторий использует локальный путь hooks через `core.hooksPath` (папка `.githooks/`, а не `.git/hooks`).

## Установка (Windows / PowerShell)

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-hooks.ps1
```

Проверить:

```powershell
git config --get core.hooksPath
```

## Что делает pre-commit
Если в индекс (staged) попали изменения кода/конфигов Flutter-клиента, hook требует, чтобы в том же коммите были обновлены:
- `CHANGELOG.md`
- `AI_WORKLOG.md`

Обход (не рекомендуется): `git commit --no-verify`


