import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/core/utils/jwt_expiry.dart';

void main() {
  test('maps temporary expiry to one hour', () {
    expect(jwtExpiresFor(LoginExpiry.temporary), '1h');
  });

  test('maps three days and seven days', () {
    expect(jwtExpiresFor(LoginExpiry.threeDays), '3d');
    expect(jwtExpiresFor(LoginExpiry.sevenDays), '7d');
  });

  test('maps current day to remaining seconds until midnight', () {
    final fixed = DateTime(2026, 5, 16, 23, 59, 30);
    expect(jwtExpiresFor(LoginExpiry.currentDay, now: fixed), '30s');
  });

  test('jwtExpireAtFor returns milliseconds advanced by the duration', () {
    final fixed = DateTime.utc(2026, 5, 16, 0, 0, 0);
    final expectedMs = fixed.millisecondsSinceEpoch + 60 * 60 * 1000;
    expect(jwtExpireAtFor(LoginExpiry.temporary, now: fixed), expectedMs);
  });
}
