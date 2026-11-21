# 資料模型與 ID 契約（v0.1）

## 1. 身分、時間、版本
- `userId`：Firebase Auth UID，不用作本機檔案路徑的原始字串。
- `materialId`：UUID，代表使用者可學習的教材；**不等於檔案 hash**。
- `assetId`：同帳號內穩定檔案參照；`sha256` 表示位元內容完整性，重複可去重。
- `trackId`：字幕軌身分；`cueId`：一個 track version 的局部唯一 cue id，不以 SRT 序號當全域 id。
- `playlistId`、`folderBindingId`、`deviceId`、`sessionId` 都用獨立穩定 ID。
- 所有區間 `[startMs,endMs)`；毫秒整數；end 必須大於 start；Server timestamp 用於排序，client sequence 用於識別過期寫入。
- `schemaVersion`、`revision` 具明確遷移邏輯，不能在既有資料上直接改型別。

## 2. 核心實體（概念欄位）
| Entity | 欄位 | 重要不變式 |
|---|---|---|
| LearningMaterial | id, ownerId, title, audioAssetId, durationMs?, status, createdAt | status = importing/localReady/uploading/cloudReady/error/archived |
| MediaAsset | id, ownerId, sha256, mime, byteLength, localPath?, storagePath?, availability | `localPath` 僅本機，永不寫雲端 |
| SubtitleTrack | id, materialId, languageTag, sourceAssetId, sourceName, revision, offsetMs, selectionMode | languageTag 為 BCP 47 如 en, zh-TW；手動優先 |
| SubtitleCue | trackId, cueId, sequence, startMs, endMs, text | cue 時區無關；文字 UTF-8，容許重疊 |
| Playlist | id, ownerId, name, order, deletedAt? | 清單可以沒有綁定來源 |
| PlaylistEntry | playlistId, materialId, order | 同一教材可加入多清單 |
| FolderBinding | id, playlistId, sourceKind, displayLabel, localGrantRef, scanCursor? | `localGrantRef` 本機專用；跨裝置只同步來源類型與顯示名稱 |
| PlaybackProgress | ownerId, materialId, positionMs, state, sessionId, deviceId, sequence, serverUpdatedAt | 每個 user + material 一條 canonical 進度；衝突另有決策 |
| Bookmark | id, ownerId, materialId, trackId, trackRevision, languageTag, cueId, cueText, startMs, endMs, createdAt, deletedAt? | 保存 cue 原始快照；字幕更新時不丟棄，依文字與音訊時間重定位；歧義時保留未定位 |
| SyncOperation | id, userId, entityType, entityId, operation, payloadHash, attempts, nextRetryAt, state | 至少一次投遞；服務端冪等處理 |

## 3. Local SQLite / Drift
- `materials`, `media_assets`, `subtitle_tracks`, `subtitle_cues`, `playlists`, `playlist_entries`, `folder_bindings`, `playback_progress`, `bookmarks`, `sync_outbox`, `sync_state`。
- FK、唯一索引（ownerId+materialId；trackId+cueId 等）、必要 query index、migration test 必備。
- 保存本機下載路徑、最後檔案存在驗證、快取狀態；在登出時對不同帳號採隔離策略（具體見 ADR）。

## 4. Firestore 建議路徑（先審再建）
```text
users/{uid}/materials/{materialId}
users/{uid}/mediaAssets/{assetId}
users/{uid}/subtitleTracks/{trackId}
users/{uid}/playlists/{playlistId}
users/{uid}/playlists/{playlistId}/entries/{materialId}
users/{uid}/progress/{materialId}
users/{uid}/bookmarks/{bookmarkId}
```
二進位檔案：`users/{uid}/assets/{assetId}/{safeFilename}`。需 Security Rules 驗證 request.auth.uid == uid、內容大小/類型/metadata，並寫 Firebase Emulator rules 測試。客戶端絕不能自行決定其他人的 UID 路徑。

## 5. 事件和 API 契約
- `ImportRequested(sourceRef, playlistId?)` → `ImportResult(materialId, stage, errors)`
- `SubtitleSelected(materialId, languageTag, assetId, isManual)` → `SubtitleTrackChanged(revision)`
- `PlaybackCommand(materialId, action, positionMs?)` → `PlaybackSnapshot(positionMs, durationMs?, processingState, speed)`
- `ProgressRecorded(materialId, positionMs, sessionId, sequence)` → outbox 待上傳項目
- `FolderScanResult(bindingId, added, updated, missing, pendingDownload)` → 匯入協調器

## 6. 參考衝突範例
兩台裝置相同 material 不等於「最新收到的寫入即正確」。本機負責立即播放，雲端 canonical progress 使用 Session ID + monotonic sequence + server 時間戳驗證；無法判定先後時須保留兩個候選位置供使用者選擇。不要靠 client timestamp 單獨判斷。

## 7. 待決的 schema ADR
雲端 hash 去重限於同帳號或跨帳號（推薦同帳號）、字幕 cue anchor 遷移策略、登出時本機快取保留政策、清單刪除的墓碑保留期限，皆見 `12-decisions-and-risks.md`。

## 8. Stage 1 固定的持久化邊界

| 邊界 | Stage 1 契約 |
|---|---|
| 本機身分 | `profileKey` 為 app 內部的非路徑型 opaque key；有雲端帳號時將它映射到經驗證的 UID。Repository instance 只服務一個 profile。ID 按 §1 產生，雜湊表示內容而非教材身分。 |
| 本機列／參照 | 依 §3 的表規劃，library 以 `(ownerId, materialId)` 取教材，同 owner 的 `assetId` 為 FK；跨表參照須包含 owner 或受該 owner 的 DB 實體隔離約束。playlist entry 以 `(playlistId, materialId)`、cue 以 `(trackId, trackRevision, cueId)` 局部唯一。時間位置用非負整數毫秒，offset 可帶正負。 |
| 檔案資料 | 本機媒體以 app 私有區相對路徑表示，`localGrantRef`、來源絕對路徑、設備下載狀態不進 Firestore。雲端資產在 UID 內唯一，object key 由已核對的帳號與 asset ID 構成。 |
| Canonical 與候選 | `users/{uid}/progress/{materialId}` 保存 §2 進度欄位及遞增 `revision`。該文件下以 session stream 識別保存 high-water 與最新未決 checkpoint，候選有原 `baseRevision`，receipt 以 UID＋opId 唯一並記錄結果與 payload hash。沒有 canonical 時 revision 為 0。 |
| Durable outbox | `(ownerId, opId)` 唯一，含 entity、operation、revision／baseRevision、版本化 payload 及其 hash、attempts、nextRetryAt、lease deadline、state、lastError。索引覆蓋 `(ownerId, state, nextRetryAt)`。初始 schema version 1，SQLite migration、rules、receipt 保存期限需在實作工作包驗證。 |

Dart 骨架目前提供 `LearningMaterial`、`ProgressCheckpoint`、音訊狀態與資料夾 inventory。WP-02 建立 schema v1 的 Drift SQLite 邊界，實體化 `media_assets`、`materials`、`material_sources`；WP-03 升至 schema v2，透過 migration 加入 `subtitle_tracks`、`subtitle_cues`，保留原始 SRT bytes 與 cue 序號/時間/文字；WP-07 升至 schema v3，加入 owner/material scoped `bookmarks`，保留 track revision、cue text 與 offset-adjusted audio interval 快照；WP-08 升至 v4，加 durable `sync_outbox`；WP-09 升至 v5，新增 owner/material scoped `playback_progress`、`progress_stream_state`、`progress_conflicts` 及 profile-scoped `progress_device_identity`；WP-12 升至 v6，新增 account-scoped `playlists`、`playlist_entries`、本機 `folder_source_entries`，v5→v6 migration 不刪除既有教材或收藏。WP-16 升至 v7，沿用現有 `sync_outbox`，替本機來源教材的既有已選字幕補排 `publishSubtitles`。工作保存教材 ID、版本與 payload hash，字幕原始資料仍在 `subtitle_tracks`。

`folder_source_entries.relative_path` 僅本機保存，不可放入同步 payload。進度 payload 使用 `sync_outbox` 的穩定 opId/hash 與 ADR-012 的 session sequence/baseRevision；手動 resolve 在收到交易成功前不改 canonical。`SqliteSyncOutbox` 領取 material 與 subtitle 操作，progress 由獨立 `ProgressRepository`/`ProgressSyncCoordinator` 處理。Firestore transactions 留在正式 adapter，見 [ADR-012／027](12-decisions-and-risks.md)。每條字幕軌以 owner + material 外鍵關聯，選中軌每教材/語言至多一條；`material_sources` 以 `(ownerId, sourceKey, assetId)` 關聯匯入來源與教材，來源鍵不得保存原始路徑；細節見 [ADR-020／021／025](12-decisions-and-risks.md)。具體衝突、重試和刪除決策見 [ADR-009／012／014／019](12-decisions-and-risks.md)。
