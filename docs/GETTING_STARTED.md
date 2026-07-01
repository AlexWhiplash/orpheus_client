# Orpheus Client — установка и запуск

## Требования
- Flutter SDK 3.44.x (проект разрабатывается на 3.44.4, канал stable). В `pubspec.yaml` → `environment`
  зафиксирован только Dart SDK (`>=3.0.0 <4.0.0`).
- Android SDK / Android Studio (для запуска на Android)

## Установка зависимостей

```powershell
flutter pub get
```

## Запуск

```powershell
flutter run
```

## Быстрые проверки

### Запуск тестов

```powershell
flutter test
```

### Быстрый прогон без отчётов

```powershell
.\quick_test.ps1
```

### Прогон с выводом отчёта в консоль

```powershell
.\test_runner.ps1
```

Показывает форматированную сводку в консоли (файлы не создаёт).

### Прогон с сохранением отчёта в файл

```powershell
.\test_runner_clean.ps1
```

Сохраняет отчёт в `test_reports/clean_report_<дата-время>.txt` (папка создаётся автоматически).



