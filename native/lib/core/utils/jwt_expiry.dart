enum LoginExpiry { threeDays, sevenDays, thirtyDays }

String jwtExpiresFor(LoginExpiry expiry) {
  switch (expiry) {
    case LoginExpiry.threeDays:
      return '3d';
    case LoginExpiry.sevenDays:
      return '7d';
    case LoginExpiry.thirtyDays:
      return '30d';
  }
}
