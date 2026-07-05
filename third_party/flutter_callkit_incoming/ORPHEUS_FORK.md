# Orpheus fork of flutter_callkit_incoming

**База upstream:** `3.1.3` (pub.dev: https://pub.dev/packages/flutter_callkit_incoming)

Локальная копия (vendored) подключена через `dependency_overrides` в корневом
`pubspec.yaml`. Папка `example/` удалена ради размера — на работу плагина не влияет.

## Зачем форк

При ответе на звонок на ЗАБЛОКИРОВАННОМ телефоне плагин звал
`KeyguardManager.requestDismissKeyguard()`, что на secure-устройствах (особенно
Samsung One UI) жёстко выкидывало пользователя на системный PIN — ответить было
невозможно. Показ окна звонка поверх локскрина мы делаем сами в хост-приложении
(`MainActivity.setShowWhenLocked` в `onStart`/`onNewIntent`/`onCreate` по флагу
активного звонка из `CallIdStorage`), поэтому вызов плагина здесь лишний и вреден.

## Единственное отличие от upstream 3.1.3

Файл: `android/src/main/kotlin/com/hiennv/flutter_callkit_incoming/CallkitIncomingActivity.kt`

В методе `onAcceptClick()` УДАЛЁН вызов `dismissKeyguard()` (сам метод `dismissKeyguard()`
оставлен нетронутым — просто больше не вызывается). Всё остальное идентично upstream.

```
 startActivity(acceptIntent)
-dismissKeyguard()          // <- удалено (ORPHEUS FORK)
 finish()
```

## Как обновляться, когда выйдет новая версия upstream

1. Проверить, есть ли новая версия: `flutter pub outdated` (см. строку
   `flutter_callkit_incoming` — колонки Resolvable/Latest) или `tool/check_callkit_fork.ps1`.
2. Прочитать CHANGELOG новой версии на pub.dev.
3. Скачать новую версию в pub cache: временно убрать `dependency_overrides`, поднять
   `^X.Y.Z` в `dependencies`, `flutter pub get` — версия окажется в
   `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\flutter_callkit_incoming-X.Y.Z`.
4. Скопировать её в `third_party/flutter_callkit_incoming` (удалить `example/`).
5. ЗАНОВО применить правку выше: удалить `dismissKeyguard()` в `onAcceptClick()`.
6. Вернуть `dependency_overrides` на path, обновить «База upstream» в этом файле.
7. `flutter pub get` + пересборка + **device-тест ответа на заблокированном (Samsung И Pixel)**.

## Проверка на обновление при релизе

`tool/check_callkit_fork.ps1` сравнивает `FORK_BASE_VERSION` (см. ниже) с последней
версией на pub.dev и предупреждает, если upstream ушёл вперёд. Запускается вручную
и (опционально) из pre-commit хука на бампе версии приложения.

`FORK_BASE_VERSION=3.1.3`
