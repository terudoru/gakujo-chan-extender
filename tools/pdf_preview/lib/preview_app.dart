import 'package:material_ui/material_ui.dart';

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
