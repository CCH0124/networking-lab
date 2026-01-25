# [Multi-Chassis-Link-Aggregation(MLAG)](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-514/Layer-2/Multi-Chassis-Link-Aggregation-MLAG/#)

MLAG 使得一台伺服器或交換器，能夠將其『雙埠口 bond』(例如 LAG、EtherChannel、port group 或 trunk) 分別連接到**兩台不同的交換器**上，但運作起來就像是連接到**一台單一的邏輯交換器**一樣。

這提供了**更強的備援能力 (redundancy)** 和**更大的系統吞吐量 (throughput)**。

（透過 MLAG）雙重連接的設備可以建立 LACP bond，使其鏈路同時包含到每一台實體交換器的連線；儘管它們連接到兩台不同的實體交換器，Cumulus Linux 仍然支援來自這些雙重連接設備的 **active-active (主動-主動) 鏈路**。


MLAG 最重要的價值：**它把兩台交換器「偽裝」成一台**。

1.  **解決了什麼問題？ (The Problem)**
    * 傳統的 LAG (Bonding/Port-Channel) 只能接往「同一台」交換器。如果那台交換器當機，整台伺服器就斷線了。

2.  **MLAG 如何運作？ (The Solution)**
    * 它允許你把 LAG 的兩條線，**一條接 A 交換器，一條接 B 交換器**。
    * A 和 B 交換器透過 MLAG 技術同步資訊，讓伺服器「誤以為」A 和 B 其實是同一台設備。

3.  **主要優勢 (Benefits)**
    * **備援 (Redundancy)**：A 交換器當機（或需要維護重開），B 交換器會無縫接手，伺服器完全不會斷線。
    * **吞吐量 (Throughput)**：因為 Cumulus 支援 **Active-Active** LACP，這代表伺服器到 A 和 B 的**兩條鏈路是同時都在傳輸資料的**（頻寬加倍），而不是一條在跑、一條在睡 (Active-Standby)。

這張圖展示了 MLAG 的兩種主要應用情境，核心觀念就是「**把兩台變一台**」。

## How Does MLAG Work?
### 1. 基礎應用：伺服器高可用性 

![](https://docs.nvidia.com/networking-ethernet-software/images/cumulus-linux/mlag-basic-setup.png)

* **解決的問題**：傳統的 LAG (Port-Channel) 只能接同一台交換器。如果那台交換器掛了，伺服器就斷線了。
* **MLAG 做法**：
    * `leaf01` 和 `leaf02` 設定為「MLAG Peers」(對等體)，它們會彼此同步 LACP 和 MAC Table 資訊。
    * `server01` 只需要設定一個**標準的 LACP Bond** (LAG)，一條線接 `leaf01`，一條線接 `leaf02`。
    * 對 `server01` 來說，它**完全不知道**自己接了兩台交換器。它以為 `leaf01` 和 `leaf02` 是**同一台邏輯交換器**。
* **好處**：
    1.  **設備備援 (Redundancy)**：`leaf01` 當機或重開，`server01` 的流量會無縫切換到 `leaf02`，不會斷線。
    2.  **Active-Active 頻寬**：兩條鏈路**同時運作**傳輸流量，頻寬加倍 (Full-duplex)。

### 2. 進階應用：Spine-Leaf 架構

![](https://docs.nvidia.com/networking-ethernet-software/images/cumulus-linux/mlag-two-pair.png)

* **擴展應用**：MLAG 不只可以用在「伺服器端」(Downlink)，也可以用在「交換器對交換器」(Uplink)。
* **做法**：
    * `leaf01` 和 `leaf02` 組成一個 MLAG Peer (邏輯 Leaf 交換器)。
    * `spine01` 和 `spine02` 也組成另一個 MLAG Peer (邏輯 Spine 交換器)。
    * "邏輯 Leaf" 再和 "邏輯 Spine" 建立一個跨機箱的 LAG。
* **好處**：
    * 這建立了一個**完全無 L2 迴圈 (Loop-free)** 且**全 active-active** 的 L2 網路架構。
    * 無論是 Leaf 還是 Spine 層的任何一台交換器單點故障，整張網路都能正常運行，且所有路徑都能被充分利用。
* **彈性**：如原文所提，MLAG 不限制你只能用兩條線，你可以從伺服器拉 4 條線 (2 條去 leaf01, 2 條去 leaf02)，它們都會被綁成同一個大 LAG。


## LACP and Dual-connected Links


![](https://docs.nvidia.com/networking-ethernet-software/images/cumulus-linux/mlag-dual-connect.png)

兩台 Leaf 交換器 (leaf01, leaf02) 互連。三台伺服器 (server01, 02, 03) 均建立 bond，並將鏈路分散連接到 leaf01 和 leaf02。

這段完美解釋了 MLAG 的「黑魔法」：**如何欺騙伺服器，讓它以為兩台交換器是同一台**。

1.  **LACP 是關鍵**
    * MLAG 依賴**標準的 LACP (802.3ad)** 協定來運作。
    * **雙方都必須啟用 LACP**：伺服器端 (Host) 和兩台 MLAG 交換器 (Leafs) 都必須設定 LACP。

2.  **伺服器端：保持單純 (Keep it Simple)**
    * 對伺服器 (server01) 來說，它**完全不需要知道 MLAG 的存在**。
    * 伺服器管理者只需要做一個**標準的 LACP Bond (LAG)**，然後一條線插到 `leaf01`，一條線插到 `leaf02`。

3.  **交換器端：LACP 偽裝 (The "Magic")**
    * 這才是 MLAG 的核心。`leaf01` 和 `leaf02` 會「共謀」偽裝成同一台設備。
    * 當 `server01` 發出 LACP 封包時，`leaf01` 和 `leaf02` 在回覆 LACP 封包時，會使用一個**共享的、虛擬的「LACP System ID」** (而不是各自的 MAC 位址)。
    * **結果**：`server01` 同時收到 `leaf01` 和 `leaf02` 的 LACP 回應，但因為它們的 **System ID 完全相同**，`server01` 會「誤以為」這兩條線路是插在**同一台交換器**的不同插槽上，因此**同意**建立 LACP Bond，並進入 Active-Active 模式。

4.  **同步機制 (The "Sanity Check")**
    * `leaf01` 和 `leaf02` 之間需要一個機制來確認 MLAG Bond 是健康的。
    * 這就是 `clagd` 服務的功用：
        * `leaf01` 告訴 `leaf02`：「嘿，我這邊看到了 `server01` 的 MAC (MAC-S1)，它在 `clag-id 10` 裡」。
        * `leaf02` 告訴 `leaf01`：「嘿，我也看到了 `server01` 的 MAC (MAC-S1)，它也在 `clag-id 10` 裡」。
    * 當雙方**比對 MAC 清單和 `clag-id` 都匹配**時，就確認這個 MLAG Bond 已成功建立且運作正常。

## 配置

1. 將每個從雙連接設備連接到 MLAG 對的界面都放入一個 Bond 中，即使該 Bond 在單一實體交換器上僅包含一條鏈路。

interface

```bash
...
auto bond1
iface bond1
    alias bond1 on swp1
    bond-slaves swp1
...

auto bond2
iface bond2
    alias bond2 on swp2
    bond-slaves swp2
...

```

NVUE 

```yaml
...
    interface:
      bond1:
        bond:
          lacp-bypass: on
          member: # this
            swp1: {}
          mlag:
            enable: on
            id: 1
        bridge:
          domain:
            br_default:
              access: 10
        link:
          mtu: 9000
        type: bond
      bond2:
        bond:
          lacp-bypass: on
          member: # this
            swp2: {}
          mlag:
            enable: on
            id: 2
        bridge:
          domain:
            br_default:
              access: 20
        link:
          mtu: 9000
        type: bond

```

2. 為每個 `bond` 新增唯一的 MLAG ID


必須為每台對等交換器 (peer switch) 上的每一個**雙重連接 (dual-connected) bond**指定一個唯一的 MLAG ID (clag-id)，這樣交換器才能知道哪些鏈路是雙重連接的，或是連接到同一台主機/交換器。

這個值必須介于 1 到 65535 之間，並且在**兩台對等交換器上必須相同**。

* **用途**：`clag-id` 是**兩台交換器之間用來「認親」的暗號**。
* `leaf01` 上的 `bond1` 和 `leaf02` 上的 `bond1` **必須設定完全相同的 `clag-id`** (例如 ID 1)。
* **邏輯**：當兩台交換器都發現自己有一個 `clag-id` 為 1 的 Bond 時，它們就知道：「OK，這兩個 Bond 是 MLAG 夥伴，它們底下接的是同一台伺服器」。
* **唯一性**：`bond1` (e.g., 接 server01) 和 `bond2` (e.g., 接 server02) 的 `clag-id` 必須不同 (e.g., ID 1 vs ID 2)。

> `clag-id` 設為 0 會停用該 bond 上的 MLAG 功能。

interface

```bash
...
auto bond1
iface bond1
    alias bond1 on swp1
    bond-slaves swp1
    clag-id 1 # this

auto bond2
iface bond2
    alias bond2 on swp2
    bond-slaves swp2
    clag-id 2 # this
...
```

NVUE

```yaml
    interface:
      bond1:
        bond:
          lacp-bypass: on
          member:
            swp1: {}
          mlag: # this
            enable: on
            id: 1 # this
        bridge:
          domain:
            br_default:
              access: 10
        link:
          mtu: 9000
        type: bond
      bond2:
        bond:
          lacp-bypass: on
          member:
            swp2: {}
          mlag: # this
            enable: on
            id: 2 # this
        bridge:
          domain:
            br_default:
              access: 20
        link:
          mtu: 9000
        type: bond
```

3. 將上面建立的 bound 新增到 bridge

本實驗將 bond1 和 bond2 添加到一個 VLAN-aware bridge。

**必須**將 MLAG bond 上設定的**所有 VLAN** 都添加到 bridge 中，這樣一來，當 MLAG bond 發生故障時，連接到下游設備的流量才能透過 peerlink (對等體鏈路) 重新導向。

* **用途**：MLAG Bond (`bond1`) 本身只是一個 L2 的 LAG。必須把它當作一個普通的 Trunk Port，加入到系統的 VLAN-aware bridge (e.g., `bridge`) 裡，它才能開始轉發 L2 流量。
* **(VLAN 一致性)**：
      * **所有**允許在 `bond1` (MLAG Bond) 上通過的 VLAN，**也必須**被加到 `bridge` 介面的 `bridge-vids` (VLAN 列表) 中。
      * **原因 (Failover)**：假設 `leaf01` 的 `bond1` 斷線，`server01` 的流量會全部改走 `leaf02`。如果 `server01` 的流量需要去到 `leaf01` 後面的設備，流量就必須跨越 peerlink (MLAG 互連線) 從 `leaf02` 跑到 `leaf01`。如果 `leaf01` 的 `bridge` 根本不認識這個 VLAN，封包一過來就會被丟棄，導致 failover (容錯轉移) 失敗。

Interface 

```bash
...
auto bridge
iface bridge
    bridge-ports bond1 bond2
    bridge-vlan-aware yes
...
```

NVUE

```yaml
    interface:
      bond1:
        bond:
          lacp-bypass: on
          member:
            swp1: {}
          mlag:
            enable: on
            id: 1 
        bridge: # this
          domain:
            br_default:
              access: 10
        link:
          mtu: 9000
        type: bond
      bond2:
        bond:
          lacp-bypass: on
          member:
            swp2: {}
          mlag:
            enable: on
            id: 2 
        bridge: # this
          domain:
            br_default:
              access: 20
        link:
          mtu: 9000
        type: bond
```

4. 建立跨機箱 Bond（Inter-Chassis Bond）以及對等鏈路 VLAN（作為 VLAN 子介面）

此外，還需要提供以下配置項目：

- 對等鏈路 IP 位址（Peer Link IP Address）
  - 為對等鏈路分配專用的 IP 位址，用於對等交換器之間的通信。
- MLAG Bond 介面（MLAG Bond Interfaces）
  - 配置 MLAG Bond 中的介面，這些介面負責連接雙連接設備。
- MLAG 系統 MAC 位址（MLAG System MAC Address）
  - 分配一個全局唯一的系統 MAC 位址，該位址用於標識 MLAG 作為單一邏輯系統。
- 備援介面（Backup Interface）
  - 指定一個備援介面，用於在對等鏈路發生故障時承擔流量轉發的角色。

* 預設情況下，Cumulus Linux 會將機箱間 bond 命名為 `peerlink`，peer link VLAN 命名為 `peerlink.4094`。使用 `peerlink.4094` 來確保此 VLAN **獨立於 bridge 和 STP**。
* Peer link IP 是一個 L3 位址，用於兩台交換器之間的 L3 連通性。
* Nvidia 提供了一個保留的 MAC 位址範圍（介於 44:38:39:ff:00:00 和 44:38:39:ff:ff:ff 之間），可用於 MLAG。使用此範圍內的 MAC 地址可避免與相同橋接網絡中的其他介面發生衝突：
  * 不要使用組播 MAC 地址（Multicast MAC Address）。
  * 不要在不同的 MLAG 組中使用相同的 MAC 地址；確保為網絡中的每對 MLAG 配對指定不同的 MAC 地址。
* **備援 IP 位址 (Backup IP)** 是當 peer link 斷線時，交換器會使用的 L3 備份介面
  * **必須**添加此 IP，且它**必須**與 peer link IP 不同
  * 確保有路由可以不透過 peer link 就能連到此備份 IP (例如使用 loopback 或管理 IP)。建議使用交換器的回環（Loopback）或管理 IP 地址作為備援 IP 地址。


Interface

```bash
auto br_default
iface br_default
    # 將介面橋接再一起
    bridge-ports bond1 bond2 bond3 peerlink vxlan48
    hwaddress 44:38:39:22:01:b1
    bridge-vlan-aware yes
    bridge-vids 10 20 30
    bridge-pvid 1
...
auto peerlink
iface peerlink
    bond-slaves swp49 swp50
    bond-mode 802.3ad
    bond-lacp-bypass-allow no
auto peerlink.4094
iface peerlink.4094
    clagd-peer-ip linklocal # this
    clagd-priority 1000
    clagd-backup-ip 10.10.10.2 # this 另外一台 switch IP
    clagd-sys-mac 44:38:39:FF:00:AA # this MLAG MAC
    clagd-args --initDelay 10
```

NVUE


```yaml
...
    interfaces:
      peerlink:
        bond:
          member:
            swp49: {}
            swp50: {}
        type: peerlink
      peerlink.4094:
        base-interface: peerlink
        type: sub
        vlan: 4094
...
    mlag:
      backup:
        10.10.10.2: {} # this
      enable: on
      init-delay: 10
      peer-ip: linklocal # this
      priority: 1000
```


MLAG 同步兩個對等交換器之間的動態狀態，但不會同步交換器的配置。因此，在修改其中一台對等交換器的配置後，*必須在另一台對等交換器上進行相同的更改*。這適用於所有配置更改，包括：

- 埠(Port)配置：如 VLAN 成員資格、MTU 和綁定參數等。
- 橋接(Bridge)配置：如生成樹(spanning tree)參數或橋接屬性等。
- 靜態地址(Static address)條目：如靜態 FDB 條目和靜態 IGMP 條目等。
- QoS 配置：如 ACL 條目（訪問控制列表）。


##### 1. Peerlink：L2/L3 心跳主線
* `peerlink` 是兩台 MLAG 交換器 (如 leaf01, leaf02) 之間的「主動脈」。
* 它本身是一個 **L2 Bond** (範例中用 `swp49`, `swp50` 綁定)，這是為了 Peerlink 自身的線路備援。
* **最關鍵的設計**：Cumulus **不在**這個 L2 Bond 上跑 L2 流量，而是在它上面建立一個 **L3 子介面 (`peerlink.4094`)**。
* 這兩台交換器是透過這個 L3 介面來溝通、同步所有 MLAG 狀態。

##### 2. VLAN 4094 (L3 Only)
* `VLAN 4094` 是 Cumulus 保留給 MLAG Peerlink 專用的。
* 你**絕對不能**把 `VLAN 4094` 加入到 L2 Bridge (`bridge-vids`) 中。
* 它**不是**用來傳輸一般資料的 VLAN，它**只**是用於兩台交換器之間 L3 通訊的點對點 (Point-to-Point) 鏈路。

##### 3. Backup IP：防止「Split-Brain」的生命線
* **什麼是 Split-Brain (腦裂)？**：
    * 情境：`leaf01` 和 `leaf02` 之間的 `peerlink` (主動脈) 斷了。
    * `leaf01` 認為 `leaf02` 掛了；`leaf02` 也認為 `leaf01` 掛了。
    * **後果**：兩台交換器都認為自己是「主」(Primary)，都啟用了伺服器連線。這會造成 L2 網路大混亂和嚴重丟包。
* **Backup IP 的作用 (防止腦裂)**：
    * 這是一個「帶外 (Out-of-Band)」的 L3 備援心跳，通常是**管理埠口 (mgmt port)** 的 IP。
    * 當 `peerlink` 斷線時，`leaf01` 會立刻透過管理網路去 `ping` `leaf02` 的備份 IP。
    * **情境 1 (Ping 成功)**：`leaf01` 知道 `leaf02` 其實還活著，只是 Peerlink 斷了。它會立刻把自己設為「次要」(Secondary)，關閉所有 MLAG 埠口，讓流量全部由 `leaf02` 處理。**(避免了 Split-Brain)**
    * **情境 2 (Ping 失敗)**：`leaf01` 確定 `leaf02` 真的當機了，於是它會接管所有流量，成為「主要」(Primary)。

##### 4. MLAG System MAC：共享的 L2 身份
* `mlag mac-address ...` 這個指令是設定這「一對」MLAG 交換器**共用的虛擬 MAC**。
* 當伺服器發送 LACP 封包時，`leaf01` 和 `leaf02` 都會用這個「共享 MAC」來回應。
* 這才能「欺騙」伺服器，讓它以為自己只接到了**一台**交換器，進而同意建立 LACP Bond。

##### 5. 沒有「設定檔」同步
* MLAG 只會同步動態狀態 MAC Table 等，它**不會**幫你同步設定檔(`interfaces`)。
* 如果你在 `leaf01` 新增了 `VLAN 20`，你**必須**也手動到 `leaf02` 去新增 `VLAN 20`。

### Set Roles and Priority

每對啟用了 MLAG 的交換器中，每台交換器都有一個角色。當兩台交換器建立對等關係時，其中一台會被指定為 **主角色（Primary Role）**，另一台則被指定為 **次角色（Secondary Role）**。

- 當啟用了 MLAG 的交換器處於 **次角色** 時，它不會在雙連接鏈路（Dual-Connected Links）上發送 STP BPDU（生成樹協議橋接協議數據單元）；它只會在單連接鏈路（Single-Connected Links）上發送 BPDU。
- 而處於 **主角色** 的交換器，則會在所有的單連接和雙連接鏈路上發送 STP BPDU。

預設下，交換器比較 `peerlink` 兩端的 MAC 位址來確定角色；MAC 位址較低的交換器將被指定為主角色（Primary Role）。可以用 `priority` 來覆蓋該預設行為，手動指定主角色的交換器。

interface

```bash
auto peerlink.4094
iface peerlink.4094
    clagd-peer-ip linklocal 
    clagd-priority 1000 # this
    clagd-backup-ip 10.10.10.2
    clagd-sys-mac 44:38:39:FF:00:AA
    clagd-args --initDelay 10
```

NVUE 

```yaml
...
    mlag:
      backup:
        10.10.10.2: {}
      enable: on
      init-delay: 10
      peer-ip: linklocal
      priority: 1000 # this
...
```

#### Peer Link Sizing

##### 1. 最大的誤解：Peerlink 只跑心跳 (Heartbeat)
* **錯誤**：以為 Peerlink 只跑 `clagd` 的 LACP/MAC 同步訊號，所以隨便給 1G 就夠了。
* **實質上**：正常情況下，Peerlink 流量**確實很小**。但它的設計**不是**為了「正常情況」，而是為了「**故障和非對稱流量**」。

##### 2. Peerlink 的真正考驗：「單線主機」
Peerlink 頻寬的主要用途，是處理「**非對稱 (asymmetric) L2 流量**」。

* **情境**：
    1.  一台主機 (`server01`) 因為故障（或硬體限制），**只**連接到 `leaf01`。
    2.  此時，上游的 Spine 交換器**不知道**這件事。Spine 依然會執行 ECMP 負載平衡，把要送給 `server01` 的流量**一半丟給 `leaf01`** (路徑正確)，**另一半丟給 `leaf02`** (路徑錯誤)。
    3.  當流量抵達 `leaf02` (錯誤的交換器) 時，`leaf02` 查詢 MAC 表，發現 `server01` 的 MAC 是從 `peerlink` 學來的。
    4.  `leaf02` **必須**將這些「走錯路」的流量，**透過 Peerlink 轉發給 `leaf01`**，`leaf01` 才能把它送給 `server01`。
    
##### 3. 容量規劃公式 (Rule of Thumb)

重點：

**Peerlink 總頻寬 ≥ (機櫃內「總單線頻寬」) / 2**

* **什麼是「總單線頻寬 (Total Single-Attached Bandwidth)」？**
    * 就是你預期在「最糟情況」下，會有多少流量是單邊連接的。
* **範例解讀**：
    ![](https://docs.nvidia.com/networking-ethernet-software/images/cumulus-linux/mlag-peerlink-sizing.png)
    * 3 台主機，每台都是 2x10G。
    * **最糟情境**：`leaf01` 故障，3 台主機全部變成「單線」(10G) 連接到 `leaf02`。
    * **總單線頻寬** = 10G * 3 台 = 30G。
    * **Peerlink 需求** = 30G / 2 = 15G。
    * **為什麼除以 2？** 因為上游 Spine 還是會把 30G 流量的一半 (15G) 丟給死掉的 `leaf01` (假設 `leaf01` 只是 port 壞，機器還活著)，或丟給 `leaf02` (如果 `leaf01` 全死)，但重點是：**總會有 50% 的流量會走錯路** (在這個案例中，是 *回程* 流量)，必須穿過 Peerlink。
    * **設計**：因此 Peerlink 設計為 2x10G (20G)，大於 15G，較安全。

* **Peerlink 絕對要 Bond**：Peerlink 本身就是一個「單點故障 (SPOF)」，你**必須**用至少兩條實體線路來做 Bond (LAG)，防止 Peerlink 自己斷線。
* **不要省 Peerlink 頻寬**：Peerlink 的頻寬**不是**用來應付「平時」，而是用來應付「**故障時**」的流量繞行。如果頻寬不足，平時沒事，一但發生故障，Peerlink 就會塞爆，導致整個機櫃的服務癱瘓。


#### Peer Link Routing
在 MLAG 環境中啟用路由協定時，管理上行鏈路 (Uplinks) 也同樣必要；預設情況下，MLAG **不會**感知 L3 (第三層) 的上行鏈路介面。如果 Peer link 發生故障，MLAG **不會**自動移除靜態路由，也**不會**關閉 BGP 或 OSPF 鄰居關係（除非你使用像 `ifstated` 這樣的獨立鏈路狀態服務）。

當你將 MLAG 與 VRR (虛擬路由器備援) 一起使用時，請在 `peerlink.4094` 介面上建立一個 L3 路由鄰居關係。如果 peer link 之間沒有建立 L3 路由連線，那麼在 MLAG 對中的一台交換器發生上行鏈路故障期間，如果目的地在該台『上行鏈路已斷』的交換器上，出口流量將無法轉發（導致黑洞）。


```yaml

...
      default:
        router:
          bgp:
            address-family:
              ipv4-unicast:
                enable: on
                redistribute:
                  connected:
                    enable: on
              l2vpn-evpn:
                enable: on
            enable: on
            neighbor:
              peerlink.4094: # this
                peer-group: underlay
                type: unnumbered
                ....
            peer-group: # this
              underlay:
                address-family:
                  l2vpn-evpn:
                    enable: on
                remote-as: external

```

#### 1. 核心問題：L2 故障，L3 不知道 (L2/L3 Mismatch)
* **MLAG 是 L2 技術**：它只負責同步 MAC 表、確保 L2 迴圈。
* **Routing 是 L3 技術**：BGP/OSPF 只關心 L3 鄰居是否存活。
* 如果 `peerlink` (MLAG 的 L2/L3 心跳線) 斷了，MLAG L2 容錯會啟動，但 **BGP/OSPF 鄰居關係可能不會斷** (如果 L3 路由是走 UPLINK)，或者靜態路由**不會**自動移除。
* 這會造成「**流量黑洞 (Black Hole)**」。一台交換器 (e.g., leaf01) 的 Uplink 斷了，但 leaf02 依然認為 leaf01 的 L3 路由是可達的，繼續把流量轉發給 leaf01，導致流量丟失。

##### 2. 解決方案：在 Peerlink 上建立 L3 鄰居
* **目的**：讓 L3 (路由) 的狀態和 L2 (MLAG) 的狀態**綁定在一起**。
* **做法**：強制 BGP 或 OSPF **也**透過 `peerlink.4094` 這個 L3 介面建立鄰居關係。
* **運作原理**：
    1.  `peerlink` (實體線路) 斷線。
    2.  `peerlink.4094` (L3 介面) 立刻變為 `Down`。
    3.  跑在 `peerlink.4094` 上的 BGP/OSPF 鄰居關係**立即中斷**。
    4.  L3 路由表**立刻**撤除 (withdraw) 來自故障 Peer 的路由。
* 這等於是為 L3 路由協定增加了一個「保險絲」。Peerlink 一斷，L3 路由立刻跟著斷，確保流量 100% 轉移到健康的 Peer，**徹底解決 L3 黑洞問題**。這在 MLAG + VRR (L3 閘道) 環境下**是標準必要設定**。


### 4. 設定提醒
* `peerlink.4094` 預設只有 IPv6 Link-Local IP。
* 如果你要跑 BGP，可以用 Unnumbered (直接`neighbor peerlink.4094`)，很方便。
* 如果你要跑 OSPFv2 (for IPv4)，你**必須**手動幫 `peerlink.4094` 加上 IPv4 位址 (如範例中的 `/30`)。

## 驗證
1. Status

```bash

root@leaf01:/# nv show mlag
                operational                applied     description
--------------  -------------------------  ----------  ---------------------------------------------------------------------
enable                                     on          Turn the feature 'on' or 'off'.  This feature is disabled by default.
debug                                      off         Enable MLAG debugging
init-delay                                 10          The delay, in seconds, before bonds are brought up.
mac-address     44:38:39:ff:00:aa          auto        Override anycast-mac and anycast-id
peer-ip         fe80::a8c1:abff:febf:e316  linklocal   Peer Ip Address
priority        1000                       1000        Mlag Priority
[backup]        10.10.10.2                 10.10.10.2  Set of MLAG backups
anycast-ip      10.0.1.12                              Vxlan Anycast Ip address
backup-active   True                                   Mlag Backup Status
backup-reason                                          Mlag Backup Reason
local-id        aa:c1:ab:d3:09:fe                      Mlag Local Unique Id
local-role      primary                                Mlag Local Role
peer-alive      True                                   Mlag Peer Alive Status
peer-id         aa:c1:ab:bf:e3:16                      Mlag Peer Unique Id
peer-interface  peerlink.4094                          Mlag Peerlink Interface
peer-priority   2000                                   Mlag Peer Priority
peer-role       secondary                              Mlag Peer Role
```

2. interface 資訊

```bash
root@leaf01:/# clagctl
The peer is alive
     Our Priority, ID, and Role: 1000 aa:c1:ab:d3:09:fe primary
    Peer Priority, ID, and Role: 2000 aa:c1:ab:bf:e3:16 secondary
          Peer Interface and IP: peerlink.4094 fe80::a8c1:abff:febf:e316 (linklocal)
               VxLAN Anycast IP: 10.0.1.12
                      Backup IP: 10.10.10.2 (active)
                     System MAC: 44:38:39:ff:00:aa

CLAG Interfaces
Our Interface      Peer Interface     CLAG Id   Conflicts              Proto-Down Reason
----------------   ----------------   -------   --------------------   -----------------
           bond1   bond1              1         -                      -              
           bond2   bond2              2         -                      -              
           bond3   bond3              3         -                      -              
         vxlan48   vxlan48            -         -                      -              

```
