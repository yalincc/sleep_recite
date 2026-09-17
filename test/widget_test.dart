// 基础冒烟测试：应用能渲染出底部三页导航
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sleep_recite/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeShell()));
    expect(find.text('我的课文'), findsOneWidget);
    expect(find.text('书单'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
  });
}
