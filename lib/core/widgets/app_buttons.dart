import 'package:flutter/material.dart';

import '../../app/theme.dart';

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.height = 54,
    this.radius = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.accentInk,
          disabledBackgroundColor: AppColors.accent.withValues(alpha: busy ? 1 : 0.4),
          disabledForegroundColor: AppColors.accentInk,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        ),
        child: busy
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.accentInk),
              )
            : Text(label, style: AppText.semibold(size: 16, color: AppColors.accentInk)),
      ),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(label, style: AppText.medium()),
      ),
    );
  }
}
