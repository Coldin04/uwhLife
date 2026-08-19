import 'dart:ui' show ImageFilter;

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

/// 首页底部的快捷入口：圆形图标配一行简短标题，适合在背景图上继续复用。
class CircularFeatureButton extends StatelessWidget {
  const CircularFeatureButton({
    super.key,
    required this.icon,
    required this.title,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
    this.status,
    this.busy = false,
    this.labelColor,
    this.micaOpacity,
    this.iconOnly = false,
  });

  final IconData icon;
  final String title;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;
  final String? status;
  final bool busy;
  final Color? labelColor;
  final double? micaOpacity;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final visibleStatus = status?.trim();
    final resolvedLabelColor = labelColor ?? foregroundColor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: Offset(0, iconOnly ? 8 : 0),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: ClipOval(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: backgroundColor.withValues(
                      alpha:
                          micaOpacity ??
                          (backgroundColor.computeLuminance() > 0.5
                              ? 0.52
                              : 0.72),
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: Center(
                        child: busy
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: foregroundColor,
                                ),
                              )
                            : Icon(icon, color: foregroundColor, size: 27),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!iconOnly) ...[
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: resolvedLabelColor,
              fontSize: 12,
              fontWeight: _homeSemiBold,
            ),
          ),
        ],
        if (!iconOnly && visibleStatus != null && visibleStatus.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            visibleStatus,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: resolvedLabelColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}
