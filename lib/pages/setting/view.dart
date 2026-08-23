import 'package:PiliPlus/common/widgets/flutter/list_tile.dart';
import 'package:PiliPlus/common/widgets/scaffold/simple_scaffold.dart';
import 'package:PiliPlus/common/widgets/view_safe_area.dart';
import 'package:PiliPlus/http/login.dart';
import 'package:PiliPlus/models/common/setting_type.dart';
import 'package:PiliPlus/pages/about/view.dart';
import 'package:PiliPlus/pages/login/controller.dart';
import 'package:PiliPlus/pages/setting/common_setting.dart';
import 'package:PiliPlus/pages/setting/widgets/multi_select_dialog.dart';
import 'package:PiliPlus/pages/setting/widgets/setting_group.dart';
import 'package:PiliPlus/pages/webdav/view.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:PiliPlus/utils/accounts/account.dart';
import 'package:PiliPlus/utils/extension/size_ext.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:material_ui/material_ui.dart' hide ListTile;

class _SettingsModel {
  final SettingType type;
  final String? subtitle;
  final Icon icon;

  const _SettingsModel({
    required this.type,
    this.subtitle,
    required this.icon,
  });
}

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  late SettingType _type = SettingType.privacySetting;
  final RxBool _noAccount = Accounts.account.isEmpty.obs;
  late bool _isPortrait;
  late ThemeData theme;

  static const List<_SettingsModel> _settingItems = [
    _SettingsModel(
      type: SettingType.privacySetting,
      subtitle: '黑名单',
      icon: Icon(Icons.privacy_tip_outlined),
    ),
    _SettingsModel(
      type: SettingType.recommendSetting,
      subtitle: '推荐来源（web/app）、刷新保留内容、过滤器',
      icon: Icon(Icons.explore_outlined),
    ),
    _SettingsModel(
      type: SettingType.videoSetting,
      subtitle: '画质、音质、解码、缓冲、音频输出等',
      icon: Icon(Icons.video_settings_outlined),
    ),
    _SettingsModel(
      type: SettingType.playSetting,
      subtitle: '双击/长按、全屏、后台播放、弹幕、字幕、底部进度条等',
      icon: Icon(Icons.touch_app_outlined),
    ),
    _SettingsModel(
      type: SettingType.styleSetting,
      subtitle: '横屏适配（平板）、侧栏、列宽、首页、动态红点、主题、字号、图片、帧率等',
      icon: Icon(Icons.style_outlined),
    ),
    _SettingsModel(
      type: SettingType.extraSetting,
      subtitle: '震动、搜索、收藏、ai、评论、动态、代理、更新检查等',
      icon: Icon(Icons.extension_outlined),
    ),
  ];

  static const _SettingsModel _webdavItem = _SettingsModel(
    type: SettingType.webdavSetting,
    icon: Icon(MdiIcons.databaseCogOutline),
  );

  static const _SettingsModel _aboutItem = _SettingsModel(
    type: SettingType.about,
    icon: Icon(Icons.info_outline),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    theme = Theme.of(context);
    _isPortrait = MediaQuery.sizeOf(context).isPortrait;
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: theme.brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: SimpleScaffold(
        appBar: _isPortrait ? AppBar(title: const Text('设置')) : null,
        body: ViewSafeArea(
          child: _isPortrait
              ? _buildList(theme)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 4,
                      child: ColoredBox(
                        color: theme.colorScheme.surfaceContainerLow,
                        child: Column(
                          children: [
                            SizedBox(
                              height: MediaQuery.viewPaddingOf(context).top,
                            ),
                            _buildWideSearchBar(theme),
                            Expanded(
                              child: _buildList(theme, withSearch: false),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 6,
                      child: ColoredBox(
                        color: theme.colorScheme.surface,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height:
                                  MediaQuery.viewPaddingOf(context).top + 12,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                _type.title,
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Expanded(child: _buildDetail()),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDetail() => switch (_type) {
    .privacySetting ||
    .recommendSetting ||
    .videoSetting ||
    .playSetting ||
    .styleSetting ||
    .extraSetting => CommonSetting(settingType: _type, showAppBar: false),
    .webdavSetting => const WebDavSettingPage(showAppBar: false),
    .about => const AboutPage(showAppBar: false),
  };

  @override
  void dispose() {
    _noAccount.close();
    super.dispose();
  }

  void _toPage(SettingType type) {
    if (_isPortrait) {
      Get.to(
        () => switch (type) {
          .privacySetting ||
          .recommendSetting ||
          .videoSetting ||
          .playSetting ||
          .styleSetting ||
          .extraSetting => CommonSetting(settingType: type),
          .webdavSetting => const WebDavSettingPage(),
          .about => const AboutPage(),
        },
      );
    } else {
      _type = type;
      setState(() {});
    }
  }

  Color? _getTileColor(ThemeData theme, SettingType type) {
    if (_isPortrait) {
      return null;
    } else {
      return type == _type ? theme.colorScheme.primaryContainer : null;
    }
  }

  Widget _buildList(ThemeData theme, {bool withSearch = true}) {
    final padding = MediaQuery.viewPaddingOf(context);
    TextStyle titleStyle = theme.textTheme.titleMedium!;
    TextStyle subTitleStyle = theme.textTheme.labelMedium!.copyWith(
      color: theme.colorScheme.outline,
    );
    ListTile entryTile(_SettingsModel item) {
      final selected = !_isPortrait && item.type == _type;
      return ListTile(
        onTap: () => _toPage(item.type),
        selected: selected,
        selectedColor: selected ? theme.colorScheme.onPrimaryContainer : null,
        iconColor: selected ? theme.colorScheme.onPrimaryContainer : null,
        leading: item.icon,
        title: Text(item.type.title, style: titleStyle),
        subtitle: item.subtitle == null
            ? null
            : Text(item.subtitle!, style: subTitleStyle),
      );
    }
    return ListView(
      padding: EdgeInsets.only(bottom: padding.bottom + 100),
      children: [
        if (withSearch) _buildSearchItem(theme),
        const SettingsGroupTitle(title: '常规'),
        SettingsGroupColumn(
          children: [for (final item in _settingItems) entryTile(item)],
          colorFor: (i) => _getTileColor(theme, _settingItems[i].type),
        ),
        const SettingsGroupTitle(title: '同步'),
        SettingsGroupColumn(
          children: [entryTile(_webdavItem)],
          colorFor: (_) => _getTileColor(theme, _webdavItem.type),
        ),
        const SettingsGroupTitle(title: '账号'),
        Obx(
          () => SettingsGroupColumn(
            children: [
              ListTile(
                onTap: () => LoginPageController.switchAccountDialog(context),
                leading: const Icon(Icons.switch_account_outlined),
                title: Text('切换账号', style: titleStyle),
              ),
              if (!_noAccount.value)
                ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  onTap: () => _logoutDialog(context),
                  title: Text('退出登录', style: titleStyle),
                ),
            ],
          ),
        ),
        const SettingsGroupTitle(title: '关于'),
        SettingsGroupColumn(
          children: [entryTile(_aboutItem)],
          colorFor: (_) => _getTileColor(theme, _aboutItem.type),
        ),
      ],
    );
  }

  Future<void> _logoutDialog(BuildContext context) async {
    final result = await showDialog<Set<LoginAccount>>(
      context: context,
      builder: (context) => MultiSelectDialog<LoginAccount>(
        title: '选择要登出的账号uid',
        initValues: const Iterable.empty(),
        values: {
          for (final i in Accounts.account.values) i: i.mid.toString(),
        },
      ),
    );
    if (!context.mounted || result == null || result.isEmpty) return;
    Future<void> logout() {
      _noAccount.value = result.length == Accounts.account.length;
      return Accounts.deleteAll(result);
    }

    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('提示'),
          content: Text(
            "确认要退出以下账号登录吗\n\n${result.map((i) => i.mid.toString()).join('\n')}",
          ),
          actions: [
            TextButton(
              onPressed: Get.back,
              child: Text(
                '点错了',
                style: TextStyle(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Get.back();
                logout();
              },
              child: Text(
                '仅登出',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: () async {
                SmartDialog.showLoading();
                final res = await LoginHttp.logout(Accounts.main);
                if (res['status']) {
                  SmartDialog.dismiss();
                  logout();
                  Get.back();
                } else {
                  SmartDialog.dismiss();
                  SmartDialog.showToast(res['msg'].toString());
                }
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  /// 搜索胶囊本体(竖屏/宽屏共用)
  Widget _searchCapsule(ThemeData theme) => Material(
    color: theme.colorScheme.surfaceContainerHigh,
    borderRadius: const BorderRadius.all(Radius.circular(50)),
    child: InkWell(
      onTap: () => Get.toNamed('/settingsSearch'),
      borderRadius: const BorderRadius.all(Radius.circular(50)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                size: 18,
                applyTextScaling: true,
                Icons.search,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              Text(
                ' 搜索',
                style: TextStyle(
                  height: 1,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                strutStyle: const StrutStyle(height: 1, leading: 0),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// 竖屏搜索项
  Widget _buildSearchItem(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
    child: _searchCapsule(theme),
  );

  /// 宽屏左栏顶部:返回按钮 + 搜索框
  Widget _buildWideSearchBar(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(left: 8, right: 16, bottom: 8),
    child: Row(
      children: [
        IconButton(
          onPressed: Get.back,
          tooltip: '返回',
          icon: const Icon(Icons.arrow_back),
          color: theme.colorScheme.onSurfaceVariant,
        ),
        Expanded(child: _searchCapsule(theme)),
      ],
    ),
  );
}
