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

  String get shortHint {
    switch (this) {
      case MemoryTier.context:
        return '当前会话的临时工作记忆';
      case MemoryTier.crossSession:
        return '跨会话稳定事实与偏好';
      case MemoryTier.autonomous:
        return '按时间沉淀的事件与经历';
      case MemoryTier.external:
        return '外部资料与专业知识库';
    }
  }

  String get description {
    switch (this) {
      case MemoryTier.context:
        return '会话上下文记忆（含会话摘要），仅绑定当前会话，适合短期信息与压缩锚点。';
      case MemoryTier.crossSession:
        return '核心记忆会被持续注入系统提示词，用于稳定的人设、偏好与关键事实。';
      case MemoryTier.autonomous:
        return '日记记忆用于记录可追溯的“发生过的事”，适合按时间回忆与阶段复盘。';
      case MemoryTier.external:
        return '知识库支持多分类，按需检索时调用，适合文档、资料和用户导入知识。';
    }
  }

  String get writeRule {
    switch (this) {
      case MemoryTier.context:
        return '只写当前会话后续几轮还要继续引用的线索、摘要和临时约束。';
      case MemoryTier.crossSession:
        return '只写长期稳定、可复用的事实或偏好；最好能收敛成一个明确的 core_key。';
      case MemoryTier.autonomous:
        return '只写带时间性的经历、决策、变化和阶段性结论，让系统能回答“什么时候发生了什么”。';
      case MemoryTier.external:
        return '只写外部知识、专业资料或导入内容，让它作为按需检索的知识来源。';
    }
  }

  String get retrievalRule {
    switch (this) {
      case MemoryTier.context:
        return '默认只在当前会话内参与上下文组织。';
      case MemoryTier.crossSession:
        return '会优先作为长期人格/偏好/关键设定被检索和注入。';
      case MemoryTier.autonomous:
        return '更适合按时间窗和相似事件进行回忆，而不是当作永久设定。';
      case MemoryTier.external:
        return '只有命中检索时才进入上下文，不会一直占用主提示词空间。';
    }
  }

  int? get reviewWindowDays {
    switch (this) {
      case MemoryTier.context:
        return 1;
      case MemoryTier.crossSession:
        return 30;
      case MemoryTier.autonomous:
        return 14;
      case MemoryTier.external:
        return 45;
    }
  }

  String get reviewRule {
    switch (this) {
      case MemoryTier.context:
        return '会话结束后尽快清掉，避免短期线索伪装成长期记忆。';
      case MemoryTier.crossSession:
        return '按月复核是否仍然稳定成立，不稳定就降级回笔记或日记。';
      case MemoryTier.autonomous:
        return '按两周复核是否仍有追踪价值，过期事件不要长期堆积。';
      case MemoryTier.external:
        return '按资料价值复核，失效文档应替换或回退到仅笔记保留。';
    }
  }

  String get forgettingRule {
    switch (this) {
      case MemoryTier.context:
        return '优先遗忘，除非已被提炼进其他层级。';
      case MemoryTier.crossSession:
        return '不直接删除原始笔记，只撤销长期注入资格。';
      case MemoryTier.autonomous:
        return '超过阶段窗口后只保留关键节点，其余回到笔记存档。';
      case MemoryTier.external:
        return '知识过期时替换来源，不把旧资料继续当作活跃知识。';
    }
  }

  String get avoidRule {
    switch (this) {
      case MemoryTier.context:
        return '不要把长期偏好或通用知识塞进这里。';
      case MemoryTier.crossSession:
        return '不要写短期情绪、一次性任务细节或琐碎流水账。';
      case MemoryTier.autonomous:
        return '不要把稳定设定误写成日记，否则长期逻辑会发散。';
      case MemoryTier.external:
        return '不要把用户个性偏好或会话临时状态混进知识库。';
    }
  }

  String get key => name;
}
