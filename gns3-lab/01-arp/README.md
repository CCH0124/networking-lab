# ARP 

想像一個情境，你要寄信給鄰居。你住在一個社區裡，你知道你的鄰居叫做「小明」（這就像是他的 IP 位址，網路世界中的地址）。但是，郵差送信不是看名字，而是要看門牌號碼，例如「中山路 100 號」（這就像是網卡的 MAC 位址，獨一無二的硬體身分證號碼）。你只知道他的名字「小明」，卻不知道他的門牌號碼，信就送不出去。這時候你該怎麼辦？最簡單的方法就是跑到社區的廣播站大喊：「請問誰是『小明』？可以告訴我你家的門牌號碼嗎？」
這時候，社區裡所有人都聽到了。小華、小美、小王聽到了，但發現不是在叫自己，就默默不理會。「小明」本人聽到了，就走過來跟你說：「我就是小明，我家門牌是『中山路 100 號』。」太好了！現在你知道「小明」就住在「中山路 100 號」，你把門牌號碼寫在信封上，郵差就能順利把信送達了。

ARP 就是網路世界的這個「廣播問路」過程。ARP (Address Resolution Protocol) 的中文是「位址解析協定」。它的工作就跟上面那個廣播問路的例子一模一樣。在網路世界裡：

1. IP 位址 (IP Address)：像是人的「名字」。它是在網路上識別一台設備的地址，可以變動（你搬家了，地址就變了）。例如：192.168.1.10

2. MAC 位址 (MAC Address)：像是人的「身分證號碼」。它是網路卡出廠時就焊死的，全球獨一無二，基本上不會改變。例如：A1-B2-C3-D4-E5-F6

    當你的電腦 (A) 想要傳送資料給同一個區域網路（例如：同一個 Wi-Fi）裡的另一台電腦 (B) 時：

    電腦 A 只知道電腦 B 的 IP 位址（名字）。但是，在區域網路內，設備間的實際溝通是靠 MAC 位址（身分證號碼）來進行的。這時候電腦 A 就需要 ARP 來幫忙。

    ARP 基本上的工作四步驟:

    1. 先查紀錄 (ARP Cache)
    2. 發出廣播 (ARP Request)

    如果紀錄裡沒有，電腦會對整個區域網路發出一個「廣播」封包，就像在社區大喊一樣。這個封包的內容是：「請問 IP 位址是 192.168.1.1 的是誰？請告訴我你的 MAC 位址。我的 IP 是 192.168.1.100，我的 MAC 位址是 AA-AA-AA-AA-AA-AA。」

3. 目標回應 (ARP Reply)

    網路上所有其他設備（路由器、其他電腦、手機...）都收到了這個廣播。它們檢查了一下 IP 位址，發現不是在找自己，就丟掉這個封包不理它。
    只有 PC1 發現這個廣播是在問自己的 IP (192.168.1.1)，於是它就會準備一個「單點傳送」的封包，直接回覆給電腦 Debian。這個封包的內容是：
    「嗨！我就是 192.168.1.1，我的 MAC 位址是 BB-BB-BB-BB-BB-BB。」

4. 更新筆記本並開始通訊

    Debian 收到 PC1 的回覆後，非常開心。它立刻在自己的小本本 (ARP 快取) 記下：192.168.1.1 對應的 MAC 位址是 BB-BB-BB-BB-BB-BB。現在，Debian 知道了目標的「門牌號碼」，就可以開始正式地將資料傳送給 PC1 了。

## 環境設定

設定裝置的 IP

1. PC1

    ```bash
    ip 192.168.1.1
    ```

2. PC2

    ```bash
    ip 192.168.1.2
    ```

3. Debian

    ```bash
    $ sudo vi /etc/network/interfaces

    auto enp2s0
    iface enp2s0 inet static
            address 192.168.1.100
            netmask 255.255.255.0
            gateway 192.168.1.254
    #       dns-nameservers 192.168.1.1
    $ systemctl restart networking.service
    $ ip add
    1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
        link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
        inet 127.0.0.1/8 scope host lo
        valid_lft forever preferred_lft forever
        inet6 ::1/128 scope host noprefixroute
        valid_lft forever preferred_lft forever
    2: enp2s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
        link/ether 0c:46:97:61:00:00 brd ff:ff:ff:ff:ff:ff
        inet 192.168.1.100/24 brd 192.168.1.255 scope global enp2s0
        valid_lft forever preferred_lft forever
        inet6 fe80::e46:97ff:fe61:0/64 scope link
        valid_lft forever preferred_lft forever
    ```

    互相 ping，switch 就會記錄 MAC address，相對的機器也會有。

    ```bash
    Switch>show mac address-table
            Mac Address Table
    -------------------------------------------

    Vlan    Mac Address       Type        Ports
    ----    -----------       --------    -----
    1    0050.7966.6801    DYNAMIC     Gi0/1
    1    0c46.9761.0000    DYNAMIC     Gi0/2
    Total Mac Addresses for this criterion: 2
    Switch>
    ```

### Lab

1. ARP 表查詢

    只要機器有進行網路上的溝通，基本上會被記錄，即 MAC Address 和 IP 的對應，可以使用 `arp`  進行查看

    ```bash
    PC2> arp

    0c:46:97:61:00:00  192.168.1.100 expires in 115 seconds
    00:50:79:66:68:01  192.168.1.2 expires in 113 seconds

    ```

    ```bash
    debian@debian:~$ ip neigh show
    192.168.1.2 dev enp2s0 lladdr 00:50:79:66:68:01 STALE
    192.168.1.1 dev enp2s0 lladdr 00:50:79:66:68:02 STALE
    ```

    > ARP 是一個暫時性的紀錄，當過了一段時間就會被清空，此時就要重新尋找。

2. ARP 通訊協定觀察

    當 PC1 的 ARP table 為空時，透過 debian 服務對 PC1 進行網路上的 ping 時，會如下圖發現有 ARP 協定詢問動作。

    ![alt text](images/arp.png)

    debian 請求 PC1

    可以注意此請求，`Destination` 是不明確的 MAC Address，因此會用 FF:FF:FF:FF:FF:FF 作為值，進行全域請求。

    ```bash
    Frame 42: 42 bytes on wire (336 bits), 42 bytes captured (336 bits) on interface -, id 0
    Ethernet II, Src: 0c:46:97:61:00:00 (0c:46:97:61:00:00), Dst: Private_66:68:02 (00:50:79:66:68:02)
        Destination: Private_66:68:02 (00:50:79:66:68:02)
        Source: 0c:46:97:61:00:00 (0c:46:97:61:00:00)
        Type: ARP (0x0806)
        [Stream index: 2]
    Address Resolution Protocol (request)
        Hardware type: Ethernet (1)
        Protocol type: IPv4 (0x0800)
        Hardware size: 6
        Protocol size: 4
        Opcode: request (1)
        Sender MAC address: 0c:46:97:61:00:00 (0c:46:97:61:00:00)
        Sender IP address: 192.168.1.100
        Target MAC address: 00:00:00_00:00:00 (00:00:00:00:00:00)
        Target IP address: 192.168.1.1
    ```

    PC1 回應 debian 請求 

    ```bash
    Frame 43: 42 bytes on wire (336 bits), 42 bytes captured (336 bits) on interface -, id 0
    Ethernet II, Src: Private_66:68:02 (00:50:79:66:68:02), Dst: 0c:46:97:61:00:00 (0c:46:97:61:00:00)
        Destination: 0c:46:97:61:00:00 (0c:46:97:61:00:00)
        Source: Private_66:68:02 (00:50:79:66:68:02)
        Type: ARP (0x0806)
        [Stream index: 2]
    Address Resolution Protocol (reply)
        Hardware type: Ethernet (1)
        Protocol type: IPv4 (0x0800)
        Hardware size: 6
        Protocol size: 4
        Opcode: reply (2)
        Sender MAC address: Private_66:68:02 (00:50:79:66:68:02)
        Sender IP address: 192.168.1.1
        Target MAC address: 0c:46:97:61:00:00 (0c:46:97:61:00:00)
        Target IP address: 192.168.1.100
    ```

    要知道 ARP 的封包結構，可參考 [ARP | WIKI](https://en.wikipedia.org/wiki/Address_Resolution_Protocol)。