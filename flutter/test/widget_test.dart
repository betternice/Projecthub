import 'package:flutter_test/flutter_test.dart';
import 'package:nice/main.dart';

void main() {
  testWidgets('Niceflix boots to welcome shell', (tester) async {
    await tester.pumpWidget(const NiceApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Niceflix'), findsWidgets);
  });
}
