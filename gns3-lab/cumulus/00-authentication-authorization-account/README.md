# Authentication Authorization

主要目的就是管理使用者或是使用 API 時的權限控管。

## SSH

原則上和 Linux 系統上的設定相同。除非用 NVUE 語法進行設定，則可以看官方文件。可以做到

1. root 登入設定
2. 使用者存取管理
3. SSH 配置檔設定，如下。當然不只這些

    ```bash
    Port 443
    LoginGraceTime 200s
    PermitRootLogin prohibit-password
    #StrictModes yes
    MaxAuthTries 10
    MaxSessions 10
    ```

SSH 服務運作在交換器的預設 VRF 中(default)，但會監聽所有 VRF 中的所有介面，可以依需求將 SSH 服務限制為監聽特定的 VRF。*但不能同時在預設 VRF 和其他 VRF 中執行 SSH*。

預設的 SSH 設定，

```bash
cumulus@cumulus:mgmt:~$ nv show system ssh-server
                             operational        applied
---------------------------  -----------------  -----------------
authentication-retries       6                  6
login-timeout                120                120
inactive-timeout             5                  15
permit-root-login            prohibit-password  prohibit-password
max-sessions-per-connection  10                 10
state                        enabled            enabled
strict                       enabled            enabled
login-record-period          1                  1
[vrf]
max-unauthenticated
  session-count              100                100
  throttle-percent           30                 30
  throttle-start             10                 10
[port]                       22                 22
```

### Lab

[](ssh.topo.png) 在 server 機器產生 SSH Key Pair，並透過 server 機器進行遠端登入 cumulus 交換器。

1. 產生 SSH Key Pair 透過 `ssh-keygen`
2. 配置 Authorized SSH Key

    ```bash
    # 使用者 itachi 新增名為 prod_key 的授權金鑰。公鑰檔案的內容為 ssh-ed25519  AAAAC.... prod_key(<type> <key string> <comment>)。
    - set:
        system:
        aaa:
            user:
            itachi:
                ssh:
                authorized-key:
                    prod_key:
                    key: AAAAC3NzaC1lZDI1NTE5AAAAIKb2qZz10wMhkWaEWNpN53U+FIMrVG8NTqJUmUBBQ8C6
                    type: ssh-ed25519

    ```

3. 使用另一台機器登入

    ```bash
    ubuntu@ubuntu-cloud:~$ ssh -i .ssh/id_ed25519 itachi@192.168.192.131
    The authenticity of host '192.168.192.131 (192.168.192.131)' can't be established.
    ECDSA key fingerprint is SHA256:AjgOrNxSn+AY4s77L0QjN5PQbkMzA7CA1JCEOyN33YQ.
    This key is not known by any other names.
    Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
    Warning: Permanently added '192.168.192.131' (ECDSA) to the list of known hosts.
    Welcome to NVIDIA Cumulus (R) Linux (R)
    Linux cumulus 6.1.0-cl-1-amd64 #1 SMP PREEMPT_DYNAMIC Debian 6.1.123-1+cl5.12.1u12 (2025-02-19) x86_64
    Welcome to NVIDIA Cumulus (R) Linux (R)
    For support and online technical documentation, visit https://www.nvidia.com/en-us/support
    The registered trademark Linux (R) is used pursuant to a sublicense from LMI, the exclusive licensee of Linus Torvalds, owner of the mark on a world-wide basis.
    Number of total successful connections since last 1 days: 0

    ZTP in progress. To disable, do 'ztp -d'

    itachi@cumulus:mgmt:~$
    ```

4. 查看資訊

    ```bash
    cumulus@cumulus:mgmt:~$ nv show system ssh-server active-sessions
    Peer Address:Port      Local Address:Port       State
    ---------------------  -----------------------  -----
    192.168.192.132:47878  192.168.192.131%mgmt:22  ESTAB
    cumulus@cumulus:mgmt:~$ w
    13:47:48 up 56 min,  2 users,  load average: 0.00, 0.02, 0.00
    USER     TTY      FROM             LOGIN@   IDLE   JCPU   PCPU WHAT
    cumulus  ttyS0    -                12:52    0.00s  0.10s   ?    w
    itachi   pts/0    192.168.192.132  13:46    1:04   0.01s  0.01s -bash
    ```

## User Accounts

1. 預設帳號

    預設上有 `cumulus` 和 `root` 帳號。`cumulus` 帳號有這些 NVUE 權限

    * nv show
    * nv set
    * nv unset
    * nv apply

    至於 `root` 帳號，預設會停用預設密碼，並沒有這些權限 SSH、telnet、FTP 等登入交換器。

2. NVUE 預設角色與權限

    NVUE 透過角色（Role）來控制使用者對系統設定的存取程度：

    從 Linux 作業系統來看

    |角色名稱|權限說明|
    |---|---|
    |sudo|允許使用者透過 sudo 以特權身分執行指令 。|
    |nvshow|唯讀。僅能執行 nv show 指令 。|
    |nvset|可執行 nv show，以及 nv set/unset 來暫存設定變更 。|
    |nvapply|完整權限。可執行 show、set、unset，並能執行 nv apply 套用設定 。|
    |system-admin|具備系統管理權限，可建立、修改或刪除其他 system-admin 帳號 。|

    它們在作業系統中有對應群組。

    ```bash
    $ cat /etc/group | grep "nv"
    sudo:x:27:nvue,cumulus
    shadow:x:42:nvue,www-data
    netshow:x:996:nvue
    nvue:x:995:
    nvshow:x:994:itachi
    nvset:x:993:
    nvapply:x:992:cumulus
    ```

    如果以 NVUE 的配置，則角色有

    * system-admin
        * 有 sudo 和管理 nv 相關操作權限
    * nvue-admin
        * 管理 nv 相關操作權限
    * nvue-monitor
        * nv show 權限，即讀

3. 密碼安全性政策 (Password Hardening)

    Cumulus Linux 預設啟用了嚴格的密碼政策，這邊不再贅述。但可以注意的是可以為本機使用者提供雜湊密碼，而不是明文密碼。必須以 Linux crypt 格式指定哈希密碼；密碼長度必須至少為 15 到 20 個字符，並且必須包含特殊字符、數字、小寫字母等。通常，密碼格式設定為 `$id$salt$hashed`，其中 `$id` 是哈希演算法。在 GNU 或 Linux 中：

    * `$1$` is MD5
    * `$2a$` is Blowfish
    * `$2y$` is Blowfish
    * `$5$` is SHA-256
    * `$6$` is SHA-512

    交換器上產生雜湊密碼:

    ```bash
    python3 -c "import crypt; import getpass; print(crypt.crypt(getpass.getpass(), salt=crypt.METHOD_SHA512))"
    ```

    為本機使用者設定哈希密碼

    ```bash
    nv set system aaa user <username> hashed-password <password>
    ```

    預設系統設定密碼原則:

    ```bash
    ~$ nv show system security password-hardening
                            operational  applied
    -----------------------  -----------  -------
    state                    enabled      enabled
    reject-user-passw-match  enabled      enabled
    lower-class              enabled      enabled
    upper-class              enabled      enabled
    digits-class             enabled      enabled
    special-class            enabled      enabled
    expiration-warning       15           15
    expiration               180          180
    history-cnt              10           10
    len-min                  8            8

    ```

4. 顯示使用者帳戶

    建立使用者，建立完成後系統會自動用 hash 方式建立 `hashed-password`

    ```bash
    cumulus@cumulus:mgmt:~$ nv set system aaa user admin2 role system-admin
    created [rev_id: 24]
    cumulus@cumulus:mgmt:~$ nv set system aaa user admin2 password
    Enter new password:
    Confirm password:
    cumulus@cumulus:mgmt:~$ nv set system aaa user admin2 full-name "FIRST LAST"
    cumulus@cumulus:mgmt:~$ nv config diff
    - set:
        system:
        aaa:
            user:
              admin2:
                full-name: FIRST LAST
                hashed-password: '*'
                role: system-admin
    cumulus@cumulus:mgmt:~$ nv config apply
    applied_and_saved [rev_id: 24]
    ```

    顯示使用者

    ```bash
    cumulus@cumulus:mgmt:~$ nv show system aaa user admin2
                    operational   applied
    ---------------  ------------  ------------
    state            enabled       enabled
    role             system-admin  system-admin
    full-name        FIRST LAST    FIRST LAST
    hashed-password  *             *
    [spiffe-id]
    ```

### Lab

產生一個密碼的雜湊。

```bash
python3 -c "import crypt; import getpass; print(crypt.crypt(getpass.getpass(), salt=crypt.METHOD_SHA512))"
```

建立名為 naruto 的使用，且權限只有讀。

```yaml
- set:
    system:
      aaa:
        user:
          naruto:
             full-name: test account
             hashed-password: '$6$uSjcxRnVFXMIm0Us$3erA50JikcaavOsNjWONkAInUwfkbDG8W0c6ZvVbfbeFrH2IuGJIHpgl.ZOf1DZi3ARsba6Byd9C5.JyGs2wT0'
             role: nvue-monitor
             state: enabled
```

可以看到在作業系統中建立了對應的家目錄。

```bash
~$ ls /home
cumulus  itachi  naruto
```

顯示系統上已設定的使用者帳號

```bash
cumulus@cumulus:mgmt:~$  nv show system aaa user
Username  Full-name     Role          state
--------  ------------  ------------  -------
cumulus   cumulus,,,    system-admin  enabled
itachi                  nvue-monitor  enabled
naruto    test account  nvue-monitor  enabled
```

## Role-Based Access Control

除了上面提到到三個預設角色，可以自行新增角色來限制授權，而更細緻控制使用者可以在交換器上管理的內容。要建立角色須包含以下要素，

* Role
  * 一個虛擬標識符，可用於多個類(class)。每個使用者只能指派一個角色。
* Class
  * 概念類似 Linux 使用者 `group`。建立和管理類別是同時配置多個使用者最簡單的方法，尤是在配置權限時。
* Action
  * 針對類(class)要允許還是拒絕。

### Lab

將自定義的角色分配給使用者。步驟

1. 創建角色(role)及其所屬類(class)。
2. 每個類指定操作動作允許或拒絕。
3. 為每個類新增指令路徑和權限。
4. 給使用者指派角色(role)。

配置:

```bash
~$ cat nvue-role.yaml
- set:
    system:
      aaa:
        role:
          'TEST':
            class:
              class1: {}
              class2: {}
        class:
          class1:
            action: deny
            command-path:
              /system/aaa/user:
                permission: rw
              /vrf/:
                permission: rw
          class2:
            action: allow
            command-path:
              /interface/:
                permission: all
        user:
          madara:
             full-name: role test account
             hashed-password: '$6$P4yLp9vNswPmlHeX$FRUI7/f3ZDhzr5WtOsq5IVffL94oVYl4SWnsVbP8rFRKSaAJotblf7vuj9PKXUZhLXHMGy312uXj7JfGqVGMN1'
             role: TEST
             state: enabled
```

驗證:

```bash
$ nv show system aaa role TEST
         applied
-------  -------
[class]  class1
[class]  class2
$ nv show system aaa class class1
                applied
--------------  ----------------
action          deny
[command-path]  /system/aaa/user
[command-path]  /vrf/

```

測試:

```bash
madara@cumulus:mgmt:/var/home/cumulus$ nv show interface description
Interface  Admin Status  Oper Status  Description
---------  ------------  -----------  -----------
eth0       up            up
lo         up            unknown
mgmt       up            up
swp1       up            down
swp2       up            down
swp3       up            down
swp4       up            down
swp5       up            down
swp6       up            down

madara@cumulus:mgmt:/var/home/cumulus$ nv show system aaa
Error: No permission to execute this command.
madara@cumulus:mgmt:/var/home/cumulus$ nv show system aaa
Error: No permission to execute this command.
madara@cumulus:mgmt:/var/home/cumulus$ nv show vrf
Error: No permission to execute this command.
```