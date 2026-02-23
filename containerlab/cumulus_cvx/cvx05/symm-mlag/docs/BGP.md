# [BGP](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-514/Layer-3/Border-Gateway-Protocol-BGP/) 

BGP 是運行網際網路的路由協定。它透過交換路由和可達性資訊來管理資料包如何在網路之間路由。

## 運作原理

BGP 負責在自治系統 (AS) 之間導向封包，而 AS (Autonomous Systems) 是指在單一共同管理下的一組路由器。

- 每台路由器都會維護一張路由表（routing table），這張表控制著交換器如何轉發封包。
- 路由器上的 BGP 進程（process）會根據來自其他路由器的資訊以及來自 RIB 的資訊，來產生路由表中的內容。
    - RIB (Routing Information Base，路由資訊庫) 負責儲存路由，並在發生變更時持續更新路由表。

## Autonomous System

- ASN 64512 到 65535 之間的編號是保留供私有使用的
    - 在資料中心內部使用 BGP 時，必須使用這段私有編號範圍，或是使用自己擁有的 ASN。

- ASN 是 BGP 建立轉發拓撲（forwarding topology）的核心。
- 一則 BGP 路由通告（route advertisement）不僅攜帶原始發起者（originator）的 ASN，還會附帶該通告所經過的 ASN 列表。
- 當 BGP 節點（speaker）轉發路由通告時，它會將自己的 ASN 添加到這個列表中。這個 ASN 列表就稱為「AS path」（AS 路徑）。
    - BGP 利用 AS path 來偵測並避免路由迴圈（loops）。

## eBGP and iBGP

若要使用 BGP，必須在 BGP 路由器之間建立鄰居關係。這被稱為 BGP peer。BGP peer 有兩種。分別是 
- iBGP
- eBGP

對於 BGP，首先必須建立 TCP 連線，使用 179 埠號，並進行三次握手。TCP 連線建立後，一方發送 `Open Message` 訊息，另一方回應另一個 `Open Message` 訊息。此時狀態變為 `OpenSent`。鄰居收到 `Open Message` 後，會產生 `Keepalive Message`，這種等待對方回覆 `Keepalive` 的狀態稱為 `OpenConfirm`。最後，在收到 `keepalive` 的回應後，點對點連線就建立了，這個最後的狀態叫做 `Established`。

在上述過程中，如果發生任何 IP 連線問題或任何鄰居設定錯誤或任何其他問題，則狀態變為 `Active` 狀態。

|BGP states| Events |
|---|---|
|Idle|初始狀態，嘗試啟動 TCP 連線|
|Connect|嘗試建立 TCP 連線|
|Active|嘗試建立 TCP 連線|
|Open sent|交換 OPEN 訊息並協商能力，例如 BGP 版本、AS 編號和保持時間(Hold time)。|
|Open confirm|交換 OPEN 訊息並協商能力，例如 BGP 版本、AS 編號和保持時間(Hold time)。|
|Established|BGP 會話完全建立，開始透過 UPDATE 訊息交換路由資訊|


BGP 會保留 BGP 路由表的版本號碼。每當 BGP 更新路由表並更新路由資訊時，版本號碼都會隨之變更。連線建立後，路由表傳送給每個鄰居，後面都會是以*增量*方式更新。

對於 BGP 來說，會維護一個單獨的路由表，該表基於最短 AS 路徑和其他各種路徑屬性(Path Attributes)。

### BGP Message

BGP 使用 4 種訊息：
- Open Message
- Update Message
- Keepalive Message
- Notification Message

BGP 標頭

1. Marker(16 bytes)

指示 BGP peer 之間同步的資訊是否完整。此欄位用於 BGP 認證時的計算。若無認證，則二進位全 1，十六進位全 F。但現今的 BGP 安全性主要依賴於 TCP MD5 等傳輸層機制 。如果接收到的標記欄位值不正確，將觸發一個「連線未同步」（Connection Not Synchronized）的 NOTIFICATION 錯誤，並立即終止 BGP 會話 。   


2. Length(2 bytes)

用以指示整個 BGP 訊息的總長度（以位元組為單位），包含標頭本身。此欄位的值必須介於 19（用於 KEEPALIVE 訊息）到 4096 之間 。該欄位至關重要，它讓接收方的 BGP 發言者（speaker）能夠確定訊息的邊界，並分配適當的緩衝區空間。如果實際接收到的資料長度與此欄位的值不匹配，將導致「訊息長度錯誤」（Bad Message Length）的 NOTIFICATION 訊息，並中斷連線 。

3. Type(1 bytes)

指示 BGP 訊息頭後面的訊息類型。
- Open Message (1)
- Update Message (2)
- Keepalive Message (3)
- Notification Message (4)
- Route-refresh (5)

[huawei | BGP Message](https://info.support.huawei.com/hedex/api/pages/EDOC1100277644/AEM10221/04/resources/vrp/dc_vrp_feature_bgp_5002.html)

#### Open Message

- 用於建立 BGP 連線
- 提供參數協商(交換參數)
    - 這個協商階段至關重要，它確保了兩個對等方在交換任何路由資訊之前，是相互相容的，且對會話參數達成了一致。

交換的參數:

- AS Number
- BGP Version
- BGP Router ID
- Keepalive
- Hold Time
- Optional Parameters Length
- Optional Parameters

#### Update Message

- 向已連線鄰居發送路由更新
    - 通告一組共享相同路徑屬性的新的、可行的路由
    - 撤銷一組先前通告的、現已不可達的路由。
    - 在單一訊息中同時執行上述兩種操作 。

- BGP 會話啟動後，會持續傳送更新訊息，直到交換完整的 BGP 路由表為止
    - 此後，每次發送更新訊息時，BGP 路由表都會更新，並且BGP路由表版本號碼會增加 1

封包結構
- Withdrawn Routes Length(2 bytes)
    - 「已撤銷路由」欄位的總長度。值為 0 表示此訊息中沒有路由被撤銷 
- Withdrawn Routes (variable)
    - 一個不再可達的 IP 位址前綴列表。每個前綴被編碼為一個 (Length, Prefix) 元組，其中 Length 是前綴的位元長度 。
- Total Path Attribute Length (2 bytes)
    - 後面「路徑屬性」欄位的總長度。值為 0 表示沒有新的路由被通告，此訊息僅用於撤銷路由 。
- Path Attributes (variable)
- Network Layer Reachability Information (NLRI) (variable)
    - 正在被通告的 IP 位址前綴列表。與「已撤銷路由」欄位一樣，每個前綴被編碼為一個 (Length, Prefix)。


##### Path Attributes

路徑屬性（Path Attributes, PAs）是 BGP 用於做出基於策略的路由決策的機制，超越了 IGP 所使用的簡單的最短路徑度量。屬性有以下

- ORIGIN（類型 1，Well-known Mandatory）
- AS_PATH（類型 2，Well-known Mandatory)
- NEXT_HOP（類型 3，Well-known Mandatory）
- MULTI_EXIT_DISC (MED)（類型 4，Optional Non-transitive）
- etc.

##### **BGP 路徑屬性分類 (Path Attribute Classifications)**
BGP 路由的選取取決於附帶的各種路徑屬性 (PAs)。PAs 主要有四種分類，影響了它們能否跨越 AS 傳播：

| 屬性類別 | 識別性 (Required by all implementations) | 傳遞性 (Advertised Between ASs) | 範例 |
| :--- | :--- | :--- | :--- |
| Well-known Mandatory | 必須識別 | 是 | Next-Hop, AS-Path, Origin |
| Well-known Discretionary | 必須識別 | 否 | Local Preference |
| Optional Transitive | 不必須識別 | 是 (如識別則傳播) | Community, Atomic Aggregate |
| Optional Non-transitive | 不必須識別 | 否 | MED, Originator ID, Cluster List |

#### Keepalive Message 

- 用於檢查鏈路的可用性
- 防止 hold time 時間過期

keepalive Messaage 每 60 秒發送一次。如果在 3 個 keepalive 時間（hold time），即 180 秒內沒有收到回應，則認為連線遺失。

#### Notification Message

- 用於偵測到錯誤時發送
- 收到此訊息後，BGP 和 TCP 連線將關閉
    - 通知訊息由 BGP 標頭、Error Code、Error subcode 以及描述錯誤的 Data 組成

封包格式

- Error Code (1 bytes)
- Error Subcode (1 bytes)
- Data (可變長度)

## BGP Unnumbered

1. 傳統 BGP 的問題：

- 傳統 BGP peering 需要在每個介面上配置 IPv4 位址。
- 當宣告 IPv4 路由時，必須指定一個 IPv4 位址作為「下一跳」（next hop）。
- 在大型網路中，這會消耗大量的 IPv4 位址空間。

2. BGP Unnumbered (RFC 5549) 的解決方案：

- 允許 BGP 交換 IPv4 路由，而無需在介面上配置 IPv4 位址。
- 它使用 **IPv6 link-local（鏈路本地）位址** 作為 IPv4 路由的「下一跳」。
- 這極大地節省了 IPv4 位址的消耗。

3. Cumulus Linux 的實作機制：

- BGP unnumbered 依賴 ENHE（擴展下一跳編碼）。
- Cumulus Linux 不會直接將「IPv4 前綴搭配 IPv6 下一跳」的路由安裝到系統核心（kernel）。
- 相反，BGP 會將該 IPv6 link-local 下一跳轉換為一個 IPv4 link-local 位址（例如 169.254.x.x）。
- 同時，它會從對端鄰居的 link-local 位址推導出其 MAC 位址，並為這個 IPv4 link-local 位址安裝一筆靜態鄰居條目（IP+MAC 綁定），以便核心知道如何轉發封包。

### Cumulus BGP Configuration

使用 BGP numbered（BGP 編號）或 BGP unnumbered（BGP 未編號）來配置 BGP。透過 BGP unnumbered，可以在 Cumulus Linux 交換器之間建立 BGP 鄰居關係（peering）並交換 IPv4 前綴（prefixes），而無需在每台交換器上配置 IPv4 位址。

#### BGP Numbered

**經典 BGP (Classic BGP)**的設定四要素。所謂**Numbered (具名)**，是指 BGP 鄰居 (neighbor) 關係是建立在**明確的 L3 介面 IP 位址**上的。

（這與 BGP Unnumbered 相反，Unnumbered 是用「介面名稱」來自動建立鄰居，不需手動指定 IP。）

要設定這種 BGP，你必須搞定四件事：

1.  **我是誰 (ASN)**：
    * 你必須先設定**自己**的 **ASN** (自治系統編號)。
    * (Cumulus 提示：在 Leaf-Spine 架構，你可以用 `auto BGP` 讓系統自動產生 ASN，省去麻煩)。

2.  **我的名字 (Router-ID)**：
    * 每個 BGP 路由器都需要一個獨一無二的 **Router ID** (就像它的名字)。
    * **[最佳實踐]**：系統會**自動抓 Loopback 介面的 IP** 來當作 Router ID。這是標準做法，因為 Loopback 介面永遠不會斷線 (Down)，最為穩定。

3.  **我的鄰居是誰 (Neighbor)**：
    * 這是「Numbered」的核心。你必須**手動**指定：
        * 鄰居的 **IP 位址** (就是你跟他相連的那條 L3 鏈路的對口 IP)。
        * 鄰居的 **ASN** (用 `remote-as` 指令)。
    * (系統會根據你填的 ASN 和你自己的 ASN 是否相同，來自動判斷這是 iBGP 還是 eBGP)。

4.  **我要廣播什麼 (Prefixes)**：
    * BGP 建立起來後，預設是不會通告任何路由的。
    * 必須手動用 `network` (宣告) 指令，告訴 BGP：「請幫我把**這些** IP 網段 (Prefixes) 廣播給我的鄰居」。

#### BGP Unnumbered

BGP 無編號配置與上面所示的 BGP 編號配置的唯一區別在於，BGP 鄰居是介面（而不是 IP 位址）。無需在兩端對等體之間的介面上分別設定 IP 位址。


## Verify Configuration

BGP Neighbor

```bash

leaf01# show ip bgp summary

IPv4 Unicast Summary:
BGP router identifier 10.10.10.1, local AS number 65101 vrf-id 0
BGP table version 12
RIB entries 15, using 3000 bytes of memory
Peers 3, using 68 KiB of memory
Peer groups 1, using 64 bytes of memory

Neighbor              V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt
leaf02(peerlink.4094) 4      65102       124       126        0    0    0 00:04:23            7        8
spine01(swp51)        4      65199       122       113        0    0    0 00:03:54            5        8
spine02(swp52)        4      65199       127       119        0    0    0 00:03:51            5        8

Total number of neighbors 3
```

```bash
spine01# show ip bgp summary

IPv4 Unicast Summary:
BGP router identifier 10.10.10.101, local AS number 65199 vrf-id 0
BGP table version 72
RIB entries 19, using 3800 bytes of memory
Peers 6, using 137 KiB of memory
Peer groups 1, using 64 bytes of memory

Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt
leaf01(swp1)    4      65101      2787      2771        0    0    0 00:04:19            3       10
leaf02(swp2)    4      65102      2770      2762        0    0    0 00:04:18            3       10
leaf03(swp3)    4      65103      2780      2769        0    0    0 01:05:46            3       10
leaf04(swp4)    4      65104      2784      2771        0    0    0 01:05:46            3       10
border01(swp5)  4      65253      2866      2775        0    0    0 00:04:18            3       10
border02(swp6)  4      65254      2876      2775        0    0    0 00:04:19            3       10

Total number of neighbors 6
spine01# 
```

是否可以在路由表中看到其他鄰居的前綴

```bash

leaf01# show ip route  
Codes: K - kernel route, C - connected, S - static, R - RIP,
       O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
       T - Table, v - VNC, V - VNC-Direct, A - Babel, D - SHARP,
       F - PBR, f - OpenFabric, Z - FRR,
       > - selected route, * - FIB route, q - queued, r - rejected, b - backup
       t - trapped, o - offload failure
C>* 10.0.1.12/32 is directly connected, lo, 02:01:38
B>* 10.0.1.34/32 [20/0] via fe80::a8c1:abff:fe58:cf0c, swp51, weight 1, 00:06:02
B>* 10.0.1.255/32 [20/0] via fe80::a8c1:abff:fe58:cf0c, swp51, weight 1, 00:06:02
C>* 10.10.10.1/32 is directly connected, lo, 04:22:28
B>* 10.10.10.2/32 [20/0] via fe80::a8c1:abff:fe1d:b01b, peerlink.4094, weight 1, 00:06:02
B>* 10.10.10.3/32 [20/0] via fe80::a8c1:abff:fe58:cf0c, swp51, weight 1, 00:06:02
B>* 10.10.10.4/32 [20/0] via fe80::a8c1:abff:fe58:cf0c, swp51, weight 1, 00:06:02
B>* 10.10.10.63/32 [20/0] via fe80::a8c1:abff:fe58:cf0c, swp51, weight 1, 00:06:01
B>* 10.10.10.64/32 [20/0] via fe80::a8c1:abff:fe58:cf0c, swp51, weight 1, 00:06:02
B>* 10.10.10.101/32 [20/0] via fe80::a8c1:abff:fe58:cf0c, swp51, weight 1, 00:06:02
```

```bash
spine01# show ip route
Codes: K - kernel route, C - connected, S - static, R - RIP,
       O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
       T - Table, v - VNC, V - VNC-Direct, A - Babel, D - SHARP,
       F - PBR, f - OpenFabric, Z - FRR,
       > - selected route, * - FIB route, q - queued, r - rejected, b - backup
       t - trapped, o - offload failure
B>* 10.0.1.12/32 [20/0] via fe80::a8c1:abff:fe0d:562d, swp1, weight 1, 00:05:34
  *                     via fe80::a8c1:abff:fe29:e00f, swp2, weight 1, 00:05:34
B>* 10.0.1.34/32 [20/0] via fe80::a8c1:abff:feaa:7e1d, swp3, weight 1, 00:05:03
  *                     via fe80::a8c1:abff:feb3:3f17, swp4, weight 1, 00:05:03
B>* 10.0.1.255/32 [20/0] via fe80::a8c1:abff:fee6:4359, swp5, weight 1, 00:05:33
  *                      via fe80::a8c1:abff:fef8:4e69, swp6, weight 1, 00:05:33
B>* 10.10.10.1/32 [20/0] via fe80::a8c1:abff:fe0d:562d, swp1, weight 1, 00:05:34
B>* 10.10.10.2/32 [20/0] via fe80::a8c1:abff:fe29:e00f, swp2, weight 1, 00:05:34
B>* 10.10.10.3/32 [20/0] via fe80::a8c1:abff:feaa:7e1d, swp3, weight 1, 01:07:01
B>* 10.10.10.4/32 [20/0] via fe80::a8c1:abff:feb3:3f17, swp4, weight 1, 01:07:01
B>* 10.10.10.63/32 [20/0] via fe80::a8c1:abff:fee6:4359, swp5, weight 1, 00:05:33
B>* 10.10.10.64/32 [20/0] via fe80::a8c1:abff:fef8:4e69, swp6, weight 1, 00:05:34
C>* 10.10.10.101/32 is directly connected, lo, 04:21:26
```

## Optional BGP Configuration

### Peer Groups

與其為每一個獨立的對等體 (peer) 指定屬性，可以定義一個或多個對等體群組 (peer groups)，並將該對等體會話 (peer session) 共通的所有屬性關聯到這個群組上。只需要將一個對等體附加到群組一次；之後，它就會繼承該群組已啟用的所有位址家族 (address families)。

```yaml
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
            peer-group: # this 
              underlay: # 對應 neighbor.<interface>.peer-group
                address-family:
                  l2vpn-evpn:
                    enable: on
                remote-as: external
```

### Multiple BGP ASNs

Cumulus Linux 支援對不同的 VRF 實例使用不同的 ASN。


```yaml
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
                route-export:
                  to-evpn:
                    enable: on
            autonomous-system: 65101 # this
            enable: on
            router-id: 10.10.10.1 # this
      RED:
        evpn:
          enable: on
          vni:
            '4001': {}
        router:
          bgp:
            address-family:
              ipv4-unicast:
                enable: on
                redistribute:
                  connected:
                    enable: on
                route-export:
                  to-evpn:
                    enable: on
            autonomous-system: 65101 # this
            enable: on
            router-id: 10.10.10.1 # this
```

## 實驗配置


### 1. BGP 配置了什麼內容？

BGP 設定主要分為兩層：**Underlay (底層網路)** 和 **Overlay (覆蓋網路)**。

**核心架構：eBGP Spine-Leaf (BGP Unnumbered)**

這套架構採用 eBGP，Spine 和 Leaf 處於不同的 ASN (自治系統編號)，這是現代資料中心的最佳實踐。

  * **Spine (e.g., spine-2)**：
      * ASN (自治系統編號) 為 `65199`。
      * Router-ID (路由器 ID) 為 `10.10.10.102` (它的 Loopback IP)。
  * **Leaf (e.g., leaf-4)**：
      * ASN 為 `65104` (每對 Leaf 都有獨立的 ASN)。
      * Router-ID 為 `10.10.10.4` (它的 Loopback IP)。

**關鍵設定：BGP Unnumbered (無編號)**

沒有使用傳統的「具名 (Numbered) BGP」，而是使用了更先進的「Unnumbered BGP」來建立 Underlay (底層) 鄰居關係：

  * 在 Spine (`spine-2`) 上，不是手動指定 `neighbor 10.x.x.x ...`，而是使用介面名稱：
    ```bash
    neighbor swp1 interface peer-group underlay
    neighbor swp2 interface peer-group underlay
    ...
    ```
  * 在 Leaf (`leaf-4`) 上，同樣使用介面名稱來指向 Spines 和 MLAG 對等體：
    ```bash
    neighbor peerlink.4094 interface peer-group underlay  # 與 MLAG 夥伴 (leaf-3) 建立 BGP
    neighbor swp51 interface peer-group underlay          # 與 spine-1 建立 BGP
    neighbor swp52 interface peer-group underlay          # 與 spine-2 建立 BGP
    ```
  * **作用**：BGP 會自動使用 IPv6 Link-Local 位址來建立 BGP 鄰居，**完全不需要**在 Spine 和 Leaf 之間的 L3 介面上手動設定 IP 位址，大幅簡化了 Underlay 的 IP 管理。

**路由通告 (Address Family `ipv4 unicast`)**

  * 在 `vrf default` (底層網路) 中，Spine 和 Leaf 都啟用了 `address-family ipv4 unicast`。
  * 兩邊都設定了 `redistribute connected`。
  * **作用**：這是 Underlay 的核心。Leaf 會將自己的 Loopback IP (VTEP IP，例如 `10.10.10.4`) 通告給 Spine；Spine 再將其通告給所有其他 Leaf。這確保了**所有 VTEP 之間 L3 路由可達**，VXLAN 隧道才能建立。


### 2. BGP 如何與 EVPN 整合？

BGP 本身只是傳輸工具 (Transport)，EVPN 則是 BGP 承載的一種「貨物」(Address Family)。設定檔展示了 EVPN 如何利用 BGP 來取代傳統的 L2 泛洪 (Flooding)，並實現 L3 路由。

整合分為 L2 和 L3 兩個層面：

#### A. L2 整合 (通告 MAC 位址 - EVPN Type 2)

1.  **啟用 EVPN 貨運**：

      * 在 Spine 和 Leaf 的 BGP 設定中，都啟用了 `address-family l2vpn evpn`。
      * 並在所有鄰居下都用 `activate` 指令啟動。
      * **作用**：這告訴 BGP：「你現在除了要運送 IPv4 路由，還必須開始運送 EVPN (L2/L3) 路由」。

2.  **Spine 的角色 (路由中轉)**：

      * Spine 的 BGP 設定**只有** `l2vpn evpn`，它**沒有** `vlan`、`vni` 或 `vxlan` 介面。
      * **作用**：Spine 扮演「EVPN 路由反射器」(Route Reflector) 的角色。它**不**是 VTEP，它**只**負責將 Leaf 傳來的 EVPN 路由 (MAC/IP)，轉發給所有其他 Leaf。

3.  **Leaf 的角色 (VTEP)**：

      * `leaf-4` 的 `interfaces` 檔中定義了 VXLAN 介面 `vxlan48`。
      * `bridge-vlan-vni-map 10=10 20=20 30=30 ...`：這行建立了 L2 VLAN 和 L2 VNI 的對應。
      * `bridge-learning off`：**關鍵設定**。關閉傳統的 L2 資料平面學習 (Flood-and-Learn)。
      * **整合流程**：當 `server01` (在 VLAN 10) 上線時，`leaf-4` 會偵測到。BGP (EVPN) 會自動建立一筆 **EVPN Type-2 路由** (包含 `server01` 的 MAC/IP、VNI 10 等資訊)，然後透過 BGP 將這筆「L2 路由」通告給 Spine，Spine 再轉發給所有其他 Leaf。

#### B. L3 整合 (通告 IP 路由 - EVPN Type 5)

架構採用了最高效的「**分散式對稱路由 (Distributed Symmetric Routing)**」模型。

1.  **建立 VRF (多租戶)**：

      * `leaf-4` 上建立了 `vrf RED` 和 `vrf BLUE` 兩個租戶。
      * SVI (L3 介面) 被分配到 VRF 中，例如 `vlan10` 被放入 `vrf RED`。

2.  **建立 L3 VNI**：

      * `interfaces` 檔中，`vxlan48` 將 L3 專用的 `vlan4024` 對應到 `vni 4001` (RED VRF)，`vlan4036` 對應到 `vni 4002` (BLUE VRF)。
      * `frr.conf` 中，`vrf RED` 也宣告了 `vni 4001`。
      * **作用**：`vni 4001` 和 `4002` 成為 L3 VRF 之間專用的「路由隧道」。

3.  **BGP 通告 L3 路由 (關鍵)**：

      * `leaf-4` 的 `frr.conf` 中，**在 VRF 內部**也啟動了 BGP (`router bgp 65104 vrf RED`)。
      * `redistribute connected`：將 `vrf RED` 中的 SVI 網段 (如 `vlan10` 的 `10.1.10.0/24`) 注入 BGP。
      * `address-family l2vpn evpn` -> `advertise ipv4 unicast`：**這就是整合的魔術**。這行指令告訴 BGP，請將 `vrf RED` 中所有的 L3 IPv4 路由 (例如 `10.1.10.0/24`)，轉換為 **EVPN Type-5 路由 (IP Prefix Route)**，並通告給其他 VTEP。

#### 總結

1.  **BGP (Underlay)**：您使用 **eBGP Unnumbered** 來建立 Spine 和 Leaf 之間的 L3 網路，目的是讓所有 VTEP (Loopback IP) 之間路由可達。
2.  **BGP (Overlay)**：您使用 BGP 的 **`l2vpn evpn` 位址家族**作為 VXLAN 的**控制平面**。
3.  **L2 整合**：EVPN 會自動將學到的 MAC 位址轉換為 **Type-2 路由**，並透過 BGP 通告，實現 L2 網路的延伸 (取代了 Flooding)。
4.  **L3 整合**：EVPN 透過 VRF 內的 `advertise ipv4 unicast`，將 SVI 網段轉換為 **Type-5 路由**，並透過 BGP 通告，實現高效的「分散式 L3 閘道」(取代了傳統的核心路由)。