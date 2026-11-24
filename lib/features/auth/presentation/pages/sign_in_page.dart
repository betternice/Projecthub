import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme.dart';
import '../../../../core/widgets/app_buttons.dart';
import '../../domain/entities/device_login.dart';
import '../cubit/sign_in_cubit.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _clientId = TextEditingController();
  final _tmdbKey = TextEditingController();

  @override
  void dispose() {
    _clientId.dispose();
    _tmdbKey.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SignInCubit, SignInState>(
      listenWhen: (previous, current) =>
          previous.initialClientId != current.initialClientId || previous.initialTmdbKey != current.initialTmdbKey,
      listener: (context, state) {
        if (_clientId.text.isEmpty) _clientId.text = state.initialClientId;
        if (_tmdbKey.text.isEmpty) _tmdbKey.text = state.initialTmdbKey;
      },
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              Text('OneDrive', style: AppText.medium(color: AppColors.muted)),
              const SizedBox(height: 16),
              Text('Movie\nCollection', style: AppText.semibold(size: 40, height: 1.1)),
              const SizedBox(height: 16),
              Text(
                'คลังหนังจากไฟล์ใน OneDrive พร้อมปก รายละเอียด และปุ่มเล่น',
                style: AppText.body(size: 16, color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              BlocBuilder<SignInCubit, SignInState>(
                buildWhen: (previous, current) => previous.login != current.login,
                builder: (context, state) {
                  final login = state.login;
                  return login == null ? _Form(clientId: _clientId, tmdbKey: _tmdbKey) : _CodeCard(login: login);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.clientId, required this.tmdbKey});

  final TextEditingController clientId;
  final TextEditingController tmdbKey;

  static const _steps = [
    '1. เปิด portal.azure.com แล้วสร้าง App registration ชื่อ Movie Collection',
    '2. เลือกบัญชี Microsoft ส่วนตัวและที่ทำงาน',
    '3. เปิด Authentication แล้วตั้ง Allow public client flows เป็น Yes',
    '4. เพิ่มสิทธิ์ Microsoft Graph แบบ Delegated ชื่อ Files.Read',
    '5. นำ Application (client) ID มาวางด้านบน',
  ];

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SignInCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label('Application (client) ID'),
        TextField(
          controller: clientId,
          autocorrect: false,
          enableSuggestions: false,
          style: AppText.body(),
          decoration: const InputDecoration(hintText: '00000000-0000-0000-0000-000000000000'),
        ),
        _Label('TMDB API key ไม่จำเป็น'),
        TextField(
          controller: tmdbKey,
          autocorrect: false,
          enableSuggestions: false,
          style: AppText.body(),
          decoration: const InputDecoration(hintText: 'เว้นไว้ได้ ปกและเรื่องย่อมาให้อยู่แล้ว'),
        ),
        const SizedBox(height: 16),
        for (final step in _steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(step, style: AppText.body(size: 13, color: AppColors.faint, height: 1.45)),
          ),
        BlocBuilder<SignInCubit, SignInState>(
          buildWhen: (previous, current) => previous.errorMessage != current.errorMessage,
          builder: (context, state) {
            final message = state.errorMessage;
            if (message == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(message, style: AppText.medium(size: 14, color: AppColors.danger, height: 1.4)),
            );
          },
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder(
          valueListenable: clientId,
          builder: (context, value, _) => BlocSelector<SignInCubit, SignInState, bool>(
            selector: (state) => state.starting,
            builder: (context, starting) => PrimaryButton(
              label: 'เข้าสู่ระบบด้วย Microsoft',
              busy: starting,
              onPressed: isValidClientId(value.text)
                  ? () {
                      FocusScope.of(context).unfocus();
                      cubit.start(clientId: clientId.text, tmdbKey: tmdbKey.text);
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: AppText.medium(size: 13, color: AppColors.muted)),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.login});

  final DeviceLogin login;

  Future<void> _openBrowser(BuildContext context) async {
    final opened = await launchUrl(login.verificationUri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เปิดเบราว์เซอร์ไม่ได้ ไปที่ ${login.verificationUri} ด้วยตัวเอง')),
      );
    }
  }

  Future<void> _copyCode(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: login.userCode));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คัดลอกรหัสแล้ว')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ใส่รหัสนี้ในหน้า Microsoft', style: AppText.medium(size: 14, color: AppColors.muted)),
          const SizedBox(height: 12),
          SelectableText(login.userCode, style: AppText.semibold(size: 36).copyWith(letterSpacing: 2)),
          const SizedBox(height: 12),
          Text('กำลังรอการยืนยันจากเบราว์เซอร์', style: AppText.body(size: 14, color: AppColors.faint)),
          const SizedBox(height: 20),
          PrimaryButton(label: 'เปิดหน้าเว็บ Microsoft', onPressed: () => _openBrowser(context)),
          const SizedBox(height: 12),
          SecondaryButton(label: 'คัดลอกรหัส', onPressed: () => _copyCode(context)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: context.read<SignInCubit>().cancel,
            child: Text('ยกเลิก', style: AppText.medium(color: AppColors.muted)),
          ),
        ],
      ),
    );
  }
}
