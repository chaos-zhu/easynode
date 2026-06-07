import 'package:flutter/foundation.dart';

bool? debugIosAppStoreComplianceOverride;

bool get isIosAppStoreCompliance {
  final override = debugIosAppStoreComplianceOverride;
  if (override != null) return override;
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
