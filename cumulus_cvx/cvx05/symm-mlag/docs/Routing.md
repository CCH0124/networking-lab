# Routing

## Static Routing
##### 1. 核心定義：完全「手動」的路由
* **靜態路由 (Static Routing)** 是最陽春的路由方式。
* 它**沒有**任何技巧。你（網路管理員）必須**手動**、明確地告訴路由器：「你要去 `A 網路`，請把封包丟給 `B 閘道`」。
* 路由器**不會**自己思考，它只會「照單轉發」。

##### 2. 運作方式
* 交換器 (L3) 收到一個 IP 封包。
* 它會查詢它的「路由表 (Routing Table)」。
* 如果它在表裡找到一筆符合的「靜態」條目（你手動設定的），它就會把封包往那個條目指定的「下一跳 (Next Hop)」丟過去。
* 如果找不到，就丟給「預設閘道 (Default Gateway)」（如果有的話），再不然就丟棄 (drop)。

##### 3. 適用時機 (Pros)
* **① 簡單、可預測**：設定單純，流量路徑固定，容易偵錯。
* **② 資源消耗低**：不需要跑 BGP/OSPF 那些複雜的協定，不佔 CPU/RAM。
* **③ 適用場景**：
    * **末端網路 (Stub Network)**：例如一個只有單一出口的小型辦公室或分支機構。
    * **特定路由**：當你「故意」要讓某個流量走特定路徑時。
    * **預設路由 (Default Route)**：`0.0.0.0/0` (所有流量) 丟給 ISP 閘道，這就是最常見的靜態路由。

##### 4. 關鍵限制 (Cons)
* **最重要的缺點**：**沒有容錯 (No Failover)**。
* 因為是你「手動」指定的，如果那個「下一跳 (Next Hop)」設備當機或線路斷了，靜態路由**不會**自動幫你找一條新的備援路徑。
* 封包會持續被丟進那個「黑洞」，直到你手動介入、修改路由為止。
* 只適用於*路由不常變動*和*路徑單純*的環境。

### 配置

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
                ...
            autonomous-system: 65253
            enable: on
            router-id: 10.10.10.63
          static: # this
            10.1.10.0/24:
              address-family: ipv4-unicast
              via:
                10.1.102.4:
                  type: ipv4-address
            10.1.20.0/24:
              address-family: ipv4-unicast
              via:
                10.1.102.4:
                  type: ipv4-address
```