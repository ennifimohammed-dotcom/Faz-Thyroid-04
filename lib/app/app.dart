import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../features/home_shell.dart';
import '../features/lock/lock_gate.dart';
import '../features/state/app_state.dart';
import 'palette.dart';

ThemeData _theme(Brightness b, AppPalette p) {
  final dark = b == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(seedColor: p.seed, brightness: b).copyWith(
    primary: p.seed,
    onPrimary: Colors.white,
    secondary: p.secondary,
  );
  final rose = p.seed;
  final surface = dark ? const Color(0xFF2A1F27) : Colors.white;
  final field = dark ? const Color(0xFF34262F) : const Color(0xFFFFFAFC);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: c, width: w),
      );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    extensions: [
      BrandColors(deep: p.deep, blush: p.blush, gradient: p.gradient),
    ],
    scaffoldBackgroundColor: dark ? const Color(0xFF1C1419) : p.blush,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: scheme.primary,
      titleTextStyle: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: scheme.primary),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: rose.withValues(alpha: 0.14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      border: border(rose.withValues(alpha: 0.35)),
      enabledBorder: border(rose.withValues(alpha: 0.30)),
      focusedBorder: border(rose, 2),
      errorBorder: border(Colors.red.shade400),
      focusedErrorBorder: border(Colors.red.shade400, 2),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: rose,
        foregroundColor: Colors.white,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: rose,
        side: BorderSide(color: rose),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: rose,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: const CircleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: rose.withValues(alpha: 0.18),
      elevation: 0,
      height: 70,
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: const StadiumBorder(),
      side: BorderSide(color: rose.withValues(alpha: 0.3)),
    ),
    dividerTheme: DividerThemeData(color: rose.withValues(alpha: 0.15)),
    textTheme: base.textTheme.apply(
      bodyColor: dark ? const Color(0xFFF3E6EE) : const Color(0xFF3B2A35),
      displayColor: dark ? const Color(0xFFF3E6EE) : const Color(0xFF3B2A35),
    ),
  );
}

class ThyroidApp extends StatelessWidget {
  const ThyroidApp({super.key});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return MaterialApp(
      title: 'FazTyroid',
      debugShowCheckedModeBanner: false,
      locale: Locale(st.lang),
      supportedLocales: const [Locale('fr'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: st.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          LockGate(child: child ?? const SizedBox.shrink()),
      theme: _theme(Brightness.light, st.palette),
      darkTheme: _theme(Brightness.dark, st.palette),
      home: const HomeShell(),
    );
  }
}
