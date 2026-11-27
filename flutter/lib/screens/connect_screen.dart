import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/azure_config.dart';
import '../auth/microsoft.dart';
import '../models.dart';
import '../onedrive/graph.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/tv_focus.dart';

/// เพิ่มบัญชี Microsoft/OneDrive (รองรับหลายบัญชี)
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _name;
  DeviceLogin? _pending;
  String? _error;
  var _busy = false;
  Timer? _timer;
  var _waitSeconds = 5;
  var _filled = false;

  String get _clientId => kAzureClientId;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: 'My OneDrive');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    final app = AppScope.of(context);
    _name.text = app.suggestedOneDriveLabel();
    _filled = true;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _name.dispose();
    super.dispose();
  }

  void _schedulePoll(DeviceLogin pending) {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _waitSeconds), () => _tick(pending));
  }

  Future<void> _tick(DeviceLogin pending) async {
    final app = AppScope.of(context);
    try {
      final result = await pollDeviceToken(_clientId, pending.deviceCode);
      if (!mounted || _pending?.deviceCode != pending.deviceCode) return;
      if (result.status == 'pending' || result.status == 'slow_down') {
        if (result.status == 'slow_down') _waitSeconds += 5;
        _schedulePoll(pending);
        return;
      }
      if (result.status == 'success' && result.tokens != null) {
        final tokens = result.tokens!;
        final profile = await fetchProfile(tokens.accessToken);
        if (!mounted) return;
        await app.saveClientId(_clientId);
        await app.addOrUpdateAccount(Session(
          id: profile.userPrincipalName,
          accessToken: tokens.accessToken,
          refreshToken: tokens.refreshToken,
          expiresAt: tokens.expiresAt,
          displayName: profile.displayName,
          clientId: _clientId,
          label: _name.text.trim().isEmpty ? profile.displayName : _name.text.trim(),
          accountHint: profile.userPrincipalName,
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

  Future<void> _add() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await AppScope.of(context).saveClientId(_clientId);
      if (kIsWeb) {
        // Browser blocks device-code CORS — redirect to Microsoft instead.
        await startWebMicrosoftLogin(
          clientId: _clientId,
          accountLabel: _name.text.trim().isEmpty ? 'My OneDrive' : _name.text.trim(),
        );
        return;
      }
      final pending = await requestDeviceCode(_clientId);
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
        _error = friendlyHttpError(error);
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

  String _message(Object error) => friendlyHttpError(error);

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Scaffold(
      backgroundColor: themeBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 28),
              child: pending == null ? _setupForm() : _deviceCode(pending),
            ),
          ),
        ),
      ),
    );
  }

  Widget _setupForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TvButton(
              label: 'กลับ',
              filled: false,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            const Spacer(),
            Text(AppScope.of(context).tr('addOneDrive'), style: displayStyle(size: 28)),
            const Spacer(),
            const SizedBox(width: 96),
          ],
        ),
        const SizedBox(height: 28),
        _field(
          label: 'Name',
          child: TextField(
            controller: _name,
            style: bodyStyle(size: 20),
            cursorColor: themeAccent,
            decoration: _inputDecoration(),
          ),
        ),
        const SizedBox(height: 14),
        _field(
          label: 'Protocol',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1E),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('OneDrive', style: bodyStyle(size: 20, color: themeMuted)),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          kIsWeb
              ? 'บนเว็บจะเปิดหน้า Microsoft ให้ล็อกอิน แล้วกลับมาที่ Niceflix อัตโนมัติ'
              : 'ล็อกอินบัญชี Microsoft อื่นได้เรื่อยๆ — แต่ละบัญชีจะเป็นคลังแยก',
          style: bodyStyle(size: 14, color: themeMuted),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: bodyStyle(size: 16, color: themeDanger)),
        ],
        const Spacer(),
        Center(
          child: TvButton(
            label: _busy ? 'กำลังเชื่อม…' : 'Add',
            autofocus: true,
            onPressed: _busy ? () {} : _add,
            icon: Icons.add,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _deviceCode(DeviceLogin pending) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Sign in with Microsoft', style: displayStyle(size: 34)),
        const SizedBox(height: 12),
        Text(
          'เปิด ${pending.verificationUri} แล้วใส่รหัส — ใช้บัญชี Microsoft ที่ต้องการเพิ่ม',
          style: bodyStyle(size: 18, color: themeMuted),
        ),
        const SizedBox(height: 36),
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
              Text(pending.userCode, style: brandStyle(size: 64, color: themeText)),
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
            TvButton(label: 'เปิดหน้าเข้าสู่ระบบ', autofocus: true, onPressed: _openVerify, icon: Icons.open_in_new),
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

  Widget _field({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: bodyStyle(size: 14, color: themeMuted)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: bodyStyle(size: 16, color: const Color(0xFF55555C)),
      filled: true,
      fillColor: themePanel,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: themeFocus, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }
}
