## 目标

首页顶栏的个人头像点击后跳转到当前用户的个人主页（`/member?mid=当前用户mid`），参照我的页头像的跳转逻辑，不再切到"我的页"。

## 改动（2 个文件）

### 1. `lib/pages/main/controller.dart`
- 新增 `import 'package:PiliPlus/utils/accounts.dart';`
- 在 `toMinePage()`（L271）附近新增方法：

```dart
void toMemberPage() {
  final mid = Accounts.main.mid;
  if (accountService.isLogin.value && mid > 0) {
    Get.toNamed('/member?mid=$mid');
  } else {
    toMinePage();
  }
}
```

说明：
- `Accounts.main.mid` 即当前登录用户的 mid（登录态下为有效值，匿名账户为 0），与我的页使用的 `userInfo.value.mid` 一致，无需额外网络请求。
- 登录态判断复用顶栏头像显示所用的 `accountService.isLogin`，保证状态一致；`mid > 0` 兜底防止登录态与账户缓存不一致时跳到无效页面。
- 跳转写法 `Get.toNamed('/member?mid=$mid')` 与我的页 `onLogin()`（mine/controller.dart:372）完全一致，路由 `/member` 已注册（app_pages.dart:109）。

### 2. `lib/pages/home/view.dart`（`userAvatar()`）
- L217 已登录头像 InkWell：`onTap: mainController.toMinePage` → `onTap: mainController.toMemberPage`
- L259 未登录图标按钮：`onPressed: mainController.toMinePage` → `onPressed: mainController.toMemberPage`

## 未登录时的行为

未登录时没有"当前用户的个人主页"，`toMemberPage()` 会回退到现有 `toMinePage()` 行为（切到"我的"tab，页内有登录入口），保持现状不变。若你希望未登录时直接跳登录页（完全复刻我的页头像逻辑），告诉我即可调整。

## 验证方式

代码改动后无法在此环境运行 Flutter 应用，建议本地编译（`flutter analyze`）确认无静态错误；运行验证需在设备上点击顶栏头像确认跳转。