# WP-00 macOS 套件 Spike 重跑

使用工作專案的暫存副本。以下變更只套在副本。用 Flutter 3.32.2、Dart 3.8.1、Xcode 26.2、CocoaPods 1.16.2。Firebase CLI 14.4.0 搭配既有 JDK 21。需要套件下載的網路存取與可用磁碟空間。

1. 保留 `flutter_riverpod: 3.3.2`，在副本加入以下 exact pins。

   ```yaml
   drift: 2.31.0
   just_audio: 0.10.6
   firebase_core: 5.1.0
   firebase_auth: 7.0.1
   cloud_firestore: 7.1.0
   firebase_storage: 14.0.1
   ```

2. 執行 `flutter pub get`。將副本的 `macos/Podfile` 的 `platform :osx` 和 Runner project 內的 `MACOSX_DEPLOYMENT_TARGET` 改成 11.0。只在副本的 `macos/Runner/DebugProfile.entitlements` 加入 `com.apple.security.network.client = true`。保留 App Sandbox。
3. 用下方 Dart 程式覆蓋副本的 `lib/main.dart`，在 `pubspec.yaml` 的 `flutter.assets` 加入 `smoke.m4a`，並於副本根目錄執行以下指令。

   ```sh
   ffmpeg -nostdin -loglevel error -f lavfi -i sine=frequency=440:duration=1 -c:a aac smoke.m4a
   flutter build macos --debug
   ```

4. 在另一個暫存目錄放置下方 Emulator 設定與 Rules。用 `firebase emulators:exec --project demo-elp-stage1 --only auth,firestore,storage 'bash run-macos.sh'` 執行。這個 `demo-` project ID 與 app options 只用於本機 Emulator。未使用正式 Firebase 專案、憑證或計費。
5. `run-macos.sh` 指向實際暫存副本建置產物。結果以 app stdout 中各步驟的 `SPIKE PASS`／`SPIKE FAIL` 判讀。
6. 匿名 Auth 若因 Keychain 缺少 entitlement 而失敗，probe 會以本機 Emulator 專用路徑繼續驗證 Firestore／Storage 的資料傳輸。兩個特例 Rules 只允許讀寫該合成 fixture，部署正式 Rules 時不得帶入。此時整體 script exit 仍為 1，Auth 與傳輸結果可獨立判讀。

## Dart probe

```dart
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  runApp(
    const ProviderScope(child: MaterialApp(home: Text('Local plugin smoke'))),
  );
  smoke();
}

Future<void> smoke() async {
  var stage = 'SQLite';
  try {
    final db = NativeDatabase.memory();
    await db.ensureOpen(_BootstrapUser());
    final rows = await db.runSelect('select 42 as result', []);
    if (rows.single['result'] != 42) throw StateError('SQLite mismatch');
    await db.close();
    print('SPIKE PASS SQLite');
    stage = 'just_audio';
    final directory = await Directory.systemTemp.createTemp('elp-smoke');
    final player = AudioPlayer();
    try {
      final data = await rootBundle.load('smoke.m4a');
      final file = File('${directory.path}/smoke.m4a');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final duration = await player.setFilePath(file.path);
      if (duration == null || duration <= Duration.zero) {
        throw StateError('Missing audio duration');
      }
    } finally {
      await player.dispose();
      await directory.delete(recursive: true);
    }
    print('SPIKE PASS just_audio local decode duration');
  } catch (e) {
    print('SPIKE FAIL $stage $e');
  }
  stage = 'Core';
  try {
    final app = await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: 'local-emulator-only',
        appId: '1:1234567890:ios:1234567890abcdef',
        messagingSenderId: '1234567890',
        projectId: 'demo-elp-stage1',
        storageBucket: 'demo-elp-stage1.appspot.com',
      ),
    );
    print('SPIKE PASS Core');
    final auth = FirebaseAuth.instanceFor(app: app);
    final store = FirebaseFirestore.instanceFor(app: app);
    final storage = FirebaseStorage.instanceFor(app: app);
    await auth.useAuthEmulator('127.0.0.1', 19099);
    store.useFirestoreEmulator('127.0.0.1', 18080);
    await storage.useStorageEmulator('127.0.0.1', 19199);
    String? uid;
    try {
      final result = await auth.signInAnonymously().timeout(
        const Duration(seconds: 20),
      );
      uid = result.user!.uid;
      print('SPIKE PASS Auth anonymous');
    } catch (e) {
      print('SPIKE FAIL Auth $e');
    }

    final doc = store.doc(
      uid == null ? 'wp00_transport_smoke/probe' : 'users/$uid/smoke/stage1',
    );
    try {
      await doc.set({'value': 42}).timeout(const Duration(seconds: 20));
      final got = await doc
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));
      if (got.data()?['value'] != 42) throw StateError('Firestore mismatch');
      print('SPIKE PASS Firestore server read/write');
    } catch (e) {
      print('SPIKE FAIL Firestore $e');
    }

    final ref = storage.ref(
      uid == null ? 'wp00_transport_smoke/probe.txt' : 'users/$uid/smoke.txt',
    );
    try {
      await ref
          .putData(Uint8List.fromList(utf8.encode('synthetic smoke')))
          .timeout(const Duration(seconds: 20));
      final bytes = await ref
          .getData(1024)
          .timeout(const Duration(seconds: 20));
      if (utf8.decode(bytes!) != 'synthetic smoke')
        throw StateError('Storage mismatch');
      print('SPIKE PASS Storage upload/download');
    } catch (e) {
      print('SPIKE FAIL Storage $e');
    }

    if (auth.currentUser != null) await auth.signOut();
  } catch (e) {
    print('SPIKE FAIL $stage $e');
  } finally {
    print('SPIKE DONE');
  }
}

class _BootstrapUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
```

## firebase.json

```json
{"firestore":{"rules":"firestore.rules"},"storage":{"rules":"storage.rules"},"emulators":{"auth":{"host":"127.0.0.1","port":19099},"firestore":{"host":"127.0.0.1","port":18080},"storage":{"host":"127.0.0.1","port":19199},"hub":{"host":"127.0.0.1","port":19400},"logging":{"host":"127.0.0.1","port":19500},"ui":{"enabled":false}}}
```

## firestore.rules

```text
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /wp00_transport_smoke/probe {
      allow read, write: if true;
    }
    match /users/{uid}/smoke/{id} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

## storage.rules

```text
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /wp00_transport_smoke/probe.txt {
      allow read, write: if true;
    }
    match /users/{uid}/smoke.txt {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

## run-macos.sh

```bash
#!/bin/bash
set -eu
app=/absolute/path/to/elp-spike/build/macos/Build/Products/Debug/english_learning_player.app/Contents/MacOS/english_learning_player
"$app" > macos-runtime.log 2>&1 &
app_pid=$!
trap 'kill "$app_pid" 2>/dev/null || true' EXIT
for ((second=0; second<85; second++)); do
  if rg -q 'SPIKE DONE' macos-runtime.log; then break; fi
  if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
  sleep 1
done
rg 'SPIKE (PASS|FAIL)' macos-runtime.log || true
rg -q 'SPIKE DONE' macos-runtime.log
! rg -q 'SPIKE FAIL' macos-runtime.log
```
