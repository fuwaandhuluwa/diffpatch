

使用方式：
1. hpatchz.b 后缀修改为 exe, 如当前目录有 new_version 目录删除即可
2. 将上一正式版本软件（非补丁版本，补丁版本不可用）放置于 old_version 目录下
3. 双击运行 restore.bat 即可，运行过程中如需要 presss any key to continue 则随便按键即可继续运行
4. 自动生成 new_version 目录, 运行 new_version 目录下的 new_installer.msi 即可安装新版软件




注意事项：
1. 因为采用差分升级，所以客户端和公司内部每次版本更新，必须互相保留此次版本的备份以及记录，以便下次升级时还可以使用差分升级方案
2. 此方案针对 MSI 文件和解压后的目录文件都可使用，务必保持差分升级前后的 old_version 内容一致