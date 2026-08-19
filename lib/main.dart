import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/platform/orientation_policy.dart';
import 'core/theme/app_theme.dart';
import 'features/root/root_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Start in portrait so Android phones never flash into landscape while the
  // first frame is loading. OrientationPolicy unlocks tablet-sized displays.
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const OrientationPolicy(child: UwhLifeApp()));
}

class UwhLifeApp extends StatelessWidget {
  const UwhLifeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '芜忧芜院',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'AlibabaPuHuiTi',
        fontFamilyFallback: const <String>[
          'Noto Sans CJK SC',
          'PingFang SC',
          'sans-serif',
        ],
        colorScheme: buildColorScheme(Brightness.light),
        dialogTheme: buildDialogTheme(Brightness.light),
        bottomSheetTheme: buildBottomSheetTheme(Brightness.light),
        snackBarTheme: buildSnackBarTheme(Brightness.light),
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        fontFamily: 'AlibabaPuHuiTi',
        fontFamilyFallback: const <String>[
          'Noto Sans CJK SC',
          'PingFang SC',
          'sans-serif',
        ],
        colorScheme: buildColorScheme(Brightness.dark),
        dialogTheme: buildDialogTheme(Brightness.dark),
        bottomSheetTheme: buildBottomSheetTheme(Brightness.dark),
        snackBarTheme: buildSnackBarTheme(Brightness.dark),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const RootPage(),
    );
  }
}
