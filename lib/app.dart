import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'core/models/app_settings.dart';
import 'core/models/provider_config.dart';
import 'core/repositories/chat_repository.dart';
import 'core/repositories/memory_repository.dart';
import 'core/repositories/settings_repository.dart';
import 'core/services/local_database.dart';
import 'core/services/local_storage.dart';
import 'core/services/runtime_hub.dart';
import 'core/services/workspace_service.dart';
import 'features/chat/chat_screen.dart';
import 'features/pet/pet_screen.dart';
import 'ui/theme/cmyke_theme.dart';
import 'ui/windows/pet_desktop_controller.dart';

class CMYKEApp extends StatefulWidget {
  const CMYKEApp({super.key});

  @override
  State<CMYKEApp> createState() => _CMYKEAppState();
}

class _CMYKEAppState extends State<CMYKEApp> {
  late final LocalDatabase _database;
  late final LocalStorage _legacyStorage;
  late final ChatRepository _chatRepository;
  late final MemoryRepository _memoryRepository;
  late final SettingsRepository _settingsRepository;
  late final WorkspaceService _workspaceService;
  bool _ready = false;
  bool _embeddingConfigMissing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _database = LocalDatabase();
    _legacyStorage = LocalStorage();
    _workspaceService = WorkspaceService();
    _settingsRepository = SettingsRepository(
      database: _database,
      legacyStorage: _legacyStorage,
    );
    _chatRepository = ChatRepository(
      database: _database,
      legacyStorage: _legacyStorage,
      workspaceService: _workspaceService,
    );
    _memoryRepository = MemoryRepository(
      database: _database,
      legacyStorage: _legacyStorage,
      resolveEmbeddingProvider: _resolveEmbeddingProvider,
    );
    _settingsRepository.addListener(_handleSettingsChanged);
    PetDesktopController.instance.attach(_settingsRepository);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        if (mounted) {
          setState(() {
            _embeddingConfigMissing = false;
            _ready = true;
          });
        }
        return;
      }
      await Future.wait([
        _chatRepository.load(),
        _memoryRepository.load(),
        _settingsRepository.load(),
      ]);
      RuntimeHub.instance.configureToolGateway(_settingsRepository.settings);
      final savedModelPath = _settingsRepository.settings.live3dModelPath
          ?.trim();
      if (savedModelPath != null && savedModelPath.isNotEmpty) {
        await RuntimeHub.instance.live3dBridge.loadModel(savedModelPath);
      }
      if (mounted) {
        setState(() {
          _embeddingConfigMissing = _isEmbeddingMissing();
          _ready = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  @override
  void dispose() {
    _chatRepository.dispose();
    _memoryRepository.dispose();
    _settingsRepository.removeListener(_handleSettingsChanged);
    PetDesktopController.instance.detach(_settingsRepository);
    _settingsRepository.dispose();
    _database.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _settingsRepository,
      builder: (context, _) {
        final settings = _settingsRepository.settings;
        return MaterialApp(
          title: 'CMYKE',
          debugShowCheckedModeBanner: false,
          theme: CmykeTheme.light(
            palette: settings.uiPalette,
            glass: settings.uiGlass,
          ),
          darkTheme: CmykeTheme.dark(
            palette: settings.uiPalette,
            glass: settings.uiGlass,
          ),
          themeMode: ThemeMode.system,
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    if (_error != null) {
      return _StartupError(message: _error!);
    }
    if (!_ready) {
      return const _StartupLoading();
    }
    if (_settingsRepository.settings.petMode) {
      return PetScreen(
        chatRepository: _chatRepository,
        memoryRepository: _memoryRepository,
        settingsRepository: _settingsRepository,
      );
    }
    return ChatScreen(
      chatRepository: _chatRepository,
      memoryRepository: _memoryRepository,
      settingsRepository: _settingsRepository,
      workspaceService: _workspaceService,
      embeddingConfigMissing: _embeddingConfigMissing,
    );
  }

  ProviderConfig? _resolveEmbeddingProvider() {
    try {
      final settings = _settingsRepository.settings;
      final provider =
          _settingsRepository.findProvider(settings.embeddingProviderId) ??
          _activeLlmProvider();
      if (provider == null) {
        return null;
      }
      if (provider.protocol == ProviderProtocol.deviceBuiltin) {
        return null;
      }
      final embeddingModel = provider.embeddingModel?.trim();
      if (embeddingModel == null || embeddingModel.isEmpty) {
        return null;
      }
      return provider;
    } catch (_) {
      return null;
    }
  }

  ProviderConfig? _activeLlmProvider() {
    final settings = _settingsRepository.settings;
    return _settingsRepository.findProvider(settings.llmProviderId);
  }

  bool _isEmbeddingMissing() {
    try {
      final settings = _settingsRepository.settings;
      if (settings.route != ModelRoute.standard) {
        return false;
      }
      return _resolveEmbeddingProvider() == null;
    } catch (_) {
      return false;
    }
  }

  void _handleSettingsChanged() {
    if (!_ready || !mounted) {
      return;
    }
    RuntimeHub.instance.configureToolGateway(_settingsRepository.settings);
    setState(() {
      _embeddingConfigMissing = _isEmbeddingMissing();
    });
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'CMYKE 启动失败',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
