import 'package:flutter_test/flutter_test.dart';
import 'package:remote_link/app.dart';

void main() {
  testWidgets('RemoteLinkApp 渲染', (tester) async {
    await tester.pumpWidget(const RemoteLinkApp());
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RemoteLinkApp), findsOneWidget);
  });
}
