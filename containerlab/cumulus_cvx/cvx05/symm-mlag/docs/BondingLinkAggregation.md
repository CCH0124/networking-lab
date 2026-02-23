# [Bonding Link Aggregation](https://docs.nvidia.com/networking-ethernet-software/cumulus-linux-514/Layer-2/Bonding-Link-Aggregation/)

「Linux bonding (網路綁定) 提供了一種將多個網路介面 (稱為 slave) 聚合成單一邏輯綁定介面 (稱為 bond) 的方法。鏈路聚合 (Link aggregation) 對於**線性擴展頻寬**、**負載平衡**和**容錯保護 (failover)** 非常有用。

Cumulus Linux 支援兩種 bonding 模式：

1.  **IEEE 802.3ad (LACP 模式)**：
    此模式將一個或多個鏈路組合成一個『鏈路聚合群組 (LAG)』，以便 MAC (媒體存取控制) 客戶端能將該群組視為單一鏈路。IEEE 802.3ad 鏈路聚合是**預設模式**。

2.  **Balance-xor 模式**：
    此模式會根據雜湊 (hashed) 過的協定標頭資訊，將傳出的流量平衡地分佈到活躍的埠口 (active ports)，並從任何活躍的埠口接受傳入的流量。所有的 slave 介面都會處於活躍狀態，以進行負載平衡和容錯。**此模式對於 MLAG (Multi-Chassis Link Aggregation) 部署很有用**。

這段在講我們常說的「Port-Channel」或「LAG」在 Linux 上的實作 (Bonding)，以及 Cumulus 的兩種主要玩法。

1.  **Bonding 是什麼？**
    * 就是把好幾條實體網路線 (slaves) 綁(bind)成一條邏輯上的大水管 (bond)。
    * **三大好處**：頻寬疊加、流量負載平衡、斷線容錯 (failover)。

2.  **模式一：802.3ad (LACP) - 標準模式**
    * 這就是我們最熟悉的 **LACP** (Link Aggregation Control Protocol)。
    * 它需要**雙邊**（交換器和伺服器）都設定 LACP 協商。
    * 這是 Cumulus Linux 上的**預設模式**。如果你建立一個 bond 卻不指定模式，它預設就是 802.3ad。

3.  **模式二：Balance-xor - 特殊模式 (for MLAG)**
    * 這是一種**靜態 (static)** 的綁定模式，它**不使用 LACP 協定**。
    * 它的負載平衡方式是靠自己算 Hash (XOR 演算法) 來決定封包走哪條路。
    * **[關鍵]**：Cumulus **特別指出**這個模式在 **MLAG** 環境中很有用。
    * **當你設定 MLAG 時，你的 Bond (Port-Channel) 是跨在**兩台不同的實體交換器上。在這種架構下，使用 `balance-xor` 模式可以提供更穩定、可預測的流量分佈和容錯，而不需要依賴 LACP 協商。

> Cumulus 支援標準的 LACP (802.3ad) 當作預設值。但如果要設定 MLAG，官方建議考慮使用 `balance-xor` 模式。

## Create Bound

![](https://docs.nvidia.com/networking-ethernet-software/images/cumulus-linux/bonding-example1.png)

Linux

```bash
auto bond1
iface bond1
    bond-slaves swp1
    bond-mode 802.3ad # 預設

auto peerlink
iface peerlink
    bond-slaves swp49 swp50
```
NVUE

```yaml
    interface:
      bond1:
        bond:
          lacp-bypass: on
          member:
            swp1: {} #
...
      peerlink:
        bond:
          member:
            swp49: {}
            swp50: {}
        type: peerlink
```

- 如果 bond 介面名稱以 `bond` 開頭，VUE 自動將 interface 類型視為 bond。
- 不成為 `bridge` 的一部分，則必須指定 IP 位址。

```bash
# SLAVE
root@leaf01:/# ip link show
43: swp2@if44: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 9000 qdisc noqueue master bond2 state UP mode DEFAULT group default 
    link/ether aa:c1:ab:61:53:34 brd ff:ff:ff:ff:ff:ff link-netnsid 4
51: swp3@if52: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 9000 qdisc noqueue master bond3 state UP mode DEFAULT group default 
    link/ether aa:c1:ab:b8:ab:3a brd ff:ff:ff:ff:ff:ff link-netnsid 5
64: swp52@if65: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9216 qdisc noqueue state UP mode DEFAULT group default 
    link/ether aa:c1:ab:2c:d2:5f brd ff:ff:ff:ff:ff:ff link-netnsid 1
72: swp51@if71: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 9216 qdisc noqueue state UP mode DEFAULT group default 
    link/ether aa:c1:ab:8c:ab:0e brd ff:ff:ff:ff:ff:ff link-netnsid 2
77: swp49@if76: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 9216 qdisc noqueue master peerlink state UP mode DEFAULT group default 
    link/ether aa:c1:ab:f6:a9:1b brd ff:ff:ff:ff:ff:ff link-netnsid 6
81: swp50@if80: <BROADCAST,MULTICAST,SLAVE,UP,LOWER_UP> mtu 9216 qdisc noqueue master peerlink state UP mode DEFAULT group default 
    link/ether aa:c1:ab:f6:a9:1b brd ff:ff:ff:ff:ff:ff link-netnsid 6
...
# MASTER
root@leaf01:/# ip link show type bond
7: bond2: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 9000 qdisc noqueue master br_default state UP mode DORMANT group default qlen 1000
    link/ether aa:c1:ab:61:53:34 brd ff:ff:ff:ff:ff:ff
8: bond1: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 9000 qdisc noqueue master br_default state UP mode DORMANT group default qlen 1000
    link/ether aa:c1:ab:5a:4b:f4 brd ff:ff:ff:ff:ff:ff
9: peerlink: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 9216 qdisc noqueue master br_default state UP mode DEFAULT group default qlen 1000
    link/ether aa:c1:ab:f6:a9:1b brd ff:ff:ff:ff:ff:ff
10: bond3: <BROADCAST,MULTICAST,MASTER,UP,LOWER_UP> mtu 9000 qdisc noqueue master br_default state UP mode DORMANT group default qlen 1000
    link/ether aa:c1:ab:b8:ab:3a brd ff:ff:ff:ff:ff:ff
```

一個 bond (綁定介面) 內的所有 slave 介面 (成員介面) 都會使用與該 bond 相同的 MAC 位址。通常，你**第一個**加入 bond 的 slave 介面會『貢獻』出它的 MAC 位址，作為這個 bond 介面的 MAC 位址。這個 bond 的 MAC 位址，是所有離開 bond 流量的**來源 MAC 位址**，同時也提供了一個單一的**目標 MAC 位址**來接收送往 bond 的流量。如果你移除了那個 bond 從其衍生出 MAC 位址的 slave 介面（也就是第一個加入的介面），bond 介面將會發生 flapping (瞬斷/彈跳) 以更新 MAC 位址，這會對流量造成影響。

Bond 介面的「L2 身份」是怎麼來 ?

1.  **MAC 位址共用 (L2 身份)**
    * 一個 Bond (例如 `bond0`) 是一個「邏輯」介面，它底下可能綁了 `swp1`, `swp2` 兩條實體線路。
    * 為了讓外界（如另一台交換器）認為這是一條單一的鏈路，這三個介面 (`bond0`, `swp1`, `swp2`) 都**必須使用同一個 MAC 位址**。

2.  **MAC 位址來源 (誰說了算？)**
    * `bond0` 的 MAC 位址**不是**隨機產生的。
    * 它是「繼承」來的：預設規則是，**你第一個加入 bond 的 slave 介面** (e.g., `swp1`) 會把自己的 MAC 位址「捐」給 `bond0` 當作 MAC。

3.  **關鍵警告 (維運陷阱) ⚠️**
    * **情境**：你先加了 `swp1` (MAC: ...AA) 再加 `swp2` (MAC: ...BB)。此時 `bond0` 的 MAC 就是 `...AA`。
    * **問題**：如果這時你因為維護或故障，把 `swp1` (那個「捐贈者」) 從 bond 中移除了。
    * **後果**：`bond0` 失去了它的 MAC 來源。它**必須**換一個 MAC 位址（例如改用 `swp2` 的 `...BB`）。
    * **影響**：MAC 位址的變更對 L2 網路是大事。`bond0` 介面會強制 **flap (瞬斷一次)**，以便讓整個網路（尤其是對向交換器的 MAC table 和鄰居的 ARP table）重新學習它的新 MAC (`...BB`)。這個 flap 會造成**流量中斷**。

## Custom Hash

交換器透過基於封包雜湊計算將出站流量分配到 `bond` 中的某個 SLAVE 介面，從而在各個從屬介面之間實現負載平衡。

雜湊計算利用封包的標頭數據來選擇將封包傳輸到哪個從屬介面：

- 對於 IP 流量，交換器在計算時使用 IP 標頭中的來源和目的地欄位。
- 對於 IP 和 TCP 或 UDP 流量，交換器在雜湊計算中還會包含來源和目的地的埠號。

3. show bound info

```bash
root@leaf01:/# nv show interface bond1 link
                       operational        applied  description
---------------------  -----------------  -------  ----------------------------------------------------------------------
auto-negotiate         off                on       Link speed and characteristic auto negotiation
duplex                 full               full     Link duplex
fec                                       auto     Link forward error correction mechanism
mtu                    9000               9000     interface mtu
speed                  10G                auto     Link speed
dot1x
  mab                                     off      bypass MAC authentication
  parking-vlan                            off      VLAN for unauthorized MAC addresses
state                  up                 up       The state of the interface
stats
  carrier-transitions  1                           Number of times the interface state has transitioned between up and...
  in-bytes             181840 B                    total number of bytes received on the interface
  in-drops             2                           number of received packets dropped
  in-errors            0                           number of received packets with errors
  in-pkts              1502                        total number of packets received on the interface
  out-bytes            1867355738 B                total number of bytes transmitted out of the interface
  out-drops            11                          The number of outbound packets that were chosen to be discarded eve...
  out-errors           0                           The number of outbound packets that could not be transmitted becaus...
  out-pkts             26675399                    total number of packets transmitted out of the interface
mac                    aa:c1:ab:5a:4b:f4           MAC Address on an interface
```
