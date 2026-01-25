
# [EVPN](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-514/Network-Virtualization/Ethernet-Virtual-Private-Network-EVPN/##)

這是 Data Center 網路的核心。簡單來說，它在解釋為什麼我們現在用 EVPN 來取代舊的 VXLAN。


##### 1. EVPN 是 VXLAN 的「大腦」 (控制平面) 
* **傳統 VXLAN (RFC 7348)**：只有「資料平面」。它就像一台超大的 L2 交換器，依賴「**Flooding-and-Learning**」(泛洪和學習) 來找 MAC。這在大型網路中會造成嚴重的廣播風暴，效率極低。
* **EVPN (RFC 7432)**：為 VXLAN 加上了「控制平面」。它使用 **MP-BGP** 協定來取代 Flooding。

##### 2. EVPN 的運作方式：用「通告」取代「學習」
* **VTEP** (Leaf 交換器) 不再需要用 Flooding 來找 MAC。
* 相反地，當一台主機 (Host/VM) 上線時，本地 VTEP 會透過 **BGP** 把這個主機的「**MAC 和 IP**」資訊**通告 (Advertise)** 給所有其他的 VTEP。
* **(技術細節)**：
    * **Type-2 路由**：用來通告「MAC/IP 位址」。
    * **Type-3 路由**：用來通告「VNI 成員」(哪些 VTEP 上有哪些 VNI)，以便建立 BUM 流量轉發列表。

##### 3. EVPN 帶來的巨大好處
* **ARP 抑制 (ARP Suppression)**：這是**殺手級功能**。既然每個 VTEP (Leaf) 都透過 BGP 知道了所有主機的 IP 和 MAC，當有主機發出 ARP 請求時，本地 VTEP 就可以**直接「代答」**，根本**不需要**把 ARP 廣播 (Flooding) 到整個 VXLAN 網路。
* **整合 L2 和 L3**：EVPN 不只做 L2 橋接，還能同時做 L3 路由。
* **分散式對稱路由 (Distributed Symmetric Routing)**：這是 L3 的重點。意思是「**L3 閘道 (Gateway) 在每一台 Leaf 交換器上**」。
    * 流量**不需要**繞送到某個「中央路由器」去做 VLAN 間路由。
    * L2 和 L3 流量都可以在本地 Leaf (VTEP) 上以線速 (wire-speed) 完成轉發，效能最佳。
* **主機移動性**：VM 從一台伺服器 (Leaf A) 漂移到另一台 (Leaf B)，Leaf B 只需要發出 BGP Type-2 更新，所有 VTEP 就會立刻知道 VM 的新位置。

##### 4. Cumulus 實作細節
* **軟體**：EVPN 是由 **FRR (Free Range Routing)** 這個開源路由套件提供的。
* **架構**：在 Spine-Leaf 架構中，通常**只有 Leaf 是 VTEP** (負責 VXLAN 封裝/解封裝)。**Spine 只做 L3 路由** (Underlay)，它不需要知道 VNI 或 MAC。
* **BGP 選擇**：你可以用 eBGP (推薦) 或 iBGP 來跑 EVPN。

##### 主要特點

- 基於標準的 VXLAN 控制平面（control plane）
- 依賴多協議 BGP (MP-BGP) 來交換資訊，並使用 BGP-MPLS IP VPN (RFC 4364) 技術
- 不僅能夠在同一個第 2 層（Layer 2）區段的終端系統之間進行橋接（bridging），還能在不同區段（子網路）之間進行路由（routing）
- 支援多租戶（multi-tenancy）
...

## BGP-EVPN - Layer 2

要讓 EVPN (控制平面) 運作，必須先架設好 VXLAN (資料平面) 和 BGP (傳輸工具)。

###### 1. EVPN 基礎設定三步驟
要讓 EVPN 跑起來，你必須完成這三件事：

1.  **設定 VXLAN (資料平面)**：
    * 定義「VLAN 和 VNI 的一對一對應」(e.g., `VLAN 10` = `VNI 10010`)。
    * 設定 VTEP (VXLAN 隧道) 的本地 IP 位址 (通常是 `loopback` 介面的 IP)。
      * vxlan-local-tunnelip
2.  **設定 BGP (傳輸工具)**：
    * 建立 Underlay 路由，讓所有 VTEP 的 Loopback IP 之間能互通 (e.g., 跑 OSPF 或 BGP)。
    * 建立 BGP 鄰居關係 (通常是 Leaf 和 Spine 建立 eBGP)。
3.  **啟用 EVPN (控制平面)**：
    * 在 BGP 設定中，啟動 `l2vpn evpn` 這個 **Address Family**。
    * 這一步才是真正告訴 BGP：「除了 IP 路由，你現在**還要**開始幫我傳送 MAC/IP (EVPN Type-2) 路由」。

##### 2. Cumulus 的 EVPN 模型
* Cumulus 採用的是最標準的 **VLAN-Based 服務介面** (RFC 7432)。
* 這簡化了邏輯：一個 L2 VNI (VXLAN) **直接對應**到一個 VLAN。你不需要做複雜的 Bridge-Domain 設定。

##### 3. Spine 交換器的角色
* 這條 **NOTE** 非常重要，是 Spine-Leaf 架構的核心。
* **Spine (或 Route Reflector)**：它們**不是 VTEP**。它們不負責封裝/解封裝 VXLAN 流量。
* **Spine 的工作**：它們只當作「BGP 路由中轉站」。它們只需要運行 BGP `l2vpn evpn` address family，幫忙把 Leaf 之間通告的 MAC/IP 路由轉發出去。
* **結論**：在 Spine 交換器上，你**不需要**設定任何 `vxlan` 介面、VNI、或 VLAN-VNI mapping。你只需要設定 BGP 就夠了。

### Configure

1. 配置 VXLAN

本範例將 VLAN 10 映射到 vni10，將 VLAN 20 映射到 vni20，並將 VXLAN 本地隧道 IP 位址設置為 10.10.10.1。*NVUE 會自動建立一個單一的 VXLAN 設備 (vxlan48)，將該 VXLAN 設備 (vxlan48) 加入到預設的橋接器 br_default*，並將 VLAN 到 VNI 的映射添加到該 VXLAN 設備（bridge-vlan-vni-map）。


Interface

```bash
...
auto lo
iface lo inet loopback
        address 10.10.10.1/32
        vxlan-local-tunnelip 10.10.10.1 # local tunnel IP
...
auto vxlan0
iface vxlan0
 bridge-vlan-vni-map 10=10 20=20
 bridge-vids 10 20
 bridge-learning off

auto vxlan48
iface vxlan48
    bridge-vlan-vni-map 10=10 20=20 30=30 4024=4001 4036=4002
    bridge-vids 10 20 30 4024 4036
    bridge-learning off

auto br_default
iface br_default
        bridge-ports swp1 swp2 vxlan0
        bridge-vlan-aware yes
        bridge-vids 10 20
        bridge-pvid 1
```

NVUE


```yaml
- set:
    bridge:
      domain:
        br_default:
          vlan:
            '10':
              vni:
                '10': {}
            '20':
              vni:
                '20': {}
...
    nve:
      vxlan:
        arp-nd-suppress: on
        enable: on
        mlag:
          shared-address: 10.0.1.12
        source:
          address: 10.10.10.1 # local tunnel IP
```

2. 配置 BGP

本實驗範例指令將 ASN（自治系統編號）和路由器 ID（router ID）指派給 leaf01 和 spine01，指定兩個 BGP 鄰居（peers）之間的介面，以及要宣告（originate）的前綴（prefixes）。

leaf01

```yaml
...
    router:
      bgp:
        autonomous-system: 65101
        enable: on
        router-id: 10.10.10.1
...
    vrf:
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
            neighbor: # distribute routing information
              peerlink.4094:
                peer-group: underlay
                type: unnumbered
              swp51: # this
                peer-group: underlay
                type: unnumbered
              swp52:
                peer-group: underlay
                type: unnumbered
            peer-group:
              underlay:
                address-family:
                  l2vpn-evpn:
                    enable: on
                remote-as: external
```

spine01

```yaml
...
    router:
      bgp:
        autonomous-system: 65199
        enable: on
        router-id: 10.10.10.101
    vrf:
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
              swp1: # this
                peer-group: underlay
                type: unnumbered
              swp2:
                peer-group: underlay
                type: unnumbered
              swp3:
                peer-group: underlay
                type: unnumbered
              swp4:
                peer-group: underlay
                type: unnumbered
              swp5:
                peer-group: underlay
                type: unnumbered
              swp6:
                peer-group: underlay
                type: unnumbered
            path-selection:
              multipath:
                aspath-ignore: on
            peer-group:
              underlay:
                address-family:
                  l2vpn-evpn:
                    enable: on
                remote-as: external
```

3. EVPN 啟用

```yaml
- set
    evpn:
      enable: on # this
...
    vrf:
      default:
        router:
          bgp:
            address-family:
...
              l2vpn-evpn:
                enable: on # this
...
            neighbor:
              peerlink.4094:
                peer-group: underlay
                type: unnumbered
              swp51:
                peer-group: underlay
                type: unnumbered
              swp52:
                peer-group: underlay
                type: unnumbered
            peer-group:
              underlay:
                address-family:
                  l2vpn-evpn: 
                    enable: on # this
                remote-as: external
```


#### EVPN and VXLAN Active-active Mode

在 EVPN VXLAN active-active 模式中，MLAG 對 (pair) 中的兩台交換器都會與其他的 EVPN 設備 (例如，使用 hop-by-hop eBGP 的 spine 交換器) 建立 EVPN BGP 鄰居關係，並通告它們本地已知的 VNI 和 MAC 位址。

當 MLAG 處於 active 狀態時，兩台交換器會使用一個**共享的 Anycast IP 位址**來通告這些資訊。

這段是 MLAG + EVPN 架構的**靈魂**。它解釋了如何讓兩台實體交換器 (VTEP) 在 VXLAN 網路中「偽裝」成一台邏輯 VTEP。

對於 VXLAN active-active 模式下的 EVPN 對稱（symmetric）配置中的 type-5 路由，Cumulus Linux 使用**主要 IP 位址宣告（Primary IP Address Advertisement）**


##### 1. 核心概念：共享的 VTEP (Anycast IP)
* **關鍵**：在 MLAG + EVPN 架構中，`leaf01` 和 `leaf02` **不再**是兩個獨立的 VTEP。它們共享一個「**Anycast IP**」 (由 `clag-vxlan-anycast-ip` 設定)，對外宣告自己是**同一個邏輯 VTEP**。
* **運作方式**：
    1.  `leaf01` 和 `leaf02` 都使用這個**共享的 Anycast IP** 作為 BGP Next-Hop，向 Spine 交換器通告 EVPN 路由 (Type-2 MAC/IP 路由)。
    2.  Spine 交換器只會學到一筆到這個「Anycast VTEP」的路由。
    3.  當 Spine 要轉發 VXLAN 封包時，它會透過 Underlay 的 ECMP 負載平衡，將封包隨機丟給 `leaf01` **或** `leaf02`。
    4.  由於 `leaf01` 和 `leaf02` 透過 MLAG **同步了 MAC 表**，所以無論哪台收到封包，都能正確地將其轉發給本地的伺服器。

##### 2. Loopback 上的「雙 IP」設定
這是設定上的重點。必須在 `loopback` 介面上設定**兩個** IP：
1.  **`vxlan-local-tunnelip`**：這是每台交換器**自己獨有 (Unique) 的 IP** (e.g., `10.10.10.1` vs `10.10.10.2`)。主要用於 Underlay 路由協定 (OSPF/BGP) 建立鄰居。
2.  **`clag-vxlan-anycast-ip`**：這是兩台交換器**共享 (Shared) 的 IP** (e.g., `10.10.10.100`)。這就是 EVPN BGP 用來通告路由的「VTEP IP」。

##### 3. 設定警告
* **Anycast IP 必須被路由**：**必須**確保這個共享的 `clag-vxlan-anycast-ip` 位址有被通告到 Underlay 網路 (e.g., OSPF `network` 指令要包含它)，否則 Spine 不知道如何將 VXLAN 流量送達。
* **設定必須 100% 同步**：兩台 MLAG 交換器上的 VNI 和 VLAN 對應設定**必須完全一致**。
* **Peerlink 必須在 Bridge 內**：這是標準 MLAG 要求，`peerlink` (L2 鏈路) 必須加入 `bridge` 才能同步 MAC 表。

##### 4. 角色分工：MLAG vs. EVPN
* **MLAG**：負責在**兩台 Peer 交換器之間**同步「資料平面」狀態 (例如本地伺服器的 MAC 位址)。
* **EVPN**：負責將這些 MAC/IP 資訊，通告到**整個 Data Center 網路** (控制平面)。


## RD (Route Distinguisher) 和 RT (Route Target) 的自動化機制
當 FRR 得知一個本地 VNI 的存在，但在 FRR 中並沒有針對該 VNI 的明確設定時，交換器會自動為這個 VNI 衍生出 RD (路由識別碼) 以及 import/export RTs (路由目標)。
- RD 的格式為：`RouterId:VNI-Index`
- Import/Export RTs 的格式為：`AS:VNI`

對於來自 L2 VNI 的路由 (type-2 和 type-3)，RD 會使用 VXLAN 本地隧道 IP (`vxlan-local-tunnelip`) 來取代 RouterId，格式變為：`vxlan-local-tunnelip:VNI`。*EVPN 路由交換就是使用這些 RD 和 RT*。

RD 的作用是**區分**不同 VNI 中的 EVPN 路由（即使它們有相同的 MAC 和 IP 位址），而 RT 則描述了該路由的 VPN 成員資格。

RD 中的 `VNI-Index` 是交換器產生的唯一數字，它只具有本地意義；在遠端交換器上，*它唯一的作用就是區分路由*。使用這個數字是因為它必須小於或等於 65535（而 VNI 本身的值可能更大）。

在 RT 中，`AS` (AS 號碼) 始終是一個 2-byte 的值，以便為大型 VNI 騰出空間。如果路由器有 4-byte 的 AS 號，它只會使用較低的 2-byte。這確保了同一個 AS 內的路由器，對於不同 VNI 會產生唯一的 RT，但對於相同 VNI 則會產生相同的 RT。

這段是 EVPN 的靈魂。簡單說，Cumulus (FRR) 幫你把最麻煩的 RD/RT 設定**自動化**了。

##### 1. 核心功能：RD/RT 自動化
* 你不需要手動去 FRR 裡設定每一個 VNI 的 RD 和 RT。
* 只要交換器上有 VNI，FRR 就會自動幫你生成一套 RD/RT，讓 EVPN 開始運作。

##### 2. RD (路由識別碼)：防止「撞 MAC/IP」
* **用途**：RD 的唯一目的，就是讓**不同 VNI** (不同租戶) 中的路由變得「**全域唯一**」。
* **情境**：`VNI 10` (租戶 A) 和 `VNI 20` (租戶 B) **都**有一台主機是 `192.168.1.100`。
* **RD 的作用**：
    * 租戶 A 的路由會變成：`(RD:VNI-10):192.168.1.100`
    * 租戶 B 的路由會變成：`(RD:VNI-20):192.168.1.100`
* **結果**：BGP 會把它們視為兩筆**完全不同**的路由，從而避免了衝突。
* **Cumulus 格式**：`vxlan-local-tunnelip:VNI` (例如 `10.10.10.1:10010`)

##### 3. RT (路由目標)：控制「路由共享」
* **用途**：RT 像一個「標籤」，決定了哪些路由該由哪些 VNI「導入」(Import) 或「導出」(Export)。
* **Cumulus 格式**：`AS:VNI` (例如 `65001:10010`)
* **運作方式**：
    * **Export RT (導出)**：Leaf-1 為 `VNI 10010` 的路由貼上 `65001:10010` 的標籤，然後通告出去。
    * **Import RT (導入)**：Leaf-2 在 BGP 中設定：「我只接收 (導入) 標籤為 `65001:10010` 的路由，並把它們放進我的 `VNI 10010`」。
* **結果**：這確保了 `VNI 10010` 的路由只會被其他 `VNI 10010` 的 VTEP 接收，實現了 L2 隔離。

##### 4. 關鍵 eBGP 的自動修復 (The "Magic Fix")
* 這段是 **Cumulus EVPN 為何適用於 eBGP (Spine-Leaf)** 的核心。
* **問題**：在 eBGP 架構中 (Spine 和 Leaf 是不同 AS)，`AS:VNI` 這個自動 RT 規則會**失效**。
    * Leaf-1 (AS 65001) 導出 `65001:10010`。
    * Leaf-2 (AS 65002) 卻在等待導入 `65002:10010`。
    * **結果**：標籤不匹配，Leaf-2 **拒絕**導入 Leaf-1 的路由，網路不通。
* **Cumulus 的解決方案**：Cumulus (FRR) 知道這個問題。因此，當它在 eBGP 環境下「自動」產生 RT 時，它會偷偷修改導入規則：
    * **Import RT 規則變為**：`*:VNI` (例如 `*:10010`)
    * **白話文**：「**我不管你是哪個 AS 來的** (`*` = 萬用字元)，只要你通告的 VNI 是 `10010`，我就導入！」
* **結論**：這個自動的「萬用字元導入」機制，讓 eBGP EVPN 在 Cumulus 上可以「開箱即用」，你不需要手動去改 RT 策略。

## EVPN 與 VXLAN

- VXLAN 「資料平面」(Data Plane)
  - 它是負責將封包打包 (封裝) 並傳送的「貨運卡車」。
- EVPN 則是**「控制平面」(Control Plane)**
  - 它是指揮這一切的「GPS 導航與調度中心」。

EVPN 在這個架構中的主要工作是利用 BGP (邊界閘道協定) 來動態交換和通告 (Advertise) 網路資訊，讓所有交換器（VTEPs）都知道「誰在哪裡」以及「如何最佳地到達」。

根據設定檔，EVPN 具體完成了以下幾項任務：

##### 1. 實現 L3 分散式路由 (通告 IP 路由)

這是我們一直在討論的核心功能（Symmetric IRB）。

* **工作內容**：EVPN 會通告 **L3 路由資訊 (IP 前綴)**。
* **如何運作**：
    1.  `leaf-3` 和 `leaf-4` 擁有 `VLAN 20` (子網 `10.1.20.0/24`)。
    2.  因為它們的 `vrf RED` 中設定了 `route-export: to-evpn: enable: on`，BGP 會將這個 `10.1.20.0/24` 子網打包成 **EVPN Type 5 (IP Prefix) 路由**。
    3.  它們各自通告：「我能到達 `10.1.20.0/24`，Next-hop 是我的 VTEP IP (10.10.10.3 或 10.10.10.4)，且 L3 VNI 是 `4001`。」
* **最終效果**：`leaf-1` 學習到這些 EVPN 路由，從而知道要到達 `10.1.20.105`，它可以**直接**將 VXLAN 封包傳送給 `leaf-3` 或 `leaf-4`，實現了最高效率的 L3 路由。

```bash
leaf01# show bgp l2vpn evpn route type 5
BGP table version is 1, local router ID is 10.10.10.1
Status codes: s suppressed, d damped, h history, * valid, > best, i - internal
Origin codes: i - IGP, e - EGP, ? - incomplete
EVPN type-1 prefix: [1]:[ESI]:[EthTag]:[IPlen]:[VTEP-IP]:[Frag-id]
EVPN type-2 prefix: [2]:[EthTag]:[MAClen]:[MAC]:[IPlen]:[IP]
EVPN type-3 prefix: [3]:[EthTag]:[IPlen]:[OrigIP]
EVPN type-4 prefix: [4]:[ESI]:[IPlen]:[OrigIP]
EVPN type-5 prefix: [5]:[EthTag]:[IPlen]:[IP]

   Network          Next Hop            Metric LocPrf Weight Path
                    Extended Community
                    ...
*  [5]:[0]:[24]:[10.1.30.0] RD 10.10.10.3:2
                    10.10.10.3 (leaf02)
                                                           0 65102 65199 65103 ?
                    RT:65103:4002 ET:8 Rmac:44:38:39:22:01:84
Route Distinguisher: 10.10.10.3:3
*> [5]:[0]:[24]:[10.1.10.0] RD 10.10.10.3:3
                    10.10.10.3 (spine02)
                                                           0 65199 65103 ?
                    RT:65103:4001 ET:8 Rmac:44:38:39:22:01:84
*  [5]:[0]:[24]:[10.1.10.0] RD 10.10.10.3:3
                    10.10.10.3 (leaf02)
                                                           0 65102 65199 65103 ?
                    RT:65103:4001 ET:8 Rmac:44:38:39:22:01:84
*> [5]:[0]:[24]:[10.1.20.0] RD 10.10.10.3:3
                    10.10.10.3 (spine02)
                                                           0 65199 65103 ?
                    RT:65103:4001 ET:8 Rmac:44:38:39:22:01:84
*  [5]:[0]:[24]:[10.1.20.0] RD 10.10.10.3:3
                    10.10.10.3 (leaf02)
                                                           0 65102 65199 65103 ?
                    RT:65103:4001 ET:8 Rmac:44:38:39:22:01:84
```

##### 2. 實現 L2 資訊交換 (通告 MAC 位址)

EVPN 取代了傳統 VXLAN 依靠「洪泛與學習」(Flood and Learn) 來發現 MAC 位址的低效率做法。

* **工作內容**：EVPN 會通告**L2 MAC 位址資訊**。
* **如何運作**：
    1.  `server01` (假設 MAC 是 `AA:AA`) 開機，`leaf-1` 在 `vlan10` 上學習到這個 MAC。
    2.  `leaf-1` 會透過 BGP (EVPN) 向所有其他 VTEP 發送一條 **EVPN Type 2 (MAC/IP) 路由**通告。
    3.  這個通告說：「MAC `AA:AA` (IP `10.1.10.101`) 位於 L2 VNI `10`，你可以透過我的任播 VTEP IP (`10.0.1.12`) 找到它。」
* **最終效果**：當 `leaf-3` 上的某台伺服器需要與 `server01` (在同一個 VLAN) 通訊時，`leaf-3` **不需要**在網路上廣播 (洪泛) ARP 請求。它只需查詢 BGP 表，就能精確知道 `AA:AA` 位於 `leaf-1`/`leaf-2` 叢集，並直接將 L2 VXLAN 封包傳送過去。

```bash
leaf01# show bgp l2vpn evpn route type 2
BGP table version is 3, local router ID is 10.10.10.1
Status codes: s suppressed, d damped, h history, * valid, > best, i - internal
Origin codes: i - IGP, e - EGP, ? - incomplete
EVPN type-1 prefix: [1]:[ESI]:[EthTag]:[IPlen]:[VTEP-IP]:[Frag-id]
EVPN type-2 prefix: [2]:[EthTag]:[MAClen]:[MAC]:[IPlen]:[IP]
EVPN type-3 prefix: [3]:[EthTag]:[IPlen]:[OrigIP]
EVPN type-4 prefix: [4]:[ESI]:[IPlen]:[OrigIP]
EVPN type-5 prefix: [5]:[EthTag]:[IPlen]:[IP]

   Network          Next Hop            Metric LocPrf Weight Path
                    Extended Community
                    ...
Route Distinguisher: 10.10.10.1:4
*> [2]:[0]:[48]:[44:38:39:22:01:78] RD 10.10.10.1:4
                    10.0.1.12 (leaf01)
                                                       32768 i
                    ET:8 RT:65101:20 MM:0, sticky MAC
*> [2]:[0]:[48]:[aa:c1:ab:65:96:40] RD 10.10.10.1:4
                    10.0.1.12 (leaf01)
                                                       32768 i
                    ET:8 RT:65101:20
Route Distinguisher: 10.10.10.1:5
*> [2]:[0]:[48]:[44:38:39:22:01:78] RD 10.10.10.1:5
                    10.0.1.12 (leaf01)
                                                       32768 i
                    ET:8 RT:65101:30 MM:0, sticky MAC
*> [2]:[0]:[48]:[aa:c1:ab:63:37:39] RD 10.10.10.1:5
                    10.0.1.12 (leaf01)
                                                       32768 i
                    ET:8 RT:65101:30
*> [2]:[0]:[48]:[aa:c1:ab:63:37:39]:[128]:[fe80::a8c1:abff:fe63:3739] RD 10.10.10.1:5
                    10.0.1.12 (leaf01)
                                                       32768 i
                    ET:8 RT:65101:30
Route Distinguisher: 10.10.10.1:6
*> [2]:[0]:[48]:[44:38:39:22:01:78] RD 10.10.10.1:6
                    10.0.1.12 (leaf01)
                                                       32768 i
                    ET:8 RT:65101:10 MM:0, sticky MAC
*> [2]:[0]:[48]:[aa:c1:ab:50:9d:2d] RD 10.10.10.1:6
                    10.0.1.12 (leaf01)
                                                       32768 i
                    ET:8 RT:65101:10
Route Distinguisher: 10.10.10.3:4
...
```
##### 3. 抑制廣播 (ARP/ND Suppression)

這是 EVPN 帶來的一個巨大效能優勢，能大幅減少網路中的「噪音」。

* **工作內容**：主動抑制不必要的 ARP (IPv4) 和 ND (IPv6) 廣播。
* **如何運作**：
    1.  設定檔中啟用了 `arp-nd-suppress: on`。
    2.  因為 EVPN (透過 Type 2 路由) 已經讓所有 VTEP 學習到了網路中大部分伺服器的「IP-MAC 綁定關係」。
    3.  當 `server01` (10.1.10.101) 發送 ARP 請求詢問「`10.1.10.1` (閘道) 是誰？」時，`leaf-1` 收到這個廣播。
    4.  `leaf-1` **不會**將這個 ARP 廣播轉發到 VXLAN 網路中。它會**代替**閘道直接回覆 (Proxy ARP)：「`10.1.10.1` 的 MAC 是 `00:00:5E:00:01:01` (VRR Anycast MAC)」。
* **最終效果**：絕大多數的 ARP 請求都在本地 Leaf 交換器上就被「攔截」並回覆了，防止了廣播風暴，極大地提升了網路穩定性和效能。


> EVPN 是現代資料中心網路的**核心大腦**。它將 L2 MAC 位址和 L3 IP 路由資訊全部放入 BGP 中，讓 BGP 成為一個統一的控制平面，實現了所有高效功能：**分散式路由 (IRB)**、**任播閘道 (Anycast Gateway)** 和**任播 VTEP (Anycast VTEP / ECMP)**。

## Inter-subnet Routing

EVPN 包含了多種在不同子網路 (VLAN) 之間進行路由（也稱為 VLAN 間路由）的模型。選擇的模型，取決於是**否『每個 VTEP』**都充當 L3 閘道器。

Cumulus Linux 支援以下模型：

1.  **集中式路由 (Centralized routing):**
    * 由**特定的 VTEP** (指定 VTEP) 充當 L3 閘道器，並執行子網路間的路由。
    * **其他 VTEP (Leaf) 只需執行 L2 橋接** (Bridging)。

2.  **分散式非對稱路由 (Distributed asymmetric routing):**
    * **每個 VTEP** 都參與路由。
    * 但是，所有的路由**只在入口 VTEP (ingress VTEP)上發生**；出口 VTEP (egress VTEP)只執行 L2 橋接。

3.  **分散式對稱路由 (Distributed symmetric routing):**
    * **每個 VTEP** 都參與路由。
    * 路由會在**入口 VTEP 和出口 VTEP 兩端**都執行。

### 分散式路由的特性 - 本實驗
通常會使用「**Anycast IP 和 MAC 位址**」來部署分散式路由，讓 VTEP 為每個子網路提供服務。在這種模型下，每個 VTEP 上都擁有該子網路相同的 IP/MAC。這個模型**極大地促進了主機和 VM 的移動性 (VM mobility)**，因為主機/VM 從一個 VTEP 搬移到另一個時，完全不需要更改其設定。

### VRF 的角色
所有的路由都發生在一個租戶 **VRF (虛擬路由與轉發)** 的情境下。Cumulus 會為每個租戶配置一個 VRF 實例。每個租戶的子網路間路由都發生在該租戶的 VRF 內，並與其他租戶的路由完全隔離。

### 集中式路由詳述
在集中式路由中，會設定一個特定的 VTEP 作為 EVPN Fabric 中所有主機的預設閘道器。當一個主機 (Host-A) 想要與另一個子網路的主機 (Host-B) 通訊時，它會將封包尋址到閘道器 VTEP (Gateway VTEP)。

流程：**入口 VTEP** (Host-A 連接的 Leaf) 會透過 VXLAN 隧道將封包**橋接 (bridge)**到**閘道器 VTEP**。**閘道器 VTEP** 接著**路由 (route)**這個封包，然後再將封包**橋接 (bridge)**到**出口 VTEP** (Host-B 連接的 Leaf)

這段是 EVPN 架構的**核心設計決策**：你的「L3 閘道 (Gateway)」要放在哪裡？

##### 1. 核心問題：誰來做 L3 路由 (VLAN 間路由)？
EVPN 提供了兩種截然不同的架構：

* **集中式路由 (Centralized Routing)**
    * **架構**：這就像是「傳統核心交換器」的做法。你會指定**一對**特定的交換器（例如 Spine 或一對專用的 "Service Leaf"）充當**所有** VLAN 的 L3 閘道。
    * **流程 (效率差)**：原文描述了這個低效率的流程，俗稱「**髮夾彎 (Traffic Trombone)**」。
        1.  `Host-A` (VLAN 10) 傳送封包給 `Host-B` (VLAN 20)。
        2.  `Leaf-1` (Ingress VTEP) **只做 L2**，它透過 VXLAN 隧道將封包「橋接」給「閘道器 VTEP」。(第一段 VXLAN)
        3.  `閘道器 VTEP` 收到 L2 封包，解開，執行 L3 路由 (VLAN 10 -> 20)。
        4.  `閘道器 VTEP` 接著**再次**用 VXLAN 封裝，將封包「橋接」給 `Leaf-2`。(第二段 VXLAN)
        5.  `Leaf-2` (Egress VTEP) 收到 L2 封包，解開，送給 `Host-B`。
    * **缺點**：**效率極低**。所有跨 VLAN 流量都必須繞遠路到「中央閘道」再回來，浪費 Spine 頻寬。

* **分散式路由 (Distributed Routing)**
    * **架構**：這是 EVPN 的**標準和推薦做法**。L3 閘道**不在** Spine 上，而是**在每一台 Leaf (VTEP) 上**。
    * **關鍵技術**：原文提到的 **Anycast IP/MAC**。
    * **運作**：`Leaf-1`、`Leaf-2`、`Leaf-3`... **所有** Leaf 交換器上，都設定了**一模一樣**的 SVI 和 IP (例如 `VLAN 10` 的 `10.1.10.1`)，並使用相同的虛擬 MAC (這和 VRR 的概念一樣)。
    * **流程 (效率高)**：
        1.  `Host-A` (VLAN 10, 在 Leaf-1) 傳送封包給 `Host-B` (VLAN 20, 在 Leaf-2)。
        2.  `Host-A` 將封包送給它的閘道 `10.1.10.1` (也就是 `Leaf-1`)。
        3.  `Leaf-1` (Ingress VTEP) **在本地**就執行了 L3 路由 (VLAN 10 -> 20)。
        4.  `Leaf-1` **直接**透過 VXLAN 將**已經路由過的** L2 封包 (屬於 VLAN 20) 傳送給 `Leaf-2`。
        5.  `Leaf-2` (Egress VTEP) 收到 L2 封包，解開，送給 `Host-B`。
    * **優點**：**一步到位**。路由總是在「第一跳」就完成，效能最佳。

##### 2. 分散式的兩種子模式 (對稱 vs 非對稱)
* **非對稱 (Asymmetric)**：路由**只在入口** (Ingress) 發生。出口 (Egress) 只做 L2。
* **對稱 (Symmetric)**：路由在**入口和出口**都會發生。這是目前**最主流**的 EVPN 部署方式 (通常搭配 EVPN Type-5 路由)，效能和擴展性最佳。

##### 3. 多租戶 (Multi-Tenancy)
* EVPN 的設計基礎。這一切 (L2 橋接、L3 路由) 都是在 **VRF** (虛擬路由表) 內完成的。
* 這代表租戶 A 的 `VLAN 10` 和租戶 B 的 `VLAN 10` 可以完全隔離，使用各自獨立的 L3 閘道。

### 非對稱路由 (Asymmetric Routing)
* **概要**：這也稱為「Ingress 路由模型」。VTEP 上的 L3 閘道器會執行 VLAN 間路由，然後將封包「橋接」到目標 VNI。
* **需求**：
    * 每個 VTEP **必須**知道**所有**的 VNI 和主機 MAC 位址 (L2 VNI)。
    * 它們**也必須**知道所有主機的 IP 位址 (L3 VNI)。
* **警告**：
    * 這個模型**沒有**使用 L3 VNI。
    * VTEP 必須匯入 (import) **所有** L2 VNI 的 RT。這在大型網路中會導致 VTEP 上的 MAC 表規模失控 (poor scaling)。

### 對稱路由 (Symmetric Routing) 本實驗
* **概要**：這個模型在 Ingress 和 Egress VTEP 上都執行路由。它使用一個 L3 VNI 來在 VTEP 之間「路由」封包，而不是 L2 橋接。
* **流程**：
    1.  Ingress VTEP (入口) 將封包從來源 VLAN (e.g., VLAN 10) 路由到 **L3 VNI**。
    2.  封包透過 L3 VNI (VXLAN 隧道) 被「路由」到 Egress VTEP。
    3.  Egress VTEP (出口) 收到 L3 VNI 封包，再將其路由到目標 VLAN (e.g., VLAN 20)。
* **需求**：
    * 你**必須**為 VRF 建立一個專用的 **L3 VNI**。
    * 每個 VTEP 都**必須**有一個**全域唯一的 MAC 位址** (稱為 **Router MAC**)。
    * VTEP **只**通告 (advertise) **本地連接**的子網路 (EVPN Type-5 路由)。
    * **本地 SVI (VLAN 介面) 不再需要 Anycast IP** (因為路由是透過 L3 VNI 進行的)。
    * 你**必須**為 L3 VNI SVI 介面設定 MAC 位址 (使用 `vlan-raw-device`)。
* **警告**：
    * `vlan-id` 和 L3 VNI ID **不能相同**。
    * L3 VNI SVI 上的 MAC 位址**必須**是唯一的 Router MAC。
    * Cumulus **不支援** L3 VNI 的 Port-based (基於埠口) 設定。

### 重點整理

這張圖是 EVPN L3 路由的「進階篇」，主要在比較**非對稱**和**對稱**這兩種「分散式閘道」模型。

##### 1. 核心差異：VLAN 間流量是「橋接」還是「路由」？
* **分散式 (Distributed)** 代表 L3 閘道在**每一台 Leaf** 上，這是共識。
* 真正的差別在於，當 `Leaf-1` 收到 `VLAN 10` 要去 `VLAN 20` 的封包時，它怎麼把封包丟給 `Leaf-2`？

##### 2. 非對稱路由 (Asymmetric Routing)
* **運作模式**：L2 橋接模型 (Bridging Model)
* `Leaf-1` (Ingress) 執行路由 (VLAN 10 -> 20)。然後，它把這個已經屬於 `VLAN 20` 的 L2 封包，封裝到 `VNI 20` (L2 VNI) 的 VXLAN 隧道中，**橋接**給 `Leaf-2`。
* **最大缺點 (Poor Scaling)**：
    * 為了能「橋接」到 `VNI 20`，`Leaf-1` **必須**知道 `VNI 20` 裡面的**所有 MAC 位址**。
    * **推論**：**網路中的每一台 VTEP (Leaf)，都必須學習並維護全網路所有 VLAN (VNI) 的所有 MAC 位址表**。
    * **結果**：當網路規模變大 (e.g., 500 個 VLAN)，每台 Leaf 的 MAC 表都會爆炸，硬體吃不消。

##### 3. 對稱路由 (Symmetric Routing) - 現代 EVPN 標準
* **運作模式**：L3 路由模型 (Routing Model)
* `Leaf-1` (Ingress) 執行路由 (VLAN 10 -> L3 VNI)。它**不關心**目標 MAC 是誰，它只把封包「**路由**」到一個專用的「**L3 VNI**」隧道中，這個隧道的目的地就是 `Leaf-2` 的 Router IP。
* **流程**：
    1.  **Ingress (入口)**：`Leaf-1` 執行第一次路由 (來源 VLAN -> L3 VNI)。
    2.  **Egress (出口)**：`Leaf-2` 收到 L3 VNI 封包，執行第二次路由 (L3 VNI -> 目標 VLAN)。
* **最大優點(Great Scaling)**：
    * VTEP (Leaf) **不再**需要學習「遠端」VLAN 的 MAC 位址。
    * `Leaf-1` **只需要**知道自己本地 `VLAN 10` 的 MAC。
    * `Leaf-2` **只需要**知道自己本地 `VLAN 20` 的 MAC。
    * VTEP 之間交換的是 **L3 路由** (EVPN Type-5，IP 前綴)，而不是 L2 MAC (Type-2)。
* **關鍵設定**：
    1.  **L3 VNI**：必須在 VRF 中額外建立一個專門用來「路由」的 VNI。
    2.  **Router MAC**：每台 VTEP 都需要一個獨特的 MAC，在 L3 VNI 隧道中用這個 MAC 來當作 L2 標頭。

##### 總結
* **Asymmetric (非對稱)**：在 Ingress 路由，在 Egress 橋接。**簡單，但無法擴展** (Scalability 差)。
* **Symmetric (對稱)**：在 Ingress 和 Egress 都路由。**需要 L3 VNI，但擴展性極佳**。這是目前 Data Center 的**主流標準**。

### Announce EVPN Type-5 Routes
租戶 VRF 需要以下設定來將 BGP RIB 中的 IP 前綴宣佈為 EVPN 類型 5 路由。

NVUE
```yaml
...
    vrf:
      BLUE:
        evpn:
          enable: on
          vni:
            '4002': {}
        router:
          bgp:
            address-family:
              ipv4-unicast:
                enable: on
                redistribute:
                  connected:
                    enable: on
                route-export: # this
                  to-evpn:
                    enable: on
            autonomous-system: 65101
            enable: on
            router-id: 10.10.10.1
```

### Advertise Primary IP address (VXLAN Active-Active Mode)

在 EVPN 對稱路由 (symmetric routing) 且搭配 VXLAN active-active (MLAG) 的設定中，所有 EVPN 路由都會使用 anycast IP (共享 IP) 作為下一跳 (next hop) IP 位址，並使用 anycast MAC (共享 MAC) 作為路由器 MAC (router MAC) 來進行通告。

這整段文件在講一個 MLAG + EVPN 的**防腦裂 (Split-Brain) 機制**，但專注在 **L3 (Type-5) 路由**。

##### 1. 核心問題：MLAG 故障時的 L3 流量黑洞
* **正常情況 (Healthy)**：`leaf01` 和 `leaf02` 組成 MLAG。它們共享一個 **Anycast IP** (e.g., `10.0.1.12`) 和 **Anycast MAC**。它們對 Spine 交換器「偽裝」成**一台**邏輯 VTEP (`10.0.1.12`)。Spine 會對 L3 流量進行 ECMP 負載平衡，丟給 `leaf01` 或 `leaf02` 都能通。
* **故障情況 (Failure)**：`peerlink` 斷線 (Split-Brain)。`leaf01` 和 `leaf02` 都認為自己是 Primary。**兩台**交換器都還在對外通告「我是 `10.0.1.12`」。
* **黑洞發生**：
    1.  Spine 收到一份 L3 流量 (Type-5)，要送給 `leaf01` 後面的伺服器。
    2.  Spine 的 ECMP 決定把這份流量丟給 `leaf02` (因為 `leaf02` 也說自己是 `10.0.1.12`)。
    3.  流量抵達 `leaf02`。但因為 `peerlink` 斷了，`leaf02` **沒有** `leaf01` 的 L3 路由資訊。
    4.  `leaf02` **丟棄封包**。

##### 2. 解決方案：Adverse Primary IP (預設啟用)
這個功能就是為了解決上述的 L3 黑洞。

* **機制**：當 MLAG 偵測到故障 (進入 "adverse" 狀態)，它會**立刻修改 BGP (EVPN) 的通告內容**。
* **行為改變 (關鍵)**：
    * **L2 路由 (Type-2)**：**不變**。繼續通告 Anycast IP/MAC。
    * **L3 路由 (Type-5)**：**改變**！交換器**停止**通告 Anycast IP。
        * `leaf01` 會改為通告：「L3 路由的 Next-Hop 是**我 (leaf01) 的唯一 IP** (e.g., `10.10.10.1`)」。
        * `leaf02` 也會改為通告：「L3 路由的 Next-Hop 是**我 (leaf02) 的唯一 IP** (e.g., `10.10.10.2`)」。
* **解決黑洞**：
    1.  Spine 交換器現在會收到**兩條** L3 路由：一條指向 `10.10.10.1`，一條指向 `1.1.1.2`。
    2.  Spine **不再**認為它們是同一台 VTEP。
    3.  Spine 會根據 BGP 路由表，**精確地**將 L3 流量送到**正確**的 VTEP (e.g., 送往 `leaf01` 後面的流量就只會送給 `10.10.10.1`)。
    4.  **ECMP 負載平衡失效了，但路由的準確性回來了**，避免了流量黑洞。

##### 3. 圖表重點

![](https://docs.nvidia.com/networking-ethernet-software/images/cumulus-linux/anycast-fabric-address.png)

* **Anycast MAC (EVPN) vs VRR MAC (Gateway)**：
    * **VRR MAC** (圖中的 `...01:01`)：這是 L3 閘道 (SVI) 用的，通常是**全網域共用**，讓所有伺服器有共同的 Gateway MAC。
    * **Anycast MAC** (圖中的 `...00:01`)：這是 **EVPN VTEP** 用的 (Type-2 路由的 Router MAC)，是**每一對 MLAG pair** 共享的。
    * **結論**：這兩個是不同的虛擬 MAC，用於不同的 L3 功能。


##### Show Advertise Primary IP Address Information

```bash
leaf01#  show bgp l2vpn evpn vni 4001
VNI: 4001 (known to the kernel)
  Type: L3
  Tenant VRF: RED
  RD: 10.10.10.1:3
  Originator IP: 10.0.1.12
  Advertise-gw-macip : n/a
  Advertise-svi-macip : n/a
  Advertise-pip: Yes
  System-IP: 10.10.10.1
  System-MAC: 44:38:39:22:01:7a
  Router-MAC: 44:38:39:ff:00:aa
  Import Route Target:
    65101:4001
  Export Route Target:
    65101:4001
```