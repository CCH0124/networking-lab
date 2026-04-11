# EVPN Multihoming (EVPN-MH)

EVPN Multihoming (EVPN-MH) 是現代資料中心 Clos 拓撲架構中，用來取代傳統專有 MLAG (Multi-Chassis Link Aggregation) 協定的新一代標準化技術。它為終端設備（如伺服器）提供了全主動 (all-active) 的連線備援機制。

在 EVPN-MH 的架構中，我們不再使用 MLAG 的 LAG ID，而是引入了「乙太網路網段 (Ethernet Segment, ES)」的概念。ES 是指連接到同一台伺服器的一組交換器鏈路，每個 ES 在整個 PoD 中都會被分配一個唯一且動態生成的乙太網路網段識別碼 (ESI)。系統會透過 BGP-EVPN 的 Type-1、Type-2 與 Type-4 路由來自動探索這些網段並轉發流量，同時在各個 ES 對等節點間同步 MAC 與鄰居資料庫。

在評估資料中心底層與覆疊網路 (Overlay) 的設計時，強烈建議優先選擇 EVPN-MH 來取代 MLAG。以下為 EVPN-MH 的核心好處以及它與傳統 MLAG 的關鍵差異：

## EVPN Multihoming 的主要好處

1. **消除實體跨交換器鏈路 (ISL / Peerlink) 的需求：**
    傳統的 ToR (Top of Rack) 交換器若要提供備援，必須在兩台設備間拉設實體的 peerlink 纜線。EVPN-MH 徹底消除了對這些互連鏈路的需求。
2. **突破節點數量的擴展限制：**
    在實際部署中，傳統 MLAG 系統極難在亞微秒級的更新時間內維持超過兩台設備的狀態一致性，因此其雙重連接 (dual homing) 的能力始終被死鎖在兩台交換器以內。相對，EVPN-MH 具備優異的擴展性。在 NVIDIA Spectrum-2 及更新的 ASIC 架構上，一個 Ethernet Segment (冗餘群組) 可以跨越兩台以上的交換器，提供伺服器更強大的主動-主動 (active-active) 負載平衡與多節點彈性。
3. **實現多廠商設備互通 (Multi-vendor Interoperability)：**
    這是在企業級架構中最具價值的優勢之一。EVPN-MH 採用單一的 BGP-EVPN 控制平面，這是一項開放的標準協定。只要各廠商的設備遵循 RFC 規範實作 EVPN-MH，就能夠加入同一個乙太網路網段中，幫助企業擺脫過去被單一網路設備供應商綁定的困境。
4. **簡化網路與動態建立 L2 鄰接關係：**
    EVPN-MH 允許我們在整個網路架構中全面使用 BGP，免去理解與維護各種專有協定的負擔。它利用 EVPN 訊息來傳遞主機的連線狀態，並能動態地建立至伺服器的 Layer 2 鄰接關係。

## EVPN-MH 與 MLAG 的核心差異總結

透過對比，我們可以看出為何現代架構正在淘汰 MLAG 並轉向 EVPN-MH：

* **架構與配置複雜度：** MLAG 牽涉較多活動元件 (moving parts)，設定繁瑣且架構較為複雜。EVPN-MH 則透過統一的 BGP 協定收斂，大幅降低了維護多重協定的維運成本。
* **設備互通性：** MLAG 是各家廠商的專有技術，完全無法在不同廠牌的設備間互通。EVPN-MH 則是標準化的實作，支援多廠商混合部署。
* **實體佈線限制：** MLAG 強制要求必須部署 ISL (inter-switch link / peerlink) 來同步狀態。EVPN-MH 不需要這些額外的互連鏈路，節省了連接埠資源。
* **冗餘節點上限：** MLAG 最多僅能由 2 台葉節點 (Leaf switches) 組成。EVPN-MH 則超越了這個限制，能支援超過 2 台葉節點共同服務同一個終端設備。

## Lab

![EVPN Multihoming (EVPN-MH)](EVPN%20Multihoming.png)

### Spine

Spine 在 EVPN 實驗架構中扮演負責讓所有 Leaf 之間能夠交換路由資訊。核心配置

* ASN：設定為 65199。在 eBGP 架構中，Spine 擁有獨立的 ASN，與 Leaf 區隔。
* BGP Unnumbered
  * 透過 Bonding 介面與下面配置實現。這不需要手動為交換器之間的鏈路配置 IP，系統會自動使用 IPv6 Link-local 地址建立鄰居。

  ```yaml
  ...
    vrf:
      default:
        router:
          bgp:
            peer-group:
              underlay:
                remote-as: external # 代表使用 eBGP
  ```

* EVPN 啟用：除了交換普通路由，還要幫忙傳遞 EVPN 的二層訊息

  ```yaml
  ...
    vrf:
      default:
        ...
            address-family:
              ...
              l2vpn-evpn:
                state: enabled
  ```

  開啟與鄰居的 EVPN 對話。針對加入 `underlay` 這個群組的所有鄰居（即 swp1 到 swp4 這些 Leaf），跟他們討論 EVPN 的內容

  ```yaml
    vrf:
      default:
        router:
          bgp:
            peer-group:
              underlay:
              ...
                address-family:
                  l2vpn-evpn:
                    state: enabled
  ```

  在 NVIDIA Cumulus Linux 的 NVUE 配置中，需要兩步驟來完成 EVPN 的部署。首先，我們在全域 BGP 下開啟 `l2vpn-evpn`，這相當於為交換器載入了 EVPN 的大腦；接著，我們在負責底層連線的 `peer-group` 中再次啟用它。這是一個關鍵動作，因為它正式授權交換器將複雜的 Type-1 到 Type-5 EVPN 路由，透過實體介面（swp1-swp4）傳遞給下游的 Leaf 交換器。

#### spine01

```yaml
- set:
    system:
      hostname: spine01
    interface:
      lo:
        ipv4:
          address:
            10.10.10.101/32: {}
      swp1:
        type: swp
      swp2:
        type: swp
      swp3:
        type: swp
      swp4:
        type: swp
    router:
      bgp:
        autonomous-system: 65199
        router-id: 10.10.10.101
    vrf:
      default:
        router:
          bgp:
            peer-group:
              underlay:
                remote-as: external
                address-family:
                  l2vpn-evpn:
                    state: enabled
            neighbor:
              swp1:
                peer-group: underlay
              swp2:
                peer-group: underlay
              swp3:
                peer-group: underlay
              swp4:
                peer-group: underlay
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
              l2vpn-evpn:
                state: enabled
```

#### spine02

```yaml
- set:
    system:
      hostname: spine02
    interface:
      lo:
        ipv4:
          address:
            10.10.10.102/32: {}
      swp1:
        type: swp
      swp2:
        type: swp
      swp3:
        type: swp
      swp4:
        type: swp
    router:
      bgp:
        autonomous-system: 65199
        router-id: 10.10.10.102
    vrf:
      default:
        router:
          bgp:
            peer-group:
              underlay:
                remote-as: external
                address-family:
                  l2vpn-evpn:
                    state: enabled
            neighbor:
              swp1:
                peer-group: underlay
              swp2:
                peer-group: underlay
              swp3:
                peer-group: underlay
              swp4:
                peer-group: underlay
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
              l2vpn-evpn:
                state: enabled
```

### Leaf

Leaf 是業務接入點，負責將物理 VLAN 映射到虛擬隧道 (VXLAN)，並處理伺服器的雙掛備援 (Multihoming)。

1. 基礎建設層 (Underlay & BGP)

    * AS 編號 (ASN): 65101。
      * 每個機架 (Rack) 通常給予獨立的 ASN。這讓 Spine 可以輕易判斷路由的來源。
    * Loopback IP: 10.10.10.1/32。
      * 這是交換器的身份證地址，也是 VXLAN 隧道的起點與終點 (VTEP IP)。所有的數據包都會封裝成發往此地址的格式。
    * BGP Unnumbered: 應用於 swp13, swp14。
      * 不手動配置中間網段 IP。交換器透過 IPv6 Link-local 自動發現 Spine。
2. 虛擬隧道層 (VXLAN & VNI)
    * L2 VNI (Layer 2): 10, 20, 30。
      * 配置中是一對一映射，如 VLAN 10 對應 VNI 10。
      * 將本地 VLAN 標籤轉換為全網唯一的虛擬網路 ID (VNI)，讓二層封包能像在同一個交換器下一樣跨區傳輸。

    * L3 VNI (Layer 3): 4001。
      * 如 VRF RED 對應 VNI 4001。
      * 這是對稱式 IRB的核心。當流量需要從 VLAN 10 跳到 VLAN 20 時，會進入這個三層隧道進行路由轉發。

      ```yaml
      BLUE:
        evpn:
          vni:
            '4002': {}
      ```

3. EVPN Multihoming
    負責伺服器的雙掛備援與負載平衡。
    * ESI (Ethernet Segment Identifier): 03:44:38:39:ff:00:aa:00:00:01。
      * 實驗範例套用於 bonding 介面
      * 這是一組暗號。當 leaf01 與 leaf02 都在各自的接口配置相同的 ESI 時，它們就會知道彼此正連接到同一個伺服器，自動形成一個冗餘小組。

      ```yaml
      bond1:
        bond:
          member:
            swp1: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 1
              mac-address: 44:38:39:FF:00:AA
              df-preference: 50000
      ```

    * Redundancy Mode: all-active
      * 告訴系統兩條路都能走。這不是一主一備，而是兩台 Leaf 同時轉發流量，實現吞吐量翻倍。
4. 服務與控制層 (BGP EVPN Address-Family)

    * 路由重分佈 (Redistribute Connected)
      * 將交換器上直接連接的網段資訊抓取出來。 leaf01 下面接了 Server1，透過這個指令，BGP 程式會自動把 Server1 在我這裡這個訊息記錄到 VRF RED 的路由表中。

      ```yaml
      ...
              address-family:
                ipv4-unicast:
                  redistribute:
                    connected:
                      state: enabled
      ```

    * 路由導出至 EVPN
        * 它將上述學到的 IPv4 路由轉化為 EVPN Type-5 (IP Prefix Route)。如果沒有這行，leaf01 雖然知道 Server1 在它下面，但它不會告訴別人。開啟這個功能後，leaf01 會向 Spine 發送 Type-5 路由封包，讓全網如遠端的 leaf03  都知道如何透過 L3 VNI 4001 找到這個網段。
        * 可以補充說明這就是 Type-5 路由。Type-2 宣告的是*特定主機（/32 或 MAC）*，而 Type-5 宣告的是*整個子網*。

        ```yaml
        BLUE:
          ...
          router:
            bgp:
              ...
                  route-export:
                    to-evpn: {}
        ```

#### leaf01

```yaml
- set:
    system:
      hostname: leaf01
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
    interface:
      lo:
        ipv4:
          address:
            10.10.10.1/32: {}
      swp1:
        type: swp
      swp2:
        type: swp
      swp3:
        type: swp
      swp13:
        type: swp
        evpn:
          multihoming:
            uplink: enabled
      swp14:
        type: swp
        evpn:
          multihoming:
            uplink: enabled
      bond1:
        bond:
          member:
            swp1: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 1
              mac-address: 44:38:39:FF:00:AA
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 10
      bond2:
        bond:
          member:
            swp2: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 2
              mac-address: 44:38:39:FF:00:AA
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 20
      bond3:
        bond:
          member:
            swp3: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 3
              mac-address: 44:38:39:FF:00:AA
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 30
      vlan10:
        type: svi
        vlan: 10
        vrf: RED
        ipv4:
          address:
            10.1.10.2/24: {}
          vrr:
            state: enabled
            address:
              10.1.10.1/24: {}
      vlan20:
        type: svi
        vlan: 20
        vrf: RED
        ipv4:
          address:
            10.1.20.2/24: {}
          vrr:
            state: enabled
            address:
              10.1.20.1/24: {}
      vlan30:
        type: svi
        vlan: 30
        vrf: BLUE
        ipv4:
          address:
            10.1.30.2/24: {}
          vrr:
            state: enabled
            address:
              10.1.30.1/24: {}
    nve:
      vxlan:
        state: enabled
        source:
          address: 10.10.10.1
        arp-nd-suppress: enabled
    evpn:
      state: enabled
      multihoming:
        state: enabled
    router:
      bgp:
        autonomous-system: 65101
        router-id: 10.10.10.1
    vrf:
      default:
        router:
          bgp:
            peer-group:
              underlay:
                remote-as: external
                address-family:
                  l2vpn-evpn:
                    state: enabled
            neighbor:
              swp13:
                peer-group: underlay
              swp14:
                peer-group: underlay
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
      RED:
        evpn:
          vni:
            '4001': {}
        router:
          bgp:
            autonomous-system: 65101
            router-id: 10.10.10.1
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
                route-export:
                  to-evpn: {}
      BLUE:
        evpn:
          vni:
            '4002': {}
        router:
          bgp:
            autonomous-system: 65101
            router-id: 10.10.10.1
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
                route-export:
                  to-evpn: {}
```

#### leaf02

```yaml
- set:
    system:
      hostname: leaf02
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
    interface:
      lo:
        ipv4:
          address:
            10.10.10.2/32: {}
      swp1:
        type: swp
      swp2:
        type: swp
      swp3:
        type: swp
      swp13:
        type: swp
        evpn:
          multihoming:
            uplink: enabled
      swp14:
        type: swp
        evpn:
          multihoming:
            uplink: enabled
      bond1:
        bond:
          member:
            swp1: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 1
              mac-address: 44:38:39:FF:00:AA
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 10
      bond2:
        bond:
          member:
            swp2: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 2
              mac-address: 44:38:39:FF:00:AA
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 20
      bond3:
        bond:
          member:
            swp3: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 3
              mac-address: 44:38:39:FF:00:AA
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 30
      vlan10:
        type: svi
        vlan: 10
        vrf: RED
        ipv4:
          address:
            10.1.10.3/24: {}
          vrr:
            state: enabled
            address:
              10.1.10.1/24: {}
      vlan20:
        type: svi
        vlan: 20
        vrf: RED
        ipv4:
          address:
            10.1.20.3/24: {}
          vrr:
            state: enabled
            address:
              10.1.20.1/24: {}
      vlan30:
        type: svi
        vlan: 30
        vrf: BLUE
        ipv4:
          address:
            10.1.30.3/24: {}
          vrr:
            state: enabled
            address:
              10.1.30.1/24: {}
    nve:
      vxlan:
        state: enabled
        source:
          address: 10.10.10.2
        arp-nd-suppress: enabled
    evpn:
      state: enabled
      multihoming:
        state: enabled
    router:
      bgp:
        autonomous-system: 65102
        router-id: 10.10.10.2
    vrf:
      default:
        router:
          bgp:
            peer-group:
              underlay:
                remote-as: external
                address-family:
                  l2vpn-evpn:
                    state: enabled
            neighbor:
              swp13:
                peer-group: underlay
              swp14:
                peer-group: underlay
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
      RED:
        evpn:
          vni:
            '4001': {}
        router:
          bgp:
            autonomous-system: 65102
            router-id: 10.10.10.2
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
                route-export:
                  to-evpn: {}
      BLUE:
        evpn:
          vni:
            '4002': {}
        router:
          bgp:
            autonomous-system: 65102
            router-id: 10.10.10.2
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
                route-export:
                  to-evpn: {}
```

#### leaf03

```yaml
- set:
    system:
      hostname: leaf03
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
    interface:
      lo:
        ipv4:
          address:
            10.10.10.3/32: {}
      swp1:
        type: swp
      swp2:
        type: swp
      swp3:
        type: swp
      swp13:
        type: swp
        evpn:
          multihoming:
            uplink: enabled
      swp14:
        type: swp
        evpn:
          multihoming:
            uplink: enabled
      bond1:
        bond:
          member:
            swp1: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 1
              mac-address: 44:38:39:FF:00:BB
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 10
      bond2:
        bond:
          member:
            swp2: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 2
              mac-address: 44:38:39:FF:00:BB
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 20
      bond3:
        bond:
          member:
            swp3: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 3
              mac-address: 44:38:39:FF:00:BB
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 30
      vlan10:
        type: svi
        vlan: 10
        vrf: RED
        ipv4:
          address:
            10.1.10.4/24: {}
          vrr:
            state: enabled
            address:
              10.1.10.1/24: {}
      vlan20:
        type: svi
        vlan: 20
        vrf: RED
        ipv4:
          address:
            10.1.20.4/24: {}
          vrr:
            state: enabled
            address:
              10.1.20.1/24: {}
      vlan30:
        type: svi
        vlan: 30
        vrf: BLUE
        ipv4:
          address:
            10.1.30.4/24: {}
          vrr:
            state: enabled
            address:
              10.1.30.1/24: {}
    nve:
      vxlan:
        state: enabled
        source:
          address: 10.10.10.3
        arp-nd-suppress: enabled
    evpn:
      state: enabled
      multihoming:
        state: enabled
    router:
      bgp:
        autonomous-system: 65103
        router-id: 10.10.10.3
    vrf:
      default:
        router:
          bgp:
            peer-group:
              underlay:
                remote-as: external
                address-family:
                  l2vpn-evpn:
                    state: enabled
            neighbor:
              swp13:
                peer-group: underlay
              swp14:
                peer-group: underlay
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
      RED:
        evpn:
          vni:
            '4001': {}
        router:
          bgp:
            autonomous-system: 65103
            router-id: 10.10.10.3
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
                route-export:
                  to-evpn: {}
      BLUE:
        evpn:
          vni:
            '4002': {}
        router:
          bgp:
            autonomous-system: 65103
            router-id: 10.10.10.3
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
                route-export:
                  to-evpn: {}
```

#### leaf04

```yaml
- set:
    system:
      hostname: leaf04
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
    interface:
      lo:
        ipv4:
          address:
            10.10.10.4/32: {}
      swp1:
        type: swp
      swp2:
        type: swp
      swp3:
        type: swp
      swp13:
        type: swp
        evpn:
          multihoming:
            uplink: enabled
      swp14:
        type: swp
        evpn:
          multihoming:
            uplink: enabled
      bond1:
        bond:
          member:
            swp1: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 1
              mac-address: 44:38:39:FF:00:BB
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 10
      bond2:
        bond:
          member:
            swp2: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 2
              mac-address: 44:38:39:FF:00:BB
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 20
      bond3:
        bond:
          member:
            swp3: {}
          lacp-bypass: enabled
        evpn:
          multihoming:
            segment:
              local-id: 3
              mac-address: 44:38:39:FF:00:BB
              df-preference: 50000
        link:
          mtu: 9000
        bridge:
          domain:
            br_default:
              access: 30
      vlan10:
        type: svi
        vlan: 10
        vrf: RED
        ipv4:
          address:
            10.1.10.5/24: {}
          vrr:
            state: enabled
            address:
              10.1.10.1/24: {}
      vlan20:
        type: svi
        vlan: 20
        vrf: RED
        ipv4:
          address:
            10.1.20.5/24: {}
          vrr:
            state: enabled
            address:
              10.1.20.1/24: {}
      vlan30:
        type: svi
        vlan: 30
        vrf: BLUE
        ipv4:
          address:
            10.1.30.5/24: {}
          vrr:
            state: enabled
            address:
              10.1.30.1/24: {}
    nve:
      vxlan:
        state: enabled
        source:
          address: 10.10.10.4
        arp-nd-suppress: enabled
    evpn:
      state: enabled
      multihoming:
        state: enabled
    router:
      bgp:
        autonomous-system: 65104
        router-id: 10.10.10.4
    vrf:
      default:
        router:
          bgp:
            peer-group:
              underlay:
                remote-as: external
                address-family:
                  l2vpn-evpn:
                    state: enabled
            neighbor:
              swp13:
                peer-group: underlay
              swp14:
                peer-group: underlay
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
      RED:
        evpn:
          vni:
            '4001': {}
        router:
          bgp:
            autonomous-system: 65104
            router-id: 10.10.10.4
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
                route-export:
                  to-evpn: {}
      BLUE:
        evpn:
          vni:
            '4002': {}
        router:
          bgp:
            autonomous-system: 65104
            router-id: 10.10.10.4
            address-family:
              ipv4-unicast:
                redistribute:
                  connected:
                    state: enabled
                route-export:
                  to-evpn: {}
```

### Server

#### server1

```yaml
network:
  version: 2
  ethernets:
    enp2s0: {}
    enp2s1: {}
  bonds:
    bond0:
      interfaces:
        - enp2s0
        - enp2s1
      addresses:
        - 10.1.10.101/24
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        lacp-rate: fast
        transmit-hash-policy: layer3+4
      routes:
        - to: default
          via: 10.1.10.1
```

#### server2

```yaml
network:
  version: 2
  ethernets:
    enp2s0: {}
    enp2s1: {}
  bonds:
    bond0:
      interfaces:
        - enp2s0
        - enp2s1
      addresses:
        - 10.1.20.102/24
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        lacp-rate: fast
        transmit-hash-policy: layer3+4
      routes:
        - to: default
          via: 10.1.20.1
```

#### server3

```yaml
network:
  version: 2
  ethernets:
    enp2s0: {}
    enp2s1: {}
  bonds:
    bond0:
      interfaces:
        - enp2s0
        - enp2s1
      addresses:
        - 10.1.30.103/24
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        lacp-rate: fast
        transmit-hash-policy: layer3+4
      routes:
        - to: default
          via: 10.1.30.1
```

#### server4

```yaml
network:
  version: 2
  ethernets:
    enp2s0: {}
    enp2s1: {}
  bonds:
    bond0:
      interfaces:
        - enp2s0
        - enp2s1
      addresses:
        - 10.1.10.104/24
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        lacp-rate: fast
        transmit-hash-policy: layer3+4
      routes:
        - to: default
          via: 10.1.10.1
```

#### server5

```yaml
network:
  version: 2
  ethernets:
    enp2s0: {}
    enp2s1: {}
  bonds:
    bond0:
      interfaces:
        - enp2s0
        - enp2s1
      addresses:
        - 10.1.20.105/24
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        lacp-rate: fast
        transmit-hash-policy: layer3+4
      routes:
        - to: default
          via: 10.1.20.1
```

#### server6

```yaml
network:
  version: 2
  ethernets:
    enp2s0: {}
    enp2s1: {}
  bonds:
    bond0:
      interfaces:
        - enp2s0
        - enp2s1
      addresses:
        - 10.1.30.106/24
      parameters:
        mode: 802.3ad
        mii-monitor-interval: 100
        lacp-rate: fast
        transmit-hash-policy: layer3+4
      routes:
        - to: default
          via: 10.1.30.1
```

### 驗證

1. 驗證全域 EVPN-MH 狀態與 Uplink 追蹤 (Global State & Uplink Tracking)

    必須確認交換器已正確啟用 EVPN-MH，並且系統有正確監控到 Uplink 介面。在 EVPN-MH 架構中，當所有 Uplink 斷線時，交換器會自動將連接伺服器的 Ethernet Segment (ES) Bond 介面設為 protodown 或 error-disabled 狀態，以防止流量黑洞。

    ```bash
    cumulus@leaf01:mgmt:~$ nv show evpn multihoming
                        operational  applied
    -------------------  -----------  -------
    state                             enabled
    mac-holdtime         1080         1080
    neighbor-holdtime    1080         1080
    startup-delay        180          180
    ead-evi-route
      rx                              enabled
      tx                              enabled
    segment
      df-preference                   32767
    startup-delay-timer  --:--:--
    uplink-count         2
    uplink-active        2
    ```

    此指令會顯示全域的 EVPN-MH 狀態，包含 `mac-holdtime`、`neighbor-holdtime`、`startup-delay` 等計時器，以及當前活躍的 Uplink 數量 (`uplink-active`) 與總數 (`uplink-count`)。確認 `state` 為 `enabled`，且 `uplink-active` 數量符合實體接線預期，在拓撲中應顯示為 2（代表去往 Spine01/02 的路徑正常）。

2. 檢查乙太網路網段 (Ethernet Segment) 狀態
    確認各個連接伺服器的 Bond 介面是否已經成功生成 Ethernet Segment ID (ESI)，以及其 Designated Forwarder (DF) 優先級是否正確。

    ```bash
    cumulus@leaf01:mgmt:~$ nv show evpn multihoming esi

    ESInterface - Local interface, NHG - Nexthop group ID, DFPref - Designated
    forwarder preference, VNICnt - ESI EVPN instances, MacCnt - Mac entries using
    this ES as destination, RemoteVTEPs - Remote tunnel Endpoint, Flags - * - ready-
    for_bgp, s - oper-up, x - non-designated-forward, r - remote, l - local, f -
    designated-forward, b - bridge-port, A - active

    ESI                            ESInterface  NHG        DFPref  VNICnt  MacCnt  RemoteVTEPs  Flags
    -----------------------------  -----------  ---------  ------  ------  ------  -----------  -------
    03:44:38:39:ff:00:aa:00:00:01  bond1        536870913  50000   1       1       10.10.10.2   lrf*bsA
    03:44:38:39:ff:00:aa:00:00:02  bond2        536870914  50000   1       1       10.10.10.2   lrf*bsA
    03:44:38:39:ff:00:aa:00:00:03  bond3        536870915  50000   1       1       10.10.10.2   lrf*bsA
    03:44:38:39:ff:00:bb:00:00:01               536870917  0       0       1       10.10.10.3   rA
                                                                                  10.10.10.4
    03:44:38:39:ff:00:bb:00:00:02               536870920  0       0       1       10.10.10.3   rA
                                                                                  10.10.10.4
    03:44:38:39:ff:00:bb:00:00:03               536870921  0       0       1       10.10.10.3   rA
                                                                                  10.10.10.4
    ```

    這個指令極為重要，它會列出所有的 ESI 以及其關聯的本地介面 (Local interface)、DF 優先級 (DFPref)、MAC 數量 (MacCnt)，以及遠端 VTEP 的 IP 位址。其 `Flags` 中帶有 `local` (代表本地直連) 與 `remote` (代表成功從對等交換器學習到)等值。

    詳細來看:

    **核心欄位解析**

    | 參數名稱 | 解析與說明 |
    | :--- | :--- |
    | **ESI** | **乙太網路網段識別碼**。由您配置的 `mac-address` (44:38:39:FF:00:AA/BB) 與 `local-id` (1, 2, 3) 自動生成。 |
    | **ESInterface** | **本地綁定介面**。顯示該 ESI 在本地對應的 `bond` 介面。若為空值，代表該 ESI 是從遠端（其他 Rack）學習過來的。 |
    | **NHG** | **下跳群組識別碼 (Nexthop Group ID)**。系統內部用於硬體轉發流量的唯一編號。 |
    | **DFPref** | **DF 選舉權重 (Preference)**。配置的數值為 `50000`。數值越高，越優先成為該網段的指定轉發者 (DF)。 |
    | **VNICnt** | **VNI 數量**。該 ESI 目前關聯的 EVPN 實例數量（例如 VLAN 10 在此顯示為 1）。 |
    | **MacCnt** | **MAC 位址數量**。目前在該 ESI 後端學習到的終端設備 MAC 數量。 |
    | **RemoteVTEPs** | **遠端對等節點**。共享同一個 ESI 的鄰居交換器 Loopback IP。 |
    | **Flags** | **狀態標籤**。反映該網段的運行協議狀態。 |

    **狀態標籤 (Flags) 深度解析**

    輸出中出現了兩組主要的 Flags，分別代表「本地網段」與「遠端網段」：

    A. 本地網段狀態：`lrf*bsA` (以 ESI ...aa...01 為例)
      這代表 `leaf01` 物理連接了此設備，且目前正負責轉發。
      * **l (local):** 本地有物理連線（透過 `bond1`）。
      * **r (remote):** 檢測到鄰居 `10.10.10.2` (leaf02) 也宣告了同一個 ESI。
      * **f (designated-forwarder):** **關鍵標籤**。代表 `leaf01` 目前在該網段被選為 **DF (主)**，負責轉發 BUM 流量。
      * **\* (ready-for-bgp):** 該網段已準備好透過 BGP 宣告。
      * **b (bridge-port):** 該介面已成功加入橋接網域。
      * **s (oper-up):** 介面物理狀態與協議狀態均為 Up。
      * **A (active):** 該網段目前處於活動轉發狀態。

    B. 遠端網段狀態：`rA` (以 ESI ...bb...01 為例)
      這代表該設備連接在 `leaf03` 與 `leaf04` 的機櫃下。
      * **r (remote):** 此 ESI 是透過 BGP EVPN Type-4 路由從遠端學習而來。
      * **A (active):** 遠端路徑是可達的，且 `leaf01` 知道該網段由 `10.10.10.3` 與 `10.10.10.4` 共同服務。

    **拓撲運行現狀總結**

    根據輸出結果，目前的運行邏輯如下：

      1. **Rack 1 (leaf01 & leaf02):**
          * `leaf01` 與 `leaf02` 成功形成了 ES 群組。
          * 對於 `bond1`, `bond2`, `bond3`，`leaf01` 目前都擔任 **DF (f 標籤)**，代表它在這些網段是主導地位。
      2. **跨 Rack 通訊:**
          * `leaf01` 已經正確看見了位於另一端機櫃的 `Server4`, `Server5`, `Server6` 所屬的 ESI (...bb...)。
          * 它同時看見了 `10.10.10.3` 與 `10.10.10.4` 這兩個 VTEP，這意味著當 `leaf01` 往這些伺服器傳送流量時，可以實現 **ECMP (等價多路徑)** 負載平衡。

    若發現特定 ES 異常，可針對單一 ESI 進行深入檢視其旗標 (如 `bridge-port on`, `designated-forward on`) 以及遠端 VTEP 的狀態。

    ```bash
    $ nv show evpn multihoming esi 03:44:38:39:ff:00:aa:00:00:02
                            operational
    ----------------------  -----------
    local-interface         bond2
    df-preference           50000
    mac-count               1
    vni-count               1
    nexthop-group-id        536870914
    flags-string            lrf*bsA
    flags
      local                 on
      remote                on
      ready-for-bgp         on
      bridge-port           on
      oper-up               on
      nexthop-group-active  on
      designated-forward    on



    remote-vtep
    ==============

        DFAlgo - Designated forwarder election algorithm, DFPref - Designated forwarder
        preference, NHG - Remote VTEP Nexthop group ID

        VTEP        DFAlgo      DFPref  NHG
        ----------  ----------  ------  ---------
        10.10.10.2  preference  50000   268435460

    ```

3. 透過 BGP 控制平面驗證 Type-1 與 Type-4 路由 (BGP Control Plane)
    EVPN-MH 的核心是透過 BGP 交換路由資訊。Type-4 (Ethernet Segment Route) 用於自動發現共享同一個 ES 的 VTEP 並進行 DF 選舉；Type-1 (Ethernet Auto-Discovery, EAD) 則用於流量的快速容錯移轉 (Fast Failover) 與別名 (Aliasing)。

    * 驗證 Type-4 (ES 發現與 DF 選舉)
  
        ```bash
        cumulus@leaf01:mgmt:~$ sudo vtysh -c "show bgp l2vpn evpn es"
        ES Flags: B - bypass, L local, R remote, I inconsistent
        VTEP Flags: E ESR/Type-4, A active nexthop
        ESI                            Flags RD                    #VNIs    VTEPs
        03:44:38:39:ff:00:aa:00:00:01  LR    10.10.10.1:5          1        10.10.10.2(EA)
        03:44:38:39:ff:00:aa:00:00:02  LR    10.10.10.1:6          1        10.10.10.2(EA)
        03:44:38:39:ff:00:aa:00:00:03  LR    10.10.10.1:7          1        10.10.10.2(EA)
        03:44:38:39:ff:00:bb:00:00:01  R     (null)                1        10.10.10.3(A),10.10.10.4(A)
        03:44:38:39:ff:00:bb:00:00:02  R     (null)                1        10.10.10.3(A),10.10.10.4(A)
        03:44:38:39:ff:00:bb:00:00:03  R     (null)                1        10.10.10.3(A),10.10.10.4(A)

        cumulus@leaf01:mgmt:~$ nv show evpn multihoming bgp-info esi

        SrcIP - Originator IP, VNICnt - VNI Count, VRFCnt - VRF Count, MACIPCnt - MAC IP
        path count, MacGlblCnt - Mac global count, VTEP - Remote VTEP ID, FragID -
        Fragments ID, Flags - u - up, a - advertise-evi, VtepFlags - e - esr, A - active

        ESI                            RD            SrcIP       VNICnt  VRFCnt  MACIPCnt  MacGlblCnt  Local  Remote  VTEP        FragID        Flags  VtepFlags
        -----------------------------  ------------  ----------  ------  ------  --------  ----------  -----  ------  ----------  ------------  -----  ---------
        03:44:38:39:ff:00:aa:00:00:01  10.10.10.1:5  10.10.10.1  1       1       2         4           yes    yes     10.10.10.2  10.10.10.1:5  ua     eA
        03:44:38:39:ff:00:aa:00:00:02  10.10.10.1:6  10.10.10.1  1       1       2         4           yes    yes     10.10.10.2  10.10.10.1:6  ua     eA
        03:44:38:39:ff:00:aa:00:00:03  10.10.10.1:7  10.10.10.1  1       1       2         4           yes    yes     10.10.10.2  10.10.10.1:7  ua     eA
        03:44:38:39:ff:00:bb:00:00:01                (null)      1       1       0         8                  yes     10.10.10.3                       A
                                                                                                                      10.10.10.4                       A
        03:44:38:39:ff:00:bb:00:00:02                (null)      1       1       0         8                  yes     10.10.10.3                       A
                                                                                                                      10.10.10.4                       A
        03:44:38:39:ff:00:bb:00:00:03                (null)      1       1       0         8                  yes     10.10.10.3                       A
                                                                                                                      10.10.10.4                       A

        ```

        此輸出會顯示從 BGP Type-1 與 Type-4 路由中學習到的 ES 資訊。必須確認本地與遠端 VTEP 皆正確顯示於該 ESI 的路由表內。

    * **驗證 Type-1 (EAD 路由，用於多重路徑 (multihomed) 端點的資料中心)**
         此指令會列出所有 BGP 表內的 Type-1 路由。若伺服器端的 Bond 發生故障，VTEP 會發送單一的 EAD-ES withdrawal 訊息來通知所有其他 VTEP，從而觸發快速容錯移轉。

        ```bash
        cumulus@leaf01:mgmt:~$ sudo vtysh -c "show bgp l2vpn evpn route type ead"
        BGP table version is 14, local router ID is 10.10.10.1
        Status codes: s suppressed, d damped, h history, * valid, > best, i - internal
        Origin codes: i - IGP, e - EGP, ? - incomplete
        EVPN type-1 prefix: [1]:[EthTag]:[ESI]:[IPlen]:[VTEP-IP]:[Frag-id]
        EVPN type-2 prefix: [2]:[EthTag]:[MAClen]:[MAC]:[IPlen]:[IP]
        EVPN type-3 prefix: [3]:[EthTag]:[IPlen]:[OrigIP]
        EVPN type-4 prefix: [4]:[ESI]:[IPlen]:[OrigIP]
        EVPN type-5 prefix: [5]:[EthTag]:[IPlen]:[IP]

          Network          Next Hop            Metric LocPrf Weight Path
                            Extended Community
        Route Distinguisher: 10.10.10.1:4
        *> [1]:[0]:[03:44:38:39:ff:00:aa:00:00:02]:[128]:[::]:[0] RD 10.10.10.1:4
                            10.10.10.1 (leaf01)
                                                              32768 i
                            ET:8 RT:65101:20
        Route Distinguisher: 10.10.10.1:5
        *> [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:01]:[128]:[::]:[0] RD 10.10.10.1:5
                            10.10.10.1 (leaf01)
                                                              32768 i
                            ET:8 ESI-label-Rt:AA RT:65101:10
        Route Distinguisher: 10.10.10.1:6
        *> [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:02]:[128]:[::]:[0] RD 10.10.10.1:6
                            10.10.10.1 (leaf01)
                                                              32768 i
                            ET:8 ESI-label-Rt:AA RT:65101:20
        Route Distinguisher: 10.10.10.1:7
        *> [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:03]:[128]:[::]:[0] RD 10.10.10.1:7
                            10.10.10.1 (leaf01)
                                                              32768 i
                            ET:8 ESI-label-Rt:AA RT:65101:30
        Route Distinguisher: 10.10.10.1:8
        *> [1]:[0]:[03:44:38:39:ff:00:aa:00:00:03]:[128]:[::]:[0] RD 10.10.10.1:8
                            10.10.10.1 (leaf01)
                                                              32768 i
                            ET:8 RT:65101:30
        Route Distinguisher: 10.10.10.1:9
        *> [1]:[0]:[03:44:38:39:ff:00:aa:00:00:01]:[128]:[::]:[0] RD 10.10.10.1:9
                            10.10.10.1 (leaf01)
                                                              32768 i
                            ET:8 RT:65101:10
        Route Distinguisher: 10.10.10.2:2
        *> [1]:[0]:[03:44:38:39:ff:00:aa:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:2
                            10.10.10.2 (spine02)
                                                                  0 65199 65102 i
                            RT:65102:20 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:aa:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:2
                            10.10.10.2 (spine01)
                                                                  0 65199 65102 i
                            RT:65102:20 ET:8
        Route Distinguisher: 10.10.10.2:3
        *> [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:3
                            10.10.10.2 (spine01)
                                                                  0 65199 65102 i
                            RT:65102:10 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:3
                            10.10.10.2 (spine02)
                                                                  0 65199 65102 i
                            RT:65102:10 ET:8 ESI-label-Rt:AA
        Route Distinguisher: 10.10.10.2:4
        *> [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:4
                            10.10.10.2 (spine01)
                                                                  0 65199 65102 i
                            RT:65102:20 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:4
                            10.10.10.2 (spine02)
                                                                  0 65199 65102 i
                            RT:65102:20 ET:8 ESI-label-Rt:AA
        Route Distinguisher: 10.10.10.2:5
        *> [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:5
                            10.10.10.2 (spine01)
                                                                  0 65199 65102 i
                            RT:65102:30 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:aa:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:5
                            10.10.10.2 (spine02)
                                                                  0 65199 65102 i
                            RT:65102:30 ET:8 ESI-label-Rt:AA
        Route Distinguisher: 10.10.10.2:8
        *> [1]:[0]:[03:44:38:39:ff:00:aa:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:8
                            10.10.10.2 (spine02)
                                                                  0 65199 65102 i
                            RT:65102:30 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:aa:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:8
                            10.10.10.2 (spine01)
                                                                  0 65199 65102 i
                            RT:65102:30 ET:8
        Route Distinguisher: 10.10.10.2:9
        *> [1]:[0]:[03:44:38:39:ff:00:aa:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:9
                            10.10.10.2 (spine02)
                                                                  0 65199 65102 i
                            RT:65102:10 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:aa:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.2:9
                            10.10.10.2 (spine01)
                                                                  0 65199 65102 i
                            RT:65102:10 ET:8
        Route Distinguisher: 10.10.10.3:2
        *> [1]:[0]:[03:44:38:39:ff:00:bb:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:2
                            10.10.10.3 (spine02)
                                                                  0 65199 65103 i
                            RT:65103:20 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:bb:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:2
                            10.10.10.3 (spine01)
                                                                  0 65199 65103 i
                            RT:65103:20 ET:8
        Route Distinguisher: 10.10.10.3:3
        *> [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:3
                            10.10.10.3 (spine01)
                                                                  0 65199 65103 i
                            RT:65103:10 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:3
                            10.10.10.3 (spine02)
                                                                  0 65199 65103 i
                            RT:65103:10 ET:8 ESI-label-Rt:AA
        Route Distinguisher: 10.10.10.3:4
        *> [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:4
                            10.10.10.3 (spine01)
                                                                  0 65199 65103 i
                            RT:65103:20 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:4
                            10.10.10.3 (spine02)
                                                                  0 65199 65103 i
                            RT:65103:20 ET:8 ESI-label-Rt:AA
        Route Distinguisher: 10.10.10.3:5
        *> [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:5
                            10.10.10.3 (spine01)
                                                                  0 65199 65103 i
                            RT:65103:30 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:5
                            10.10.10.3 (spine02)
                                                                  0 65199 65103 i
                            RT:65103:30 ET:8 ESI-label-Rt:AA
        Route Distinguisher: 10.10.10.3:8
        *> [1]:[0]:[03:44:38:39:ff:00:bb:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:8
                            10.10.10.3 (spine02)
                                                                  0 65199 65103 i
                            RT:65103:30 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:bb:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:8
                            10.10.10.3 (spine01)
                                                                  0 65199 65103 i
                            RT:65103:30 ET:8
        Route Distinguisher: 10.10.10.3:9
        *> [1]:[0]:[03:44:38:39:ff:00:bb:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:9
                            10.10.10.3 (spine02)
                                                                  0 65199 65103 i
                            RT:65103:10 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:bb:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.3:9
                            10.10.10.3 (spine01)
                                                                  0 65199 65103 i
                            RT:65103:10 ET:8
        Route Distinguisher: 10.10.10.4:2
        *> [1]:[0]:[03:44:38:39:ff:00:bb:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:2
                            10.10.10.4 (spine02)
                                                                  0 65199 65104 i
                            RT:65104:20 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:bb:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:2
                            10.10.10.4 (spine01)
                                                                  0 65199 65104 i
                            RT:65104:20 ET:8
        Route Distinguisher: 10.10.10.4:3
        *> [1]:[0]:[03:44:38:39:ff:00:bb:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:3
                            10.10.10.4 (spine02)
                                                                  0 65199 65104 i
                            RT:65104:30 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:bb:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:3
                            10.10.10.4 (spine01)
                                                                  0 65199 65104 i
                            RT:65104:30 ET:8
        Route Distinguisher: 10.10.10.4:4
        *> [1]:[0]:[03:44:38:39:ff:00:bb:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:4
                            10.10.10.4 (spine02)
                                                                  0 65199 65104 i
                            RT:65104:10 ET:8
        *  [1]:[0]:[03:44:38:39:ff:00:bb:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:4
                            10.10.10.4 (spine01)
                                                                  0 65199 65104 i
                            RT:65104:10 ET:8
        Route Distinguisher: 10.10.10.4:9
        *> [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:9
                            10.10.10.4 (spine01)
                                                                  0 65199 65104 i
                            RT:65104:10 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:01]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:9
                            10.10.10.4 (spine02)
                                                                  0 65199 65104 i
                            RT:65104:10 ET:8 ESI-label-Rt:AA
        Route Distinguisher: 10.10.10.4:10
        *> [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:10
                            10.10.10.4 (spine01)
                                                                  0 65199 65104 i
                            RT:65104:20 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:02]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:10
                            10.10.10.4 (spine02)
                                                                  0 65199 65104 i
                            RT:65104:20 ET:8 ESI-label-Rt:AA
        Route Distinguisher: 10.10.10.4:11
        *> [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:11
                            10.10.10.4 (spine01)
                                                                  0 65199 65104 i
                            RT:65104:30 ET:8 ESI-label-Rt:AA
        *  [1]:[4294967295]:[03:44:38:39:ff:00:bb:00:00:03]:[32]:[0.0.0.0]:[0] RD 10.10.10.4:11
                            10.10.10.4 (spine02)
                                                                  0 65199 65104 i
                            RT:65104:30 ET:8 ESI-label-Rt:AA

        Displayed 24 prefixes (42 paths) (of requested type)
        ```

        我們可以用以下方式拆解並理解上述輸出：

        1. 什麼是 Type-1 (EAD) 路由？
            在 EVPN Multihoming 架構中，Type-1 路由不負責告訴別人主機在哪裡（那是 Type-2 的工作），它負責的是：
            * Aliasing (負載平衡)：告訴鄰居我可以幫忙分擔去往某個網段的流量。
            * Mass Withdraw (快速撤銷)：故障時一包封包就切斷所有關聯路徑，達成毫秒級收斂。
        2. 欄位 `[1]:[EthTag]:[ESI]` 解析
            * [1]：代表這是 Type-1 路由。
            * [EthTag] (Ethernet Tag ID)：這是最關鍵的觀察點。
              * `4294967295` (即 0xFFFFFFFF)：這叫 EAD-per-ES 路由。它不針對特定 VLAN，而是針對整個物理網段發布的。它的目的是「快速收斂」。
              * `0`：這叫 EAD-per-EVI 路由。它是針對特定 VNI 發布的，目的是實現*負載平衡 (Aliasing)*。

        3. `[ESI]`：這是配置的乙太網路網段識別碼。

            * 結尾為 aa...：代表 Rack 1（Server 1-3）的網段。
            * 結尾為 bb...：代表 Rack 2（Server 4-6）的網段。

4. 驗證 VNI 層級的 ES 映射與連線 (Per-VNI ES Mapping)
    我們必須確保這些 Ethernet Segments 有正確對應到覆疊網路 (Overlay) 中的 L2 VNI 上。
    * **檢視各 VNI 的 ES 映射**
        這會顯示特定的 VNI 下綁定了哪些 ESI，以及它們是本地 (Local, L) 還是遠端 (Remote, R) 學習到的。

        ```bash
        cumulus@leaf01:mgmt:~$ nv show evpn vni 10 multihoming esi

        Local - ESI type configured as local, Remote - ESI type configured as remote

        ESI                            Local  Remote
        -----------------------------  -----  ------
        03:44:38:39:ff:00:aa:00:00:01  yes
        cumulus@leaf01:mgmt:~$ nv show evpn vni 20 multihoming esi

        Local - ESI type configured as local, Remote - ESI type configured as remote

        ESI                            Local  Remote
        -----------------------------  -----  ------
        03:44:38:39:ff:00:aa:00:00:02  yes
        cumulus@leaf01:mgmt:~$ nv show evpn vni 30 multihoming esi

        Local - ESI type configured as local, Remote - ESI type configured as remote

        ESI                            Local  Remote
        -----------------------------  -----  ------
        03:44:38:39:ff:00:aa:00:00:03  yes
        ```

    * **檢視 BGP 層級的 VNI 映射**

        此指令能進一步確認 BGP 針對每個 VNI 所宣告的 ES 狀態，包含是否具備 EAD-per-ES (E) 或 EAD-per-EVI (V) 的能力旗標。

        ```bash
        cumulus@leaf01:mgmt:~$ sudo vtysh -c "show bgp l2vpn evpn es-evi"
        Flags: L local, R remote, I inconsistent
        VTEP-Flags: E EAD-per-ES, V EAD-per-EVI
        VNI      ESI                            Flags VTEPs
        20       03:44:38:39:ff:00:aa:00:00:02  LR    10.10.10.2(EV)
        20       03:44:38:39:ff:00:bb:00:00:02  R     10.10.10.3(EV),10.10.10.4(EV)
        30       03:44:38:39:ff:00:aa:00:00:03  LR    10.10.10.2(EV)
        30       03:44:38:39:ff:00:bb:00:00:03  R     10.10.10.3(EV),10.10.10.4(EV)
        10       03:44:38:39:ff:00:aa:00:00:01  LR    10.10.10.2(EV)
        10       03:44:38:39:ff:00:bb:00:00:01  R     10.10.10.3(EV),10.10.10.4(EV)
        ```

        解讀資料內容:
        * 本地機櫃狀態 (ESI 末兩碼為 aa) `10  03:44:38:39:ff:00:aa:00:00:01  LR  10.10.10.2(EV)`
          * leaf01 知道伺服器連在自己身上（L），同時也收到了 leaf02 (10.10.10.2) 傳來的路由訊息（R）。
          * 這證明了 Rack 1 的 All-Active（全主動） 模式已在控制平面達成共識。當流量進來時，系統知道可以透過這兩台交換器進行負載平衡。

        * 遠端機櫃狀態 (ESI 末兩碼為 bb) `10  03:44:38:39:ff:00:bb:00:00:01  R   10.10.10.3(EV),10.10.10.4(EV)`
          * leaf01 本地沒有連接此網段（無 L 標籤），但透過 BGP 學習到了遠端資訊（R）。
          * 它看見了遠端 ESI 同時由 10.10.10.3 與 10.10.10.4 服務。這使得 leaf01 在發送流量給 Server 4 時，能夠自動進行 Aliasing，將流量平衡發往遠端的兩台 Leaf。

        另外 `EAD-per-ES` 與 `VAD-per-EVI` 分別代表什麼意思 ?

        在 EVPN Multihoming (EVPN-MH) 的標準中，這兩者都屬於 BGP EVPN Route Type-1 (Ethernet Auto-Discovery Route)，但它們負責解決的問題完全不同。簡單來說，`EAD-per-ES`負責速度（故障收斂），而`EAD-per-EVI`負責效率（負載平衡）。

        1. EAD-per-ES (Ethernet Auto-Discovery per Ethernet Segment)
            這是針對整個*乙太網路網段*發佈的路由。當交換器（Leaf）偵測到本地的 ESI（如 bond1）處於 Up 狀態時，它會發送一條針對該 ESI 的路由，其 Ethernet Tag ID 設為一個特殊值（通常是 MAX-ET）。

        2. EAD-per-EVI (Ethernet Auto-Discovery per EVPN Instance)
            這是針對特定*EVPN 實例（即 VNI/VLAN）*發佈的路由。交換器會為該 ESI 所屬的每一個 VNI 分別發送路由。例如 ESI-aa-01 同時屬於 VNI 10, 20, 30，就會有三條對應的 EAD-per-EVI 路由。

### 封包觀察

1. 接入層 LACP 與 ESI 驗證
    * 目標: 確認伺服器是否將兩台 Leaf 視為同一個邏輯設備
    * 抓包位置: Server1 與 leaf01 或 leaf02 之間的連線（如 swp1）。
    * 驗證目標(第一個封包):
      * `Partner MAC` 地址： 在 LACP PDU 封包中，檢查 `Partner System ID`。它必須是配置的 `Anycast MAC：44:38:39:FF:00:AA`。
      * 狀態： 確保 LACP 協商成功，雙方都處於 `Collecting` 與 `Distributing` 狀態。

      ```bash
      ...
        Link Aggregation Control Protocol
      LACP Version: 0x01
      TLV Type: Actor Information (0x01)
      TLV Length: 0x14
      Actor System Priority: 65535
      Actor System ID: 4e:d4:fb:d8:48:6a (4e:d4:fb:d8:48:6a)
      Actor Key: 15
      Actor Port Priority: 255
      Actor Port: 1
      Actor State: 0x3f, LACP Activity, LACP Timeout, Aggregation, Synchronization, Collecting, Distributing
      [Actor State Flags: **DCSGSA]
      Reserved: 000000
      TLV Type: Partner Information (0x02)
      TLV Length: 0x14
      Partner System Priority: 65535
      Partner System: CumulusNetwo_ff:00:aa (44:38:39:ff:00:aa)
      Partner Key: 15
      Partner Port Priority: 255
      Partner Port: 1
      Partner State: 0x3f, LACP Activity, LACP Timeout, Aggregation, Synchronization, Collecting, Distributing
          .... ...1 = LACP Activity: Active
          .... ..1. = LACP Timeout: Short Timeout
          .... .1.. = Aggregation: Aggregatable
          .... 1... = Synchronization: In Sync
          ...1 .... = Collecting: Enabled
          ..1. .... = Distributing: Enabled
          .0.. .... = Defaulted: No
          0... .... = Expired: No
      [Partner State Flags: **DCSGSA]
      Reserved: 000000
      TLV Type: Collector Information (0x03)
      TLV Length: 0x10
      Collector Max Delay: 0
      Reserved: 000000000000000000000000
      TLV Type: Terminator (0x00)
      TLV Length: 0x00
      Pad: 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
      ```

2. 控制平面 BGP EVPN 路由驗證
    * 目標：觀察 EVPN Type-1, 2, 4 路由的交換過程。
    * 抓包位置： leaf01 與 Spine01 之間的連線（swp13 或 swp14）。
    * 驗證動作： 在 leaf01 和 spine01 上重啟交換器。
    * 驗證目標：
      * Type-4 (ES Route)： 找尋包含 ESI 的路由。這是為了進行 DF 選舉。
      * Type-1 (EAD Route)： 檢查是否有 Ethernet Auto-Discovery 路由。這包含用於負載平衡的 Aliasing 標籤。
      * Type-2 (MAC/IP Route)： 當伺服器發送第一個封包時，觀察 MAC 地址如何被封裝在 BGP 更新訊息中傳遞給 Spine。

    > 在 wireshark 中可以用 `bgp.evpn.nlri.rt == 1` 進行過濾

    我們觀察第 80 個封包，結論如下:

    在 EVPN 運行前，Leaf 與 Spine 必須先交換 Loopback 地址以建立 VXLAN 隧道。第 80 個封包顯示 leaf01 (AS 65101) 正在向 spine01 宣告其 Loopback 地址 10.10.10.1/32。該底層路由採用的 BGP Unnumbered (IPv6 Link-local) 方式已成功運作 。

    **ESI 發現與鄰居關係 (EVPN Type-4)**，是驗證 EVPN-MH 的核心目標，確認兩台 Leaf 是否知道彼此共享同一個網段。這是 leaf01 在告訴 spine01（以及最終告訴 leaf02）: 我有這三個 Bond 網段，準備好進行多歸屬備援了

    * 包含了 EVPN 的特定內容 (AFI 25, SAFI 70) 。
    * Route Type: Ethernet Segment Route (4)。
    * ESI (Ethernet Segment Identifier)：應包含配置的 03:44:38:39:ff:00:aa...。
    * ES-Import Community：包含一個由 MAC 衍生出來的數值，確保只有同夥的 Leaf 會去解析這條路由。

    ```bash
    ....
    Path attributes
    Path Attribute - MP_REACH_NLRI
        Flags: 0x90, Optional, Extended-Length, Non-transitive, Complete
            1... .... = Optional: Set
            .0.. .... = Transitive: Not set
            ..0. .... = Partial: Not set
            ...1 .... = Extended-Length: Set
            .... 0000 = Unused: 0x0
        Type Code: MP_REACH_NLRI (14)
        Length: 84
        Address family identifier (AFI): Layer-2 VPN (25)
        Subsequent address family identifier (SAFI): EVPN (70)
        Next hop: 10.10.10.4
            IPv4 Address: 10.10.10.4
        Number of Subnetwork points of attachment (SNPA): 0
        Network Layer Reachability Information (NLRI)
            EVPN NLRI: Ethernet Segment Route
                Route Type: Ethernet Segment Route (4) # Type4
                Length: 23
                Route Distinguisher: 00010a0a0a040009 (10.10.10.4:9)
                ESI: 03:44:38:39:ff:00:bb:00:00:01
                    ESI Type: ESI MAC address defined (3)
                    ESI Value: 44 38 39 ff 00 bb 00 00 01
                    ESI system MAC: CumulusNetwo_ff:00:bb (44:38:39:ff:00:bb)
                    ESI system mac discriminator: 00 00
                    Remaining bytes: 01
                IP Address Length: 32
                IPv4 address: 10.10.10.4
            EVPN NLRI: Ethernet Segment Route
                Route Type: Ethernet Segment Route (4)
                Length: 23
                Route Distinguisher: 00010a0a0a04000a (10.10.10.4:10)
                ESI: 03:44:38:39:ff:00:bb:00:00:02
                    ESI Type: ESI MAC address defined (3)
                    ESI Value: 44 38 39 ff 00 bb 00 00 02
                    ESI system MAC: CumulusNetwo_ff:00:bb (44:38:39:ff:00:bb)
                    ESI system mac discriminator: 00 00
                    Remaining bytes: 02
                IP Address Length: 32
                IPv4 address: 10.10.10.4
            EVPN NLRI: Ethernet Segment Route
                Route Type: Ethernet Segment Route (4)
                Length: 23
                Route Distinguisher: 00010a0a0a04000b (10.10.10.4:11)
                ESI: 03:44:38:39:ff:00:bb:00:00:03
                    ESI Type: ESI MAC address defined (3)
                    ESI Value: 44 38 39 ff 00 bb 00 00 03
                    ESI system MAC: CumulusNetwo_ff:00:bb (44:38:39:ff:00:bb)
                    ESI system mac discriminator: 00 00
                    Remaining bytes: 03
                IP Address Length: 32
                IPv4 address: 10.10.10.4
    Path Attribute - ORIGIN: IGP
        Flags: 0x40, Transitive, Well-known, Complete
            0... .... = Optional: Not set
            .1.. .... = Transitive: Set
            ..0. .... = Partial: Not set
            ...0 .... = Extended-Length: Not set
            .... 0000 = Unused: 0x0
        Type Code: ORIGIN (1)
        Length: 1
        Origin: IGP (0)
    Path Attribute - AS_PATH: 65199 65104 
        Flags: 0x50, Transitive, Extended-Length, Well-known, Complete
            0... .... = Optional: Not set
            .1.. .... = Transitive: Set
            ..0. .... = Partial: Not set
            ...1 .... = Extended-Length: Set
            .... 0000 = Unused: 0x0
        Type Code: AS_PATH (2)
        Length: 10
        AS Path segment: 65199 65104
            Segment type: AS_SEQUENCE (2)
            Segment length (number of ASN): 2
            AS4: 65199
            AS4: 65104
    Path Attribute - EXTENDED_COMMUNITIES
        Flags: 0xc0, Optional, Transitive, Complete
            1... .... = Optional: Set
            .1.. .... = Transitive: Set
            ..0. .... = Partial: Not set
            ...0 .... = Extended-Length: Not set
            .... 0000 = Unused: 0x0
        Type Code: EXTENDED_COMMUNITIES (16)
        Length: 24
        Carried extended communities: (3 communities)
            Encapsulation: VXLAN Encapsulation [Transitive Opaque]
            ES-Import Route Target: RT: 44:38:39:ff:00:bb [Transitive EVPN]
            DF Election: 0x0200 0x0000 0xc350 [Transitive EVPN]
    ```

    **全主動負載平衡與 Aliasing (EVPN Type-1)**，這決定了流量是否能同時走 leaf01 與 leaf02 進入伺服器，內容中包含 AFI 25 / SAFI 70 的 Ethernet Auto-Discovery 路由。先前的 `show bgp l2vpn evpn es-evi` 指令已證實這些 Type-1 路由帶有 (EV) 標籤（即 EAD-per-ES 與 VAD-per-EVI），代表 Aliasing 機制已在控制平面就緒。

    * Route Type: Ethernet Auto-Discovery Route (1)。
    * EAD-per-ES: 用於鏈路斷開時的快速撤銷 (Mass Withdraw)。
    * VAD-per-EVI: 針對每個 VNI (10, 20, 30) 宣告其可達性。
    * ESI Label (VNI Label)：這是最重要的欄位。它告訴 spine01：如果你要送流量給這個 ESI 的伺服器，請封裝這個 VNI 標籤並送給我（leaf01）。

    **主機 MAC 地址同步 (EVPN Type-2)**，驗證伺服器（Server 1-3）的 MAC 地址如何被封裝並傳遞。這些 MAC 路由會關聯到特定的 ESI，確保遠端交換器知道這是一個多歸屬（Multihomed）主機。

    [wireshark | BGP](https://www.wireshark.org/docs/dfref/b/bgp.html)

3. 故障切換與收斂驗證 (Mass Withdraw)
    * 目標：驗證鏈路斷開時，網路是否能快速反應。
    * 抓包位置： leaf01 與 Spine01 之間。
    * 驗證動作： 手動關閉 leaf01 的 swp1 (連接 Server1 的接口)。
    * 驗證重點：
      * BGP Withdraw： 觀察 leaf01 是否發送了 Type-1 EAD-per-ES 的撤銷訊息。
      * 收斂速度： 在 Wireshark 中觀察從鏈路斷開到流量完全切換至 leaf02 的時間差。

    下面封包內容為第 619 個，撤銷

    ```bash
    Border Gateway Protocol - UPDATE Message
    Marker: ffffffffffffffffffffffffffffffff
    Length: 82
    Type: UPDATE Message (2)
    Withdrawn Routes Length: 0
    Total Path Attribute Length: 59
    Path attributes
        Path Attribute - MP_UNREACH_NLRI
            Flags: 0x90, Optional, Extended-Length, Non-transitive, Complete
                1... .... = Optional: Set
                .0.. .... = Transitive: Not set
                ..0. .... = Partial: Not set
                ...1 .... = Extended-Length: Set
                .... 0000 = Unused: 0x0
            Type Code: MP_UNREACH_NLRI (15)
            Length: 55
            Address family identifier (AFI): Layer-2 VPN (25)
            Subsequent address family identifier (SAFI): EVPN (70)
            Withdrawn Routes # Withdrawn
                EVPN NLRI: Ethernet Segment Route
                    Route Type: Ethernet Segment Route (4)
                    Length: 23
                    Route Distinguisher: 00010a0a0a010003 (10.10.10.1:3)
                    ESI: 03:44:38:39:ff:00:aa:00:00:01
                        ESI Type: ESI MAC address defined (3)
                        ESI Value: 44 38 39 ff 00 aa 00 00 01
                        ESI system MAC: CumulusNetwo_ff:00:aa (44:38:39:ff:00:aa)
                        ESI system mac discriminator: 00 00
                        Remaining bytes: 01
                    IP Address Length: 32
                    IPv4 address: 10.10.10.1
                EVPN NLRI: Ethernet AD Route
                    Route Type: Ethernet AD Route (1)
                    Length: 25
                    Route Distinguisher: 00010a0a0a010003 (10.10.10.1:3)
                    ESI: 03:44:38:39:ff:00:aa:00:00:01
                        ESI Type: ESI MAC address defined (3)
                        ESI Value: 44 38 39 ff 00 aa 00 00 01
                        ESI system MAC: CumulusNetwo_ff:00:aa (44:38:39:ff:00:aa)
                        ESI system mac discriminator: 00 00
                        Remaining bytes: 01
                    Ethernet Tag ID: 4294967295
                    VNI: 0

    ```

    這是 Type-1 路由中的 EAD-per-ES 變體，它是實踐 EVPN Multihoming (EVPN-MH) 中*快速收斂*與*負載平衡*最核心的封包。當中
    * `Ethernet Tag ID: 4294967295`：這是十六進位的 0xFFFFFFFF。在 EVPN 規範中，當 Tag ID 為此數值時，代表這條路由是針對整個乙太網路網段 (Ethernet Segment) 發布的，而非單一 VLAN。
    * `VNI: 0`：在 EAD-per-ES 路由中，VNI 通常設為 0，因為它關注的是物理網段的狀態。
    * `Type Code: MP_UNREACH_NLRI (15)`：使用的是 Type 15 屬性。這是 不可達 (Unreach) 訊息，代表*撤銷*。它在告訴鄰居：這條路徑已經斷了，請立刻從你的轉發表中刪除。

    下面為另一個封包部分內容

    ```bash
    Border Gateway Protocol - UPDATE Message
    Marker: ffffffffffffffffffffffffffffffff
    Length: 115
    Type: UPDATE Message (2)
    Withdrawn Routes Length: 0
    Total Path Attribute Length: 92
    Path attributes
        Path Attribute - MP_REACH_NLRI
            Flags: 0x90, Optional, Extended-Length, Non-transitive, Complete
                1... .... = Optional: Set
                .0.. .... = Transitive: Not set
                ..0. .... = Partial: Not set
                ...1 .... = Extended-Length: Set
                .... 0000 = Unused: 0x0
            Type Code: MP_REACH_NLRI (14)
            Length: 51
            Address family identifier (AFI): Layer-2 VPN (25)
            Subsequent address family identifier (SAFI): EVPN (70)
            Next hop: 10.10.10.1
                IPv4 Address: 10.10.10.1
            Number of Subnetwork points of attachment (SNPA): 0
            Network Layer Reachability Information (NLRI)
                EVPN NLRI: MAC Advertisement Route
                    Route Type: MAC Advertisement Route (2)
                    Length: 40
                    Route Distinguisher: 00010a0a0a010009 (10.10.10.1:9)
                    ESI: 03:44:38:39:ff:00:aa:00:00:01
                        ESI Type: ESI MAC address defined (3)
                        ESI Value: 44 38 39 ff 00 aa 00 00 01
                        ESI system MAC: CumulusNetwo_ff:00:aa (44:38:39:ff:00:aa)
                        ESI system mac discriminator: 00 00
                        Remaining bytes: 01
                    Ethernet Tag ID: 0
                    MAC Address Length: 48
                    MAC Address: 4e:d4:fb:d8:48:6a (4e:d4:fb:d8:48:6a)
                    IP Address Length: 32
                    IPv4 address: 10.1.10.101
                    VNI: 10
                    VNI: 4001
        Path Attribute - ORIGIN: IGP
            Flags: 0x40, Transitive, Well-known, Complete
                0... .... = Optional: Not set
                .1.. .... = Transitive: Set
                ..0. .... = Partial: Not set
                ...0 .... = Extended-Length: Not set
                .... 0000 = Unused: 0x0
            Type Code: ORIGIN (1)
            Length: 1
            Origin: IGP (0)
        Path Attribute - AS_PATH: 65199 65101 
            Flags: 0x50, Transitive, Extended-Length, Well-known, Complete
                0... .... = Optional: Not set
                .1.. .... = Transitive: Set
                ..0. .... = Partial: Not set
                ...1 .... = Extended-Length: Set
                .... 0000 = Unused: 0x0
            Type Code: AS_PATH (2)
            Length: 10
            AS Path segment: 65199 65101
                Segment type: AS_SEQUENCE (2)
                Segment length (number of ASN): 2
                AS4: 65199
                AS4: 65101
        Path Attribute - EXTENDED_COMMUNITIES
            Flags: 0xc0, Optional, Transitive, Complete
                1... .... = Optional: Set
                .1.. .... = Transitive: Set
                ..0. .... = Partial: Not set
                ...0 .... = Extended-Length: Not set
                .... 0000 = Unused: 0x0
            Type Code: EXTENDED_COMMUNITIES (16)
            Length: 16
            Carried extended communities: (2 communities)
                Route Target: 65101:10 [Transitive 2-Octet AS-Specific]
                    Type: Transitive 2-Octet AS-Specific (0x00)
                        0... .... = IANA Authority: Allocated on First Come First Serve Basis
                        .0.. .... = Transitive across ASes: Transitive
                    Subtype (AS2): Route Target (0x02)
                    2-Octet AS: 65101
                    Local Administrator: 0x00, Type: VID (802.1Q VLAN ID)
                        0... .... = A-Bit: auto-derived
                        .000 .... = Type: VID (802.1Q VLAN ID) (0)
                        .... 0000 = Domain Id: 0
                    Service Id: 10
                Encapsulation: VXLAN Encapsulation [Transitive Opaque]
                    Type: Transitive Opaque (0x03)
                        0... .... = IANA Authority: Allocated on First Come First Serve Basis
                        .0.. .... = Transitive across ASes: Transitive
                    Subtype (Opaque): Encapsulation (0x0c)
                    Tunnel type: VXLAN Encapsulation (8)

    ```

    * `Type Code: MP_REACH_NLRI (14)`：使用的是 Type 14 屬性，代表*通告*。它在告訴鄰居：「我有這條路徑，請更新轉發表。」

    * 核心身份與位置 (NLRI): 這個部分定義了誰在哪裡。
      * Route Type: MAC Advertisement Route (2)：確認這是一條 Type-2 路由，用於通告特定的主機資訊。
      * MAC Address: 4e:d4:fb:d8:48:6a：這是 Server1 的真實實體位址。
      * IPv4 address: 10.1.10.101：這是在 server1 配置中設定的靜態 IP。
      * Next hop: 10.10.10.1：代表這封名片是由 leaf01 發出的，指示遠端設備將流量送往 leaf01 的 VTEP IP。\
    * 乙太網路網段 (ESI) 的關聯: 這是驗證 EVPN-MH (Multihoming) 最關鍵的欄位
      * ESI: 03:44:38:39:ff:00:aa:00:00:01，這是 MAC 加上配置檔的 `local-id: 1`
      * 它說明，這台伺服器不是單獨連在 leaf01 下，而是連在一個*多歸屬網段*上。這讓遠端設備（如 leaf03）能結合之前收到的 Type-1 路由，實現對 Server1 的 Aliasing (全主動負載平衡)。
    * 雙 VNI 設計 (L2 與 L3 的橋樑): 在封包中出現了兩個 VNI，這實現了 Symmetric IRB (對稱式路由與橋接) 配置
      * `VNI: 10`：這是 Layer 2 VNI，對應 VLAN 10。用於同一個子網內的二層轉發。
      * `VNI: 4001`：這是 Layer 3 VNI，對應配置中的 VRF RED。
      * 這代表 leaf01 同時在進行 MAC 學習與 ARP 學習。這條路由能同時解決*二層怎麼走*與*三層怎麼繞*的問題。
    * 路由路徑與屬性
      * `AS_PATH: 65199 65101`：顯示該路由由 leaf01 (AS 65101) 產生，經過 spine01 (AS 65199) 反射轉發
      * `Route Target: 65101:10`：　這確保了只有同樣配置了 VNI 10 的交換器（如 leaf02）會去接收並處理這條訊息
      * `Encapsulation: VXLAN`：指出數據平面將採用 VXLAN 封裝技術
  
## 結論

要理解 **EVPN**，就必須先掌握它的五種核心路由類型；而要理解 **EVPN Multihoming (EVPN-MH)**，則是要看這些路由如何協作來達成無感切換與負載平衡。

1. EVPN 路由類型的核心邏輯

    在標準的 EVPN 中，我們主要依賴 **Type-2** 和 **Type-5** 來讓主機能夠互通。但當我們引入 **Multihoming (多歸屬)** 備援機制時，**Type-1** 和 **Type-4** 變成了不可或缺的靈魂角色，它們負責在後台處理複雜的鄰居發現與故障路徑撤銷。

    以下是整理的 **BGP EVPN 路由類型與 Multihoming 關聯表**：

    | 路由類型 | 官方名稱 | 核心功能 (Core Function) | 在 Multihoming 中的特殊角色 |
    | :--- | :--- | :--- | :--- |
    | **Type-1** | **Ethernet Auto-Discovery (EAD)** | 宣佈路徑的可達性與屬性。 | **快速收斂與負載平衡**：透過撤銷此路由達成 **Mass Withdraw**，或開啟 **Aliasing** 功能。 |
    | **Type-2** | **MAC/IP Advertisement** | 同步終端主機的 MAC 與 IP 地址。 | **身份綁定**：將主機地址與特定的 **ESI** 綁定，讓全網知道該主機具備備援路徑。 |
    | **Type-3** | **Inclusive Multicast (IMET)** | 處理 BUM 流量（廣播、組播、未知單播）。 | **流量優化**：確保多歸屬環境下，BUM 流量不會產生無窮迴圈或重複發送。 |
    | **Type-4** | **Ethernet Segment (ES)** | 宣告物理網段 (ESI) 的存在。 | **認親與選舉**：用於發現共享同一個網段的 Leaf 鄰居，並進行 **DF (指定轉發者)** 選舉。 |
    | **Type-5** | **IP Prefix Route** | 宣告三層網段（如 VRF 內的路由）。 | **跨網段通訊**：結合 L3 VNI，讓多租戶環境下的流量能正確路由到對應的 ESI。 |

    在實驗 **EVPN-MH** 中的「黃金三角」關係：

    1. **Type-4 (建立框架)**：兩台 Leaf 透過 Type-4 互相認識，確認彼此都接在同一個伺服器網段上。
    2. **Type-1 (鋪設路徑)**：兩台 Leaf 告訴全網這是一條全主動路徑，並準備好在斷線時發動快速撤銷。
    3. **Type-2 (帶入主角)**：當伺服器發出第一個封包，Type-2 將伺服器的身份填入上述建立好的高可用性框架中。

    透過這五種路由的協作，EVPN-MH 成功地將傳統 MLAG 需要靠實體線路（Peer-link）維護的狀態，轉化為純粹由 **BGP 控制平面** 驅動的動態協議，這正是它具備極高擴展性與多廠商互通性的原因。
