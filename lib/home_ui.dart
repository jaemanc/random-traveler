import 'package:flutter/material.dart';

const primaryBlue = Color(0xff2878f0);
const navyText = Color(0xff192f60);
const secondaryText = Color(0xff6b7e9d);

final elsewhereTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: primaryBlue,
    primary: primaryBlue,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: const Color(0xffeaf5ff),
  textTheme: ThemeData.light().textTheme.apply(
    bodyColor: navyText,
    displayColor: navyText,
  ),
);

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.93),
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.white, width: 1.5),
      boxShadow: [
        BoxShadow(
          color: primaryBlue.withValues(alpha: 0.09),
          blurRadius: 34,
          offset: const Offset(0, 16),
        ),
      ],
    ),
    child: child,
  );
}
