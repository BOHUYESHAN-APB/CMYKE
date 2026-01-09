import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/repositories/chat_repository.dart';
import 'core/repositories/memory_repository.dart';
import 'core/repositories/settings_repository.dart';
import 'core/services/local_storage.dart';
import 'features/chat/chat_screen.dart';

class CMYKEApp extends StatefulWidget {
  const CMYKEApp({super.key});

  @override
  State<CMYKEApp> createState() => _CMYKEAppState();
}

class _CMYKEAppState extends State<CMYKEApp> {
  late final LocalStorage _storage;
  late final ChatRepository _chatRepository;
  late final MemoryRepository _memoryRepository;
  late final SettingsRepository _settingsRepository;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _storage = LocalStorage();
    _chatRepository = ChatRepository(storage: _storage);
    _memoryRepository = MemoryRepository(storage: _storage);
    _settingsRepository = SettingsRepository(storage: _storage);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await Future.wait([
        _chatRepository.load(),
        _memoryRepository.load(),
        _settingsRepository.load(),
      ]);
      if (mounted) {
        setState(() => _ready = true);
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
    _settingsRepository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1B9B7B),
      brightness: Brightness.light,
      surface: const Color(0xFFFDFCF9),
    );

    return MaterialApp(
      title: 'CMYKE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF6F2EA),
        textTheme: GoogleFonts.spaceGroteskTextTheme().apply(
          bodyColor: const Color(0xFF1F2228),
          displayColor: const Color(0xFF1F2228),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: Color(0xFF1F2228),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF2EEE6),
          hintStyle: const TextStyle(color: Color(0xFF6B6F7A)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide.none,
          ),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFDFCF9),
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: Color(0xFFE4DDD2)),
          ),
        ),
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_error != null) {
      return _StartupError(message: _error!);
    }
    if (!_ready) {
      return const _StartupLoading();
    }
    return ChatScreen(
      chatRepository: _chatRepository,
      memoryRepository: _memoryRepository,
      settingsRepository: _settingsRepository,
    );
  }
}

class _StartupLoading extends StatelessWidget {
  const _StartupLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
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
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
