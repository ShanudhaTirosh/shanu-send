import 'package:flutter/material.dart';
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
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF6366F1),
          surface: Color(0xFF161E2E),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const HomeView(),
    );
  }
}
