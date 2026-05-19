# 二进制目录差分升级方案

基于 [HDiffPatch](https://github.com/sisong/HDiffPatch) 的目录级二进制差分方案，把任意"旧版目录 → 新版目录"的全部差异压缩成一个补丁文件，方便在 Fab 厂离线机台上传输与还原。

> 通用化设计：脚本固定使用 `old_version/` 与 `new_version/` 作为输入目录，与具体版本号解耦，后续每次发版只需把对应版本内容放入这两个文件夹即可复用。

---

## 一、目录结构

```
patch_demo/
├── old_version/           旧版完整目录（差分基准，可放任意层级文件）
├── new_version/           新版完整目录（差分目标，仅研发端需要）
├── hdiffz.exe             补丁制作工具（研发端，自行下载）
├── hpatchz.exe            补丁还原工具（现场端，自行下载）
├── make_patch.bat         研发端：一键制作差分补丁
├── verify_patch.bat       研发端：验证补丁正确性（SHA256 全量比对）
├── restore.bat            现场端：一键还原 new_version
└── update.hdiff           生成的差分补丁文件
```

---

## 二、工具准备（一次性）

1. 访问 https://github.com/sisong/HDiffPatch/releases
2. 下载最新 Windows 版（如 `hdiffpatch_v4.12.2_bin_windows64.zip`）
3. 解压，将其中的 `hdiffz.exe` 和 `hpatchz.exe` 复制到本 `patch_demo` 目录下

---

## 三、研发端：制作并验证补丁

### 1. 制作补丁
将旧版完整文件放入 `old_version/`，新版完整文件放入 `new_version/`，然后双击 `make_patch.bat`。脚本实际执行：

```
hdiffz.exe -m-2 old_version new_version update.hdiff
```

- `-m-2` 启用极致压缩，适合离线传输
- 支持任意子目录层级，差分结果是整个目录树的最小变更集
- 脚本会先对两个目录做 SHA256 全量比对：若内容完全一致，将直接提示「无需升级」并退出，不会生成补丁，也不会删除已存在的旧补丁

### 2. 验证补丁
双击 `verify_patch.bat`，脚本会：
- 自动创建并清理 `new_version_verify/`（无需手动准备）
- 用 `old_version + update.hdiff` 还原出 `new_version_verify/`
- 用 PowerShell 逐文件计算 SHA256 并与原始 `new_version/` 比对
- 输出成功/差异结果；验证通过后该目录会被自动删除

验证通过后即可打包交付。

---

## 四、交付包内容（U 盘）

```
升级包/
├── old_version/           （旧版完整目录，必需）
├── hpatchz.exe            （还原工具，~500KB）
├── update.hdiff           （差分补丁）
└── restore.bat            （一键还原脚本）
```

> 不需要带 `hdiffz.exe`、`new_version/`、`make_patch.bat`、`verify_patch.bat`。

---

## 五、现场端：还原并手动安装

### 1. 一键还原 new_version
将 U 盘插入 Fab 厂机台，双击 `restore.bat`，脚本将自动：
- 校验 `old_version` 旧版目录与补丁文件
- 调用 hpatchz 从补丁还原出完整 `new_version/` 目录

### 2. 手动安装
进入还原好的 `new_version/` 目录，按交付清单手动执行后续安装步骤（如双击 MSI、运行 setup.exe 等）。

---

## 六、原理速览

```
研发端:   old_version ──┐
                        ├── hdiffz ──► update.hdiff  (体积极小)
          new_version ──┘

现场端:   old_version ──┐
                        ├── hpatchz ──► new_version (二进制完全一致)
         update.hdiff ──┘
```

差分文件本质上记录了从旧版演化到新版所需的字节级修改指令，因此只要现场有完全相同的 `old_version` 基准目录，就能精确还原出 `new_version`。

---

## 七、后续可扩展点

- **排除特定文件**：在 `make_patch.bat` 的 hdiffz 命令中追加 `-ig "文件名模式"` 参数（如排除现场配置）
- **多版本迭代**：每次发版只需替换 `old_version/` 与 `new_version/` 的内容，无需修改任何脚本
- **静默安装**：在 `restore.bat` 末尾追加 `msiexec /i new_version\xxx.msi /qb` 等命令实现完全自动化
