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

    |角色名稱|權限說明|
    |---|---|
    |sudo|允許使用者透過 sudo 以特權身分執行指令 。|
    |nvshow|唯讀。僅能執行 nv show 指令 。|
    |nvset|可執行 nv show，以及 nv set/unset 來暫存設定變更 。|
    |nvapply|完整權限。可執行 show、set、unset，並能執行 nv apply 套用設定 。|
    |system-admin|具備系統管理權限，可建立、修改或刪除其他 system-admin 帳號 。|

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
