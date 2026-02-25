# 基本指南

實驗 cumulus OS 版本為 5.12

## 預設啟動檔案 (Default Startup File)

NVUE 提供了一個預設的 `/etc/nvue.d/startup.yaml` 檔案，這相當於設備的出廠設定。如以下

* hostname：預設為 cumulus
* 防火牆規則
* 使用者：包含預設的 cumulus 帳號資訊
* API 服務：預設會啟用 NVUE API。

## 常用指令

下表格詳細列出了 NVIDIA **NVUE (Network Virtualization User Experience)** 的配置管理指令，主要用於 NVIDIA Cumulus Linux 交換機。NVUE 的核心邏輯是將配置分為「待定 (Pending)」與「已套用 (Applied)」，類似 Git 的提交機制。

以下為表格內容的中文翻譯與各指令的使用說明：

| 指令 | 翻譯與功能說明 |
| --- | --- |
| **`nv config apply`** | **套用配置**：將待定配置或特定版本儲存至啟動配置 (Startup-config)。 |
| **`nv config detach`** | **分離配置**：將目前的待定配置分離出來，並分配一個整數 ID 以便獨立編輯。 |
| **`nv config diff`** | **查看差異**：顯示不同版本之間、待定與已套用配置之間，或分離配置間的差異。 |
| **`nv config find`** | **搜尋配置**：在已套用的配置中根據關鍵字搜尋特定部分。 |
| **`nv config history`** | **操作歷史**：查看交換機配置變更的紀錄（包含 ID、時間、使用者及變更來源）。 |
| **`nv config patch`** | **增補配置**：使用指定的 YAML 檔案來「更新（增量修改）」待定配置。 |
| **`nv config replace`** | **替換配置**：使用指定的 YAML 檔案來「完全覆蓋（取代）」待定配置。 |
| **`nv config revision`** | **版本列表**：列出交換機上目前儲存的所有配置版本。 |
| **`nv config save`** | **儲存配置**：手動將已套用的配置寫入 `/etc/nvu.d/startup.yaml` 以確保重啟後生效。 |
| **`nv config show`** | **顯示配置**：以 **YAML 格式** 顯示目前已套用的配置。 |
| **`nv config show -o commands`** | **顯示指令**：將目前已套用的配置以 **CLI 指令格式**（nv set...）顯示。 |
| **`nv config diff -o commands`** | **顯示指令差異**：以 **CLI 指令格式** 顯示兩個配置版本間的差異。 |

1. 如何使用這些指令

在 NVUE 中，典型的操作流程是：**修改 (Set) -> 比對 (Diff) -> 套用 (Apply)**。

  * 安全套用配置 (`apply`)
    * 這是最重要的指令。為了防止配置錯誤導致斷網，建議使用 **確認機制**：
      * `nv config apply --confirm 10m`：套用配置後，你必須在 10 分鐘內確認，否則系統會自動回滾 (Rollback) 到變更前的狀態。
      * `nv config apply --assume-yes`：如果你很確定，可以使用此參數跳過所有確認提示。

  * 檔案管理 (`patch` vs `replace`)

    * 如果你只想修改一個介面參數，請用 `patch`。
    * 如果你想讓整台交換機的狀態與你的檔案一模一樣（刪除檔案中未提到的所有配置），請用 `replace`。

  * 搜尋與排錯 (`find` & `diff`)
    * **搜尋**：例如 `nv config find swp1` 會直接顯示所有關於第一號物理接口的配置。
    * **比對**：在輸入 `apply` 之前，強烈建議先執行 `nv config diff` 看看自己到底改了什麼，避免誤刪配置。

  * 格式切換 (`-o commands`)
    * NVUE 預設輸出是 YAML（適合機器讀取或自動化），但對於人類維運來說，`nv config show -o commands` 產生的 `nv set ...` 指令格式更直觀，方便複製到其他設備執行。
  * 持久化 (`save`)
    * 如果你的系統設定 `auto save` 為關閉狀態，請務必在 `apply` 之後執行 `nv config save`，否則交換機重啟後會回到舊的設定。


當執行 `nv config apply` 時，NVUE 會自動將設定同步寫入到底層 Linux 檔案，例如 `/etc/network/interfaces` 和 `/etc/frr/frr.conf`。也不要手動修改上述的底層 Linux 檔案。若有自動化需求（如使用 Ansible），需參考[忽略 Linux 檔案](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-512/System-Configuration/NVIDIA-User-Experience-NVUE/NVUE-CLI/#configure-nvue-to-ignore-linux-files)的相關設定。

需要特別注意

1. 不要隨意 Replace，除非 YAML 檔案包含了完整的預設帳戶資訊，否則請用 `patch` 代替 `replace`，避免把 cumulus 帳號洗掉。
2. 不要手動改底層，一旦開始使用 NVUE，就放棄手動修改 /etc/network/interfaces 的習慣，避免配置衝突。
3. 確保 nvue-startup.service 已啟用，否則重啟後的配置將會失效。

### 範例

正常流程

|階段|API 動作| NVUE 指令|
|---|---|---|
|Stage 1: 預備|生成 YAML 設定|自動化邏輯|
|Stage 2: 注入|將變更寫入 Pending|`nv config patch`|
|Stage 3: 稽核|回傳差異給管理 UI|`nv config diff`|
|Stage 4: 套用|帶回滾機制的套用|`nv config apply --confirm`|
|Stage 5: 結束|持久化並紀錄歷史|`nv config save & history`|

錯誤流程

|階段| API 動作 |NVUE 指令與邏輯|目的|
|---|---|---|---|
|Stage 1. 請求接收|管理者提交 YAML|(Python API 接收資料)|啟動配置事務。|
|Stage 2. 預備注入|執行配置補丁|`nv config patch <file.yaml>`|將變更併入待定緩衝區。|
|Stage 3. 失敗偵測|檢查指令回傳|判斷 HTTP Return Code|偵測語法或邏輯錯誤。|
|Stage 4. 隔離清理|執行分離 (核心)|`nv config detach`|清空待定緩衝區|將錯誤配置丟入沙盒。|
|Stage 5. 錯誤回報|回傳失敗訊息|(傳回 stderr 錯誤內容)|讓管理者知道出錯位置並保持系統乾淨。|

## 參考資源

[nvidia | NVUE CLI 5.12](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-512/System-Configuration/NVIDIA-User-Experience-NVUE/NVUE-CLI/#)
