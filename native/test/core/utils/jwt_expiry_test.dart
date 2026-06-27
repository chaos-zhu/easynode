import 'package:flutter_test/flutter_test.dart';
import 'package:easynode_native/core/utils/jwt_expiry.dart';

void main() {
  test('maps three days and seven days', () {
    expect(jwtExpiresFor(LoginExpiry.threeDays), '3d');
    expect(jwtExpiresFor(LoginExpiry.sevenDays), '7d');
  });

  test('maps thirty days', () {
    expect(jwtExpiresFor(LoginExpiry.thirtyDays), '30d');
  });
}
