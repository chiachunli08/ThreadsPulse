# 修改來源與致謝 / Sources and acknowledgements

此儲存庫是 ThreadsPulse 的修改版。原專案與引用程式碼分別來自以下來源；本 fork 的整合程式碼與效能調整列在後段。

## 1. ThreadsPulse 原專案

- 來源：[mumuisdog/ThreadsPulse](https://github.com/mumuisdog/ThreadsPulse)。
- Fork 基礎提交：[8ef8bc92b6dec9889f6ba6d94f75d2aef0ffebc1](https://github.com/mumuisdog/ThreadsPulse/commit/8ef8bc92b6dec9889f6ba6d94f75d2aef0ffebc1)，上游插件版本 1.18.3。
- 提供 iOS tweak 架構、既有 Threads 增強功能、設定介面、側載相容修正、Theos 編譯設定、IPA 注入腳本及 GitHub Actions 基礎流程。
- 上游 `control` 中的 Author / Maintainer 為 `h4x_0x30vm`；原有作者資訊與 Git 歷史均予以保留。

## 2. Lee-Su-Threads 功能與程式碼

- 來源：[meettomorrow/lee-su-threads](https://github.com/meettomorrow/lee-su-threads)。
- 引用提交：[db0476fc10cc6a738c6a6eb49ed2f1dd89174419](https://github.com/meettomorrow/lee-su-threads/tree/db0476fc10cc6a738c6a6eb49ed2f1dd89174419)。
- 授權：MIT。完整原始授權聲明保留於 [vendor/lee-su-threads/LICENSE](vendor/lee-su-threads/LICENSE)，亦隨插件資源附上 `LeeSu-LICENSE.txt`。

| 本 fork 的檔案 | 引用或改寫來源 | 處理方式 |
|---|---|---|
| `vendor/lee-su-threads/profileParser.js` | `src/lib/profileParser.js` | 原檔保留，未修改 |
| `vendor/lee-su-threads/dateParser.js` | `src/lib/dateParser.js` | 原檔保留，未修改 |
| `vendor/lee-su-threads/location-flags.json` | `data/location-flags.json` | 原檔保留，未修改 |
| `tests/fixtures/profile-*.txt` | 上游同名測試資料 | 保留來源測試資料，用於解析回歸測試 |
| `scripts/leesu_bridge.js` | `src/injected.js` 的工作階段掃描與 About This Profile 請求 | 改寫為專用 WKWebView bridge，加入工作階段掃描重用、原生就緒通知、超時與錯誤處理 |
| `TPLeeSuCache.m` 的近期加入判斷 | `src/lib/dateParser.js` 的月份規則 | 以 Objective-C 實作月份判斷，並排除未來或無效月份 |
| `TPLeeSuLocation.m` | 上游地區映射表與「國旗＋地區名」顯示概念 | 以 Objective-C 做完整名稱比對，加入缺少的「臺灣／台湾」別名；保留未知或未分享的地點文字 |

`scripts/build_leesu_bridge.py` 會將解析器、日期處理與 bridge 組合為插件資源 `LeeSuBridge.js`，並複製地區映射表及 MIT 授權聲明。產生的資源也保留上述來源歸屬。

### 地區名稱資料的間接來源

Lee-Su-Threads 的地區映射表使用 [stefangabos/world_countries](https://github.com/stefangabos/world_countries) 的地區名稱資料，並加入其自己的別名與覆寫。本 fork 使用上述 Lee-Su-Threads 固定提交中的映射表，未另行下載或更新該資料集。

## 3. 本 fork 的新增與修改

目前插件版本為 **1.18.4-leesu.3**，整合目標為 Threads **455.0.0**。

- 將網頁資料查詢接到 iOS 原生貼文標頭與頭像標記，顯示「國旗 emoji＋地區名稱」及加入時間。
- 新增獨立的 Threads 網頁工作階段登入入口、原生資料列表、地點統計、JSON 匯出與快取清除。
- 新增依 user ID 儲存的 72 小時本機快取、欄位白名單、資料筆數限制及查詢失敗重試規則。
- 新增畫面內作者優先的查詢排程：首筆於工作階段就緒後立即啟動，後續至少間隔一秒，最多兩筆同時執行；捲離畫面的待查詢項目移出佇列，同一作者不重複查詢。
- 新增網頁文件就緒通知及 60 秒工作階段掃描重用，減少插件等待；保留 HTTP 429 的 15 分鐘冷卻機制。
- 擴充 GitHub Actions 的插件建置與回歸測試，並加入選填標籤的手動 IPA Release 設定。本次程式碼上傳未執行 IPA 建置或 IPA 發布。

主要修改提交：

- [54aafa8：原生整合、快取、設定與測試](https://github.com/chiachunli08/ThreadsPulse/commit/54aafa8b2dc3350e46c5c405ec75540840810dde)
- [139678e：國旗 emoji 與地區名稱顯示](https://github.com/chiachunli08/ThreadsPulse/commit/139678e205edd7ff67b93fd8afac540dbccd23a9)
- [a398999：查詢排程與讀取速度改善](https://github.com/chiachunli08/ThreadsPulse/commit/a398999495454b1c755237830abda779434f10ad)

上述說明用於區分原始來源與本 fork 的修改，並不將整個儲存庫重新宣告為 MIT 授權。MIT 聲明適用於對應的 Lee-Su-Threads 引用內容；上游其他作者資訊與聲明維持保留。

## 4. 上傳與驗證範圍

Git 儲存庫不包含原始或修改後的 Threads IPA，也不包含 Apple 簽名憑證或登入憑證。IPA 檔案副檔名已加入 `.gitignore`（包含大小寫變體）；GitHub Actions 的一般 Build 流程只產生插件及延伸功能產物。

已執行的測試包含 JavaScript 解析／bridge 測試、原生快取／日期／國旗顯示測試，以及查詢排程、併行上限與冷卻恢復測試。iOS 插件已通過 GitHub Actions 編譯；模擬排程時間不等同實際網路測速，仍需實機確認即時 API 與介面行為。

## English summary

This fork is based on **mumuisdog/ThreadsPulse** at the pinned revision above. It incorporates MIT-licensed parsing, date logic, location data, fixtures and adapted request/session logic from **meettomorrow/lee-su-threads**. Original credit and the full MIT notice are preserved. Territory-name data is indirectly sourced through Lee-Su-Threads from **stefangabos/world_countries**.

This fork adds the native WKWebView integration, profile cache and UI, flag labels, paced concurrent viewport scheduling, build configuration and tests described above. The MIT notice applies to the corresponding incorporated Lee-Su-Threads material; this document does not relicense the entire repository. Threads IPA files and credentials are excluded from the source upload.
