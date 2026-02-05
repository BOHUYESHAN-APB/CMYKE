class TimeRange {
  const TimeRange({
    required this.start,
    required this.end,
    required this.label,
  });

  final DateTime start;
  final DateTime end;
  final String label;
}

TimeRange? parseChineseTimeRange(String text, DateTime now) {
  final raw = text.trim();
  if (raw.isEmpty) return null;
  final t = raw.toLowerCase();

  DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  DateTime startOfWeek(DateTime dt) {
    // ISO-like: Monday = 1 ... Sunday = 7
    final d = dateOnly(dt);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  TimeRange range(DateTime start, DateTime end, String label) {
    if (end.isBefore(start)) {
      return TimeRange(
        start: start,
        end: start.add(const Duration(days: 1)),
        label: label,
      );
    }
    return TimeRange(start: start, end: end, label: label);
  }

  // Fixed phrases.
  if (t.contains('今天')) {
    final start = dateOnly(now);
    return range(start, start.add(const Duration(days: 1)), '今天');
  }
  if (t.contains('昨天')) {
    final end = dateOnly(now);
    final start = end.subtract(const Duration(days: 1));
    return range(start, end, '昨天');
  }
  if (t.contains('前天')) {
    final end = dateOnly(now).subtract(const Duration(days: 1));
    final start = end.subtract(const Duration(days: 1));
    return range(start, end, '前天');
  }

  if (t.contains('上周')) {
    final end = startOfWeek(now);
    final start = end.subtract(const Duration(days: 7));
    return range(start, end, '上周');
  }
  if (t.contains('本周') || t.contains('这周') || t.contains('这一周')) {
    final start = startOfWeek(now);
    final end = start.add(const Duration(days: 7));
    return range(start, end, '本周');
  }

  if (t.contains('上个月')) {
    final startThisMonth = DateTime(now.year, now.month, 1);
    final start = DateTime(startThisMonth.year, startThisMonth.month - 1, 1);
    return range(start, startThisMonth, '上个月');
  }
  if (t.contains('本月') || t.contains('这个月') || t.contains('这月')) {
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    return range(start, end, '本月');
  }

  // Relative: 最近/近/过去 + N + unit
  final m = RegExp(
    r'(最近|近|过去)\s*([0-9]{1,3}|[一二三四五六七八九十百]+)\s*(天|日|周|小时)',
  ).firstMatch(t);
  if (m != null) {
    final nRaw = m.group(2) ?? '';
    final unit = m.group(3) ?? '天';
    final n = _parseCnOrDigits(nRaw);
    if (n != null && n > 0) {
      Duration delta;
      switch (unit) {
        case '小时':
          delta = Duration(hours: n);
          break;
        case '周':
          delta = Duration(days: n * 7);
          break;
        case '日':
        case '天':
        default:
          delta = Duration(days: n);
          break;
      }
      final end = now;
      final start = end.subtract(delta);
      return range(start, end, '${m.group(1)}$n$unit');
    }
  }

  // Generic "最近" without a number.
  if (t.contains('最近') || t.contains('近') || t.contains('过去')) {
    final end = now;
    final start = end.subtract(const Duration(days: 7));
    return range(start, end, '最近7天');
  }

  return null;
}

int? _parseCnOrDigits(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final n = int.tryParse(trimmed);
  if (n != null) return n;

  // Basic Chinese numeral parser (1-999).
  const digits = {
    '零': 0,
    '一': 1,
    '二': 2,
    '两': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
  };
  const units = {'十': 10, '百': 100};
  var total = 0;
  var current = 0;
  for (final ch in trimmed.split('')) {
    final d = digits[ch];
    if (d != null) {
      current = d;
      continue;
    }
    final u = units[ch];
    if (u != null) {
      total += (current == 0 ? 1 : current) * u;
      current = 0;
      continue;
    }
    return null;
  }
  total += current;
  return total == 0 ? null : total;
}
