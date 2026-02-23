# VRR (Virtual Router Redundancy)

*VRR (虛擬路由器備援) 允許主機(host)與任何一台備援交換器通訊，而無需重新設定*。備援交換器會回應主機的 ARP 請求。所有交換器都以相同的方式回應，但如果一台故障，其他備援交換器會繼續回應。應該將 VRR 與 MLAG 一起使用。

*當多個設備透過單一邏輯連接（例如 MLAG Bond）進行連接時，使用 VRR*。連接到 MLAG bond 的設備（伺服器）認為 bond 的另一端只有一台設備，因此只會轉發一份傳輸中的訊框(Frame)。

有了 VRR，虛擬 MAC 在兩台 MLAG 設備上都是 Active (主動) 的，因此無論哪台 MLAG 設備收到訊框，它都會處理。

在此實驗網路包含三台伺服器與兩台 Cumulus Linux 交換器，交換器使用了 `MLAG`。

- 備援交換器中的 Bridge 會各自接收並回覆「虛擬路由器 IP」的 ARP 請求。
- 伺服器發出的每個 ARP 請求，都會收到來自每台交換器的回覆；這些回覆是完全相同的
- VRR 使用預設的全網織（Fabric-wide）MAC 地址 00:00:5E:00:01:01。如果需要，VRR 的 MAC 值可以變更。



##### 1. 為什麼 MLAG + VRRP (標準協定) 會出錯？
這是一個 L2 和 L3 角色衝突導致的「流量黑洞」問題。

- MLAG (L2)：是 Active-Active。伺服器的 LAG 會把 L2 流量「負載平衡」到 leaf01 和 leaf02。
- VRRP (L3)：是 Active-Standby。只有一台交換器 (Master) 會真正處理指向「虛擬 IP/MAC」的流量；另一台 (Backup) 則會丟棄這些流量。

##### 2. VRR 如何解決這個問題？ (Active-Active 閘道)
VRR (Virtual Router Redundancy) 是 Cumulus (NVIDIA) 專為 MLAG 開發的方案。

- VRR 讓兩台 MLAG 交換器在 L3 閘道層級也是 Active-Active。
- leaf01 和 leaf02 都會宣告自己是虛擬 MAC (00:00:5E:00:01:01) 的**擁有者 (Active)**。

[正常流程]

1. server01 的 MLAG Bond 把封包丟給 leaf02。
2. leaf02 收到封包，它的 L3 角色是 VRR Active。
3. leaf02 正常處理並路由 (Route) 這個封包。
4. 結果：無論 L2 MLAG 把流量分到哪台交換器，該交換器都能正常轉發 L3 流量。

### 總結

- VRRP (標準) 是 Active-Standby，不能與 Active-Active 的 MLAG 一起使用。
- VRR (Cumulus 方案) 是 Active-Active，專為 MLAG 設計。
- 必須在 VRR 和 VRRP 之間二選一，不能並存。
- 在 MLAG 架構下，你必須使用 VRR 來做 L3 閘道備援。

## Configure the Switches

1. 只能設定在 SVI 上
  - VRR 必須設定在 L3 SVI 介面 (例如 vlan10) 上。
  - 不能把 VRR 設定在實體 Port (e.g., swp1) 或子介面 (e.g., swp1.10) 上

2. 雙 IP 架構 (L3 SVI)

SVI 必須有 *unique IP 和 virtual IP*。這代表一台啟用 VRR 的 SVI (e.g., vlan10) 會有兩個 IP 位址：
  1. Unique IP (實體 IP)：
    - 這是 vlan10 介面自己的 IP 位址 (例如 10.1.10.2/24)。
    - 這個 IP 在 leaf01 和 leaf02 上必須不同 (e.g., 10.1.10.2 和 10.1.10.3)。
    - 用途：交換器本身要發起流量時 (如 PING、SSH、BGP)，會用這個 IP 當作來源。
  2. Virtual IP (虛擬 IP)：
    - 這就是伺服器要設定的 Gateway (閘道) 位址 (例如 10.1.10.1/24)
    - 這個 IP 在 leaf01 和 leaf02 上必須設定得一模一樣。因為是一對
    - 用途：專門用來回應伺服器的 ARP 請求和接收閘道流量


> Cumulus Linux only supports VRR on an SVI. You cannot configure VRR on a physical interface or virtual subinterface.
> 要讓 VRR 運作，你必須先像平常一樣為 SVI 設定一個實體 IP，然後再用 ip vrr address 指令「疊加」一個虛擬 IP 上去

以下是本實驗範例

- VLAN 10 配置
  - VLAN 10 已在橋接介面中定義。
  - VLAN 10 分配了一個 IP 地址。
  - 預設使用 VRR 的 MAC 地址 00:00:5e:00:01:01

Interface

```bash
...
auto vlan10
iface vlan10
    address 10.1.10.2/24
    address-virtual 00:00:5E:00:01:01 10.1.10.1/24 # VRR
    hwaddress 44:38:39:22:01:b1
    vrf RED
    vlan-raw-device br_default
    vlan-id 10
...
```

NVUE

```yaml
  interface:
  ...
      vlan10:
        ip:
          address:
            10.1.10.2/24: {}
          vrf: RED
          vrr: # this
            address:
              10.1.10.1/24: {}
            enable: on
            state:
              up: {}  
...
```


為 VRR 交換器設置了一個全網織（Fabric-wide）的 MAC 地址，以確保 VRR 交換器之間的一致性，這在 EVPN 多網織環境中特別實用。可以使用以下配置選項

- 全域修改 VRR MAC 地址
  - 使用 NVUE 命令更改所有 VRR 交換器上的全域 MAC 地址。這適用於需要在整個網絡中統一 MAC 地址的情況。
  - 將 VRR MAC 地址設置為保留範圍內的值，範圍為 00:00:5E:00:01:00 和 00:00:5E:00:01:FF 之間。
  - 設定 Fabric ID 來自動生成 VRR MAC 地址
    - 指定一個 Fabric ID，該值可以是 1 到 255 之間的數字。

NVUE

```yaml
...
    system:
      timezone: Europe/Paris
      global:
        anycast-mac: 44:38:39:FF:00:AA
        fabric-mac: 00:00:5E:00:01:01 # This
        system-mac: 44:38:39:22:01:7a
```

Interface

```bash
...
auto vlan10
iface vlan10
    address 10.1.10.2/24
    address-virtual 00:00:5E:00:01:01 10.1.10.1/24 # VRR # this
    hwaddress 44:38:39:22:01:b1
    vrf RED
    vlan-raw-device br_default
    vlan-id 10
...
```

- 針對特定 VLAN 覆蓋全域設定
  - 如果特定 VLAN 需要特別的路由行為，可以修改該 VLAN 的 VRR MAC 地址，而不影響全域設定。

## EVPN Routing with VRR

在 **EVPN 路由環境**中，如果希望在同一個 VLAN 上將多個子網配置為 VRR 地址，則必須為這些子網配置**相同的 VRR MAC 位址**。

1. **統一的 VRR MAC 位址**  
   - 確保所有配置在同一個 VLAN 上的 VRR 地址子網使用**相同的 VRR MAC 位址**，以確保網路中不會因 MAC 地址不一致而出現通信問題。

2. **EVPN 環境中的一致性要求**  
    - 在 EVPN 路由環境中，使用相同的 VRR MAC 位址對於保證多交換器之間路由的正確性和一致性至關重要，特別是在涉及多個子網時。  
    - why ?
      - 在 EVPN (VXLAN) 中，閘道的 MAC 和 IP 是透過 BGP (控制平面) 來通告的。
      - 如果你所有的閘道 (vlan10, vlan20...) 都使用同一個 MAC，BGP 只需要通告「MAC ...01:01 對應到 虛擬 VTEP IP」這樣一筆資訊 (Type-2 route)。
      - 如果每個 SVI 都用不同的 MAC，BGP 就必須為每個 SVI 單獨通告 MAC 路由，這會增加 BGP 的負擔，並在網路變動 (convergence) 時拖慢收斂速度。 

## 驗證

1. 證交換器上的配置

```bash
root@leaf01:/# nv show interface
Interface         MTU    Speed  State  Remote Host  Remote Port  Type      Summary
----------------  -----  -----  -----  -----------  -----------  --------  --------------------------------
+ bond1           9000   10G    up                               bond
+ bond2           9000   10G    up                               bond
+ bond3           9000   10G    up                               bond
+ eth0            1500   10G    up     border-1     eth0         eth       IP Address:      172.20.20.11/24
  eth0                                 border-2     eth0                   IP Address: 3fff:172:20:20::b/64
  eth0                                 leaf-2       eth0
  eth0                                 leaf03       eth0
  eth0                                 leaf04       eth0
  eth0                                 spine-2      eth0
  eth0                                 spine02      eth0
+ lo              65536         up                               loopback  IP Address:         10.0.1.12/32
  lo                                                                       IP Address:        10.10.10.1/32
  lo                                                                       IP Address:          127.0.0.1/8
  lo                                                                       IP Address:              ::1/128
+ peerlink        9216   20G    up                               bond
+ peerlink.4094   9216          up                               sub
+ swp1            9000   10G    up                               swp
+ swp2            9000   10G    up                               swp
+ swp3            9000   10G    up                               swp
+ swp49           9216   10G    up     leaf-2       swp49        swp
+ swp50           9216   10G    up     leaf-2       swp50        swp
+ swp51           9216   10G    up     spine-2      swp1         swp
+ swp52           9216   10G    up     spine02      swp1         swp
+ vlan10          9216          up                               svi       IP Address:         10.1.10.2/24
+ vlan10-v0       9216          up                               svi       IP Address:         10.1.10.1/24
+ vlan20          9216          up                               svi       IP Address:         10.1.20.2/24
+ vlan20-v0       9216          up                               svi       IP Address:         10.1.20.1/24
+ vlan30          9216          up                               svi       IP Address:         10.1.30.2/24
+ vlan30-v0       9216          up                               svi       IP Address:         10.1.30.1/24
+ vlan4024_l3     9216          up                               svi
+ vlan4024_l3-v0  9216          up                               svi
+ vlan4036_l3     9216          up                               svi
+ vlan4036_l3-v0  9216          up                               svi
```


設定檔案中，VRR (Virtual Router Redundancy) 被應用於 MLAG (Multi-Chassis Link Aggregation) 叢集中的交換器（Leaf 和 Border 交換器），為連接的伺服器(server)或其他設備提供一個高可用性 (Highly Available) 的預設閘道 (Default Gateway)。

這在 Cumulus Linux 中通常指的是一種 active-active 的閘道機制（有時也稱為 "VRR-lite" 或與 EVPN 結合實現為 "Anycast Gateway"），而非傳統的 active-standby VRRP。

### 運作方式解釋

1.  **MLAG 叢集**：
    * `leaf-1` 和 `leaf-2` 組成一個 MLAG 叢集。
    * `leaf-3` 和 `leaf-4` 組成另一個 MLAG 叢集。
    * `border-1` 和 `border-2` 也組成一個 MLAG 叢集。

2.  **虛擬 IP (VIP) 和 虛擬 MAC**：
    * 在一個 MLAG 叢集中的兩台交換器上，會針對同一個 VLAN (SVI - Switched Virtual Interface) 設定一個**共用**的虛擬 IP 位址。
    * 這個虛擬 IP 位址就是該 VLAN 中所有伺服器的預設閘道。
    * 在 `nvue.yml` 檔案中，可以看到 VRR 被全域啟用 (`router.vrr.enable: on`)，並且在 SVI 介面下設定了 `vrr` 位址。
    * 在傳統的 `interfaces` 檔案中，這顯示為 `address-virtual`。

3.  **Active-Active 閘道**：
    * 由於兩台 MLAG 交換器都擁用這個虛擬 IP，並且伺服器（例如 `server01`）透過 LACP bond 同時連接到這兩台交換器，因此兩台交換器**同時**（Active-Active）充當伺服器的閘道。
    * 流量可以透過任一台交換器進行路由，提供了負載平衡和無縫的容錯轉移。如果一台交換器故障，另一台會繼續使用同一個虛擬 IP 處理流量，伺服器端不會察覺到任何中斷。

## 舉例說明 VRR

根據提供的設定檔案，這裡有兩個具體的例子：

### 範例 1：Leaf 交換器 (leaf-1 & leaf-2) 上的 VLAN 10

* **leaf-1 設定** (`v2/leaf-1/nvue.yml`)：
    * `vlan10` (屬於 VRF RED)
    * 實體 IP：`10.1.10.2/24`
    * **VRR 虛擬 IP**：`10.1.10.1/24`

* **leaf-2 設定** (`v2/leaf-2/nvue.yml`)：
    * `vlan10` (屬於 VRF RED)
    * 實體 IP：`10.1.10.3/24`
    * **VRR 虛擬 IP**：`10.1.10.1/24` （與 leaf-1 完全相同）

* **server01 設定** (`v2/server01/etc/network/interfaces`)：
    * 伺服器 IP：`10.1.10.101`
    * **預設閘道**：`post-up ip route add 10.0.0.0/8 via 10.1.10.1`

* **應用**：
    `server01` 將所有離開本地子網的流量都傳送到 `10.1.10.1`。由於 `leaf-1` 和 `leaf-2` 都是 `10.1.10.1` 的擁有者，它們可以同時（active-active）接收並路由 `server01` 的流量。

### 範例 2：Border 交換器 (border-1 & border-2) 上的 VLAN 102

* **border-1 設定** (`v2/border-1/nvue.yml`)：
    * `vlan102` (屬於 VRF BLUE)
    * 實體 IP：`10.1.102.64/24`
    * **VRR 虛擬 IP**：`10.1.102.1/24`
    * **VRR 虛擬 MAC**：`00:00:00:00:00:02`

* **border-2 設定** (`v2/border-2/nvue.yml`)：
    * `vlan102` (屬於 VRF BLUE)
    * 實體 IP：`10.1.102.65/24`
    * **VRR 虛擬 IP**：`10.1.102.1/24` （相同）
    * **VRR 虛擬 MAC**：`00:00:00:00:00:02` （相同）

* **應用**：
    * 連接到 VLAN 102 的任何設備（例如防火牆或外部路由器）會使用 `10.1.102.1` 作為其閘道。`border-1` 和 `border-2` 作為 MLAG 夥伴，共同為這個虛擬 IP 提供 active-active 的路由服務。
    * 在的設定中，VRR 和 EVPN 的整合創造了一個稱為**分散式任意點傳播閘道 (Distributed Anycast Gateway, DAG)** 的架構。

簡單來說：
* **VRR**：在 MLAG 叢集（如 `leaf-1` 和 `leaf-2`）中建立一個**共享的、高可用的虛擬閘道 IP**。
* **EVPN**：作為 BGP 的控制平面，將這個閘道（及其背後的子網）的資訊**通告 (advertise)** 給整個 VXLAN 網路中的所有其他交換器。

## 整合的目標與效果 (VRR and EVPN)


這個整合的主要目標是同時實現**高可用性 (High Availability)** 和**最佳化的 L3 路由 (Optimal L3 Routing)**。

1.  **高可用性 (Active-Active Gateway)**：
    * **目標**：消除單點故障。伺服器（如 `server01`）只需要設定一個預設閘道 (`10.1.10.1`)。
    * **效果**：這個閘道 `10.1.10.1` 同時存在於 `leaf-1` 和 `leaf-2` 上。由於 `server01` 透過 LACP bond 連接到這兩台交換器，因此兩條路徑都是 active。如果 `leaf-1` 故障，`leaf-2` 會繼續使用完全相同的 IP 和 MAC 位址來處理流量，伺服器不會有任何中斷。

2.  **分散式 L3 路由 (Symmetric IRB)**：
    * **目標**：讓路由決策盡可能*靠近*來源。這避免了傳統網路中需要將所有跨子網流量都傳送到一對核心或邊界路由器（稱為 "hairpinning"）的低效率做法。
    * **效果**：EVPN 會將每個 Leaf 交換器上的 VRR 子網（L3 資訊）通告給所有其他 Leaf 交換器。
        * 當一台交換器（例如 `leaf-1`）收到一個需要路由到另一個子網的封包時，它**不需要**將封包傳送到 Spines 或 Borders 進行路由。
        * `leaf-1` 在本地的 VRF 中查詢路由表。它會從 EVPN 學習到目標子網（例如 `leaf-3` 上的 VLAN 20）是可達的，並且知道 next-hop 是 `leaf-3` 的 VTEP IP。
        * `leaf-1` 立即將封包路由、封裝到 VXLAN 中，並直接傳送給 `leaf-3`。這稱為**對稱式整合路由和橋接 (Symmetric IRB)**。

### 舉例說明 (VRR and EVPN)

根據提供的設定檔，重新梳理並舉例說明 VRR 與 EVPN 如何整合，以及它們如何實現**分散式任意點傳播閘道 (Distributed Anycast Gateway, DAG)**。

這個架構的**核心目標**是：
1.  **高可用性 (VRR)**：在 MLAG 叢集中提供一個共享的、永不中斷的 L3 閘道。
2.  **最佳化路由 (EVPN)**：在整個 VXLAN Fabric 中實現分散式 L3 路由，讓流量直接在來源和目的地的 Leaf 交換器之間傳送，無需繞道 (hairpinning)。

##### 1. Anycast Gateway (VRR) - 對伺服器任播

這是 Anycast 的第一層，發生在 MLAG 叢集內部，為本地伺服器提供服務。

- 目標：為同一個 VLAN/子網中的所有伺服器提供一個共享的、高可用的 L3 預設閘道。
- 機制：leaf-3 和 leaf-4 組成一個 MLAG 叢集。它們在 vlan20 介面上都設定了完全相同的 VRR 虛擬 IP 10.1.20.1。
- 效果：server05 (IP 10.1.20.105) 只需要設定一個預設閘道 10.1.20.1。無論它的 LACP 流量被雜湊到 leaf-3 還是 leaf-4，兩台交換器都能以 10.1.20.1 的身份回應並路由其流量。

##### 2. Anycast VTEP (EVPN) - 對全網路任播

這是 Anycast 的第二層，由 EVPN 實現，為整個 VXLAN Fabric 網路提供服務。

- 目標：讓網路上所有其他交換器（如 leaf-1）知道「10.1.20.0/24 這個子網可以從 leaf-3 和 leaf-4 這組 MLAG 叢集存取」。
- 機制：這個「任播 VTEP」在設定中，根據流量類型（L2 vs L3）有兩種實現方式：
  - L2 橋接 (EVPN Type 2 路由)： 系統會使用一個共享的 Anycast VTEP IP。
    - 範例：leaf-3 和 leaf-4 共享一個 `mlag: shared-address`（或 `clagd-vxlan-anycast-ip`）10.0.1.34。
    - 當 leaf-1 需要轉發 L2 流量（例如廣播或同子網內的單播）到 leaf-3/leaf-4 叢集時，BGP EVPN (Type 2 路由) 會告訴 leaf-1：「Next-hop 是 10.0.1.34」。
    - leaf-1 會將 L2 封包封裝到 10.0.1.34。Spine 交換器會透過 ECMP 將這個封包路由到 leaf-3 或 leaf-4。
  - L3 路由 (EVPN Type 5 路由)： 系統會使用 ECMP (等價多路徑) 來實現「功能上」的任播。
    - 範例：在我們接下來的 L3 路由範例中，leaf-3 和 leaf-4 會各自通告「我能到達 10.1.20.0/24」。
    - leaf-3 的通告：Next-hop 是 10.10.10.3 (它的唯一 VTEP IP)。
    - leaf-4 的通告：Next-hop 是 10.10.10.4 (它的唯一 VTEP IP)。
    - leaf-1 收到這兩條通告，因此在 VRF RED 路由表中安裝了兩條到達 10.1.20.0/24 的 ECMP 路由。

### L3 路由 (Symmetric IRB) 流程

##### 1. 控制平面 (Control Plane - 建立 L3 任播路由)：
1. 通告 (Advertise)：
- leaf-3 檢查其 VRF RED，發現有本地連接的 vlan20 (子網 10.1.20.0/24)。
- leaf-3 透過 BGP EVPN (Type 5 路由) 通告：「我 (Next-hop 10.10.10.3) 能到達 10.1.20.0/24 (L3 VNI 4001)」。
- leaf-4 同樣通告：「我 (Next-hop 10.10.10.4) 也能到達 10.1.20.0/24 (L3 VNI 4001)」。

2. 學習 (Learn)：

- leaf-1 收到這兩條 BGP 通告。
- leaf-1 在 VRF RED 的路由表中，為 10.1.20.0/24 建立了兩條 ECMP 路徑：一條指向 10.10.10.3 (leaf-3)，另一條指向 10.10.10.4 (leaf-4)。
- 對 leaf-1 而言，leaf-3 和 leaf-4 這個「VTEP 叢集」在功能上就是一個「任播」目的地。

##### 2. 資料平面 (Data Plane - 封包轉發)：

1. 本地閘道 (VRR)：server01 (10.1.10.101) 將封包傳送到其預設閘道 10.1.10.1 (VRR IP)。LACP 雜湊將封包送達 leaf-1。
2. 本地路由 (ECMP)：leaf-1 收到封包，在 VRF RED 中執行 L3 路由查詢。
  - 查詢目的：10.1.20.105。
  - 查詢結果：命中 10.1.20.0/24 的 ECMP 路由。轉發晶片根據封包雜湊，從兩條路徑中選擇一條。例如，選擇了 10.10.10.4 (leaf-4)。

3. VXLAN 封裝 (Symmetric IRB)：leaf-1 立即在本地執行路由（TTL-1）並封裝封包：
  - VXLAN VNI：使用 L3 VNI 4001 (代表 VRF RED)。
  - Outer IP Header：
    - Outer Source: 10.10.10.1 (leaf-1 的唯一 VTEP IP)
    - Outer Destination: 10.10.10.4 (leaf-4 的唯一 VTEP IP)
4. 解封裝與交付：
  - Spine 交換器將這個 VXLAN 封包路由到 leaf-4。
  - leaf-4 收到封包，看到 L3 VNI 4001，解開封裝。
  - leaf-4 在 VRF RED 中查詢內部封包，發現 10.1.20.105 位於其本地連接的 vlan20，並將封包交付給 server05。
