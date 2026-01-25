# [VLAN](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-514/Layer-2/Ethernet-Bridging-VLANs/#)

這段話的核心觀念很簡單，主要在說明「Bridge 是什麼」和「它的 MTU 如何決定」：

1.  **核心功能 (L2 串連)**：
    * Bridge 的主要工作是「橋接」，把好幾個不同的網路介面（無論是實體的網孔，還是虛擬的介面）綁在一起。
    * 綁定後，這些介面會變成**同一個 L2 網域**（也就是同一個廣播域，Broadcast Domain）。這讓掛在這些不同介面下的裝置（主機）能像在同一個區域網路 (LAN) 裡一樣互相溝通。

2.  **本身屬性 (邏輯介面)**：
    * Bridge **不是**一個實體的硬體（雖然硬體交換器 *內建* 了橋接功能），在系統中，它是一個「邏輯介面」。
    * 既然是介面，它就會有自己的 **MAC 位址** 和 **MTU** (最大傳輸單元) 值。

3.  **MTU 決定規則 (關鍵重點)**：
    * Bridge 的 MTU **不是**自己隨便設定的，也不是取最大值。
    * 它的 MTU 值取決於它底下所有成員介面中，**MTU 值最小的那一個**。
        * 如果你的 Bridge 串接了 MTU 9000 (Jumbo Frame) 和 MTU 1500 (標準) 兩個介面，那麼整個 Bridge 的 MTU 就會被「拉低」到 1500，以確保所有成員都能正常處理封包。

## Ethernet Bridge Types

NVIDIA 建議您使用 **VLAN 感知模式**的橋接器，而非傳統模式的橋接器。Cumulus Linux 的橋接器驅動程式具備 **VLAN 過濾 (VLAN filtering)** 的能力，這使得設定上能更接近（功能更相仿於）現有的主流網路設備。

Cumulus Linux 處理 L2 橋接 (Bridge) 的兩種方法


這段話的重點很明確，是在告訴你 Cumulus Linux 處理 L2 橋接 (Bridge) 的兩種方法，以及**官方推薦哪一種**。

1.  **兩種模式並存 (Two Modes)**：
    * **傳統模式 (Traditional Bridge)**：這是 Linux 系統本來就有的橋接方式 (e.g., `brctl`)。它比較單純，通常是把所有介面綁在一起，對 VLAN 的處理比較不直覺 (e.g., 需額外建立 sub-interface `eth0.10`)。
    * **VLAN 感知模式 (VLAN-aware Bridge)**：這是 Cumulus (NVIDIA) **推薦**的新模式。

2.  **為什麼推薦 VLAN-aware？ (The "Why")**：
    * 關鍵字是 **VLAN Filtering (VLAN 過濾)**。
    * **[技術員解讀]**：這代表 Bridge 本身就能夠「看懂」並處理 802.1Q VLAN 標籤。你可以直接在 Bridge 上設定哪些 port 是 Access Port (PVID)
        、哪些是 Trunk Port (allowed VLANs)，**這讓 Cumulus 交換器的行為和設定邏輯，幾乎等同於你我熟悉的Cisco/Arista 等專用網路設備**，管理上更直覺。

3.  **相容性 (Co-existence)**：
    * 你可以在同一台 Cumulus 設備上同時使用這兩種模式的 Bridge（雖然不建議這樣混用，除非有特殊需求）。

## Bridge MAC Addresses

「當一個訊框 (frame) 透過介面進入橋接器時，交換器會學習 (learn) 該訊框的 MAC 位址，並將這個 MAC 位址記錄在橋接器表 (bridge table) 中。

橋接器透過查詢（訊框的）目標 MAC 位址，來將訊框轉發 (forward) 到其預定的目的地。

三件 L2 交換器最基本的工作：**學習 (Learn)**、**轉發 (Forward)** 和 **老化 (Aging)**。

1.  **如何學習 (Learning) 🧠**
    * **時機**：當封包**進來 (Ingress)** 時。
    * **學什麼**：學習封包的「**來源 MAC (Source MAC)**」。
    * **動作**：把「這個 MAC」跟「它是從哪個 Port 進來的」綁定，記錄在「**Bridge Table**」（我們俗稱的 **MAC Address Table**）。
    * *[例子：`PC_A` (MAC-A) 從 `Port_1` 送出封包，交換器就學到：`MAC-A` 在 `Port_1` 上。]*

2.  **如何轉發 (Forwarding) ➡️**
    * **時機**：當封包需要**出去 (Egress)** 時。
    * **查什麼**：查詢封包的「**目標 MAC (Destination MAC)**」。
    * **動作**：去查 MAC Table。如果表裡有紀錄，就精準地從對應的 Port 送出去；如果查不到，就會執行 "Flooding"（廣播到所有 Port）。

3.  **如何老化 (Aging) ⏳ (Cumulus Specific)**
    * **目的**：保持 MAC Table 的資料是「新鮮的」，自動清掉已經離線或搬移的裝置。
    * **Cumulus 預設值**：**1800 秒 (30 分鐘)**。
    * **刷新 (Refresh)**：如果 30 分鐘內，同一個 MAC 又從同一個 Port 發送封包，計時器就會**重置 (Reset)**，重新倒數 30 分鐘。
    * **刪除 (Delete)**：如果一筆 MAC 紀錄放了 30 分鐘都沒被刷新，系統就認定這台裝置可能不在了，會將這筆條目**刪除**。

```bash
root@leaf01:/# nv show bridge domain br_default mac-table
      age   bridge-domain  entry-type  interface   last-update  mac                src-vni  vlan  vni   Summary
----  ----  -------------  ----------  ----------  -----------  -----------------  -------  ----  ----  -----------------------
+ 0   1099  br_default                 bond1       2472         aa:c1:ab:50:9d:2d           10
+ 1   3507  br_default     permanent   bond1       3507         aa:c1:ab:06:95:ac           10
+ 2                        permanent   bond1                    33:33:00:00:00:01
+ 3                        permanent   bond1                    33:33:00:00:00:02
+ 4                        permanent   bond1                    01:00:5e:00:00:01
+ 5   1114  br_default                 bond3       2585         aa:c1:ab:63:37:39           30
+ 6   3507  br_default     permanent   bond3       3507         aa:c1:ab:12:de:d5           30
+ 7                        permanent   bond3                    33:33:00:00:00:01
+ 8                        permanent   bond3                    33:33:00:00:00:02
+ 9                        permanent   bond3                    01:00:5e:00:00:01
+ 10  1563  br_default                 vxlan48     1563         44:38:39:22:01:8a           4024  None  remote-dst:   10.0.1.34
  10                                                                                                    remote-dst:  10.10.10.4
+ 11  1563  br_default                 vxlan48     1563         44:38:39:22:01:84           4024  None  remote-dst:   10.0.1.34
  11                                                                                                    remote-dst:  10.10.10.3
+ 12  1563  br_default                 vxlan48     1563         aa:c1:ab:fa:28:fa           10    None  remote-dst:   10.0.1.34
+ 13  1563  br_default                 vxlan48     1563         aa:c1:ab:e3:81:76           30    None  remote-dst:   10.0.1.34
+ 14  1563  br_default                 vxlan48     1563         aa:c1:ab:3e:fe:af           20    None  remote-dst:   10.0.1.34
+ 15  1564  br_default                 vxlan48     1564         44:38:39:22:01:74           4036  None  remote-dst: 10.10.10.63
+ 16  1564  br_default                 vxlan48     1564         44:38:39:22:01:78           4036  None  remote-dst:  10.10.10.2
+ 17  3507  br_default     permanent   vxlan48     3507         7a:99:89:af:2d:1b           4036  None
+ 18  1563                 permanent   vxlan48     0            00:00:00:00:00:00  30             None  remote-dst:   10.0.1.34
+ 19  3440  br_default     static      peerlink    1114         44:38:39:22:01:78           30
+ 20  3506  br_default     permanent   peerlink    3506         aa:c1:ab:af:cc:05           30
+ 21                       permanent   peerlink                 33:33:00:00:00:01
+ 22                       permanent   peerlink                 33:33:00:00:00:02
+ 23                       permanent   peerlink                 01:00:5e:00:00:01
+ 24                       permanent   peerlink                 01:80:c2:00:00:21
+ 25                       permanent   peerlink                 33:33:ff:af:cc:05
+ 26                       permanent   peerlink                 33:33:ff:00:00:00
+ 27  6     br_default                 bond2       3229         aa:c1:ab:65:96:40           20
+ 28  3506  br_default     permanent   bond2       3506         aa:c1:ab:ec:de:83           20
+ 29                       permanent   bond2                    33:33:00:00:00:01
+ 30                       permanent   bond2                    33:33:00:00:00:02
+ 31                       permanent   bond2                    01:00:5e:00:00:01
+ 32                       permanent   br_default               44:38:39:ff:00:aa
+ 33                       permanent   br_default               00:00:5e:00:01:01
+ 34                       permanent   br_default               01:80:c2:00:00:21
+ 35                       permanent   br_default               01:00:5e:00:00:01
+ 36                       permanent   br_default               33:33:00:00:00:01
+ 37                       permanent   br_default               33:33:00:00:00:02
+ 38                       permanent   br_default               33:33:ff:ff:00:aa
+ 39                       permanent   br_default               33:33:ff:00:00:00
+ 40                       permanent   br_default               33:33:ff:22:01:7a
+ 41                       permanent   br_default               33:33:ff:00:01:01
+ 42  3472  br_default     permanent   br_default  3472         44:38:39:22:01:7a           4036
```

## bridge fdb Command Output

Linux bridge fdb 命令與 FDB 交互，網橋(bridge)使用 FDB 來儲存其學習到的 MAC 位址以及學習這些 MAC 位址的連接埠

|Keyword|Description|
|---|---|
|self||
|master||
|extern_learn||


```bash
root@leaf01:/# bridge fdb show | grep "aa:c1:ab:e3:81:76"
aa:c1:ab:e3:81:76 dev vxlan48 vlan 30 extern_learn master br_default 
aa:c1:ab:e3:81:76 dev vxlan48 dst 10.0.1.34 src_vni 30 self extern_learn 
```

- aa:c1:ab:e3:81:76 使用 BGP EVPN 學習的 MAC 位址
- 第一個 FDB 項目指向一個 Linux 橋接器，該條目指向 VXLAN 裝置 vxlan48
- 第二個 FDB 項目指向 VXLAN 裝置上的相同條目，並包含額外的遠端目標資訊
- VXLAN FDB 透過附加的遠端目標資訊增強了橋接 FDB (dst 10.0.1.34 src_vni 30)

## Considerations

1. 同一 Port 的多個 Subinterface 限制

一個橋接器 (bridge) 無法同時包含來自同一個實體 Port 的多個子介面 (subinterface)。嘗試這樣設定會導致錯誤。

不能把 eth1.10 和 eth1.20 這兩個子介面，同時綁到 同一個 Bridge 裡。這在 L2 邏輯上是衝突的（一個 Port 怎麼會同時屬於兩個 VLAN 又在同一個 L2 網域？），系統會直接報錯，不讓你這樣設定。

2. 混用模式的 Flapping 警告

如果你同時使用了 VLAN 感知 (VLAN-aware) 和傳統 (traditional) 兩種橋接器，假設一個「傳統橋接器」包含了一個 bond 子介面 (e.g., bond0.10)，而這個 bond 介面 (e.g., bond0) 本身又是一個「VLAN 感知橋接器」的成員，那麼當你手動關閉 (bring down) 那個「傳統橋接器」中的 bond 子介面時，會導致橋接器發生 flapping (介面不穩定/上下彈跳)。

盡量不要混用！尤其是當你把一個 Bond (LAG) 介面同時給兩種 Bridge 模式使用時（例如 bond0 給 VLAN-aware bridge 當 Trunk，但 bond0.10 又給 traditional bridge 用），你對其中一個的操作會干擾到另一個，造成網路瞬斷 (flapping)。

3. VLAN 介面的修改限制

你不能將一個已經建立的 VLAN 原始設備 (VLAN raw device, e.g., vlan10) 重新指派 (enslave) 給一個不同的主介面 (master interface)。(你不能直接去編輯 /etc/network/interfaces 檔案中的 vlan-raw-device 設定)。你必須先刪除這個 VLAN，然後再重新建立它。

這條是設定變更的 SOP (標準作業程序)。

- 情境：你建立了一個 vlan10 介面，它本來是掛在 eth1 底下 (變成 eth1.10)。
- 錯誤操作：你不能事後直接修改設定檔，想把它改掛到 eth2 (變成 eth2.10)。
- 正確操作：必須先刪掉 vlan10 介面，再重新建立一個掛在 eth2 上的 vlan10。

4. MAC 學習的預設值

Cumulus Linux 在傳統和 VLAN 感知模式的橋接器介面上，預設都會啟用 MAC 學習 (MAC learning)。不要關閉 MAC 學習功能，除非你有特殊目的，例如正在使用 EVPN。

- 保持預設：L2 交換器能正常運作，就是依賴 MAC learning 來建立 MAC-Table。所以這個功能必須保持開啟。
- 唯一的例外：跑 EVPN (常用於 Data Center VXLAN) 時。在 EVPN 環境中，MAC 位址是透過「控制平面」(Control Plane, BGP 協定) 來通告和學習的，而不是傳統的「資料平面」(Data Plane) 學習。在這種情況下，才會需要手動關閉 MAC learning，以避免衝突。

## VLAN-aware Bridge Mode
「Cumulus Linux 中的 VLAN 感知橋接器模式 (VLAN-aware bridge mode) 實現了一種適用於大規模 Layer 2 環境的設定模型，且（整個橋接器）只運行一個 Spanning Tree Protocol (STP) 實例。

##### 1. 核心優勢：告別「子介面」地獄

* **傳統模式 (Traditional)**：如果你要在 `eth1` 上 Trunk 100 個 VLAN，你必須在 Linux 系統中手動建立 100 個子介面 (e.g., `eth1.10`, `eth1.20`, `eth1.21`...)，然後再把這些子介面一個個加入 Bridge。這非常笨重、設定檔超長，且極度消耗系統資源。
* **VLAN-aware 模式 (VLAN-aware)**：你**不需要**建立任何子介面。你只要告訴 Bridge：「`eth1` 是我的成員，它允許 VLAN 10-110 通過」。系統底層會用高效的「VLAN bitmaps」去處理，設定檔乾淨、效能高。

##### 2. 運作邏輯：完全比照「專用交換器」
* 這段提到的 PVID 和 allowed VLANs，就是 L2 交換器的標準術語：
    * **PVID (Port VLAN ID)**：就是 `Access Port` 的 VLAN ID。
    * **Native VLAN**：就是 `Trunk Port` 上，允許「不帶標籤 (untagged)」封包通過的那個 VLAN。
    * **Allowed VLANs**：就是 `Trunk Port` 上允許通過的 VLAN 列表。
* 這代表可以用管理 Cisco/Arista 交換器的邏輯來管理 Cumulus。

##### 3. 智慧學習：MAC Table 是 VLAN 感知的
* 這很重要。Bridge 知道 `VLAN 10` 裡的 `MAC_A` 和 `VLAN 20` 裡的 `MAC_A` 是**兩個完全不同的條目**。
* 這確保了 VLAN 之間的 L2 隔離性是真正落實的。

##### 4. 擴展性：單一 STP 實例
* 在大型 L2 環境中，你不需要為每個 VLAN 或每個 Bridge 都跑一個 STP。
* VLAN-aware 模式的 Bridge 只需要**一個 STP 實例**就能管理底下所有 VLAN 的 L2 迴圈，這大大簡化了管理並提高了擴展性 (Scaling)。


你雖然可以建立多個 Bridge，但它們必須是「完全獨立且功能簡化」的。

在實務上，這代表你應該盡量只用一個 Bridge。

1. 核心概念：Bridge 之間必須完全隔離

- 雖然系統允許建立 bridge-A 和 bridge-B，但你必須把它們當作兩台完全獨立、互不相干的虛擬交換器。
- 資源不能共享：
    - 一個實體 Port (e.g., swp1) 只能綁定到 一個 Bridge。
    - 一個 VNI (VXLAN 的 ID) 只能對應到 一個 Bridge。

2. 重大功能限制：MLAG (最重要)
- MLAG 只能在「單一」Bridge 內運作。

> 這條是關鍵！如果你打算使用 Cumulus 最重要的 MLAG 功能（來做跨設備的 Port-Channel），你就不能把 Port 分配到不同的 Bridge。必須把所有 L2 介面都放在同一個預設的 Bridge 裡。

3. 高級 L2 功能受限
一旦你啟用多個 Bridge，以下這些高級 L2 封包處理功能將無法使用：

- VLAN Translation (VLAN 轉換)
- Double Tagged VLANs (Q-in-Q，或稱 QinQ)

4. VXLAN 相關限制
- SVD (Single VXLAN Device)：這是一種 VXLAN 的部署模式。限制是，你不能把多個 SVD (e.g., svd1, svd2) 同時綁到 同一個 Bridge 裡面。

除非有非常特殊的 L2 隔離需求（例如需要一個 L2 版本的 VRF），否則強烈建議你整台 Cumulus 設備只使用一個 VLAN-aware bridge (通常是預設的 bridge 或 br_default) 來處理所有的 L2 流量。

只有在單一 Bridge 的架構下，你才能使用 MLAG 和其他完整的 L2/VXLAN 功能。


### Configure a VLAN-aware Bridge


```bash
auto br_default
iface br_default
    # 將介面橋接再一起
    bridge-ports bond1 bond2 bond3 peerlink vxlan48
    hwaddress 44:38:39:22:01:b1
    bridge-vlan-aware yes
    bridge-vids 10 20 30
    bridge-pvid 1
```

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
            '30':
              vni:
                '30': {}
```

`bridge-pvid` 預設為 1，不必為網橋或端口指定 `bridge-pvid`。儘管這不會影響配置，但它有助於其他用戶的可讀性。

> 如果在網橋(bridge)層級指定 `bridge-vids` 或 `bridge-pvid`，則網橋中的所有連接埠都會繼承這些設定。但是，為特定連接埠指定任何這些設定都會覆蓋網橋中的設定。

### Access Ports and Tagged Packets

```bash
auto br_default
iface br_default
    # 將介面橋接再一起
    bridge-ports bond1 bond2 bond3 peerlink vxlan48
    hwaddress 44:38:39:22:01:b1
    bridge-vlan-aware yes
    # 告訴 bridge "VLAN 10 20 30" 是合法的
    bridge-vids 10 20 30
    bridge-pvid 1
auto bond1
iface bond1
    mtu 9000
    bond-slaves swp1
    bond-mode 802.3ad
    bond-lacp-bypass-allow yes
    clag-id 1
    # 它會自動將 PVID (Native VLAN) 設為 10
    # 並且只允許 VLAN 10 的流量通過
    bridge-access 10
auto bond2
iface bond2
    mtu 9000
    bond-slaves swp2
    bond-mode 802.3ad
    bond-lacp-bypass-allow yes
    clag-id 2
    # 它會自動將 PVID (Native VLAN) 設為 20
    # 並且只允許 VLAN 20 的流量通過
    bridge-access 20
```

### Drop Untagged Frames

在 VLAN 感知橋接器模式下，你可以設定交換器埠口 (port) 來丟棄任何未帶標籤 (untagged) 的訊框。要做到這一點，在**交換器埠口**上（**不是**在 bridge 介面上）加入 `bridge-allow-untagged no` 這個設定。設定後，這個橋接器埠口將**沒有 PVID** (Port VLAN ID)，並且會丟棄所有未帶標籤的封包。

1.  **核心功能 (丟棄 Untagged)**：
    * 指令是：`bridge-allow-untagged no`。
    * 效果是：這個 Port **拒收**任何「未帶標籤」的流量 (Native VLAN 流量)。

2.  **設定位置 (重要)**：
    * 這個指令必須設定在**實體介面**上 (例如 `swp1`、`eth1`)。
    * **不能**設定在 `bridge` (例如 `br_default`) 介面上。

3.  **運作結果 (無 PVID)**：
    * 設定此指令的 Port，等於移除了它的 PVID (Native VLAN) 設定。
    * 這是一個常見的 L2 安全最佳實踐 (Best Practice)。
    * **用途**：當你希望一個 Trunk Port **只**傳輸明確標記 (explicitly tagged) 的 VLAN 流量時使用。它可以防止任何來源不明、未經標記的流量進入你的 L2 網路，避免潛在的 VLAN 跳躍攻擊或設定錯誤。

### VLAN Layer 3 Addressing

如果你正在為 Native VLAN 設定 SVI (交換器虛擬介面)，你必須明確地宣告 (declare) 這個 Native VLAN，並為它指定 IP 位址。

如果將 IP 位址直接設定在 bridge 區塊 (stanza) 本身，將會導致錯誤。

**IP 位址（L3）必須設定在 SVI (vlan 介面) 上，絕對不能設定在 L2 Bridge 上。**

1.  **L2/L3 職責分離 (關鍵)**

      * `bridge` (e.g., `br_default`) 介面是 **L2** 專用的，它只負責處理 MAC 位址、VLAN 標籤等。
      * `vlan` (e.g., `vlan10`) 介面是 **L3** 專用的 SVI，它才負責處理 IP 位址和路由。

2.  **Native VLAN 也不例外**

      * 這條規則**對於 Native VLAN 同樣適用**。
      * 你不能因為 `VLAN 10` 是 Native VLAN，就貪圖方便把 IP `10.1.10.2/24` 直接設在 `br_default` 上。
      * **必須**乖乖地建立一個名為 `vlan10` 的 SVI 介面，然後把 IP 設定在這個 `vlan10` 介面上。


```bash
auto br_default
iface br_default
    # 將介面橋接再一起
    bridge-ports bond1 bond2 bond3 peerlink vxlan48
    hwaddress 44:38:39:22:01:b1
    bridge-vlan-aware yes
    # 告訴 bridge "VLAN 10 20 30" 是合法的
    bridge-vids 10 20 30
    bridge-pvid 1
auto bond1
iface bond1
    mtu 9000
    bond-slaves swp1
    bond-mode 802.3ad
    bond-lacp-bypass-allow yes
    clag-id 1
    # 它會自動將 PVID (Native VLAN) 設為 10
    # 並且只允許 VLAN 10 的流量通過
    bridge-access 10
auto vlan10
iface vlan10
    address 10.1.10.2/24 # IP Addr
    address-virtual 00:00:5E:00:01:01 10.1.10.1/24 # VRR
    hwaddress 44:38:39:22:01:b1
    vrf RED
    vlan-raw-device br_default
    vlan-id 10
```

```yaml
...
- set:
    interface:
    ...
      vlan10:
        ip:
          address:
            10.1.10.2/24: {}
...
```

### VLAN Bridge Binding Mode

Cumulus Linux 中 SVI (VLAN 介面) 狀態 (Up/Down) 如何判定的重要觀念 ?

Cumulus Linux 會將 VLAN 設備 (SVI) 的鏈路狀態 (link state) 從其底層設備（即 Bridge）繼承而來。

因此，**只要**橋接器 (bridge) 本身處於管理上的『Up』狀態，**並且**至少有*一個*橋接器埠口 (port) 是『Up』的，那麼這個 VLAN 設備（SVI）的鏈路狀態就會是『Up』——**無論那個 Up 的 Port 是不是這個 VLAN 的成員**。

如果需要 VLAN 設備（SVI）的鏈路狀態**只**追蹤 (track) 那些『同時也是該 VLAN 成員』的 Port 子集 (subset) 的狀態，而不是追蹤所有 Port，那麼你可以設定『VLAN 橋接器綁定模式 (VLAN bridge binding mode)』。

在 VLAN 橋接器綁定模式中，Cumulus Linux 不會自動從底層設備繼承鏈路狀態，而是會根據 **屬於該 VLAN 的橋接器埠口** 來決定（SVI 的）鏈路狀態。

這段在講 SVI (L3 介面 `vlan10`) 的 Up/Down 狀態是怎麼決定的，這會直接影響到依賴這個 SVI 的路由協定 (如 OSPF, BGP) 或 HSRP/VRR。

##### 1. 預設行為 (Default Mode)：傻瓜模式
* **規則**：`vlan10` (SVI) 的狀態 = `br_default` (Bridge) 的狀態。
* **`br_default` 如何決定狀態？**：只要 Bridge 底下**任何一個 Port** (`swp1`~`swp50`) 是 Up 的，`br_default` 就是 Up。
* **問題點 (The Problem)**：
    * 假設你的 `vlan10` 介面只在 `swp1` 和 `swp2` 上運行 (Access Port)。
    * 你的 `vlan20` 介面在 `swp3` 上運行。
    * 這時，如果 `swp1` 和 `swp2` 都斷線了 (`vlan10` 實際上已經孤立)，但只要 `swp3` 還是 Up 的，`br_default` 就會是 Up。
    * 結果：`vlan10` 這個 SVI 介面**仍然會顯示為『Up』**，路由協定繼續通告這條路徑，導致流量被送到一個「黑洞」。

### 2. 解決方案 (Binding Mode)：智慧模式
* **模式名稱**：`VLAN bridge binding mode`
* **規則**：`vlan10` (SVI) 的狀態是**只看**那些屬於 `vlan10` 的 Port (e.g., `swp1`, `swp2`) 的狀態。
* **運作方式**：
    * 承上個例子：`swp1` 和 `swp2` (vlan10) 斷線了。
    * 雖然 `swp3` (vlan20) 還是 Up 的。
    * 但系統在判斷 `vlan10` 的狀態時，只會去看 `swp1` 和 `swp2`。
    * **結果**：`vlan10` 這個 SVI 介面會正確地轉為**『Down』**，路由協定會撤銷 (withdraw) 相關路由，流量會改走備援路徑。


預設情況下，SVI (VLAN 介面) 只要有任何一個 Port 活著就會是 Up。如果你希望 SVI 只關心「自己 VLAN 內的 Port」是否活著，**你就必須手動啟用 VLAN bridge binding 模式**，這樣狀態連動才會準確。*預設的行為 `vlan-bridge-binding` 是關閉*。

### MAC Address for a Bridge

設定 MAC

