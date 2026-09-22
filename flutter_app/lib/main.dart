import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'views/home_view.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ShanuSendApp(initialFiles: args));
}

class ShanuSendApp extends StatelessWidget {
  final List<String> initialFiles;

  const ShanuSendApp({
    super.key,
    this.initialFiles = const [],
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShanuSend',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: HomeView(initialFiles: initialFiles),
    );
  }
}
