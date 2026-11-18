import 'package:material_ui/material_ui.dart';

/// Zoom input intercepted by a native host, delivered once to the viewer.
class PreviewZoomController extends ChangeNotifier {
  double factor = 1;

  void zoomBy(double value) {
    if (!value.isFinite || value <= 0) return;
    factor = value.clamp(.75, 1.33);
    notifyListeners();
  }
}

/// Shared by every preview type so selection menus, localization and failure
/// feedback use the same Material widget family.
class PreviewApp extends StatelessWidget {
  const PreviewApp({super.key, required this.home, this.scaffoldMessengerKey});

  final Widget home;
  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      fontFamily: 'MBGPreviewUI',
      fontFamilyFallback: const ['Unifont'],
    );
    return MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      title: 'PDFプレビュー',
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamilyFallback: const ['Unifont']),
      ),
      home: home,
    );
  }
}
