# 基本指南

實驗 cumulus OS 版本為 5.4

## 常用指令

```bash
nv config patch nvue.yaml
# 將檔案內容合併到現有設定中（推薦）
```

確認變更

```bash
nv config diff
```

正式套用

```bash
nv config apply
```
