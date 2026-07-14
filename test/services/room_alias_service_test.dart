import 'package:flutter_test/flutter_test.dart';
import 'package:orpheus_project/services/room_alias_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final svc = RoomAliasService.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('getAll пустой по умолчанию', () async {
    expect(await svc.getAll(), isEmpty);
  });

  test('setAlias сохраняет и читается через getAll', () async {
    await svc.setAlias('pk1', 'Вася');
    final all = await svc.getAll();
    expect(all['pk1'], 'Вася');
  });

  test('setAlias обрезает пробелы', () async {
    await svc.setAlias('pk1', '  Боб  ');
    final all = await svc.getAll();
    expect(all['pk1'], 'Боб');
  });

  test('setAlias с пустым именем удаляет псевдоним', () async {
    await svc.setAlias('pk1', 'Вася');
    await svc.setAlias('pk1', '   ');
    final all = await svc.getAll();
    expect(all.containsKey('pk1'), isFalse);
  });
}
