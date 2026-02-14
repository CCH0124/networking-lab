# Border Gateway Protocol - BGP

BGP 是網際網路的路由協定，它透過交換路由資訊和可達性資訊來管理資料包在網路間的路由方式。以下是 BGP 協議基礎與核心機制

1. BGP 基礎與自動化 (Auto BGP)

    * **核心機制**：BGP 透過交換路由與可達性資訊來管理網路流量，常用於資料中心的 **Clos 拓樸**。
    * **自治系統 (AS)**：每個管理單位擁有唯一的 ASN。下面會進行描述。
    * **Auto BGP**：這是 Cumulus 的特色功能，能自動分配 ASN 以簡化配置。
    * **Spine**：固定使用 ASN `4200000000`。
    * **Leaf**：從特定範圍隨機分配，避免手動配置錯誤。

2. eBGP vs. iBGP

    * **eBGP**：用於不同 AS 之間對等連線，eBGP 對等體有不同的 ASN。透過 `AS_Path` 屬性來防止路由環路 (Loop)。
    * **iBGP**：用於同一 AS 內部對等連線，iBGP 對等體具有相同的 ASN。
    * **限制**：iBGP 路由器不會將從一個 iBGP 同伴學到的路由轉發給另一個 iBGP 同伴。
    * **解決方案**：為了解決全連結 (Full Mesh) 的擴展性問題，通常使用 **Route Reflector (路由反射器)**。

3. BGP 路徑選擇演算法 (Path Selection)

    當有多條路徑時，BGP 會依序按以下優先順序選路：

    1. **Weight**：權重最高者優先（僅限本地有效）。
    2. **Local Preference**：本地偏好最高者優先（AS 內部交換）。
    3. **Locally Originated**：本地產生的路由優先。
    4. **Shortest AS Path**：AS 路徑最短者優先。
    5. **Lowest MED**：多出口鑑別值最低者優先。
    6. **eBGP 優先於 iBGP**。
    7. **Lowest Router ID**：最後比無可比時，選路由器 ID 最小的。

4. BGP Unnumbered (無 IP 介面 BGP)

    這是現代資料中心非常熱門的技術：

    * **原理**：利用 **RFC 5549 (ENHE)**，不需要在每個互聯介面上配置 IPv4 地址。
    * **優點**：節省大量的 IPv4 地址空間，簡化配置（Peer 直接建立在 IPv6 Link-local 地址上）。
    * **運作**：雖然介面沒有 IPv4，但仍可交換 IPv4 路由資訊，並自動計算下一跳的 MAC 地址。

5. 自治系統 (Autonomous System, AS)

    AS 是由單一管理實體控制的網路集合，擁有獨立的路由策略。

    * BGP 支援 16 位元和 32 位元 AS 編號。
    * **BGP 路由資訊**：交換的路由資訊包含目的地的路由前綴 (route prefix)、到達該目的地的自治系統路徑 (**AS path**)，以及多種額外的路徑屬性 (path attributes, PAs)。

    > ASN 64,512 到 65,534 是 16 位元 ASN 範圍內的私有 ASN，而 4,200,000,000 到 4,294,967,294 是擴展 32 位元範圍內的私有 ASN。

6. BGP 傳輸層與會話建立

    BGP 使用 **TCP 協議 (Port 179)** 作為可靠的傳輸協議，在 BGP 路由器（或稱為 BGP speakers）之間建立 TCP 連線會話。

    * **無自動發現機制**：BGP 鄰居關係必須透過手動配置來定義。
    * **路由交換**：當 TCP 連線建立後，BGP 對等體會先交換完整的 BGP 路由表；之後只傳送**增量更新** (incremental updates)。
    * **Keepalive 與 Hold Time**：在沒有路由更新時，BGP 對等體會交換 Keepalive 訊息以維持會話活躍。
      * **Hold Time** 是接收連續 BGP 更新或 Keepalive 訊息之間允許經過的最大時間限制。

      下面是 Cumulus 預設值，單位為秒

      ```bash
      $ nv show vrf default router bgp timers
                            operational  applied
      ---------------------  -----------  -------
      keepalive                           3
      hold                                9
      connection-retry                    10
      route-advertisement                 none
      conditional-advertise               60
      ```

    * **router id** 要在對等端之間建立 BGP 會話，BGP 必須具有路由器 ID，該 ID 會在建立 BGP 會話時通過 OPEN 消息發送給 BGP 對等端。
      * 如果 BGP 沒有路由器 ID，它無法與任何 BGP 鄰居建立對等連線

    > BGP session 是兩個 BGP 路由器之間建立的鄰接關係

7. BGP 鄰居狀態機 (Finite-State Machine, FSM)

    BGP 使用 FSM 來維護與所有 BGP 對等體的操作狀態。一個典型的 BGP 會話會經歷以下幾個關鍵狀態：

    1. **Idle**：初始狀態，嘗試啟動 TCP 連線。
    2. **Connect/Active**：嘗試建立 TCP 連線。
    3. **OpenSent/OpenConfirm**：交換 OPEN 訊息並協商能力，例如 BGP 版本、AS 編號和保持時間。
    4. **Established**：BGP 會話完全建立，開始透過 **UPDATE 訊息**交換路由資訊。

[nvidia | cumulus 5.12 | BGP](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-512/Layer-3/Border-Gateway-Protocol-BGP/)

## Lab

### BGP Numbered Lab

1. 分配自治系統編號 (ASN)：必須為該 BGP 節點分配一個 ASN。在兩層式的 Leaf-and-Spine 架構中，可以利用 auto BGP 功能讓 Cumulus Linux 自動分配 ASN。

2. Router ID
3. 設定 Neighbor 資訊
    * 需提供鄰居的 IP 地址與 ASN
    * 對於 BGP Numbered，IP 地址是指兩台對等體 (Peers) 之間連接介面的地址，且該介面必須是 Layer 3 存取埠 (Access Port)。
    * ASN 可以是具體數字，或使用 internal（代表同 AS 鄰居）或 external（代表不同 AS 鄰居）關鍵字。
4. 指定 Prefixes：明確指定要從此 BGP 節點發布出去的網路前綴


#### spine01

```yaml
- set:
    system:
      hostname: spine01
    interface:
      lo:
        ip:
          address:
            1.1.1.1/32: {}
      swp1:
        ip:
          address:
            10.0.0.0/31: {}
    router:
      bgp:
        enable: on
        autonomous-system: 65001
        router-id: 1.1.1.1
    vrf:
      default:
        router:
          bgp:
            address-family:
              ipv4-unicast:
                enable: on
                network:
                  1.1.1.1/32: {}
            enable: on
            neighbor:
              10.0.0.1:
                type: numbered
                remote-as: external
```

#### leaf01

```yaml
- set:
    system:
      hostname: Leaf01
    interface:
      lo:
        ip:
          address:
            2.2.2.2/32: {}
      swp1:
        ip:
          address:
            10.0.0.1/31: {}
    router:
      bgp:
        autonomous-system: 65002
        enable: on
        router-id: 2.2.2.2
    vrf:
      default:
        router:
          bgp:
            address-family:
              ipv4-unicast:
                enable: on
                network:
                  2.2.2.2/32: {}
            enable: on
            neighbor:
              10.0.0.0:
                remote-as: external
                type: numbered

```

根據 Spine 和 Leaf 配置，可以看到

1. 自治系統編號 (ASN) 分配

    * **Spine01**：設定為 `65001`。
    * **Leaf01**：設定為 `65002`。
    * 雙方互指鄰居時使用 `remote-as: external`，這符合兩者 ASN 不同（eBGP）的邏輯。

2. Router ID 設定

    * 手動指定了 **Router ID**，Spine 為 `1.1.1.1`，Leaf 為 `2.2.2.2`
    * 這兩個 ID 也分別對應了各自交換器的 Loopback 地址。

3. 鄰居 (Neighbor) 資訊

    * **使用 IP 地址**：Spine 指向 `10.0.0.1`，Leaf 指向 `10.0.0.0`，指定鄰居的 IP 地址。
    * **介面屬性**：雙方在 `swp1` 介面都配置了同一網段的 IPv4 地址（`10.0.0.0/31` 與 `10.0.0.1/31`），且明確標註 `type: numbered`。
    * **Layer 3 存取埠**：配置中為介面直接分配 IP，符合 BGP Numbered 必須在 L3 埠運行的要求。

4. 路由發布 (Prefix Origination)

    * 明確指定要從此節點向外發布 (Originate) 的網路前綴。雙方都在 `address-family ipv4-unicast` 下使用 `network` 指令發布了各自的 Loopback 地址（`1.1.1.1/32` 與 `2.2.2.2/32`）。

#### 驗證

1. 驗證 BGP 鄰居摘要狀態

    快速確認連線是否建立。

    ```bash
    Leaf01:mgmt:~$ sudo vtysh -c "show ip bgp summary"

    IPv4 Unicast Summary (VRF default):
    BGP router identifier 2.2.2.2, local AS number 65002 vrf-id 0
    BGP table version 2
    RIB entries 3, using 672 bytes of memory
    Peers 1, using 20 KiB of memory

    Neighbor          V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
    spine01(10.0.0.0) 4      65001      1754      1754        0    0    0 01:27:42            1        2 N/A

    Total number of neighbors 1

    ```

    **State/PfxRcd**：這是最重要的欄位。如果顯示 **數字**（例如 `1`），表示連線已成功建立（Established），且從該鄰居收到了多少條路由；如果顯示 **Active**、**Connect** 或 **Idle**，則表示連線尚未建立，通常是 IP 不通、ASN 設錯或防火牆阻擋。


2. 查看 BGP 路由表與路徑選擇

    如果想確認路由是否正確傳遞，以及 BGP 如何選路：

    ```bash
    Leaf01:mgmt:~$ sudo vtysh -c "show ip bgp"
    BGP table version is 2, local router ID is 2.2.2.2, vrf id 0
    Default local pref 100, local AS 65002
    Status codes:  s suppressed, d damped, h history, u unsorted, * valid, > best, = multipath, + multipath nhg,
                i internal, r RIB-failure, S Stale, R Removed
    Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
    Origin codes:  i - IGP, e - EGP, ? - incomplete
    RPKI validation codes: V valid, I invalid, N Not found

    Network          Next Hop            Metric LocPrf Weight Path
    *> 1.1.1.1/32       10.0.0.0(spine01)
                                                0             0 65001 i
    *> 2.2.2.2/32       0.0.0.0(Leaf01)          0         32768 i

    Displayed  2 routes and 2 total paths

    ```

    此指令會列出所有學到的 BGP 路由。路由前方的 `*` 代表有效（Valid），`>` 代表這是最佳路徑（Best Path）。可以看到各項屬性如 **Weight**、**Local Preference**、**AS_Path** 等，這些都是 BGP 進行路徑選擇的依據。

3. 查看特定鄰居的詳細資訊

    如果需要排除故障（例如查看為什麼能力協商失敗）：
    
    ```bash
    Leaf01:mgmt:~$ sudo vtysh -c "show ip bgp neighbor 10.0.0.0"
    BGP neighbor is 10.0.0.0, remote AS 65001, local AS 65002, external link
    Local Role: undefined
    Remote Role: undefined
    Hostname: spine01
    BGP version 4, remote router ID 1.1.1.1, local router ID 2.2.2.2
    BGP state = Established, up for 01:45:40
    Last read 00:00:01, Last write 00:00:01
    Hold time is 9 seconds, keepalive interval is 3 seconds
    Configured hold time is 9 seconds, keepalive interval is 3 seconds
    Configured conditional advertisements interval is 60 seconds
    Neighbor capabilities:
        4 Byte AS: advertised and received
        Extended Message: advertised and received
        AddPath:
        IPv4 Unicast: RX advertised and received
        Long-lived Graceful Restart: advertised and received
        Address families by peer:
        Route refresh: advertised and received(old & new)
        Enhanced Route Refresh: advertised and received
        Address Family IPv4 Unicast: advertised and received
        Hostname Capability: advertised (name: Leaf01,domain name: n/a) received (name: spine01,domain name: n/a)
        Graceful Restart Capability: advertised and received
        Remote Restart timer is 120 seconds
        Address families by peer:
                Graceful Restart Capability: advertised and received
        Remote Restart timer is 120 seconds
        Address families by peer:
            none
    Graceful restart information:
        End-of-RIB send: IPv4 Unicast
        End-of-RIB received: IPv4 Unicast
        Local GR Mode: Helper*
        Remote GR Mode: Helper

        R bit: False
        N bit: False
        Timers:
        Configured Restart Time(sec): 120
        Received Restart Time(sec): 120
        IPv4 Unicast:
        F bit: False
        End-of-RIB sent: Yes
        End-of-RIB sent after update: Yes
        End-of-RIB received: Yes
        Timers:
            Configured Stale Path Time(sec): 360
    Message statistics:
        Inq depth is 0
        Outq depth is 0
                            Sent       Rcvd
        Opens:                  1          1
        Notifications:          0          0
        Updates:                3          3
        Keepalives:          2109       2109
        Route Refresh:          0          0
        Capability:             0          0
        Total:               2113       2113
    Minimum time between advertisement runs is 0 seconds

    For address family: IPv4 Unicast
    Update group 1, subgroup 1
    Packet Queue length 0
    Community attribute sent to this neighbor(all)
    1 accepted prefixes

    Connections established 1; dropped 0
    Last reset 01:45:41,  Waiting for peer OPEN
    External BGP neighbor may be up to 1 hops away.
    Local host: 10.0.0.1, Local port: 54890
    Foreign host: 10.0.0.0, Foreign port: 179
    Nexthop: 10.0.0.1
    Nexthop global: fe80::e60:5dff:fef7:1
    Nexthop local: fe80::e60:5dff:fef7:1
    BGP connection: shared network
    BGP Connect Retry Timer in Seconds: 10
    Estimated round trip time: 3 ms
    Read thread: on  Write thread: on  FD used: 59

    ```

    這會顯示該鄰居的詳細狀態、BGP 版本、保持時間（Hold Time）以及各項能力的協商狀況。

4. 使用 NVUE 查看

    * **查看 BGP 整體狀態**

    ```bash
    $ nv show router bgp            applied
    ------------------------------  -----------
    enable                          on
    autonomous-system               65002
    router-id                       2.2.2.2
    policy-update-timer             5
    graceful-shutdown               off
    wait-for-install                off
    graceful-restart
    mode                          helper-only
    restart-time                  120
    path-selection-deferral-time  360
    stale-routes-time             360
    convergence-wait
    time                          0
    establish-wait-time           0
    queue-limit
    input                         10000
    output                        10000

    ```

    * **查看特定 VRF 的鄰居**：

    ```bash
    Leaf01:mgmt:~$ nv show vrf default router bgp neighbor

    AS - Remote Autonomous System, PeerEstablishedTime - Peer established time in
    UTC format, UpTime - Last connection reset time in days,hours:min:sec, Afi-Safi
    - Address family, PfxSent - Transmitted prefix counter, PfxRcvd - Recieved
    prefix counter

    Neighbor  AS     State        PeerEstablishedTime   UpTime   MsgRcvd  MsgSent  Afi-Safi      PfxSent  PfxRcvd
    --------  -----  -----------  --------------------  -------  -------  -------  ------------  -------  -------
    10.0.0.0  65001  established  2026-02-10T03:31:12Z  1:47:49  2155     2155     ipv4-unicast  2        1
    ```

    * **檢查 BGP 路由表 (RIB)**

    ```bash
    Leaf01:mgmt:~$ nv show vrf default router bgp address-family ipv4-unicast route

    PathCount - Number of paths present for the prefix, MultipathCount - Number of
    paths that are part of the ECMP, DestFlags - * - bestpath-exists, w - fib-wait-
    for-install, s - fib-suppress, i - fib-installed, x - fib-install-failed

    Prefix      PathCount  MultipathCount  DestFlags
    ----------  ---------  --------------  ---------
    1.1.1.1/32  1          1               *
    2.2.2.2/32  1          1               *
    ```

5. 使用 ping

    ```bash
    Leaf01:mgmt:~$ ping 10.0.0.0 -c 2
    vrf-wrapper.sh: switching to vrf "default"; use '--no-vrf-switch' to disable
    PING 10.0.0.0 (10.0.0.0) 56(84) bytes of data.
    64 bytes from 10.0.0.0: icmp_seq=1 ttl=64 time=0.616 ms
    64 bytes from 10.0.0.0: icmp_seq=2 ttl=64 time=0.479 ms

    --- 10.0.0.0 ping statistics ---
    2 packets transmitted, 2 received, 0% packet loss, time 1009ms
    rtt min/avg/max/mdev = 0.479/0.547/0.616/0.068 ms
    ```

### BGP Unnumbered Lab

#### spine01 與 spine02

spine01

```yaml
- set:
    system:
      hostname: spine1
    interface:
      lo:
        ip:
          address:
            10.0.0.101/32: {}
      swp1: {}
      swp2: {}
    router:
      bgp:
        enable: on
        autonomous-system: 65000
        router-id: 10.0.0.101
    vrf:
      default:
        router:
          bgp:
            enable: on
            address-family:
              ipv4-unicast:
                enable: on
                network:
                  10.0.0.101/32: {} # 發布自己的 Loopback 路由
            neighbor:
              swp1:
                type: unnumbered
                remote-as: external # 使用 external 關鍵字簡化 ASN 管理
              swp2:
                type: unnumbered
                remote-as: external
```

spine02

```yaml
- set:
    system:
      hostname: spine2
    interface:
      lo:
        ip:
          address:
            10.0.0.102/32: {}
      swp1: {}
      swp2: {}
    router:
      bgp:
        enable: on
        autonomous-system: 65000
        router-id: 10.0.0.102
    vrf:
      default:
        router:
          bgp:
            enable: on
            address-family:
              ipv4-unicast:
                enable: on
                network:
                  10.0.0.102/32: {} # 發布自己的 Loopback 路由
            neighbor:
              swp1:
                type: unnumbered
                remote-as: external # 使用 external 關鍵字簡化 ASN 管理
              swp2:
                type: unnumbered
                remote-as: external

```

#### leaf01 與 leaf02

leaf01
```yaml
- set:
    system:
      hostname: leaf1
    interface:
      lo:
        ip:
          address:
            10.0.0.1/32: {}
      swp1: {}
      swp2: {}
    router:
      bgp:
        enable: on
        autonomous-system: 65001
        router-id: 10.0.0.1
    vrf:
      default:
        router:
          bgp:
            enable: on
            address-family:
              ipv4-unicast:
                enable: on
                network:
                  10.0.0.1/32: {}
            neighbor:
              swp1:
                type: unnumbered
                remote-as: external
              swp2:
                type: unnumbered
                remote-as: external

```

leaf02

```yaml
- set:
    system:
      hostname: leaf2
    interface:
      lo:
        ip:
          address:
            10.0.0.2/32: {}
      swp1: {}
      swp2: {}
    router:
      bgp:
        enable: on
        autonomous-system: 65002
        router-id: 10.0.0.2
    vrf:
      default:
        router:
          bgp:
            enable: on
            address-family:
              ipv4-unicast:
                enable: on
                network:
                  10.0.0.2/32: {}
            neighbor:
              swp1:
                type: unnumbered
                remote-as: external
              swp2:
                type: unnumbered
                remote-as: external
```


#### 驗證

1. 確認鄰居連線狀態

    spine01:

    ```bash
    ~$ sudo vtysh -c "show ip bgp summary"

    IPv4 Unicast Summary (VRF default):
    BGP router identifier 10.0.0.101, local AS number 65000 vrf-id 0
    BGP table version 3
    RIB entries 5, using 1120 bytes of memory
    Peers 2, using 40 KiB of memory

    Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
    leaf1(swp1)     4      65001       587       587        0    0    0 00:29:06            1        3 N/A
    leaf2(swp2)     4      65002       585       584        0    0    0 00:28:59            1        3 N/A

    Total number of neighbors 2
    ```

    leaf2:

    ```bash
    $ sudo vtysh -c "show ip bgp summary"

    IPv4 Unicast Summary (VRF default):
    BGP router identifier 10.0.0.2, local AS number 65002 vrf-id 0
    BGP table version 5
    RIB entries 7, using 1568 bytes of memory
    Peers 2, using 40 KiB of memory

    Neighbor        V         AS   MsgRcvd   MsgSent   TblVer  InQ OutQ  Up/Down State/PfxRcd   PfxSnt Desc
    spine2(swp1)    4      65000       621       623        0    0    0 00:30:51            2        4 N/A
    spine1(swp2)    4      65000       606       608        0    0    0 00:30:06            2        4 N/A

    Total number of neighbors 2
    ```

    在 State/PfxRcd 欄位應顯示收到的路由數量（數字），若顯示 Active 或 Idle 則表示連線失敗。

2. 查看 BGP 路由表與選路

    spine01

    ```bash
    $ sudo vtysh -c "show ip bgp"
    BGP table version is 3, local router ID is 10.0.0.101, vrf id 0
    Default local pref 100, local AS 65000
    Status codes:  s suppressed, d damped, h history, u unsorted, * valid, > best, = multipath, + multipath nhg,
                i internal, r RIB-failure, S Stale, R Removed
    Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
    Origin codes:  i - IGP, e - EGP, ? - incomplete
    RPKI validation codes: V valid, I invalid, N Not found

    Network          Next Hop            Metric LocPrf Weight Path
    *> 10.0.0.1/32      swp1                     0             0 65001 i
    *> 10.0.0.2/32      swp2                     0             0 65002 i
    *> 10.0.0.101/32    0.0.0.0(spine1)          0         32768 i

    Displayed  3 routes and 3 total paths
    ```

    leaf02

    ```bash
    $ sudo vtysh -c "show ip bgp"
    BGP table version is 5, local router ID is 10.0.0.2, vrf id 0
    Default local pref 100, local AS 65002
    Status codes:  s suppressed, d damped, h history, u unsorted, * valid, > best, = multipath, + multipath nhg,
                i internal, r RIB-failure, S Stale, R Removed
    Nexthop codes: @NNN nexthop's vrf id, < announce-nh-self
    Origin codes:  i - IGP, e - EGP, ? - incomplete
    RPKI validation codes: V valid, I invalid, N Not found

    Network          Next Hop            Metric LocPrf Weight Path
    *> 10.0.0.1/32      swp1                                   0 65000 65001 i
    *=                  swp2                                   0 65000 65001 i
    *> 10.0.0.2/32      0.0.0.0(leaf2)           0         32768 i
    *> 10.0.0.101/32    swp2                     0             0 65000 i
    *> 10.0.0.102/32    swp1                     0             0 65000 i

    Displayed  4 routes and 5 total paths
    ```

    確認是否有從鄰居學到的路由，即 lookback 都被學習到。`*>` 代表最佳路徑選擇。

3. 驗證系統路由表

    leaf02

    ```bash
    $ sudo vtysh -c "show ip route"
    Codes: K - kernel route, C - connected, S - static, R - RIP,
        O - OSPF, I - IS-IS, B - BGP, E - EIGRP, N - NHRP,
        T - Table, A - Babel, D - SHARP, F - PBR, f - OpenFabric,
        Z - FRR,
        > - selected route, * - FIB route, q - queued, r - rejected, b - backup
        t - trapped, o - offload failure

    B>* 10.0.0.1/32 [20/0] via fe80::e49:82ff:fef7:1, swp1, weight 1, 00:43:14
    *                    via fe80::e92:7eff:fe37:2, swp2, weight 1, 00:43:14
    C>* 10.0.0.2/32 is directly connected, lo, 00:44:56
    B>* 10.0.0.101/32 [20/0] via fe80::e92:7eff:fe37:2, swp2, weight 1, 00:43:14
    B>* 10.0.0.102/32 [20/0] via fe80::e49:82ff:fef7:1, swp1, weight 1, 00:43:59
    ```

    確認 BGP 學到的路由是否已成功學習到路由表中，BGP 會標示為 B 路由。

4. 透過 ping 確認連通

    leaf2 ping leaf1

    ```bash
    $ ping 10.0.0.1 -c 2
    vrf-wrapper.sh: switching to vrf "default"; use '--no-vrf-switch' to disable
    PING 10.0.0.1 (10.0.0.1) 56(84) bytes of data.
    64 bytes from 10.0.0.1: icmp_seq=1 ttl=63 time=1.49 ms
    64 bytes from 10.0.0.1: icmp_seq=2 ttl=63 time=1.16 ms

    --- 10.0.0.1 ping statistics ---
    2 packets transmitted, 2 received, 0% packet loss, time 1003ms
    rtt min/avg/max/mdev = 1.155/1.324/1.493/0.169 ms
    ```

#### 封包觀察

目標是觀察 BGP Messages 類型，來看如何建立與維護 Peer 關係時使用的訊息。

下圖是 BGP Header，當中紅色區塊是下面類型共同的。

![](https://suj0140.wordpress.com/wp-content/uploads/2015/04/2.png)

1. Marker (16 bytes)
  主要用於 同步 (Synchronization) 與 認證 (Authentication)。它幫助接收端路由器在 TCP 資料流中定位 BGP 訊息的起始位置。如果沒有使用特殊的認證機制，此欄位通常會被填滿全為「1」的位元。

2. Length (2 bytes)
  指示該 BGP 訊息的 總位元組長度。此長度包含了標頭本身（19 bytes）加上後續所有的資料負載 (Payload)。由於標頭固定為 19 bytes，因此訊息最小長度為 19 (例如 Keepalive 訊息)，最大長度通常限制在 4096 bytes。

3. Type (1 byte)
  用來區分此訊息屬於哪一種 BGP 訊息類型。常見類型值：

* Open: 用於開啟會話並建立鄰居關係。值為 1。
* Update: 用於傳遞、更新或撤銷路由資訊。值為 2。
* Notification: 當偵測到錯誤時發送，通常會導致連線中斷。值為 3。
* Keepalive: 週期性發送，用來確認鄰居路由器仍處於活動狀態。值為 4。

##### BGP 訊息類型

1. Open: 用於發起連線

  ```bash
    0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                                                               |
  +                                                               +
  |                                                               |
  +                      Marker (16 bytes)                        +
  |                 (用於同步與認證，通常為全 1)                   |
  +                                                               +
  |                                                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |          Length (2 bytes)     | Type (1 byte) |
  |      (含標頭總長，最小 29)      |  (Open = 1)   |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |    Version    |     My Autonomous System      |   Hold Time   |
  |   (BGP 版本)   |        (本機的 AS 號碼)        |  (保持時間)   |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                         BGP Identifier                        |
  |                        (通常為 Router ID)                      |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  | Opt Parm Len  |                                               |
  | (選用參數長度) |         Optional Parameters (variable)        |
  +-+-+-+-+-+-+-+-+                                               |
  |                                                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  ```
  
  封包 314，會和對方交換 `Version`、`My AS`、`Hold Time`、`BGP Identifier` 等訊息。

  ```
  Border Gateway Protocol - OPEN Message
      Marker: ffffffffffffffffffffffffffffffff
      Length: 107
      Type: OPEN Message (1) # 用於開啟會話並建立鄰居關係
      Version: 4
      My AS: 65002
      Hold Time: 9
      BGP Identifier: 10.0.0.2
      Optional Parameters Length: 78
      Optional Parameters
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 6
              Capability: Multiprotocol extensions capability
                  Type: Multiprotocol extensions capability (1)
                  Length: 4
                  AFI: IPv4 (1)
                  Reserved: 00
                  SAFI: Unicast (1)
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 8
              Capability: Extended Next Hop Encoding
                  Type: Extended Next Hop Encoding (5)
                  Length: 6
                  AFI: IPv4 (1)
                  SAFI: Unicast (1)
                  Next hop AFI: IPv6 (2)
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 2
              Capability: Route Refresh Capability (Cisco)
                  Type: Route Refresh Capability (Cisco) (128)
                  Length: 0
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 2
              Capability: Route refresh capability
                  Type: Route refresh capability (2)
                  Length: 0
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 2
              Capability: Enhanced route refresh capability
                  Type: Enhanced route refresh capability (70)
                  Length: 0
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 6
              Capability: Support for 4-octet AS number capability
                  Type: Support for 4-octet AS number capability (65)
                  Length: 4
                  AS Number: 65002
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 2
              Capability: BGP-Extended Message
                  Type: BGP-Extended Message (6)
                  Length: 0
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 6
              Capability: Support for Additional Paths
                  Type: Support for Additional Paths (69)
                  Length: 4
                  AFI: IPv4 (1)
                  SAFI: Unicast (1)
                  Send/Receive: Receive (1)
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 9
              Capability: FQDN Capability
                  Type: FQDN Capability (73)
                  Length: 7
                  Hostname Length: 5
                  Hostname: leaf2
                  Domain Name Length: 0
                  Domain Name: 
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 4
              Capability: Graceful Restart capability
                  Type: Graceful Restart capability (64)
                  Length: 2
                  Restart Timers: 0x0078
                      0... .... .... .... = Restart state: No
                      .0.. .... .... .... = Graceful notification: No
                      .... 0000 0111 1000 = Time: 120
          Optional Parameter: Capability
              Parameter Type: Capability (2)
              Parameter Length: 9
              Capability: Long-Lived Graceful Restart (LLGR) Capability
                  Type: Long-Lived Graceful Restart (LLGR) Capability (71)
                  Length: 7
                  Unknown: 00010180000000
  ```

2. Keepalive: 用於確認鄰居是否還在線上

  ```bash
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                                                               |
  +                                                               +
  |                                                               |
  +                      Marker (16 bytes)                        +
  |                (用於同步與認證，通常為全 1)                   |
  +                                                               +
  |                                                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |          Length (2 bytes)     | Type (1 byte) |
  |          (固定值為 19)        | (Keepalive=4) |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  ```

  週期性發送，用來向鄰居確認自己仍活著且連線正常。發送頻率再 cumulus 是 3 秒。

  ```bash
  Border Gateway Protocol - KEEPALIVE Message
      Marker: ffffffffffffffffffffffffffffffff
      Length: 19
      Type: KEEPALIVE Message (4)
  ```

3. Update: 用於交換路徑資訊

  ```bash
    0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                                                               |
  +                                                               +
  |                                                               |
  +                      Marker (16 bytes)                        +
  |                (用於同步與認證，通常為全 1)                   |
  +                                                               +
  |                                                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |          Length (2 bytes)     | Type (1 byte) |
  |      (含標頭總長，變動值)       |  (Update=2)   |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |   Withdrawn Routes Length (2 bytes) |
  +-------------------------------------+-------------------------+
  |    Withdrawn Routes (variable)      | (要撤銷的路由列表)
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |   Total Path Attribute Length (2 bytes) |
  +-----------------------------------------+---------------------+
  |    Path Attributes (variable)           | (路徑屬性，如 AS-Path)
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |    Network Layer Reachability Information (variable)          |
  |    (NLRI，即目的地網路位址列表)                                |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  ```
  
  Update 訊息可以同時執行兩件事：
    * 撤銷舊路由： 告訴鄰居哪些路不能走了。
    * 宣布新路由： 告訴鄰居去哪些地方要經過哪個 Next Hop，且具備哪些屬性。
  
  以下顯示封包 323 部分內容

  ```bash
  Border Gateway Protocol - UPDATE Message
      Marker: ffffffffffffffffffffffffffffffff
      Length: 91
      Type: UPDATE Message (2)
      Withdrawn Routes Length: 0 # 沒有路由要被刪除
      Total Path Attribute Length: 68
      Path attributes
          Path Attribute - MP_REACH_NLRI
              Flags: 0x90, Optional, Extended-Length, Non-transitive, Complete
              Type Code: MP_REACH_NLRI (14)
              Length: 42
              Address family identifier (AFI): IPv4 (1)
              Subsequent address family identifier (SAFI): Unicast (1)
              Next hop: IPv6=fe80::e37:3fff:feb5:2 Link-local=fe80::e37:3fff:feb5:2 # 流量下一步該送往哪個 IP 介面
                  IPv6 Address: fe80::e37:3fff:feb5:2
                  Link-local Address: fe80::e37:3fff:feb5:2
              Number of Subnetwork points of attachment (SNPA): 0
              Network Layer Reachability Information (NLRI)
          Path Attribute - ORIGIN: IGP # 標示此路由是由內部手動或協定產生
              Flags: 0x40, Transitive, Well-known, Complete
              Type Code: ORIGIN (1)
              Length: 1
              Origin: IGP (0)
          Path Attribute - AS_PATH: 65002 65000 65001 # 路由經過的歷程，用來防止環路與選路
              Flags: 0x50, Transitive, Extended-Length, Well-known, Complete
              Type Code: AS_PATH (2)
              Length: 14
              AS Path segment: 65002 65000 65001

  ```

4. Notification: 用於報告錯誤並關閉連線

  ```bash
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |                                                               |
  +                                                               +
  |                                                               |
  +                      Marker (16 bytes)                        +
  |                (用於同步與認證，通常為全 1)                   |
  +                                                               +
  |                                                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  |          Length (2 bytes)     | Type (1 byte) |
  |      (含標頭總長，最小 21)      | (Notification=3) |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  | Error Code (1)| Error Subcode |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-------------------------------+
  |                                                               |
  |            Data (variable，用於診斷錯誤的數據)                   |
  |                                                               |
  +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
  ```

## 總結

BGP 是一種**路徑向量路由演算法** (path-vector routing algorithm)，主要用於在不同的自治系統 (Autonomous Systems, AS) 之間交換路由資訊，其設計目標是確定到達特定目的地的最佳路徑，同時確保網路中不會出現路由迴圈。不像鏈路狀態路由協議那樣包含網路的完整拓撲。BGP 中 AS_Path 用作迴路防止機制。

BGP peer 是什麼 ? 為了交換路由資訊而建立起*鄰居關係*或*會話（Session）*的 BGP 路由器。會有三大要素

* BGP Session
* Session Establishment
* BGP Messages

下表是 BGP Numbered 與 BGP Unnumbered 的比較

|特性|BGP Numbered|BGP Unnumbered|
|---|---|---|
|接口 IP 分配|每個互聯接口都需要 IPv4 地址|接口不需要 IPv4 地址（僅需 Loopback）|
|鄰居定義方式|指定鄰居的 IP 地址|指定接口名稱 (如 swp1)|
|擴展性|規模越大，IP 地址管理越痛苦|極佳，適合大規模數據中心 (Clos 拓撲)|
|地址族支持|IPv4 或 IPv6|可在 IPv6 承載上交換 IPv4/IPv6 路由|
|主要協議基礎|標準 BGP|IPv6 Link-Local + RFC 5549/8950|

> 如果需要連接外部防火牆、舊款交換機或服務商，考慮使用 BGP Numbered，因為這些第三方設備往往不支持透過 IPv6 Link-Local 來交換 IPv4 路由。
