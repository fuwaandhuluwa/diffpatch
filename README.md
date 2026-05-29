# 软件差异化升级方案

为了解决软件包每次更新太大的问题，如某些客户端限制，邮件附件大小限制 20M 等，我们需要尽量减小包的大小，那可行的方案就是差异化更新，只发送有更新的模块或者更新的内容部分，又不想更改现有的软件包安装方式。
本方案采用二进制差分通用方案，实现两个目录级的差分对比，将差异生成专门的 diff 文件用于传输，减小软件传输大小，方便后续使用。


# 二进制目录差分升级方案

基于 [HDiffPatch](https://github.com/sisong/HDiffPatch) 的目录级二进制差分方案，把任意"旧版目录 → 新版目录"的全部差异压缩成一个补丁文件，方便在 Fab 厂离线机台上传输与还原。

> 通用化设计：脚本固定使用 `old_version/` 与 `new_version/` 作为输入目录，与具体版本号解耦，后续每次发版只需把对应版本内容放入这两个文件夹即可复用。

脚本支持**多模式自动混合打包**，自动检测，无需手动切换：

| 模式 | 触发条件 | 差分对象 | 输出文件 |
|------|---------|---------|---------|
| **MSI 模式** | `old_version/` 和 `new_version/` 含同名 `.msi` 文件 | MSI 解压后的松散文件 | `update_msi_<名称>.hdiff` + `new_installer_<名称>.msi` |
| **目录模式** | 存在非 MSI 文件（.vsix、.exe、配置文件等） | 目录内全部非 MSI 文件 | `update_dir.hdiff` |

**两种模式可同时生效**——如果 `old_version/` 和 `new_version/` 同时包含 MSI 和其他文件（如 .vsix、.exe），脚本会为每对 MSI 生成独立的 MSI 差分补丁，并为所有非 MSI 文件生成一个目录差分补丁。所有输出统一放到 `输出/` 目录。

### 为什么 MSI 需要先解压？

MSI 内嵌 CAB 压缩包，里面的 DLL/EXE 等已被高强度压缩。即使两个版本只改了几行代码，CAB 压缩后的字节流会"雪崩式"全变，导致直接对 MSI 做二进制差分压缩率很差（通常 70%–80%）。先用 `msiexec /a` 展开成松散文件再差分，可大幅提升压缩率。

---

## 一、目录结构

```
patch_demo/
├── old_version/           旧版完整目录（可含 .msi + .vsix + .exe + 任意文件）
├── new_version/           新版完整目录（同上，仅研发端需要）
├── temp/                  工作目录（脚本自动管理，无需关注）
├── 输出/                  自动生成的交付包目录
│   ├── hpatchz.exe        补丁还原工具
│   ├── restore.bat        一键还原脚本
│   ├── UpgradeReadme.txt  自动生成的使用说明
│   ├── old_version/       空目录（用户放入基准文件）
│   ├── update_msi_*.hdiff [MSI模式] MSI差分补丁（每个MSI一个）
│   ├── new_installer_*.msi[MSI模式] 瘦身MSI
│   └── update_dir.hdiff   [目录模式] 非MSI文件差分补丁
├── hdiffz.exe             补丁制作工具（研发端，自行下载）
├── hpatchz.exe            补丁还原工具（研发端，自行下载）
├── make_patch.bat         研发端：一键制作差分补丁
├── verify_patch.bat       研发端：验证补丁正确性
└── restore.bat            还原脚本模板（会被复制到输出目录）
```

---

## 二、工具准备（一次性）

1. 访问 https://github.com/sisong/HDiffPatch/releases
2. 下载最新 Windows 版（如 `hdiffpatch_v4.12.2_bin_windows64.zip`）
3. 解压，将其中的 `hdiffz.exe` 和 `hpatchz.exe` 复制到本 `patch_demo` 目录下

---

## 三、研发端：制作补丁

将旧版文件放入 `old_version/`，新版文件放入 `new_version/`，然后双击 `make_patch.bat`。

脚本会自动执行以下四个阶段：

### Phase 1: MSI 配对处理
- 扫描 `new_version/*.msi`，在 `old_version/` 中寻找同名 MSI
- 对每对 MSI：`msiexec /a` 解压 → 删除解压后的 .msi → `hdiffz -m-2` 差分
- 输出：`update_msi_<名称>.hdiff` + `new_installer_<名称>.msi`

### Phase 2: 非 MSI 文件差分
- 将 old/new_version 中排除 .msi 后的所有文件做整体目录差分
- 输出：`update_dir.hdiff`

### Phase 3: 组装输出包
- 复制 `hpatchz.exe`、`restore.bat` 到 `输出/` 目录
- 创建空 `old_version/` 子目录

### Phase 4: 生成 UpgradeReadme.txt
- 自动列出 `old_version/` 中用户需要准备的所有文件名和大小
- 列出本次生成的所有补丁文件

---

## 四、交付包内容（U 盘）

运行 `make_patch.bat` 后，直接将 `输出/` 目录整个拷贝到 U 盘即可：

```
输出/
├── old_version/              （空目录，用户放入基准文件）
├── hpatchz.exe               （还原工具）
├── restore.bat               （一键还原脚本）
├── UpgradeReadme.txt          （使用说明，含需放入的文件清单）
├── update_msi_AppName.hdiff   [如有MSI] MSI差分补丁
├── new_installer_AppName.msi  [如有MSI] 瘦身MSI
└── update_dir.hdiff           [如有非MSI文件] 目录差分补丁
```

> 不需要带 `hdiffz.exe`、`new_version/`、`make_patch.bat`、`verify_patch.bat`。

---

## 五、现场端：还原并安装

1. 阅读 `UpgradeReadme.txt`，按说明将基准文件放入 `old_version/`
2. 双击 `restore.bat`

脚本将自动：
1. 遍历所有 `update_msi_*.hdiff`，对每个 MSI 补丁：
   - `msiexec /a` 展开旧 MSI → 应用补丁 → 还原新版 payload
   - 复制对应的瘦身 MSI 到 `new_version/`
2. 如果存在 `update_dir.hdiff`：
   - 从 `old_version/` 提取非 MSI 文件 → 应用补丁 → 合并到 `new_version/`
3. 完成后进入 `new_version/` 目录按需安装

---

## 六、原理速览

### 多模式混合打包
```
研发端:
  old_version/
  ├── app.msi        ─┐
  ├── plugin.vsix     │  自动分离
  └── tool.exe         │
                       │
  new_version/         │
  ├── app.msi        ─┤──► MSI模式 ──► update_msi_app.hdiff + new_installer_app.msi
  ├── plugin.vsix     │
  └── tool.exe        ─┘──► 目录模式 ──► update_dir.hdiff

现场端:
  old_version/ + *.hdiff ──► restore.bat ──► new_version/ (完整还原)
```

---

## 七、后续可扩展点

- **排除特定文件**：在 `make_patch.bat` 的 hdiffz 命令中追加 `-ig "文件名模式"` 参数（如排除现场配置）
- **多版本迭代**：每次发版只需替换 `old_version/` 与 `new_version/` 的内容，无需修改任何脚本
- **静默安装**：在 `restore.bat` 末尾追加安装命令实现完全自动化
- **备选方案**：若 `msiexec /a` 在不同 Windows 版本上展开结果不一致（极小概率），可改用 7-Zip 解压 MSI
