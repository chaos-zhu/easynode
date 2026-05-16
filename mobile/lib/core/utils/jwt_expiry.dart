enum LoginExpiry { temporary, currentDay, threeDays, sevenDays }

String jwtExpiresFor(LoginExpiry expiry, {DateTime? now}) {
  switch (expiry) {
    case LoginExpiry.temporary:
      return '1h';
    case LoginExpiry.currentDay:
      final current = now ?? DateTime.now();
      final tomorrow = DateTime(current.year, current.month, current.day + 1);
      final seconds = tomorrow.difference(current).inSeconds;
      return '${seconds}s';
    case LoginExpiry.threeDays:
      return '3d';
    case LoginExpiry.sevenDays:
      return '7d';
  }
}

int jwtExpireAtFor(LoginExpiry expiry, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final expires = jwtExpiresFor(expiry, now: current);
  final match = RegExp(r'^(\d+)([smhd])$').firstMatch(expires);
  if (match == null) {
    throw const FormatException('invalid jwt expiry');
  }
  final count = int.parse(match.group(1)!);
  final unit = match.group(2)!;
  final multiplier = switch (unit) {
    's' => 1000,
    'm' => 60 * 1000,
    'h' => 60 * 60 * 1000,
    'd' => 24 * 60 * 60 * 1000,
    _ => 1000,
  };
  return current.millisecondsSinceEpoch + count * multiplier;
}
