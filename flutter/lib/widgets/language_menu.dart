import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'tv_focus.dart';

/// เมนูเลือกภาษา ไทย / English
class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        if (compact) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in AppLang.values) ...[
                if (option != AppLang.values.first) const SizedBox(width: 8),
                TvButton(
                  label: option == AppLang.th ? 'TH' : 'EN',
                  filled: app.lang == option,
                  onPressed: () => app.setLang(option),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(app.tr('languageMenu'), style: bodyStyle(size: 14, color: themeMuted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final option in AppLang.values)
                  TvButton(
                    label: option.label,
                    filled: app.lang == option,
                    icon: Icons.translate_rounded,
                    onPressed: () => app.setLang(option),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
