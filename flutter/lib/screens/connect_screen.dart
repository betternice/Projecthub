import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/microsoft.dart';
import '../models.dart';
import '../onedrive/graph.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/tv_focus.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _client = TextEditingController();
  final _clientFocus = FocusNode();
  DeviceLogin? _pending;
  String? _error;
  var _busy = false;
  Timer? _timer;
  var _waitSeconds = 5;
  var _filledSavedId = false;

  static final _guid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filledSavedId) return;
    final saved = AppScope.of(context).savedClientId;
    if (saved.isNotEmpty) _client.text = saved;
    _filledSavedId = true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _client.dispose();
    _clientFocus.dispose();
    super.dispose();
  }

  void _schedulePoll(DeviceLogin pending) {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _waitSeconds), () => _tick(pending));
  }

  Future<void> _tick(DeviceLogin pending) async {
    final app = AppScope.of(context);
    try {
      final result = await pollDeviceToken(_client.text.trim(), pending.deviceCode);
      if (!mounted || _pending?.deviceCode != pending.deviceCode) return;
      if (result.status == 'pending' || result.status == 'slow_down') {
        if (result.status == 'slow_down') _waitSeconds += 5;
        _schedulePoll(pending);
        return;
      }
      if (result.status == 'success' && result.tokens != null) {
        final tokens = result.tokens!;
        final name = await fetchProfileName(tokens.accessToken);
        if (!mounted) return;
        await app.saveSession(Session(
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiresAt: tokens.expiresAt,
          displayName: name,
          clientId: _client.text.trim(),
        ));
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _pending = null;
        _error = result.status == 'expired' ? 'รหัสหมดอายุแล้ว ลองเชื่อมใหม่' : 'ยกเลิกการเชื่อม OneDrive';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _pending = null;
        _error = _message(error);
      });
    }
  }

  Future<void> _start() async {
    final id = _client.text.trim();
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await AppScope.of(context).saveClientId(id);
      if (!_guid.hasMatch(id)) {
        throw Exception('ใส่ Application (client) ID จาก Azure ให้ถูกต้อง');
      }
      final pending = await requestDeviceCode(id);
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _waitSeconds = pending.interval;
        _busy = false;
      });
      _schedulePoll(pending);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _message(error);
      });
    }
  }

  Future<void> _openVerify() async {
    final uri = Uri.tryParse(_pending?.verificationUri ?? '');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyCode() async {
    final code = _pending?.userCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
  }

  String _message(Object error) => error.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Scaffold(
      backgroundColor: themeBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 36),
              child: pending == null ? _setupForm() : _deviceCode(pending),
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('NICE', style: brandStyle(size: 56, color: themeAccent)),
        const SizedBox(height: 10),
        Text('เชื่อม OneDrive', style: displayStyle(size: 40)),
        const SizedBox(height: 12),
        Text(
          'ใส่ Application (client) ID จาก Azure แล้วใช้รีโมททีวียืนยันบนมือถือหรือคอมพิวเตอร์',
          style: bodyStyle(size: 18, color: themeMuted),
        ),
        const SizedBox(height: 36),
        TextField(
          controller: _client,
          focusNode: _clientFocus,
          autofocus: true,
          style: bodyStyle(size: 20),
          cursorColor: themeAccent,
          decoration: InputDecoration(
            labelText: 'Azure Application (client) ID',
            labelStyle: bodyStyle(size: 16, color: themeMuted),
            filled: true,
            fillColor: themePanel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: themeFocus, width: 2),
            ),
          ),
          onSubmitted: (_) {
            if (!_busy) _start();
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: bodyStyle(size: 16, color: themeDanger)),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            TvButton(
              label: _busy ? 'กำลังเชื่อม…' : 'เริ่มเชื่อม OneDrive',
              onPressed: _busy ? () {} : _start,
              autofocus: false,
              icon: Icons.cloud_outlined,
            ),
            const SizedBox(width: 16),
            TvButton(
              label: 'ยกเลิก',
              filled: false,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _deviceCode(DeviceLogin pending) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('NICE', style: brandStyle(size: 56, color: themeAccent)),
        const SizedBox(height: 10),
        Text('ยืนยันบนอุปกรณ์อื่น', style: displayStyle(size: 40)),
        const SizedBox(height: 12),
        Text(
          'เปิด ${pending.verificationUri} แล้วใส่รหัสด้านล่าง',
          style: bodyStyle(size: 18, color: themeMuted),
        ),
        const SizedBox(height: 40),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
          decoration: BoxDecoration(
            color: themePanel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: themeLine),
          ),
          child: Column(
            children: [
              Text(pending.userCode, style: brandStyle(size: 72, color: themeText)),
              const SizedBox(height: 8),
              Text('กำลังรอการยืนยัน…', style: bodyStyle(size: 16, color: themeMuted)),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: bodyStyle(size: 16, color: themeDanger)),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            TvButton(label: 'เปิดหน้ายืนยัน', autofocus: true, onPressed: _openVerify, icon: Icons.open_in_new),
            const SizedBox(width: 16),
            TvButton(label: 'คัดลอกรหัส', filled: false, onPressed: _copyCode),
            const SizedBox(width: 16),
            TvButton(
              label: 'ยกเลิก',
              filled: false,
              onPressed: () {
                _timer?.cancel();
                setState(() => _pending = null);
              },
            ),
          ],
        ),
      ],
    );
  }
}
