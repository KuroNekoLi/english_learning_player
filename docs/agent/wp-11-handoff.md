# WP-11 交棒摘要：Mac 資料夾授權與掃描

## 契約與介面

- `FolderAccessGateway` 維持 Stage 1 契約：`pickFolder`、`restoreGrant`、`scan`、`watch`、`stageFile`、`disconnect`。
- Dart `MethodChannelFolderAccessGateway` 只轉換 platform channel DTO 為 `FolderHandle`、`FolderEntry`、`FolderFailure`；非 macOS provider 明確回報 providerUnavailable。
- Swift `FolderAccessPlugin` 透過 `NSOpenPanel` 取得使用者選擇，建立 read-only security-scoped bookmark，bookmark bytes 留在 app container 的 UserDefaults。Flutter 與雲端都不收到 bookmark/絕對來源路徑。
- `scan` 是全量 inventory；只列 M4A/MP3/SRT、回報相對路徑、byteLength、mtime 及 available/pendingDownload。metadata-only `NSFileCoordinator` 避免為枚舉強制下載檔案。`notDownloaded` 為 pending；`downloaded` 代表存在本機舊版，因此仍可讀。掃描任何失敗都回錯誤，不回傳可能被誤認為「來源缺失」的部分清單。
- `watch` 使用 FSEvents subtree stream，事件只表示需重掃；ViewModel 350ms debounce 後重做全量 scan。停止 stream 時釋放 FSEventStream 並停止 security scope。
- `stageFile` 限制在授權根目錄內，拒絕絕對路徑、`..`、任一路徑元件 symlink，對讀取使用 NSFileCoordinator，僅複製已下載檔至 app-owned staging；不改寫來源。
- Library macOS panel 只提供選擇、重掃、解除授權與 inventory 數量；教材匯入/reconcile/outbox 留 WP-12。

## 實際驗證

- `flutter test`: 全量 103 項 PASS；新增 T-FOLDER-01..10（MethodChannel 4、ViewModel 5、panel widget 1），覆蓋取消、DTO/status、失敗映射、watch event/rescan、初次未選資料夾、部分下載保留、權限撤銷、disconnect 及 panel 顯示。
- `flutter analyze`: PASS；`dart format .` PASS（80 files，格式化 1 個測試檔）；`dart format --output=none --set-exit-if-changed .` PASS（80 files，0 changed）。`git diff --check`: PASS。
- `flutter build macos --release`: PASS；`flutter build ios --simulator --debug`: PASS；`flutter build apk --debug`: PASS。Android build 以 `/tmp/wp11-flutter-config` 指定既有 JDK 17，不修改全域 Flutter 設定；建置出現 NDK 26.3 vs plugin 建議 27.0.12077973 warning，但完成產物。
- macOS 產物 `codesign` entitlements 確認 sandbox 與 user-selected read-only。此環境產物 ad-hoc signed，非 Developer ID 發佈簽章。
- 已用 sandboxed Release app 開啟系統 folder picker，手動取消；確認返回 App 且沒有建立來源授權。重啟 App 後首次未連線狀態正常顯示。
- 未選取任何使用者資料夾，故不宣稱真實 bookmark 重啟恢復/撤銷/搬移、iCloud placeholder、stage copy 或 FSEvents OS smoke 通過。完整驗證需使用者授權一個專用測試資料夾；要驗證分發簽章需 Developer ID 簽章設定。

## 已知邊界

- 本 WP 使用單一固定本機 binding ID `primary-icloud-source`，適合目前最小垂直切片；持久 FolderBinding/Playlist 建立與多來源管理留 WP-12。
- 沒有 Login Item。App 關閉期間不宣稱持續監看；啟動後授權恢復並全量重掃。
- FSEvents 漏失時由啟動/手動重掃恢復；事件本身不當作完整增量日誌。
- iOS/Android 只使用 unsupported gateway，沒有 folder picker/background scan。
- ADR-007/008 納入 WP-11 adapter、資料保護、官方 API 及未驗證限制。
