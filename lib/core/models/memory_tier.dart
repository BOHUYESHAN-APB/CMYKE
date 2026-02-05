enum MemoryTier { context, crossSession, autonomous, external }

extension MemoryTierLabel on MemoryTier {
  String get label {
    switch (this) {
      case MemoryTier.context:
        return '会话上下文';
      case MemoryTier.crossSession:
        return '核心记忆';
      case MemoryTier.autonomous:
        return '日记记忆';
      case MemoryTier.external:
        return '知识库';
    }
  }

  String get key => name;
}
