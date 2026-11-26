import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/tv_focus.dart';
import 'accounts_screen.dart';

class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> with SingleTickerProviderStateMixin {
  var _editing = false;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  Future<void> _select(UserProfile profile) async {
    if (_editing) return;
    await AppScope.of(context).selectProfile(profile.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _create() async {
    final app = AppScope.of(context);
    final name = await _askName(app.tr('createProfile'), '');
    if (name == null || !mounted) return;
    final profile = await app.createProfile(name);
    if (mounted) Navigator.of(context).pop(true);
    assert(profile.id.isNotEmpty);
  }

  Future<void> _rename(UserProfile profile) async {
    final app = AppScope.of(context);
    final name = await _askName(app.tr('renameProfile'), profile.name);
    if (name == null || !mounted) return;
    await app.renameProfile(profile.id, name);
    setState(() {});
  }

  Future<void> _delete(UserProfile profile) async {
    final app = AppScope.of(context);
    if (app.profiles.length <= 1) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themePanel,
        title: Text(app.tr('deleteProfile'), style: displayStyle(size: 24)),
        content: Text(
          app.tr('deleteProfileBody', {'name': profile.name}),
          style: bodyStyle(size: 16, color: themeMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(app.tr('cancel'), style: bodyStyle(size: 16, color: themeMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(app.tr('delete'), style: bodyStyle(size: 16, color: themeDanger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await app.deleteProfile(profile.id);
    setState(() {});
  }

  Future<String?> _askName(String title, String initial) async {
    final app = AppScope.of(context);
    final next = await showDialog<String>(
      context: context,
      builder: (context) => _ProfileNameDialog(
        title: title,
        initial: initial,
        hint: app.tr('profileNameHint'),
        cancelLabel: app.tr('cancel'),
        saveLabel: app.tr('save'),
      ),
    );
    if (next == null) return null;
    final trimmed = next.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _syncNow() async {
    final app = AppScope.of(context);
    await app.pullProfileSync();
    if (!app.hasOneDrive) await app.pushProfileSync();
    if (mounted) setState(() {});
  }

  Future<void> _openAccounts() async {
    final openedLibrary = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AccountsScreen()),
    );
    if (!mounted) return;
    // กด「เปิดคลังนี้」แล้ว — กลับหน้าแรกให้โหลดคลังนั้นเลย
    if (openedLibrary == true) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final fade = CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic);
        final slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(fade);

        return Scaffold(
          backgroundColor: themeBg,
          body: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    if (_editing) {
                      setState(() => _editing = false);
                    } else {
                      Navigator.of(context).maybePop(false);
                    }
                    return null;
                  },
                ),
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _ProfilesBackdrop(),
                  SafeArea(
                    child: FadeTransition(
                      opacity: fade,
                      child: SlideTransition(
                        position: slide,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(40, 20, 40, 24),
                          child: Column(
                            children: [
                              _topBar(app),
                              const Spacer(flex: 2),
                              Text('NICE', style: brandStyle(size: 28, color: themeAccent.withValues(alpha: 0.9))),
                              const SizedBox(height: 10),
                              Text(app.tr('whoIsWatching'), style: displayStyle(size: 42)),
                              const SizedBox(height: 8),
                              Text(
                                app.tr('pickProfileHint'),
                                style: bodyStyle(size: 16, color: themeMuted),
                              ),
                              const SizedBox(height: 36),
                              _profileRow(app),
                              if (app.lastSyncError != null) ...[
                                const SizedBox(height: 16),
                                Text(
                                  app.lastSyncError!,
                                  style: bodyStyle(size: 13, color: themeDanger),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                              const Spacer(flex: 3),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _topBar(AppState app) {
    return Row(
      children: [
        TvButton(
          label: app.tr('back'),
          filled: false,
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        const Spacer(),
        for (final option in AppLang.values) ...[
          TvButton(
            label: option == AppLang.th ? 'TH' : 'EN',
            filled: app.lang == option,
            onPressed: () => app.setLang(option),
          ),
          const SizedBox(width: 8),
        ],
        TvButton(
          label: app.tr('manageAccounts'),
          filled: false,
          icon: Icons.manage_accounts_outlined,
          onPressed: _openAccounts,
        ),
        if (app.hasOneDrive) ...[
          const SizedBox(width: 8),
          TvButton(
            label: app.syncingProfiles ? app.tr('syncing') : app.tr('syncOneDrive'),
            filled: false,
            icon: Icons.cloud_sync_outlined,
            iconOnly: true,
            onPressed: app.syncingProfiles ? () {} : _syncNow,
          ),
        ],
        const SizedBox(width: 8),
        TvButton(
          label: _editing ? app.tr('doneEditing') : app.tr('manageProfiles'),
          filled: _editing,
          icon: _editing ? Icons.check_rounded : Icons.tune_rounded,
          onPressed: () => setState(() => _editing = !_editing),
        ),
      ],
    );
  }

  Widget _profileRow(AppState app) {
    final items = <Widget>[
      for (var i = 0; i < app.profiles.length; i++)
        _ProfileAvatar(
          profile: app.profiles[i],
          active: app.activeProfileId == app.profiles[i].id,
          editing: _editing,
          canDelete: app.profiles.length > 1,
          delay: i * 0.06,
          animation: _enter,
          onSelect: () => _select(app.profiles[i]),
          onRename: () => _rename(app.profiles[i]),
          onDelete: () => _delete(app.profiles[i]),
        ),
      _AddProfileAvatar(
        label: app.tr('addProfile'),
        delay: app.profiles.length * 0.06,
        animation: _enter,
        onPressed: _create,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 28),
            items[i],
          ],
        ],
      ),
    );
  }

}

class _ProfileNameDialog extends StatefulWidget {
  const _ProfileNameDialog({
    required this.title,
    required this.initial,
    required this.hint,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final String title;
  final String initial;
  final String hint;
  final String cancelLabel;
  final String saveLabel;

  @override
  State<_ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<_ProfileNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: themePanel,
      title: Text(widget.title, style: displayStyle(size: 24)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: bodyStyle(size: 18),
        cursorColor: themeAccent,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: bodyStyle(size: 14, color: themeFaint),
          filled: true,
          fillColor: themeRaised,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: themeFocus, width: 2),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel, style: bodyStyle(size: 16, color: themeMuted)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(widget.saveLabel, style: bodyStyle(size: 16, color: themeAccentSoft)),
        ),
      ],
    );
  }
}

class _ProfilesBackdrop extends StatelessWidget {
  const _ProfilesBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: themeBg),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.55),
              radius: 1.05,
              colors: [
                themeAccent.withValues(alpha: 0.18),
                Colors.transparent,
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF101018),
                themeBg.withValues(alpha: 0.2),
                themeBg,
              ],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.profile,
    required this.active,
    required this.editing,
    required this.canDelete,
    required this.delay,
    required this.animation,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
  });

  final UserProfile profile;
  final bool active;
  final bool editing;
  final bool canDelete;
  final double delay;
  final Animation<double> animation;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = Color(profile.color);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(delay.clamp(0.0, 0.7), (delay + 0.35).clamp(0.35, 1.0), curve: Curves.easeOutBack),
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
        child: SizedBox(
          width: 148,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  TvFocus(
                    onPressed: editing ? onRename : onSelect,
                    borderRadius: 999,
                    scale: 1.06,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 118,
                      height: 118,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            color.withValues(alpha: 0.95),
                            color.withValues(alpha: 0.55),
                            themeRaised,
                          ],
                        ),
                        border: Border.all(
                          color: active && !editing ? themeFocus : color.withValues(alpha: 0.65),
                          width: active && !editing ? 3 : 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.28),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: editing
                          ? const Icon(Icons.edit_rounded, color: themeText, size: 34)
                          : Text(
                              profile.name.isEmpty ? '?' : profile.name.characters.first.toUpperCase(),
                              style: displayStyle(size: 44, color: themeText),
                            ),
                    ),
                  ),
                  if (editing && canDelete)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: TvFocus(
                        onPressed: onDelete,
                        borderRadius: 999,
                        scale: 1.08,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: const BoxDecoration(
                            color: themeDanger,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 18, color: themeText),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: bodyStyle(size: 17, weight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              AnimatedOpacity(
                opacity: active && !editing ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: Text(
                  AppScope.of(context).tr('inUse'),
                  style: bodyStyle(size: 12, color: themeAccentSoft),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddProfileAvatar extends StatelessWidget {
  const _AddProfileAvatar({
    required this.label,
    required this.delay,
    required this.animation,
    required this.onPressed,
  });

  final String label;
  final double delay;
  final Animation<double> animation;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(delay.clamp(0.0, 0.7), (delay + 0.35).clamp(0.35, 1.0), curve: Curves.easeOutBack),
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
        child: SizedBox(
          width: 148,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TvFocus(
                onPressed: onPressed,
                borderRadius: 999,
                scale: 1.06,
                child: Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: themeRaised.withValues(alpha: 0.9),
                    border: Border.all(color: themeLine, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.add_rounded, size: 42, color: themeMuted),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: bodyStyle(size: 16, color: themeMuted),
              ),
              const SizedBox(height: 4),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
