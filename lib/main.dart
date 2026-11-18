import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'core/effect_catalog.dart';
import 'onyx_controller.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xff111214),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Onyx Mobile',
      'Pocket-Onyx',
    ], await rootBundle.loadString('assets/LICENSE.txt'));
  });
  final catalog = await EffectCatalog.load();
  runApp(
    OnyxApp(controller: OnyxController(catalog: catalog), ownsController: true),
  );
}
