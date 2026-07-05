# Проверяет, не вышла ли новая версия flutter_callkit_incoming на pub.dev по
# сравнению с нашей вендоренной базой (third_party/flutter_callkit_incoming).
# Возвращает exit 0 если мы на актуальной базе, exit 1 если upstream ушёл вперёд.
# Запуск: pwsh tool/check_callkit_fork.ps1  (или из pre-commit хука на бампе версии).

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$forkDoc = Join-Path $repo 'third_party/flutter_callkit_incoming/ORPHEUS_FORK.md'

if (-not (Test-Path $forkDoc)) {
    Write-Host "ORPHEUS_FORK.md не найден — форк не вендорен?" -ForegroundColor Yellow
    exit 1
}

$m = Select-String -Path $forkDoc -Pattern 'FORK_BASE_VERSION=([0-9]+\.[0-9]+\.[0-9]+)'
if (-not $m) { Write-Host "FORK_BASE_VERSION не найден в ORPHEUS_FORK.md" -ForegroundColor Red; exit 1 }
$base = $m.Matches[0].Groups[1].Value

try {
    $resp = Invoke-RestMethod -Uri 'https://pub.dev/api/packages/flutter_callkit_incoming' -TimeoutSec 20
    $latest = $resp.latest.version
} catch {
    Write-Host "Не удалось получить версию с pub.dev: $($_.Exception.Message)" -ForegroundColor Yellow
    exit 0  # сеть недоступна — не блокируем
}

Write-Host "flutter_callkit_incoming: форк базы = $base, pub.dev latest = $latest"

if ([version]$latest -gt [version]$base) {
    Write-Host ""
    Write-Host "!! Вышла новая версия upstream ($latest > $base)." -ForegroundColor Yellow
    Write-Host "   Переприменить форк по инструкции: third_party/flutter_callkit_incoming/ORPHEUS_FORK.md" -ForegroundColor Yellow
    exit 1
}

Write-Host "Форк на актуальной базе upstream." -ForegroundColor Green
exit 0
