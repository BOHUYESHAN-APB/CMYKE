enum MemoryTier {
  context,
  crossSession,
  autonomous,
  external,
}

extension MemoryTierLabel on MemoryTier {
  String get label {
    switch (this) {
      case MemoryTier.context:
        return '对话内上下文';
      case MemoryTier.crossSession:
        return '跨会话记忆';
      case MemoryTier.autonomous:
        return '自主沉淀';
      case MemoryTier.external:
        return '专业数据库';
    }
  }

  String get key => name;
}
