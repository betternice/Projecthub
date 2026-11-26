import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../format.dart';
import '../metadata/tmdb.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/remote_art.dart';
import '../widgets/tv_focus.dart';

/// Search / pick correct TMDB match — title + optional year.
class MatchPickerScreen extends StatefulWidget {
  const MatchPickerScreen({
    super.key,
    required this.filename,
    this.initialTitle,
    this.initialYear,
    this.currentMatch,
  });

  final String filename;
  final String? initialTitle;
  final String? initialYear;
  final MediaMatch? currentMatch;

  @override
  State<MatchPickerScreen> createState() => _MatchPickerScreenState();
}

class _MatchPickerScreenState extends State<MatchPickerScreen> {
  late final TextEditingController _title;
  late final TextEditingController _year;
  var _loading = false;
  String? _error;
  List<MediaMatch> _results = [];

  @override
  void initState() {
    super.initState();
    final parsed = presentTitle(widget.filename);
    _title = TextEditingController(text: widget.initialTitle ?? parsed.title);
    _year = TextEditingController(text: widget.initialYear ?? parsed.year ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _search();
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final app = AppScope.of(context);
    final key = app.tmdbKey;
    if (key == null || key.isEmpty) {
      setState(() {
        _error = app.tr('matchNeedsTmdb');
        _results = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await searchMediaCandidates(
        key,
        query: _title.text,
        year: _year.text.trim().isEmpty ? null : _year.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
        if (list.isEmpty) _error = app.tr('matchNoResults');
      });
    } on TmdbException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _results = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
        _results = [];
      });
    }
  }

  void _pick(MediaMatch match) {
    Navigator.of(context).pop(match);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
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
              padding: const EdgeInsets.fromLTRB(48, 24, 48, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      TvButton(
                        label: app.tr('back'),
                        filled: false,
                        autofocus: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(app.tr('editMatch'), style: displayStyle(size: 32)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    app.tr('editMatchHint'),
                    style: bodyStyle(size: 15, color: themeMuted),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: _title,
                          style: bodyStyle(size: 18),
                          cursorColor: themeAccent,
                          textInputAction: TextInputAction.next,
                          decoration: _fieldDecoration(app.tr('matchTitle')),
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _year,
                          style: bodyStyle(size: 18),
                          cursorColor: themeAccent,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.search,
                          decoration: _fieldDecoration(app.tr('matchYear')),
                          onSubmitted: (_) => _search(),
                        ),
                      ),
                      const SizedBox(width: 14),
                      TvButton(
                        label: app.tr('matchSearch'),
                        icon: Icons.search,
                        onPressed: _loading ? () {} : _search,
                      ),
                    ],
                  ),
                  if (widget.currentMatch != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '${app.tr('matchCurrent')}: ${widget.currentMatch!.title}'
                      '${widget.currentMatch!.year != null ? ' (${widget.currentMatch!.year})' : ''}',
                      style: bodyStyle(size: 14, color: themeMuted),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (_loading)
                    const Expanded(
                      child: Center(child: CircularProgressIndicator(color: themeAccent)),
                    )
                  else if (_error != null && _results.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(_error!, style: bodyStyle(size: 18, color: themeMuted)),
                      ),
                    )
                  else
                    Expanded(
                      child: GridView.builder(
                        itemCount: _results.length,
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 168,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.52,
                        ),
                        itemBuilder: (context, index) {
                          final match = _results[index];
                          return _ResultTile(
                            match: match,
                            onPressed: () => _pick(match),
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

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: bodyStyle(size: 14, color: themeMuted),
      filled: true,
      fillColor: themeRaised,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: themeFocus, width: 2),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.match, required this.onPressed});

  final MediaMatch match;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final kindLabel = match.kind == 'tv' ? 'TV' : 'Movie';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TvFocus(
            onPressed: onPressed,
            borderRadius: 10,
            child: SizedBox.expand(
              child: match.posterUrl == null
                  ? ColoredBox(
                      color: themeRaised,
                      child: Center(
                        child: Text(kindLabel, style: bodyStyle(size: 14, color: themeMuted)),
                      ),
                    )
                  : RemoteArt(url: match.posterUrl!, fit: BoxFit.cover),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          match.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle(size: 14, weight: FontWeight.w600),
        ),
        Text(
          [match.year, kindLabel].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bodyStyle(size: 12, color: themeMuted),
        ),
      ],
    );
  }
}
