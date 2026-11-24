import 'package:flutter/services.dart';

enum Flavor {
  dev(title: 'Movie Collection Dev', bannerLabel: 'DEV'),
  uat(title: 'Movie Collection UAT', bannerLabel: 'UAT'),
  prod(title: 'Movie Collection', bannerLabel: null);

  const Flavor({required this.title, required this.bannerLabel});

  final String title;

  /// ป้ายมุมจอให้รู้ว่ากำลังใช้แอปที่ไม่ใช่ production
  final String? bannerLabel;

  /// flavor ที่ build มาด้วย `--flavor` ถ้ารันโดยไม่ระบุจะถือเป็น dev
  static final Flavor current = fromName(appFlavor) ?? Flavor.dev;

  static Flavor? fromName(String? name) => values.asNameMap()[name];
}
