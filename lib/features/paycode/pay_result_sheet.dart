import 'package:flutter/material.dart';

Future<void> showPayResultSheet({
  required BuildContext context,
  required bool success,
  String money = '',
  String payTypeName = '一码通',
  String primaryLabel = '完成',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    enableDrag: true,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.48,
        minChildSize: 0.0,
        maxChildSize: 0.62,
        snap: true,
        snapSizes: const [0.48, 0.62],
        builder: (context, scrollController) {
          return _PayResultSheetContent(
            scrollController: scrollController,
            success: success,
            money: money,
            payTypeName: payTypeName,
            primaryLabel: primaryLabel,
          );
        },
      );
    },
  );
}

class _PayResultSheetContent extends StatelessWidget {
  const _PayResultSheetContent({
    required this.scrollController,
    required this.success,
    required this.money,
    required this.payTypeName,
    required this.primaryLabel,
  });

  final ScrollController scrollController;
  final bool success;
  final String money;
  final String payTypeName;
  final String primaryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sheetColor = isDark ? const Color(0xFF1A1F1C) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF202124);
    final bodyColor = isDark ? Colors.white60 : const Color(0xFF5F6368);
    final dividerColor = isDark
        ? const Color(0xFF2A2F2C)
        : const Color(0xFFE8E8E5);
    final accentColor = success
        ? const Color(0xFF16A34A)
        : const Color(0xFFD44848);

    final hasMoney = money.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: bodyColor.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  success ? Icons.check_circle_rounded : Icons.error_rounded,
                  color: accentColor,
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              success ? '支付成功' : '支付失败',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: titleColor,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            if (success && hasMoney) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                textBaseline: TextBaseline.alphabetic,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                children: [
                  Text(
                    '¥',
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    money,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                success ? '支付已完成' : '请重新刷新付款码后再试',
                textAlign: TextAlign.center,
                style: TextStyle(color: bodyColor, fontSize: 15),
              ),
            ],
            const SizedBox(height: 26),
            Divider(height: 1, thickness: 0.5, color: dividerColor),
            const SizedBox(height: 16),
            _ResultRow(label: '支付方式', value: payTypeName),
            const SizedBox(height: 10),
            _ResultRow(label: '完成时间', value: _formatNow()),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: success
                    ? const Color(0xFF1677FF)
                    : const Color(0xFFD44848),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(primaryLabel),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatNow() {
    final now = DateTime.now();
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? Colors.white38 : const Color(0xFF9AA0A6);
    final valueColor = isDark ? Colors.white70 : const Color(0xFF202124);

    return Row(
      children: [
        Text(label, style: TextStyle(color: labelColor, fontSize: 14)),
        const Spacer(),
        Text(value, style: TextStyle(color: valueColor, fontSize: 14)),
      ],
    );
  }
}
