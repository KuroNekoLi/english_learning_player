import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/subtitle_file_picker.dart';

final subtitleFilePickerProvider = Provider<SubtitleFilePicker>(
  (ref) => SubtitleFilePicker(),
);
