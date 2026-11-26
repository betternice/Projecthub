import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../metadata/cache.dart';
import '../metadata/tmdb.dart';
import '../models.dart';
import '../onedrive/graph.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/tv_focus.dart';
import 'connect_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  Future<void> _addAccount() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ConnectScreen()),
    );
    if (ok == true && mounted) setState(() {});
  }

  Future<void> _useAccount(Session account) async {
    await AppScope.of(context).selectAccount(account.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _removeAccount(Session account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themePanel,
        title: Text(AppScope.of(context).tr('disconnectTitle'), style: displayStyle(size: 24)),
        content: Text(
          '“${account.title}”\n${account.accountHint.isEmpty ? account.displayName : account.accountHint}',
          style: bodyStyle(size: 16, color: themeMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppScope.of(context).tr('cancel'), style: bodyStyle(size: 16, color: themeMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppScope.of(context).tr('disconnect'), style: bodyStyle(size: 16, color: themeDanger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await AppScope.of(context).removeAccount(account.id);
    setState(() {});
  }

  Future<void> _renameAccount(Session account) async {
    final next = await showDialog<String>(
      context: context,
      builder: (context) => _RenameLibraryDialog(initial: account.label),
    );
    if (next == null || !mounted) return;
    await AppScope.of(context).renameAccount(account.id, next);
    setState(() {});
  }

  Future<void> _pickFolders(Session account) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OneDriveFoldersScreen(account: account)),
    );
    if (changed == true && mounted) setState(() {});
  }

  Future<void> _clearCache() async {
    final app = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themePanel,
        title: Text(app.tr('clearCacheTitle'), style: displayStyle(size: 24)),
        content: Text(app.tr('clearCacheBody'), style: bodyStyle(size: 16, color: themeMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(app.tr('cancel'), style: bodyStyle(size: 16, color: themeMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(app.tr('clearCache'), style: bodyStyle(size: 16, color: themeAccentSoft)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    clearMetadataMemoryCache();
    await MetadataDiskCache.instance.clear();
    try {
      await DefaultCacheManager().emptyCache();
    } catch (_) {}
    imageCache.clear();
    imageCache.clearLiveImages();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(app.tr('clearCacheDone'), style: bodyStyle(size: 15)),
        backgroundColor: themePanel,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
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
                    Navigator.of(context).maybePop();
                    return null;
                  },
                ),
              },
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(48, 28, 48, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          TvButton(
                            label: app.tr('back'),
                            filled: false,
                            autofocus: true,
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                          const SizedBox(width: 24),
                          Text(app.tr('manageAccounts'), style: displayStyle(size: 34)),
                          const Spacer(),
                          TvButton(
                            label: app.tr('clearCache'),
                            filled: false,
                            icon: Icons.cleaning_services_outlined,
                            onPressed: _clearCache,
                          ),
                          const SizedBox(width: 12),
                          TvButton(
                            label: app.tr('addOneDrive'),
                            icon: Icons.add,
                            onPressed: _addAccount,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        app.tr('accountsHint'),
                        style: bodyStyle(size: 16, color: themeMuted),
                      ),
                      const SizedBox(height: 22),
                      Expanded(
                        child: app.accounts.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      app.tr('noOneDriveYet'),
                                      style: bodyStyle(size: 20, color: themeMuted),
                                    ),
                                    const SizedBox(height: 20),
                                    TvButton(
                                      label: app.tr('addOneDrive'),
                                      icon: Icons.cloud_outlined,
                                      onPressed: _addAccount,
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: app.accounts.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 14),
                                itemBuilder: (context, index) {
                                  final account = app.accounts[index];
                                  final active = app.session?.id == account.id &&
                                      app.source == MediaSource.oneDrive;
                                  return _AccountCard(
                                    account: account,
                                    active: active,
                                    onUse: () => _useAccount(account),
                                    onFolders: () => _pickFolders(account),
                                    onRename: () => _renameAccount(account),
                                    onRemove: () => _removeAccount(account),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.active,
    required this.onUse,
    required this.onFolders,
    required this.onRename,
    required this.onRemove,
  });

  final Session account;
  final bool active;
  final VoidCallback onUse;
  final VoidCallback onFolders;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final folderSummary = account.hasLibraryFilter
        ? app.tr('selectedFolders', {'count': '${account.libraryFolders.length}'})
        : app.tr('allFolders');
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
      decoration: BoxDecoration(
        color: themePanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: active ? themeAccent : themeLine, width: active ? 2 : 1),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: themeRaised,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_outlined, color: themeText, size: 28),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        account.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: bodyStyle(size: 20, weight: FontWeight.w700),
                      ),
                    ),
                    if (active) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: themeAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(app.tr('viewingLibrary'), style: bodyStyle(size: 12, color: themeAccentSoft)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  account.accountHint.isEmpty ? account.displayName : account.accountHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle(size: 14, color: themeMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  folderSummary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: bodyStyle(size: 13, color: themeFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TvButton(
            label: active ? app.tr('openLibrary') : app.tr('useAccount'),
            filled: true,
            onPressed: onUse,
          ),
          const SizedBox(width: 10),
          TvButton(
            label: app.tr('folders'),
            filled: false,
            icon: Icons.folder_open_rounded,
            onPressed: onFolders,
          ),
          const SizedBox(width: 10),
          TvButton(label: app.tr('rename'), filled: false, onPressed: onRename),
          const SizedBox(width: 10),
          TvButton(label: app.tr('disconnect'), filled: false, onPressed: onRemove),
        ],
      ),
    );
  }
}

class OneDriveFoldersScreen extends StatefulWidget {
  const OneDriveFoldersScreen({super.key, required this.account});

  final Session account;

  @override
  State<OneDriveFoldersScreen> createState() => _OneDriveFoldersScreenState();
}

class _OneDriveFoldersScreenState extends State<OneDriveFoldersScreen> {
  var _loading = true;
  String? _error;
  List<DriveItem> _folders = const [];
  final Set<String> _selected = {};
  final Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    for (final folder in widget.account.libraryFolders) {
      _selected.add(folder.id);
      _names[folder.id] = folder.name;
    }
    // ห้ามเรียก AppScope.of ใน initState — รอเฟรมแรกก่อนโหลด
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final app = AppScope.of(context);
      final token = await app.getToken(accountId: widget.account.id);
      final items = await listChildren(token, 'root');
      final folders = items.where((i) => i.isFolder).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      for (final folder in folders) {
        _names[folder.id] = folder.name;
      }
      // ยังไม่เคยจำกัด → ติ๊กทุกโฟลเดอร์เป็นค่าเริ่มต้นในหน้าจอ
      if (!widget.account.hasLibraryFilter && _selected.isEmpty) {
        _selected.addAll(folders.map((f) => f.id));
      }
      setState(() {
        _folders = folders;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() => _selected
      ..clear()
      ..addAll(_folders.map((f) => f.id)));
  }

  void _clearAll() {
    setState(() => _selected.clear());
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    // ติ๊กครบทุกอัน หรือไม่ติ๊กเลย = ไม่จำกัด (แสดงทั้งหมด)
    final List<SelectedLibraryFolder> next;
    if (_selected.isEmpty || (_folders.isNotEmpty && _selected.length == _folders.length)) {
      next = const [];
    } else {
      next = _selected
          .map((id) => SelectedLibraryFolder(id: id, name: _names[id] ?? id))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    await app.setAccountLibraryFolders(widget.account.id, next);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
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
                Navigator.of(context).maybePop(false);
                return null;
              },
            ),
          },
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 28, 48, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TvButton(
                        label: AppScope.of(context).tr('back'),
                        filled: false,
                        autofocus: true,
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Text(
                          AppScope.of(context).tr('folderPickerTitle', {'name': widget.account.title}),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: displayStyle(size: 32),
                        ),
                      ),
                      TvButton(
                        label: AppScope.of(context).tr('selectAll'),
                        filled: false,
                        onPressed: _selectAll,
                      ),
                      const SizedBox(width: 10),
                      TvButton(
                        label: AppScope.of(context).tr('clear'),
                        filled: false,
                        onPressed: _clearAll,
                      ),
                      const SizedBox(width: 10),
                      TvButton(
                        label: AppScope.of(context).tr('save'),
                        filled: true,
                        onPressed: _loading ? () {} : _save,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppScope.of(context).tr('folderPickerHint'),
                    style: bodyStyle(size: 15, color: themeMuted),
                  ),
                  const SizedBox(height: 22),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator(color: themeAccent))
                        : _error != null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_error!, style: bodyStyle(size: 18, color: themeDanger)),
                                    const SizedBox(height: 16),
                                    TvButton(label: 'ลองใหม่', onPressed: _load),
                                  ],
                                ),
                              )
                            : _folders.isEmpty
                                ? Center(
                                    child: Text(
                                      'ไม่พบโฟลเดอร์ใน OneDrive root',
                                      style: bodyStyle(size: 18, color: themeMuted),
                                    ),
                                  )
                                : ListView.separated(
                                    itemCount: _folders.length,
                                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                                    itemBuilder: (context, index) {
                                      final folder = _folders[index];
                                      final checked = _selected.contains(folder.id);
                                      return TvFocus(
                                        onPressed: () => _toggle(folder.id),
                                        borderRadius: 12,
                                        scale: 1.02,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                          decoration: BoxDecoration(
                                            color: themePanel,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: checked ? themeAccent : themeLine,
                                              width: checked ? 2 : 1,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                checked
                                                    ? Icons.check_box_rounded
                                                    : Icons.check_box_outline_blank_rounded,
                                                color: checked ? themeAccentSoft : themeMuted,
                                                size: 28,
                                              ),
                                              const SizedBox(width: 16),
                                              const Icon(Icons.folder_rounded, color: themeText, size: 26),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Text(
                                                  folder.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: bodyStyle(size: 18, weight: FontWeight.w600),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RenameLibraryDialog extends StatefulWidget {
  const _RenameLibraryDialog({required this.initial});

  final String initial;

  @override
  State<_RenameLibraryDialog> createState() => _RenameLibraryDialogState();
}

class _RenameLibraryDialogState extends State<_RenameLibraryDialog> {
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
    final app = AppScope.of(context);
    return AlertDialog(
      backgroundColor: themePanel,
      title: Text(app.tr('renameLibrary'), style: displayStyle(size: 24)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: bodyStyle(size: 18),
        cursorColor: themeAccent,
        decoration: InputDecoration(
          labelText: app.tr('name'),
          labelStyle: bodyStyle(size: 14, color: themeMuted),
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
          child: Text(app.tr('cancel'), style: bodyStyle(size: 16, color: themeMuted)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(app.tr('save'), style: bodyStyle(size: 16, color: themeAccentSoft)),
        ),
      ],
    );
  }
}
