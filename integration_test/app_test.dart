import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:onyx_mobile/core/effect_catalog.dart';
import 'package:onyx_mobile/onyx_controller.dart';
import 'package:onyx_mobile/ui/app.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native mobile editor flow', (tester) async {
    final controller = OnyxController(catalog: await EffectCatalog.load())
      ..setLiveSync(false);
    addTearDown(controller.dispose);
    await tester.pumpWidget(OnyxApp(controller: controller));
    await tester.pumpAndSettle();
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }
    Future<void> shot(String name) async {
      await binding.takeScreenshot(
        '${Platform.isIOS ? 'ios' : 'android'}-$name',
      );
    }

    Future<void> reveal(Finder target, double delta) async {
      await tester.scrollUntilVisible(
        target,
        delta,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
      await tester.pumpAndSettle();
    }

    await shot('welcome');
    await tester.ensureVisible(find.byKey(const ValueKey('start-demo')).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('start-demo')).first);
    for (var attempt = 0; !controller.connected && attempt < 100; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.connected, isTrue, reason: controller.status);
    await tester.pumpAndSettle();
    expect(find.text('Amber Clean'), findsOneWidget);
    final gain = find.byKey(const ValueKey('slider-GAIN'));
    await tester.ensureVisible(gain);
    await tester.pumpAndSettle();
    expect(controller.canEdit, isTrue);
    final rectangle = tester.getRect(gain);
    await tester.tapAt(
      Offset(rectangle.left + rectangle.width * .78, rectangle.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.state!.effect(2).knobs[0], isNot(42));
    await shot('tone');
    await reveal(find.byKey(const ValueKey('save-tone')), -300);
    await tester.tap(find.byKey(const ValueKey('save-tone')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '저장'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('next-preset')));
    await tester.pumpAndSettle();
    expect(controller.state!.name, 'Velvet Drive');
    await tester.tap(find.text('설정').last);
    await tester.pumpAndSettle();
    await shot('settings');
    await tester.tap(find.text('연주').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('toggle-groove')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(controller.state!.groovePlaying, isTrue);
    await shot('groove');
    await tester.tap(find.text('NAM·IR').last);
    await tester.pumpAndSettle();
    await shot('files');
    await tester.tap(find.text('프리셋').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('read-presets')));
    await tester.pumpAndSettle();
    expect(controller.bank!.readableCount, 80);
    await reveal(find.byKey(const ValueKey('restore-range')), 250);
    await tester.enterText(find.byKey(const ValueKey('restore-range')), '1-3');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '선택'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '선택'));
    await tester.pumpAndSettle();
    await reveal(find.byKey(const ValueKey('restore-presets')), 200);
    await tester.tap(find.byKey(const ValueKey('restore-presets')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '복원'),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.logs.any((entry) => entry.contains('일치함을 확인')), isTrue);
    await shot('presets');
    expect(tester.takeException(), isNull);
  });
}
