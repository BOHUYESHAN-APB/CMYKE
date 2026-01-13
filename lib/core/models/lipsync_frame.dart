class LipSyncFrame {
  const LipSyncFrame({
    required this.aa,
    required this.ee,
    required this.ih,
    required this.oh,
    required this.ou,
    this.timestampMs,
  });

  final double aa;
  final double ee;
  final double ih;
  final double oh;
  final double ou;
  final int? timestampMs;

  Map<String, double> toMap() => {
        'aa': aa,
        'ee': ee,
        'ih': ih,
        'oh': oh,
        'ou': ou,
      };
}
