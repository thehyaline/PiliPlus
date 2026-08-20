## 修复高能进度条请求被 CDN 拦截导致的误报 Toast

### 背景
视频页 `_getDmTrend()`（lib/pages/video/controller.dart:1301-1322）在播放器初始化时旁路请求 `https://bvc.bilivideo.com/pbp/data`（高能进度条数据源，非关键请求）。该请求沿用全局 UA `Dart/3.6 (dart:io)`（lib/http/init.dart:212），bvc CDN 对非浏览器 UA 间歇性返回 404 反爬页 → 全局拦截器 AccountManager.toast() 弹"服务器异常，请稍后重试！"（account_mgr.dart:244），且 `skipShow` 静默列表（account_mgr.dart:168-178）未覆盖该域名。播放链路不受影响。

### 改动 1（修根因）：lib/pages/video/controller.dart
- 新增 import：`import 'package:dio/dio.dart';`（已确认与现有代码无符号冲突）和 `import 'package:PiliPlus/http/browser_ua.dart';`（放入现有 http 导入组，browser_ua 排在 fav.dart 之前）
- `_getDmTrend()` 的 `Request().get()` 调用增加 `options: Options(headers: {'user-agent': BrowserUa.pc})`，复用代码库已有的浏览器 UA 常量（与 mpv_convert_webp.dart、select_dialog.dart 的用法一致）

### 改动 2（静默兜底）：lib/utils/accounts/account_manager/account_mgr.dart
- `skipShow` 列表（168-178 行）加入 `'bvc.bilivideo.com'`，与现有 `hdslb.com`、`biliimg.com` 同类处理——即使 CDN 偶发再拦截也不再弹 Toast

### 验证
- `flutter analyze` 通过
- 命令行对照：`curl -A "Dart/3.6 (dart:io)" "https://bvc.bilivideo.com/pbp/data?bvid=...&cid=..."` 复现 404；浏览器 UA 返回 200 JSON
- 实际播放验证：开启"显示高能进度条"设置后进度条图表正常显示、无 Toast