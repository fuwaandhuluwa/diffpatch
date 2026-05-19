# 软件差异化升级方案

为了解决软件包每次更新太大的问题，如某些客户端限制，邮件附件大小限制 20M 等，我们需要尽量减小包的大小，那可行的方案就是差异化更新，只发送有更新的模块或者更新的内容部分，又不想更改现有的软件包安装方式。
本方案采用二进制差分通用方案，实现两个目录级的差分对比，将差异生成专门的 diff 文件用于传输，减小软件传输大小，方便后续使用。


# 二进制目录差分升级方案

基于 [HDiffPatch](https://github.com/sisong/HDiffPatch) 的目录级二进制差分方案，把任意"旧版目录 → 新版目录"的全部差异压缩成一个补丁文件，方便在 Fab 厂离线机台上传输与还原。

> 通用化设计：脚本固定使用 `old_version/` 与 `new_version/` 作为输入目录，与具体版本号解耦，后续每次发版只需把对应版本内容放入这两个文件夹即可复用。

脚本支持两种模式，**自动检测**，无需手动切换：

| 模式 | 触发条件 | 差分对象 | 压缩率 |
|------|---------|---------|--------|
| **MSI 模式** | `old_version/` 和 `new_version/` 各含唯一一个 `.msi` 文件 | MSI 解压后的松散文件 | 通常 5%–20% |
| **目录模式** | 其他情况 | 目录内全部文件 | 取决于内容 |

### 为什么 MSI 需要先解压？

MSI 内嵌 CAB 压缩包，里面的 DLL/EXE 等已被高强度压缩。即使两个版本只改了几行代码，CAB 压缩后的字节流会"雪崩式"全变，导致直接对 MSI 做二进制差分压缩率很差（通常 70%–80%）。先用 `msiexec /a` 展开成松散文件再差分，可大幅提升压缩率。

---

## 一、目录结构

```
patch_demo/
├── old_version/           旧版完整目录（差分基准）
├── new_version/           新版完整目录（差分目标，仅研发端需要）
├── temp/                  工作目录（脚本自动管理，无需关注）
├── hdiffz.exe             补丁制作工具（研发端，自行下载）
├── hpatchz.exe            补丁还原工具（现场端，自行下载）
├── make_patch.bat         研发端：一键制作差分补丁（自动检测 MSI/目录模式）
├── verify_patch.bat       研发端：验证补丁正确性（SHA256 全量比对）
├── restore.bat            现场端：一键还原 new_version
├── update.hdiff           生成的差分补丁文件
└── new_installer.msi      [MSI 模式] 瘦身的新版 MSI（用于安装）
```

---

## 二、工具准备（一次性）

1. 访问 https://github.com/sisong/HDiffPatch/releases
2. 下载最新 Windows 版（如 `hdiffpatch_v4.12.2_bin_windows64.zip`）
3. 解压，将其中的 `hdiffz.exe` 和 `hpatchz.exe` 复制到本 `patch_demo` 目录下

---

## 三、研发端：制作并验证补丁

### 1. 制作补丁

将旧版文件放入 `old_version/`，新版文件放入 `new_version/`，然后双击 `make_patch.bat`。

**目录模式**（与之前行为一致）：
```
hdiffz.exe -m-2 old_version new_version update.hdiff
```

**MSI 模式**（自动触发）：
1. `msiexec /a old.msi /qb TARGETDIR=...` 分别展开新旧 MSI 为松散文件
2. 从新版展开结果中提取瘦身 MSI → `new_installer.msi`
3. 删除两侧展开结果中的 `.msi` 文件（不参与差分）
4. `hdiffz.exe -m-2` 对松散文件做差分 → `update.hdiff`
5. 输出大小对比与压缩率

通用特性：
- `-m-2` 启用极致压缩，适合离线传输
- 脚本会先对两个目录/payload 做 SHA256 全量比对：若内容完全一致，将直接提示「无需升级」并退出

### 2. 验证补丁

双击 `verify_patch.bat`，脚本会模拟完整的现场还原流程：

**MSI 模式**：
1. 展开旧 MSI → 应用补丁 → 得到"还原版" payload
2. 展开新 MSI → 得到"期望版" payload
3. 逐文件 SHA256 比对（排除 .msi），任何差异立即报错

**目录模式**：
- 用 `old_version + update.hdiff` 还原出 `new_version_verify/`
- 逐文件 SHA256 与原始 `new_version/` 比对

验证通过后即可打包交付。

---

## 四、交付包内容（U 盘）

### 目录模式

```
升级包/
├── old_version/           （旧版完整目录，必需）
├── hpatchz.exe            （还原工具，~500KB）
├── update.hdiff           （差分补丁）
└── restore.bat            （一键还原脚本）
```

### MSI 模式

```
升级包/
├── old_version/xxx.msi    （旧版原始 MSI，基准，必需）
├── hpatchz.exe            （还原工具，~500KB）
├── update.hdiff           （松散文件层差分补丁，体积远小于直接 diff MSI）
├── new_installer.msi      （瘦身的新版 MSI，KB 级，用于触发安装）
└── restore.bat            （一键还原脚本）
```

> 不需要带 `hdiffz.exe`、`new_version/`、`make_patch.bat`、`verify_patch.bat`。

---

## 五、现场端：还原并安装

### 目录模式
将 U 盘插入机台，双击 `restore.bat`，脚本将自动还原出 `new_version/` 目录，之后手动安装。

### MSI 模式
双击 `restore.bat`，脚本将自动：
1. 用 `msiexec /a` 展开旧版 MSI 为松散文件
2. 用 `hpatchz` 应用补丁还原出新版松散文件
3. 将瘦身的 `new_installer.msi` 放入还原目录
4. 提示安装命令：`msiexec /i new_version\new_installer.msi /passive`

也可直接进入 `new_version/` 目录双击 MSI 手动安装。

---

## 六、原理速览

### 目录模式
```
研发端:   old_version ──┐
                        ├── hdiffz ──► update.hdiff  (体积极小)
          new_version ──┘

现场端:   old_version ──┐
                        ├── hpatchz ──► new_version (二进制完全一致)
         update.hdiff ──┘
```

### MSI 模式
```
研发端:   old.msi ─► msiexec /a ─► old_payload ──┐
                                                   ├── hdiffz ──► update.hdiff (极小)
          new.msi ─► msiexec /a ─► new_payload ──┘
                                 └► new_installer.msi (瘦身 MSI, KB 级)

现场端:   old.msi ─► msiexec /a ─► old_payload ──┐
                                                   ├── hpatchz ──► new_payload
                                  update.hdiff ───┘
                              new_installer.msi ──► msiexec /i ──► 安装完成
```

---

## 七、后续可扩展点

- **排除特定文件**：在 `make_patch.bat` 的 hdiffz 命令中追加 `-ig "文件名模式"` 参数（如排除现场配置）
- **多版本迭代**：每次发版只需替换 `old_version/` 与 `new_version/` 的内容，无需修改任何脚本
- **静默安装**：在 `restore.bat` 末尾追加 `msiexec /i new_version\new_installer.msi /passive` 实现完全自动化
- **备选方案**：若 `msiexec /a` 在不同 Windows 版本上展开结果不一致（极小概率），可改用 7-Zip 解压 MSI（`7z x old.msi -otemp\old_payload`），结果更稳定但需额外携带 7z.exe
