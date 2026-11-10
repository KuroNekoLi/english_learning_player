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
建議以 `FolderAccessGateway` 介面隔離：
- `pickFolder(): Future<FolderHandle?>`：使用者取消回傳 null。
- `restoreGrant(bindingId): Future<GrantStatus>`：valid/stale/denied/missing。
- `scan(bindingId): Stream<FolderScanEvent>` 或一次性 `ScanResult`，不得將大量完整檔案位元組直接經 MethodChannel 傳遞。
- `watch(bindingId)`：macOS foreground/session watcher，增量變更只通知重新掃描。
- `disconnect(bindingId)`：撤銷 App 綁定、停止 watcher，不觸碰原資料夾。
Channel 的 error code 應可區分 cancelled、permissionDenied、providerUnavailable、fileNotDownloaded、notFound、transientIO。

## 5. 掃描與去重政策
- 先依檔案名稱、大小、修改日期判別候選，穩定後讀取 hash；未完整下載不視為刪除。
- 音檔先到、字幕後到：建立 provisional material，後補雙語 subtitle tracks。
- rename 不應無故生成重複教材；優先以綁定來源 ID + 內容 hash + 上次記錄判定。
- 清單 sourceMissing 是非破壞性狀態。只有明確「從 App 雲端移除」才提交刪除操作。
- 大量檔案分批，提供掃描進度，尊重 Mac 電量、網路及儲存空間限制。

## 6. macOS 常駐 Agent
可獨立規劃 `SMAppService` Login Item/Background Agent，但不納入最先端到端驗收。沒有 Login Item 時只有 App 程序正在運作才可能持續監控。Mac 必須開機、有網路、授權仍有效，才可能同步新檔。

## 7. Platform tests
- App restart bookmark 可恢復；搬移來源/撤銷授權後正確提示。
- 新增、變更、rename、部分寫入、SRT 晚到、空資料夾、icloud placeholder、重複檔案。
- FSEvents 漏失時全量掃描可補回。
- App 強制結束後不宣稱即時同步；重開後完成補掃。
- 使用 sandboxed macOS 實際簽章包測，而非只測 debug 模式。
