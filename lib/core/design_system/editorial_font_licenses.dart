import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerEditorialFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'Inter': 'inter-OFL.txt',
      'Source Serif 4': 'sourceserif4-OFL.txt',
      'Noto Sans TC': 'notosanstc-OFL.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/fonts/${entry.value}'));
    }
  });
}
