import 'audio_file_picker.dart';
import 'audio_file_picker_factory_native.dart'
    if (dart.library.js_interop) 'audio_file_picker_factory_web.dart'
    as impl;

AudioFilePicker createAudioFilePicker() => impl.create();
