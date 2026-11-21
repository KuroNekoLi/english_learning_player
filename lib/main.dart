import 'main_native.dart'
    if (dart.library.js_interop) 'main_web.dart'
    as application;

Future<void> main() => application.main();
