import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onyx_mobile/core/effect_catalog.dart';
import 'package:onyx_mobile/onyx_controller.dart';
import 'package:onyx_mobile/ui/app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late EffectCatalog catalog;
  setUpAll(() async {
    catalog = await EffectCatalog.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('welcome, demo editing, save confirmation and native app tabs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = OnyxController(catalog: catalog)..setLiveSync(false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(OnyxApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('작은 앰프,\n더 넓은 가능성.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('start-demo')).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Amber Clean'), findsOneWidget);
    expect(find.text('데모 · 소리는 출력되지 않습니다'), findsOneWidget);
    final gain = find.byKey(const ValueKey('slider-GAIN'));
    tester.widget<Slider>(gain).onChanged!(91);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-tone')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '저장'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.state!.effect(2).knobs[0], 91);
    await tester.tap(find.text('설정').last);
    await tester.pumpAndSettle();
    expect(find.text('앰프 설정'), findsOneWidget);
    await tester.tap(find.text('연주').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-groove')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.state!.groovePlaying, isTrue);
    await tester.tap(find.text('NAM·IR').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-ir')), findsOneWidget);
    await tester.tap(find.text('프리셋').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('read-presets')));
    await tester.pumpAndSettle();
    expect(controller.bank!.readableCount, 80);
    await tester.ensureVisible(find.byKey(const ValueKey('restore-range')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('restore-range')), '1-3');
    await tester.tap(find.widgetWithText(OutlinedButton, '선택'));
    await tester.pumpAndSettle();
    expect(find.text('3개 복원·검증'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('restore-presets')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(1024, 1366),
  ]) {
    testWidgets('all tabs fit $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = OnyxController(catalog: catalog)..setLiveSync(false);
      addTearDown(controller.dispose);
      await tester.pumpWidget(OnyxApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('start-demo')).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('start-demo')).first);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      for (final tab in ['설정', '연주', 'NAM·IR', '프리셋', '톤']) {
        await tester.tap(find.text(tab).last);
        await tester.pumpAndSettle();
        if (tab == '프리셋') {
          await tester.ensureVisible(
            find.byKey(const ValueKey('read-presets')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('read-presets')));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull, reason: '$size $tab');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
