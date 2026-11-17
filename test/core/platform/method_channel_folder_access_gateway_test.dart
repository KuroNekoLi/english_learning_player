import 'package:english_learning_player/core/platform/folder_access_gateway.dart';
import 'package:english_learning_player/core/platform/method_channel_folder_access_gateway.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methods = MethodChannel('folder-access-test/methods');
  const events = EventChannel('folder-access-test/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelFolderAccessGateway gateway;

  setUp(() {
    gateway = MethodChannelFolderAccessGateway(
      methods: methods,
      events: events,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockStreamHandler(events, null);
  });

  test('T-FOLDER-01 picker cancellation creates no binding', () async {
    messenger.setMockMethodCallHandler(methods, (call) async => null);

    expect(await gateway.pickFolder('binding-a'), isNull);
  });

  test(
    'T-FOLDER-02 decodes stale grant and complete inventory statuses',
    () async {
      messenger.setMockMethodCallHandler(methods, (call) async {
        if (call.method == 'restoreGrant') return 'stale';
        if (call.method == 'scan') {
          return [
            {
              'relativePath': 'lesson/lesson.m4a',
              'status': 'available',
              'byteLength': 12,
              'modifiedAtMs': 1000,
            },
            {
              'relativePath': 'lesson/lesson.zh.srt',
              'status': 'pendingDownload',
              'byteLength': null,
              'modifiedAtMs': null,
            },
          ];
        }
        return null;
      });

      expect(await gateway.restoreGrant('binding-a'), GrantStatus.stale);
      final entries = await gateway.scan('binding-a');
      expect(entries, hasLength(2));
      expect(entries.first.status, FolderEntryStatus.available);
      expect(
        entries.first.modifiedAt,
        DateTime.fromMillisecondsSinceEpoch(1000),
      );
      expect(entries.last.status, FolderEntryStatus.pendingDownload);
      expect(entries.last.byteLength, isNull);
    },
  );

  test('T-FOLDER-03 maps revocation and pending download errors', () async {
    messenger.setMockMethodCallHandler(methods, (call) async {
      throw PlatformException(
        code: call.method == 'scan' ? 'permissionDenied' : 'fileNotDownloaded',
      );
    });

    await expectLater(
      gateway.scan('binding-a'),
      throwsA(
        isA<FolderAccessException>().having(
          (error) => error.failure,
          'failure',
          FolderFailure.permissionDenied,
        ),
      ),
    );
    await expectLater(
      gateway.stageFile('binding-a', 'lesson.m4a'),
      throwsA(
        isA<FolderAccessException>().having(
          (error) => error.failure,
          'failure',
          FolderFailure.fileNotDownloaded,
        ),
      ),
    );
  });

  test('T-FOLDER-04 watch stream forwards binding invalidations', () async {
    Object? listenArguments;
    messenger.setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (arguments, sink) {
          listenArguments = arguments;
          sink.success({'changed': true});
        },
      ),
    );

    await expectLater(gateway.watch('binding-a'), emits(null));
    expect(listenArguments, {'bindingId': 'binding-a'});
  });
}
