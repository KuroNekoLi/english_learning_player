# iCloud Drive 資料夾授權與同步（Apple 原生整合）

## 1. 架構定位
iCloud Drive 是**來源檔案系統**，不是跨 Android/iPhone/Mac 的資料同步後端。Mac 授權某資料夾 → 檢測變動 → 匯入本地 → Firebase 發佈；iPhone/Android 只需同 App 帳號即可取得雲端教材。

## 2. macOS 來源資料夾流程
```text
User selects folder via NSOpenPanel
 → Security-scoped bookmark saved locally
 → on launch resolve bookmark, renew stale bookmark
 → startAccessingSecurityScopedResource / NSFileCoordinator
 → initial full scan; observe FS events to schedule debounced rescans
 → enumerate M4A/MP3 + SRT; check completeness and iCloud availability
 → ImportReconciler (hash, filename, existing mapping)
 → Local Repository + SyncOutbox
 → stopAccessing... when finished; dispose watcher at teardown
```
- 不硬寫 `~/Library/Mobile Documents/com~apple~CloudDocs`；用系統授權的 URL。
- `FolderBinding` 顯示名稱、playlistId 可雲端同步；security bookmark 值只存在該 Mac。
- 授權被撤銷、檔案在雲端但未下載、資料夾移動、Case/Unicode 差異、命名碰撞都要可修復提示。
- FSEvents / `DispatchSource` 的事件只表示「需要再掃描」，並非可直接信任的完整異動日誌；啟動時完整 reconcile，長期執行亦定期 reconcile。
- 只允許**來源讀取**，不得反向刪除或改寫 iCloud 原始檔案。

## 3. iOS 限制與實作順序
MVP iOS 只同步 Firebase 教材，不要求 iPhone 自己監控 iCloud 資料夾。日後可用 `UIDocumentPickerViewController`、Security-Scoped URL 做使用者選取資料夾與前景掃描；iOS 系統不保證 App 被終止/長時間背景時仍能監控任意資料夾。這不是 Firebase 的 bug。

## 4. Flutter ↔ Swift 契約
以 [FolderAccessGateway](../lib/core/platform/folder_access_gateway.dart) 隔離原生授權及來源讀取。

- `pickFolder(bindingId): Future<FolderHandle?>` 接受新綁定 ID，使用者取消回傳 null。
- `restoreGrant(bindingId): Future<GrantStatus>` 回傳 valid、stale、denied 或 missing。
- `scan(bindingId): Future<List<FolderEntry>>` 取得完整 inventory 或失敗。pendingDownload 仍代表檔案存在。
- `watch(bindingId): Stream<void>` 通知應重新掃描，取消訂閱時停止觀察。
- `stageFile(bindingId, relativePath): Future<Uri>` 由原生協調讀取並複製到 app staging，以 app 所有的檔案 URI 交接。
- `disconnect(bindingId)` 停止 watcher 並釋放綁定的本機 grant。原始資料夾為唯讀。

Channel 錯誤需區分 permissionDenied、providerUnavailable、fileNotDownloaded、notFound、transientIo。授權細節見 [ADR-007／008](12-decisions-and-risks.md)。

WP-11 實作由 `MethodChannelFolderAccessGateway` 對應 Swift `FolderAccessPlugin`。原生只將 bookmark data 存在 App container 的 UserDefaults，不回傳或記錄絕對來源路徑；每次掃描/複製以 start/stop 成對管理 security scope。掃描只回傳相對路徑、檔案大小、修改時間與 available/pendingDownload，不表示教材已匯入。只有 `notDownloaded` 算待下載；`downloaded` 表示本機有較舊副本，仍可唯讀取用。FSEvents 事件僅作 inventory invalidation，Flutter 以 350ms debounce 後重做完整掃描。檔案複製時驗證相對路徑、拒絕路徑穿越與任一路徑元件 symlink，使用 NSFileCoordinator 讀取並複製到 app-owned staging。

## 5. 掃描與去重政策
- 先依檔案名稱、大小、修改日期判別候選，穩定後讀取 hash；未完整下載不視為刪除。
- 音檔先到、字幕後到：建立 provisional material，後補雙語 subtitle tracks。
- rename 不應無故生成重複教材；優先以綁定來源 ID + 內容 hash + 上次記錄判定。
- 清單 sourceMissing 是非破壞性狀態。只有明確「從 App 雲端移除」才提交刪除操作。
- 大量檔案分批，提供掃描進度，尊重 Mac 電量、網路及儲存空間限制。

WP-12 已實作本機第一條 reconciliation vertical slice：完整 inventory 成功返回後才將舊來源目錄標為缺席；available 音訊複製到帳號私有媒體並經 WP-02 importer 建立 material/outbox；本機 playlist entry 與來源目錄在 account DB 保存。pendingDownload 視為仍存在，不推導刪除。來源相對路徑只留在本機資料庫，不進雲端 payload。rename 只在同 binding 下找到唯一「本次未見的舊來源 + 相同 SHA-256」時沿用 material；多個候選保留為獨立教材，避免違反 ADR-020。字幕候選由 WP-03 matcher 精確 stem 比對，歧義不自動選；手動選取優先，字幕晚到的下一次 reconcile 會匯入，重複 bytes 不重複建立 track。來源缺席只標記 source catalog，不刪教材、playlist entry、bookmark 或 progress。

限制：本機 `sync_outbox` 與 `CloudSyncCoordinator` 目前只領取／發布 material 操作，故 playlist/folder binding 遠端 metadata 尚未建立傳輸契約；WP-12 不把此限制包裝成已同步。需要獨立核准 playlist metadata schema 和雲端 adapter 後再做遠端驗證。

## 6. macOS 常駐 Agent
可獨立規劃 `SMAppService` Login Item/Background Agent，但不納入最先端到端驗收。沒有 Login Item 時只有 App 程序正在運作才可能持續監控。Mac 必須開機、有網路、授權仍有效，才可能同步新檔。

## 7. Platform tests
- App restart bookmark 可恢復；搬移來源/撤銷授權後正確提示。
- 新增、變更、rename、部分寫入、SRT 晚到、空資料夾、icloud placeholder、重複檔案。
- FSEvents 漏失時全量掃描可補回。
- App 強制結束後不宣稱即時同步；重開後完成補掃。
- 使用 sandboxed macOS 實際簽章包測，而非只測 debug 模式。

WP-11 測試 ID T-FOLDER-01..10 覆蓋授權取消、grant 狀態與失敗映射、部分下載保留、watch invalidation/rescan、初次空狀態、解除授權及 Mac panel 顯示。macOS Release app 已建置並檢查到 app-sandbox + user-selected.read-only entitlement；實際 folder 授權、重啟恢復、撤銷以及 iCloud placeholder hydration 尚未在實際選取的測試資料夾中執行，不能以 fake 或 build 代替。
