import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../core/repositories/settings_repository.dart';
import 'desktop_asset.dart';
import 'win_window.dart';

class PetDesktopController with TrayListener {
  PetDesktopController._();

  static final PetDesktopController instance = PetDesktopController._();

  static const int _petMinWidth = 320;
  static const int _petMinHeight = 380;
  static const int _petMaxWidth = 1200;
  static const int _petMaxHeight = 1400;

  bool _initialized = false;
  bool _inPetMode = false;
  int _petEffectEpoch = 0;
  bool _clickThrough = false;
  bool _visible = true;
  SettingsRepository? _settingsRepository;
  Map<String, int>? _normalBounds;
  Map<String, int>? _petBounds;

  bool get clickThrough => _clickThrough;
  bool get inPetMode => _inPetMode;

  Future<void> attach(SettingsRepository repository) async {
    final prev = _settingsRepository;
    if (prev != null && prev != repository) {
      prev.removeListener(_handleSettingsChanged);
    }
    _settingsRepository = repository;
    await _ensureInitialized();
    repository.addListener(_handleSettingsChanged);
  }

  Future<void> detach(SettingsRepository repository) async {
    if (_settingsRepository == repository) {
      repository.removeListener(_handleSettingsChanged);
      _settingsRepository = null;
    }
    if (_initialized) {
      trayManager.removeListener(this);
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    if (!Platform.isWindows) {
      _initialized = true;
      return;
    }
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _initialized = true;
      return;
    }
    trayManager.addListener(this);
    await _installTray();
    _initialized = true;
  }

  Future<void> _installTray() async {
    final iconPath = await DesktopAsset.materializeToFilePath(
      'assets/icons/tray.ico',
      filename: 'cmyke_tray.ico',
    );
    await trayManager.setIcon(iconPath);
    await _syncTrayMenu();
  }

  Future<void> enterPetMode() async {
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    await _ensureInitialized();

    _inPetMode = true;
    final epoch = ++_petEffectEpoch;

    _normalBounds = await WinWindow.getBounds();
    final target = _petBounds ??
        const {'width': 420, 'height': 520, 'x': 10, 'y': 10};
    final targetWidth =
        (target['width'] ?? 420).clamp(_petMinWidth, _petMaxWidth);
    final targetHeight =
        (target['height'] ?? 520).clamp(_petMinHeight, _petMaxHeight);
    await WinWindow.setBounds(
      x: target['x'] ?? 10,
      y: target['y'] ?? 10,
      width: targetWidth,
      height: targetHeight,
    );
    _petBounds = {
      'x': target['x'] ?? 10,
      'y': target['y'] ?? 10,
      'width': targetWidth,
      'height': targetHeight,
    };
    await WinWindow.setSkipTaskbar(true);
    await WinWindow.setAlwaysOnTop(true);
    await WinWindow.setFrameless(true);
    await WinWindow.setResizable(true);

    // Try to make the window blend with desktop.
    unawaited(
      Future.delayed(const Duration(milliseconds: 450), () async {
        if (!_inPetMode || epoch != _petEffectEpoch) {
          return;
        }
        try {
          await Window.setEffect(effect: WindowEffect.transparent);
        } catch (_) {
          await Window.setEffect(effect: WindowEffect.disabled);
        }
      }),
    );

    await _syncTrayMenu();
  }

  Future<void> leavePetMode() async {
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    await _ensureInitialized();
    _inPetMode = false;
    _petEffectEpoch++;
    _petBounds = await WinWindow.getBounds();
    _clickThrough = false;
    await WinWindow.setIgnoreMouseEvents(false);
    await WinWindow.setSkipTaskbar(false);
    await WinWindow.setAlwaysOnTop(false);
    await WinWindow.setFrameless(false);
    await WinWindow.setResizable(true);
    try {
      await Window.setEffect(effect: WindowEffect.disabled);
    } catch (_) {
      // Best-effort: effect teardown should not block restoring bounds.
    }
    final normal = _normalBounds;
    if (normal != null) {
      await WinWindow.setBounds(
        x: normal['x'] ?? 10,
        y: normal['y'] ?? 10,
        width: normal['width'] ?? 1280,
        height: normal['height'] ?? 720,
      );
    }
    await _syncTrayMenu();
  }

  Future<void> nudgePetWindowSize({int dWidth = 0, int dHeight = 0}) async {
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    if (!_inPetMode) return;
    final bounds = await WinWindow.getBounds();
    if (bounds == null) return;
    final nextWidth =
        ((bounds['width'] ?? 420) + dWidth).clamp(_petMinWidth, _petMaxWidth);
    final nextHeight =
        ((bounds['height'] ?? 520) + dHeight)
            .clamp(_petMinHeight, _petMaxHeight);
    final x = bounds['x'] ?? 10;
    final y = bounds['y'] ?? 10;
    await WinWindow.setBounds(
      x: x,
      y: y,
      width: nextWidth,
      height: nextHeight,
    );
    _petBounds = {'x': x, 'y': y, 'width': nextWidth, 'height': nextHeight};
    await _syncTrayMenu();
  }

  Future<void> toggleClickThrough() async {
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    _clickThrough = !_clickThrough;
    await WinWindow.setIgnoreMouseEvents(_clickThrough);
    await _syncTrayMenu();
  }

  Future<void> toggleVisible() async {
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    _visible = !_visible;
    if (_visible) {
      await WinWindow.show();
    } else {
      await WinWindow.hide();
    }
    await _syncTrayMenu();
  }

  Future<void> _syncTrayMenu() async {
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }

    final settings = _settingsRepository?.settings;
    final petMode = settings?.petMode ?? false;

    final menu = Menu(
      items: [
        MenuItem(key: 'toggle_visible', label: _visible ? '隐藏桌宠' : '显示桌宠'),
        MenuItem.separator(),
        if (petMode)
          MenuItem(
            key: 'toggle_click_through',
            label: _clickThrough ? '关闭点击穿透' : '开启点击穿透',
          ),
        if (petMode)
          MenuItem(key: 'exit_pet', label: '退出桌宠（回到聊天）')
        else
          MenuItem(key: 'enter_pet', label: '进入桌宠模式'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出 CMYKE'),
      ],
    );
    await trayManager.setContextMenu(menu);
    await trayManager.setToolTip('CMYKE');
  }

  void _handleSettingsChanged() {
    if (!Platform.isWindows ||
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    unawaited(_syncTrayMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final repo = _settingsRepository;
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    switch (menuItem.key) {
      case 'toggle_visible':
        unawaited(toggleVisible());
        break;
      case 'toggle_click_through':
        unawaited(toggleClickThrough());
        break;
      case 'enter_pet':
        if (repo != null) {
          unawaited(repo.updateSettings(repo.settings.copyWith(petMode: true)));
        }
        break;
      case 'exit_pet':
        if (repo != null) {
          unawaited(
            repo.updateSettings(repo.settings.copyWith(petMode: false)),
          );
        }
        break;
      case 'quit':
        unawaited(WinWindow.close());
        break;
    }
  }
}
