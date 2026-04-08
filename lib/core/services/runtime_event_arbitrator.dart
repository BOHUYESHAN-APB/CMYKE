enum RuntimeArbitrationLane { voice, moderation, chat, proactive, danmaku }

class RuntimeArbitrationTask<T> {
  const RuntimeArbitrationTask({
    required this.id,
    required this.lane,
    required this.payload,
    required this.enqueuedAt,
    required this.notBefore,
    required this.priority,
    required this.sequence,
  });

  final String id;
  final RuntimeArbitrationLane lane;
  final T payload;
  final DateTime enqueuedAt;
  final DateTime notBefore;
  final int priority;
  final int sequence;
}

class RuntimeEventArbitrator {
  RuntimeEventArbitrator({this.maxPending = 256}) : assert(maxPending > 0);

  final int maxPending;
  final List<RuntimeArbitrationTask<Object>> _queue = [];
  int _seq = 0;

  int get pendingCount => _queue.length;

  int pendingCountForLane(RuntimeArbitrationLane lane) {
    return _queue.where((task) => task.lane == lane).length;
  }

  static int basePriorityForLane(RuntimeArbitrationLane lane) {
    switch (lane) {
      case RuntimeArbitrationLane.voice:
        return 500;
      case RuntimeArbitrationLane.moderation:
        return 400;
      case RuntimeArbitrationLane.chat:
        return 300;
      case RuntimeArbitrationLane.proactive:
        return 200;
      case RuntimeArbitrationLane.danmaku:
        return 100;
    }
  }

  bool enqueue<T>({
    required String id,
    required RuntimeArbitrationLane lane,
    required T payload,
    DateTime? now,
    DateTime? notBefore,
    int priorityBias = 0,
  }) {
    final ts = now ?? DateTime.now();
    final task = RuntimeArbitrationTask<Object>(
      id: id,
      lane: lane,
      payload: payload as Object,
      enqueuedAt: ts,
      notBefore: notBefore ?? ts,
      priority: basePriorityForLane(lane) + priorityBias,
      sequence: ++_seq,
    );

    if (_queue.length >= maxPending) {
      final lowest = _indexOfLowestPriority();
      if (lowest < 0) {
        return false;
      }
      if (_queue[lowest].priority > task.priority) {
        return false;
      }
      _queue.removeAt(lowest);
    }

    _queue.add(task);
    return true;
  }

  RuntimeArbitrationTask<Object>? dequeueReady({DateTime? now}) {
    if (_queue.isEmpty) {
      return null;
    }
    final ts = now ?? DateTime.now();
    final ready = <RuntimeArbitrationTask<Object>>[];
    for (final task in _queue) {
      if (!task.notBefore.isAfter(ts)) {
        ready.add(task);
      }
    }
    if (ready.isEmpty) {
      return null;
    }

    ready.sort((left, right) {
      final priorityCmp = right.priority.compareTo(left.priority);
      if (priorityCmp != 0) {
        return priorityCmp;
      }
      return left.sequence.compareTo(right.sequence);
    });

    final picked = ready.first;
    _queue.removeWhere((task) => task.sequence == picked.sequence);
    return picked;
  }

  void clear() {
    _queue.clear();
  }

  void clearLane(RuntimeArbitrationLane lane) {
    _queue.removeWhere((task) => task.lane == lane);
  }

  int _indexOfLowestPriority() {
    if (_queue.isEmpty) {
      return -1;
    }
    var lowest = 0;
    for (var index = 1; index < _queue.length; index += 1) {
      final current = _queue[index];
      final candidate = _queue[lowest];
      if (current.priority < candidate.priority) {
        lowest = index;
        continue;
      }
      if (current.priority == candidate.priority &&
          current.sequence > candidate.sequence) {
        lowest = index;
      }
    }
    return lowest;
  }
}
