import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════
// Mock 全局初始化
// ═══════════════════════════════════════════════════════════════════

/// 注册所有 mocktail 所需的 fallback 值。
/// 在 `setUpAll` 中调用一次即可。
void initMocktailFallbacks() {
  registerFallbackValue(Uri());
  registerFallbackValue(http.StreamedResponse(const Stream.empty(), 200));
  registerFallbackValue(<String, String>{});
}

// ═══════════════════════════════════════════════════════════════════
// Mock HTTP 客户端
// ═══════════════════════════════════════════════════════════════════

/// 模拟 [http.Client]，覆盖 GET / POST / PATCH / PUT / DELETE / send。
///
/// 用法：
/// ```dart
/// final mock = MockHttpClient();
/// when(() => mock.get(any())).thenAnswer(
///   (_) async => fakeResponse(200, '{"ok": true}'),
/// );
/// ExpenseService.client = mock;
/// ```
class MockHttpClient extends Mock implements http.Client {}

/// 快速构造一个 [http.Response] 对象，用于 mock 返回值。
///
/// [body] 为响应体字符串（通常为 JSON），内部以 UTF-8 编码为 bytes，
/// 避免 Latin1 默认编码无法处理中文的问题。
/// [statusCode] 默认 200。
http.Response fakeResponse(int statusCode, String body, {Map<String, String>? headers}) {
  return http.Response.bytes(
    utf8.encode(body),
    statusCode,
    headers: headers ?? {},
  );
}

/// 快速构造一个 200 成功响应。
http.Response fakeOk(String body, {Map<String, String>? headers}) =>
    fakeResponse(200, body, headers: headers);

/// 快速构造一个非 200 错误响应。
http.Response fakeError(int statusCode, String body, {Map<String, String>? headers}) =>
    fakeResponse(statusCode, body, headers: headers);

// ═══════════════════════════════════════════════════════════════════
// Mock SharedPreferences
// ═══════════════════════════════════════════════════════════════════

/// 模拟 [SharedPreferences]，覆盖 getString / setString 等常用方法。
///
/// 用法：
/// ```dart
/// final mockPrefs = MockSharedPreferences();
/// when(() => mockPrefs.getString(any())).thenReturn('{"0":200.0}');
/// // 将 mockPrefs 注入到被测试的 mixin / class 中
/// ```
class MockSharedPreferences extends Mock implements SharedPreferences {}
