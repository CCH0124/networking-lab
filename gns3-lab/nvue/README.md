## Show NVUE REST API Information

```bash
$ nv show system api
                     operational  applied
-------------------  -----------  -----------
state                enabled      enabled
port                 8765         8765
certificate          self-signed  self-signed
[listening-address]  any
connections
  active             1
  accepted           1
  handled            1
  requests           1
  reading            0
  writing            1
  waiting            0
```

```bash
$ nv show system api listening-address

---
any

```

## Run cURL Commands

```bash
$ curl  -u 'cumulus:PWD' --insecure https://172.21.1.10:8765/nvue_v1/interface
{
  "eth0": {
    "ifindex": 2,
    "ip": {
      "address": {
        "172.21.1.10/24": {},
        "fe80::e32:43ff:fef2:0/64": {}
      },
      "vrf": "mgmt"
    },
    "link": {
      "admin-status": "up",
      "auto-negotiate": "off",
      "duplex": "full",
      "flag": {
        "broadcast": {},
        "lower-up": {},
        "multicast": {},
        "up": {}
      },
      "mac-address": "0c:32:43:f2:00:00",
      "mtu": 1500,
      "oper-status": "up",
      "oper-status-last-change": "2026/02/13 02:36:29.288",
      "protodown": "disabled",
      "speed": "1G",
      "state": {
        "up": {}
      },
      "stats": {
        "carrier-down-count": 3,
        "carrier-transitions": 6,
        "carrier-up-count": 3,
        "in-bytes": 1722,
        "in-drops": 0,
        "in-errors": 0,
        "in-pkts": 14,
        "out-bytes": 19056,
        "out-drops": 0,
        "out-errors": 0,
        "out-pkts": 86
      }
    },
    "parent": "mgmt",
    "type": "eth"
  },
  "lo": {
    "ifindex": 1,
    "ip": {
      "address": {
        "127.0.0.1/8": {},
        "::1/128": {}
      }
    },
    "link": {
      "admin-status": "up",
      "flag": {
        "loopback": {},
        "lower-up": {},
        "up": {}
      },
      "mac-address": "00:00:00:00:00:00",
      "mtu": 65536,
      "oper-status": "unknown",
      "oper-status-last-change": "Never",
      "protodown": "disabled",
      "state": {
        "up": {}
      },
      "stats": {
        "carrier-down-count": 0,
        "carrier-transitions": 0,
        "carrier-up-count": 0,
        "in-bytes": 151918,
        "in-drops": 0,
        "in-errors": 0,
        "in-pkts": 2283,
        "out-bytes": 151918,
        "out-drops": 0,
        "out-errors": 0,
        "out-pkts": 2283
      }
    },
    "type": "loopback"
  },
  "mgmt": {
    "ifindex": 5,
    "ip": {
      "address": {
        "127.0.0.1/8": {},
        "127.0.1.1/8": {},
        "::1/128": {}
      }
    },
    ...
}
```
