# [VXLAN](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-514/Network-Virtualization/VXLAN-Devices/)
## Single VXLAN Device
核心觀念是**化零為整**，用一個「容器」來管理所有的 VNI，而不是為每個 VNI 都建立一個獨立介面。

##### 1. 傳統方式 (多設備) vs. SVD (單一設備)

* **傳統方式**：如果你有 10 個 VNI (10 個 VXLAN 隧道)，你就必須在系統上建立 10 個獨立的 VXLAN 介面 (e.g., `vxlan10`, `vxlan20`, `vxlan30`...)。每個介面都要單獨設定，然後一個個加入 Bridge。
* **SVD 方式**：你**只需要建立一個**邏輯上的「VXLAN 設備」(e.g., 範例中的 `vxlan48`)。

##### 2. SVD 是 VNI 的「容器」
* SVD (Single VXLAN Device) 本身就像一個**容器**。
* 你只需要把這個**單一的** `vxlan48` 介面加入 `br_default` (L2 Bridge)。
* 所有「VLAN-to-VNI」的對應，以及每個 VNI 的特定屬性（如 Multicast 群組），都是在這個**容器內部**一次性定義完成的。

##### 3. SVD 的核心優勢
* **設定極度簡化 (Simplifies configuration)**：
    * **共同屬性** (例如 VTEP 的 `vxlan-local-tunnelip` 來源 IP) 只需要在 `vxlan48` 這個**容器上設定一次**。
    * 傳統方式你必須在 10 個介面上重複設定 10 次來源 IP。
* **減少系統開銷 (Reduces overhead)**：
    * 系統只需要管理 `vxlan48` **這 1 個**邏輯介面，而不是 10 個或 100 個獨立介面。
    * 這對系統 (Kernel) 的負擔更小，效能和擴展性 (Scaling) 更好。

### 配置
範例中的 `vxlan48` 就是那個「容器」。它被加入 `br_default` 之後，系統就知道 `vxlan48` 負責處理 VXLAN 封包。當 `vlan 10` 的 L2 流量進來，`vxlan48` 會根據內部的對應表，把它封裝成 `VNI 10` 送出去。

```bash
auto vxlan48
iface vxlan48
    bridge-vlan-vni-map 10=10 20=20 30=30 4024=4001 4036=4002
    bridge-vids 10 20 30 4024 4036
    bridge-learning off
auto br_default
iface br_default
    # 將介面橋接再一起
    bridge-ports bond1 bond2 bond3 peerlink vxlan48
    hwaddress 44:38:39:22:01:b1
    bridge-vlan-aware yes
    bridge-vids 10 20 30
    bridge-pvid 1
```

## Automatic VLAN to VNI Mapping

是 EVPN 多租戶 (Multi-Tenancy) 架構的關鍵設定。

* 這個功能讓你**不再需要管理 VNI**。
* 你只需要為每個租戶 (VRF/Bridge) 分配一個**唯一的「偏移量 (Offset)」** (例如租戶 A 用 10000，租戶 B 用 20000)。
* 系統會自動處理 VLAN 和 VNI 的對應，既簡化了設定，也保證了 VNI 的全域唯一性，完美解決了 VLAN 重複使用的問題。

##### 1. 核心問題 (The Problem)
* 手動設定 VLAN 和 VNI 的對應 (`vlan 10` map to `vni 10010`, `vlan 11` map to `vni 10011`...) 非常**繁瑣且容易出錯**。
* 更重要的是，在多租戶 (VRF) 環境中，**VLAN ID 會被重複使用** (例如 `VRF_A` 和 `VRF_B` 都有 `VLAN 10`)。但 VNI 在全域中必須是唯一的，你不能手動為兩個 `VLAN 10` 都指定 `VNI 10010`。

##### 2. 解決方案 (The Solution)
* Cumulus 提供了「**VNI = VLAN ID + 偏移量 (Offset)**」的自動計算公式。
* 你只需要設定**兩個參數**：
    1.  `vni auto`：告訴系統這個 Bridge (VRF) 裡的 VLAN 要啟用自動模式。
    2.  `vlan-vni-offset`：指定一個**「租戶專屬」的偏移量**。

##### 3. 範例情境解讀 (多租戶)
這個範例完美展示了如何隔離兩個租戶 (br_default 和 br_01)：

* **租戶 A (使用 `br_default`)**
    * `nv set bridge domain br_default vlan-vni-offset 10000`
    * `nv set bridge domain br_default vlan 10-50 vni auto`
    * **結果 (自動計算)**：
        * `VLAN 10` -> VNI = 10 + 10000 = **10010**
        * `VLAN 20` -> VNI = 20 + 10000 = **10020**

* **租戶 B (使用 `br_01`)**
    * `nv set bridge domain br_01 vlan-vni-offset 20000`
    * `nv set bridge domain br_01 vlan 10-50 vni auto`
    * **結果 (自動計算)**：
        * `VLAN 10` -> VNI = 10 + 20000 = **20010**
        * `VLAN 20` -> VNI = 20 + 20000 = **20020**

## VXLAN Routing

VXLAN L3 路由 (我們常說的「分散式閘道」) 的四大支柱：

##### 1. 核心功能：VNI 之間的路由
* **VXLAN 路由** = **Inter-VLAN 路由** (在 VXLAN 世界的版本)。
* 它的工作就是讓 `VNI 10` (VLAN 10) 的流量，能被路由到 `VNI 20` (VLAN 20)。
* 交換器看的是 VXLAN 封包**內部**的「租戶 IP 標頭」來決定如何路由。

##### 2. 控制平面：EVPN (大腦)
* **關鍵**：VXLAN 路由 (L3) 和 VXLAN 橋接 (L2) 一樣，都需要一個大腦來運作。
* 你**不應該**再使用舊的靜態 VXLAN(Flood and Learn)，而是**必須**使用 **EVPN** (BGP) 作為控制平面。
* EVPN 會幫你自動通告 L3 路由 (IP 前綴)，而不需要手動設定或依賴廣播。

##### 3. 關鍵特性 (一)：VRF (多租戶)
* **VXLAN 路由支援 L3 多租戶**。
* 這是透過 **VRF** (虛擬路由表) 實現的。
* 這代表租戶 A 的 `VNI 10` 路由到 `VNI 20`，和租戶 B 的 `VNI 10` 路由到 `VNI 20`，是發生在**兩個完全隔離**的 VRF 中。路由表互不干擾，IP 位址可以重複使用。

##### 4. 關鍵特性 (二)：Active-Active (高可用性)
* VXLAN 路由**完全相容**於「**Active-Active**」的 VTEP 架構。
* 這指的就是 **EVPN + MLAG** (或稱為 Anycast VTEP)。
* 伺服器可以同時連接到兩台 Leaf 交換器 (MLAG)，這兩台 Leaf 同時都是 L3 閘道 (VRR/Anycast Gateway)，並且兩台都能以 Active-Active 模式處理和轉發 L3 路由流量，實現了完整的備援和負載平衡。

## Static VXLAN Tunnels
為最原始的 VXLAN 設定方式。

##### 1. 核心定義：什麼是「靜態」?
* ：靜態 (Static)在這裡的意思是**沒有**「控制平面」(Control Plane)，也就是**沒有 BGP EVPN**。
* 它依賴的是 VXLAN 最原始的**泛洪與學習 (Flood and Learn)**機制。
* 這代表 VTEP 之間**不會**自動通告 MAC 位址。**必須**手動設定一個泛洪 (BUM) 流量的轉發方式，通常是**使用 Multicast (多播)**，或是手動指定一個「靜態複製列表 (Static Replication List)」。

##### 2. 優點 (Pros)
* **部署簡單 (Simple)**：
    * 這是它最大的優點。你**不需要**去設定複雜的 BGP 和 EVPN Address Family。
    * 只要 L3 Underlay 網路通了 (通常需要 Multicast PIM)，VXLAN 就能跑。
* **廠商互通性 (Interoperable)**：
    * 這是 VXLAN 的基礎標準 (RFC 7348)。只要廠商遵循標準，A 牌的 VTEP 可以和 B 牌的 VTEP 建立靜態 VXLAN。

##### 3. 缺點與適用情境 (Cons & Use Case) ⚠️
* **關鍵限制**：原文強調**小規模環境 (small scale)**，這是有原因的。
* 因為它依賴「泛洪 (Flooding)」，在大型網路中會造成嚴重的廣播風暴，效能極差且難以擴展 (scale)。
* **總結**：靜態 VXLAN 是一種**快速、簡單**的 L2 延伸方案，但它**只**適用於實驗室或規模非常小的環境。在現代資料中心，**BGP EVPN** 已經完全取代了它。

##### 4. 範例中的「優點」(L2 vs L3)
* 避免繁瑣過程，是在對比 VXLAN (L2 over L3) 和「傳統 L2 Trunking」。
* **傳統 L2**：你必須在**所有**交換器 (Core, Spine, Leaf) 上 `trunk allow vlan 10,20,30`。
* **VXLAN**：你只需要在「**邊緣 (Edge)**」的 VTEP (Leaf) 上設定 `VLAN 10 = VNI 10010`。中間的 L3 核心網路 (Underlay) **完全不需要**知道 VLAN 10 的存在，大幅簡化了核心層的管理。

### 配置

要設定靜態 VXLAN 隧道，你需要建立 VXLAN 設備 (devices)。Cumulus Linux 支援：

- 傳統 VXLAN 設備 (Traditional VXLAN devices)： 需要（為每個 VNI）設定獨一無二的 VXLAN 設備，然後將每一個設備（介面）都加入到 bridge (橋接器)。

- 單一 VXLAN 設備 (Single VXLAN devices)： 所有具有相同設定（相同的本地隧道 IP 和 VXLAN 遠端 IP 列表）的 VXLAN 隧道，可以共用同一個 VXLAN 設備。你只需要將這一個設備（介面）加入到 bridge 即可。

#### Single VXLAN Device 配置

```bash
auto lo
iface lo inet loopback
    address 10.10.10.1/32
    vxlan-local-tunnelip 10.10.10.1


auto swp1
iface swp1
bridge-access 10




auto swp2
iface swp2
bridge-access 20




auto vxlan48
iface vxlan48
vxlan-remoteip-map 10=10.10.10.2 10=10.10.10.3 20=10.10.10.4
bridge-vlan-vni-map 10=10 20=20
bridge-vids 10 20

```

## VXLAN Active-active Mode

VXLAN active-active 模式讓一對 MLAG 交換器能夠扮演「單一 VTEP」的角色，為實體伺服器 (bare metal) 和虛擬化工作負載提供 active-active 的 VXLAN 終端。

要使用 VXLAN active-active 模式，需要設定：

- MLAG
- VXLAN 介面
- 一個路由協定 (如 OSPF 或 BGP)，以及
- EVPN (控制平面) 或靜態 VXLAN 隧道 (資料平面)

EVPN MLAG (或稱 VXLAN Active-Active) 架構的**靈魂**。它完美解決了 VTEP 備援的問題。

![](https://docs.nvidia.com/networking-ethernet-software/images/cumulus-linux/vxlan-active-active-config.png)

##### 1. 核心概念：一個 VTEP，兩台共用
* **關鍵**：VXLAN Active-Active 的目標，就是讓 `leaf01` 和 `leaf02` 這兩台 MLAG 交換器，對「**整個 VXLAN 網路**」 (也就是對其他所有 VTEP) 偽裝成**一台**邏輯 VTEP。
* **圖示**：上圖中的 `leaf01` 和 `leaf02` **共享**同一個 VTEP IP (`10.0.1.12/32`)。

##### 2. 實現機制：Anycast IP (任意點傳播 IP)
* 這就是「黑魔法」所在。
* 你會在 `leaf01` 和 `leaf02` 的 **Loopback 介面**上，設定**一模一樣**的 IP 位址 (e.g., `10.0.1.12/32`)。這就是「Anycast IP」。
* 兩台交換器都會在 BGP (Underlay) 中通告「`10.0.1.12/32` 在我這裡」。
* 兩台交換器也都使用這個**共享的 IP** 作為 VXLAN 隧道的**來源 IP**。

##### 3. 流量如何轉發 (Active-Active 的好處)
* **情境**：遠端的 `leaf03` (VTEP IP `10.0.1.13`) 要傳送封包給 `server01`。
* **流程**：
    1.  `leaf03` 透過 EVPN (BGP) 得知 `server01` 的 MAC 位址，其 Next-Hop (VTEP) 是 `10.0.1.12`。
    2.  `leaf03` 將封包 VXLAN 封裝，目的地 IP 為 `10.0.1.12`。
    3.  Underlay (底層) 路由網路 (OSPF/BGP) 會透過 **ECMP (等價多路徑)** 進行負載平衡，將這個封包**隨機**丟給 `leaf01` **或** `leaf02` (因為它們都通告了 `10.0.1.12`)。
    4.  無論是 `leaf01` 還是 `leaf02` 收到，因為它們是 MLAG 夥伴 (MAC 表同步)，它們都能將封包解封裝並正確轉發給 `server01`。
* **結論**：這實現了完美的 L3 負載平衡和 VTEP 設備層級的備援。

##### 4. 安全機制：由 MLAG (`clagd`) 控制
* **關鍵**：Anycast IP **不是**永遠都在的。
* 它的啟用/停用**完全由 `clagd` (MLAG 服務) 控制**。
* **只有**當 `leaf01` 和 `leaf02` 之間的 MLAG `peerlink` 建立成功，且**設定一致性檢查通過**時，`clagd` 才會把這個 Anycast IP「掛載」到 Loopback 介面上。
* **目的**：**防止腦裂 (Split-Brain)**。如果 Peerlink 斷線，`clagd` 會立刻**撤銷 (remove)** 這個 Anycast IP，其中一台交換器會停止 VTEP 服務，避免兩台交換器同時在網路上宣告同一個 VTEP IP 造成衝突。

本實驗配置

leaf02
```bash
auto lo
iface lo inet loopback
    address 10.10.10.2/32
    clagd-vxlan-anycast-ip 10.0.1.12
    vxlan-local-tunnelip 10.10.10.2
```

leaf01

```bash
auto lo
iface lo inet loopback
    address 10.10.10.1/32
    clagd-vxlan-anycast-ip 10.0.1.12
    vxlan-local-tunnelip 10.10.10.1
```

NVUE 

```yaml
...
    nve:
      vxlan:
        arp-nd-suppress: on
        enable: on
        mlag:
          shared-address: 10.0.1.12 # this
        source:
          address: 10.10.10.1
```
## Troubleshooting 

顯示交換器上的 MLAG 鄰居訊息

```bash
root@leaf01:/# nv show mlag neighbor

    operational  applied  description
--  -----------  -------  -----------


dynamic
==========
        interface  ip-address                 lladdr             vlan-id
    --  ---------  -------------------------  -----------------  -------
    1   vlan20     fe80::a8c1:abff:fe3e:feaf  aa:c1:ab:3e:fe:af  20
    2   vlan20     fe80::4638:39ff:fe22:18a   44:38:39:22:01:8a  20
    3   vlan10     10.1.10.1                  00:00:5e:00:01:01  10


permanent
============
        address-family  interface    ip-address                lladdr             vlan-id
    --  --------------  -----------  ------------------------  -----------------  -------
    1   2               vlan10       10.1.10.2                 44:38:39:22:01:7a  10
    2   2               vlan20       10.1.20.2                 44:38:39:22:01:7a  20
    3   2               vlan30       10.1.30.2                 44:38:39:22:01:7a  30
    4   2               vlan10       10.1.10.3                 44:38:39:22:01:78  10
    5   2               vlan20       10.1.20.3                 44:38:39:22:01:78  20
    6   2               vlan30       10.1.30.3                 44:38:39:22:01:78  30
    7   10              vlan20       fe80::4638:39ff:fe22:17a  44:38:39:22:01:7a  20
    8   10              vlan4024_l3  fe80::4638:39ff:fe22:17a  44:38:39:22:01:7a  4024
    9   10              vlan10       fe80::4638:39ff:fe22:17a  44:38:39:22:01:7a  10
    10  10              vlan4036_l3  fe80::4638:39ff:fe22:17a  44:38:39:22:01:7a  4036
    11  10              vlan30       fe80::4638:39ff:fe22:17a  44:38:39:22:01:7a  30
    12  10              vlan4024_l3  fe80::4638:39ff:fe22:178  44:38:39:22:01:78  4024
    13  10              vlan10       fe80::4638:39ff:fe22:178  44:38:39:22:01:78  10
    14  10              vlan30       fe80::4638:39ff:fe22:178  44:38:39:22:01:78  30
    15  10              vlan4036_l3  fe80::4638:39ff:fe22:178  44:38:39:22:01:78  4036
    16  10              vlan20       fe80::4638:39ff:fe22:178  44:38:39:22:01:78  20
```