# Border Gateway Protocol - BGP

BGP 是網際網路的路由協定，它透過交換路由資訊和可達性資訊來管理資料包在網路間的路由方式。

從官方文件中可以看到 BGP 四大重點

1. BGP 基礎與自動化 (Auto BGP)

    * **核心機制**：BGP 透過交換路由與可達性資訊來管理網路流量，常用於資料中心的 **Clos 拓樸**。
    * **自治系統 (AS)**：每個管理單位擁有唯一的 ASN。私有 ASN 範圍為 `64512` - `65535`。
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