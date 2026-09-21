import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'views/home_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShanuSendApp());
}

class ShanuSendApp extends StatelessWidget {
  const ShanuSendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShanuSend',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      home: const HomeView(),
    );
  }
}
