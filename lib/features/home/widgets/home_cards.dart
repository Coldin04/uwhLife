import 'package:flutter/material.dart';

const FontWeight _homeBold = FontWeight.w500;
const FontWeight _homeSemiBold = FontWeight.w400;

class PrimaryFeatureCard extends StatelessWidget {
  const PrimaryFeatureCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(30),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foregroundColor, size: 40),
              const Spacer(),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: _homeBold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: foregroundColor.withValues(alpha: 0.8),
                  fontWeight: _homeSemiBold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SecondaryFeatureCard extends StatelessWidget {
  const SecondaryFeatureCard({
    super.key,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
    this.borderColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;

  /// MD2 风格的 1px 描边。中性灰底和白底页面对比很弱，靠这条边界定卡片轮廓。
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(22);
    final border = borderColor;
    return Material(
      color: backgroundColor,
      borderRadius: border == null ? radius : null,
      shape: border == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: border),
            ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Center(child: Icon(icon, color: foregroundColor, size: 28)),
      ),
    );
  }
}
