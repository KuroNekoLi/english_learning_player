@TestOn('browser')
library;

import 'package:crypto/crypto.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/files/web_media_store.dart';
import 'package:english_learning_player/core/firebase/firebase_endpoint.dart';
import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:english_learning_player/features/auth/data/firebase_account_session.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/sync/data/firebase_material_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Chrome transfers private media using the Firebase Emulator',
    () async {
      final endpoint = FirebaseEndpoint(
        project: 'demo-english-learning-player',
        bucket: 'demo-english-learning-player.appspot.com',
        apiKey: 'demo-key',
        emulatorHost: '127.0.0.1',
      );
      final http = FirebaseHttp();
      addTearDown(http.close);
      const password = 'emulator-fixture-only';
      final stamp = DateTime.now().microsecondsSinceEpoch;
      Future<String> register(String name) async {
        final email = '$name-$stamp@example.test';
        final response = await http.send(
          'POST',
          endpoint.auth('signUp'),
          contentType: 'application/json',
          bytes: FirebaseHttp.encode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }),
        );
        await http.requireSuccess(response);
        await http.read(response).drain<void>();
        return email;
      }

      final sender = FirebaseAccountSession(endpoint, http);
      final receiver = FirebaseAccountSession(endpoint, http);
      final outsider = FirebaseAccountSession(endpoint, http);
      final email = await register('browser-owner');
      final uid = await sender.signIn(email, password);
      expect(await receiver.signIn(email, password), uid);
      final otherUid = await outsider.signIn(
        await register('browser-other'),
        password,
      );

      final sending = FirebaseMaterialTransport(endpoint, sender, http);
      final receiving = FirebaseMaterialTransport(endpoint, receiver, http);
      final unauthorized = FirebaseMaterialTransport(endpoint, outsider, http);
      final scope = AccountScope(uid);
      final source = WebMediaStore(scope);
      final destination = WebMediaStore.forTesting(scope, forceIndexedDb: true);
      final bytes = List.generate(300 * 1024, (i) => i % 256);
      final saved = await source.copyAndHash(
        AudioImportSource(
          sourceKey: 'browser-sync-fixture',
          name: 'fixture.m4a',
          openRead: () => Stream.value(bytes),
        ),
      );
      expect(source.lastWriteBackend, WebMediaBackend.opfs);
      expect(saved.sha256, sha256.convert(bytes).toString());

      const payloadHash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final asset = CloudMediaAsset(
        id: 'browser-asset',
        sha256: saved.sha256,
        byteLength: saved.byteLength,
        mediaType: saved.mediaType,
      );
      Future<CloudAssetReceipt> upload() => sending.uploadAsset(
        uid: uid,
        asset: asset,
        openRead: () => source.read(saved.relativePath),
        opId: 'browser-operation',
        payloadHash: payloadHash,
      );
      final receipt = await upload();
      expect((await upload()).storagePath, receipt.storagePath);
      await sending.publishAsset(
        uid: uid,
        metadata: CloudAssetMetadata(
          assetId: asset.id,
          sha256: receipt.sha256,
          byteLength: receipt.byteLength,
          mediaType: receipt.mediaType,
          storagePath: receipt.storagePath,
          opId: 'browser-operation',
          payloadHash: payloadHash,
        ),
      );
      await sending.publishMaterial(
        uid: uid,
        metadata: CloudMaterialMetadata(
          materialId: 'browser-material',
          title: 'Synthetic browser lesson',
          assetId: asset.id,
          sha256: receipt.sha256,
          byteLength: receipt.byteLength,
          mediaType: receipt.mediaType,
          storagePath: receipt.storagePath,
          opId: 'browser-operation',
          payloadHash: payloadHash,
        ),
      );
      final remote = (await receiving.listMaterials(uid)).single;
      final cached = await destination.copyAndHash(
        AudioImportSource(
          sourceKey: remote.materialId,
          name: 'download.m4a',
          openRead: () =>
              receiving.readAudio(uid: uid, storagePath: remote.storagePath),
        ),
      );
      expect(destination.lastWriteBackend, WebMediaBackend.indexedDb);
      expect(cached.sha256, remote.sha256);
      expect(
        await destination
            .read(cached.relativePath)
            .expand((chunk) => chunk)
            .toList(),
        bytes,
      );
      expect(await unauthorized.listMaterials(otherUid), isEmpty);
      final response = await http.send(
        'GET',
        endpoint.storage(
          object: remote.storagePath,
          query: const {'alt': 'media'},
        ),
        authorization: () async =>
            'Firebase ${await outsider.tokenFor(otherUid)}',
      );
      expect(response.statusCode, 403);
      await http.read(response).drain<void>();
    },
    skip: !const bool.fromEnvironment('ELP_RUN_FIREBASE_BROWSER_TEST'),
  );
}
