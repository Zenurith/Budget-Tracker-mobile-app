import 'package:flutter/material.dart';

import 'composition/create_presenters.dart';
import 'core/presentation/app_presenters.dart';
import 'core/view/presenter_builder.dart';
import 'views/auth_screen.dart';
import 'views/home_screen.dart';

const ink = Color(0xFF223E35);
const mutedInk = Color(0xFF526257);
const green = Color(0xFF34785B);
const canvas = Color(0xFFF7F8F3);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PocketwiseApp(presenters: createPresenters()));
}

class PocketwiseApp extends StatefulWidget {
  final AppPresenters presenters;
  const PocketwiseApp({super.key, required this.presenters});
  @override
  State<PocketwiseApp> createState() => _PocketwiseAppState();
}

class _PocketwiseAppState extends State<PocketwiseApp> {
  @override
  void initState() {
    super.initState();
    widget.presenters.initialize();
  }

  @override
  void dispose() {
    widget.presenters.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pocketwise · A little clarity, every day',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
        primary: green,
        surface: Colors.white,
      ),
      fontFamily: 'PocketwiseSans',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -1.2,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -.7,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        bodyMedium: TextStyle(color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E6DC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE0E6DC)),
        ),
        contentPadding: const EdgeInsets.all(18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE7EBE2)),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE9ECE5),
        thickness: 1,
      ),
    ),
    home: PresenterBuilder(
      presenter: widget.presenters.auth,
      builder: (context, _) {
        if (widget.presenters.auth.state.starting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return widget.presenters.auth.state.account == null
            ? AuthScreen(presenter: widget.presenters.auth)
            : HomeScreen(presenters: widget.presenters);
      },
    ),
  );
}
