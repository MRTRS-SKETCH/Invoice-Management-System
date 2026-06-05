import 'package:flutter_test/flutter_test.dart';
import '../helpers/test_helper.dart';

void main() {
  setUpAll(() => initTestEnvironment());

  group('CustomTitleBar', () {
    testWidgets('应显示"发票管理系统"标题文字', (tester) async {
      // Skipped: CustomTitleBar 依赖 window_manager（WindowListener）
    }, skip: true);

    testWidgets('应显示齿轮设置图标', (tester) async {
      // Skipped: 同上
    }, skip: true);
  });
}
