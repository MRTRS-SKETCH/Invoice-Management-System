class AppConfig {
  static String baseUrl = 'http://127.0.0.1:18090';

  /// 更新后端端口号（启动时从 port.txt 读取后调用）
  static void updatePort(int port) {
    baseUrl = 'http://127.0.0.1:$port';
  }
}