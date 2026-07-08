import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'features/root/root_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const UwhLifeApp());
}

class UwhLifeApp extends StatelessWidget {
  const UwhLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '芜忧皖江',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'AlibabaPuHuiTi',
        colorScheme: buildColorScheme(Brightness.light),
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'AlibabaPuHuiTi',
        colorScheme: buildColorScheme(Brightness.dark),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const RootPage(),
    );
  }
}
