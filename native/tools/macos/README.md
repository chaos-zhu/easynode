# macOS DMG 打包

在 `native/` 运行。脚本只构建、签名、验证和打包，不启动 App。

- Bundle ID：`io.github.chaoszhu.easynode.macos`
- Team：`5BQLRCF2QW`，与 iOS 一致。
- Xcode Release 默认使用 Apple Development，启用 Hardened Runtime。
- 官网发行由脚本切换为 Developer ID Application；不会修改 iOS 配置。
- Bundle ID 从模板值修改后，旧 macOS 安装的偏好和 Keychain 数据不会自动迁移。

## 本机验证

```sh
flutter pub get
EASYNODE_RDP_MACOS_TARGET=27.0 bash tools/rdp/build-macos.sh
python3 tools/macos/package.py --development --arch arm64 --min-macos 27.0
```

上述 27.0 是当前开发机 Homebrew 依赖所需版本，不是公开发布的系统支持承诺。
开发包使用 Apple Development 证书，只用于开发描述文件覆盖的设备，不可官网分发。
脚本允许 Xcode 注册当前 Mac 并下载开发描述文件，需要 Xcode 已登录相应团队。
产物在 `build/macos-dist/<时间>/`，包含 DMG、安装目录及 `manifest.json`。
DMG 内提供 `/Applications` 快捷方式。

## 官网发布

1. 在 Apple Developer / Xcode 中安装本 Team 的 Developer ID Application 证书和私钥。
   无需 Developer ID Installer（仅 PKG 需要）。
2. 先用目标最低 macOS 版本和架构构建 FreeRDP **及全部动态库依赖**。
   仅设置 `EASYNODE_RDP_MACOS_TARGET` 不会降低已安装 Homebrew 库的最低版本。
   脚本逐个检查 Mach-O 的架构、最低版本、依赖路径和 rpath；不满足会停止。
   当前仅提供每架构独立打包，不能把 arm64 引擎装进标为 universal 的发行包。
3. 使用 Apple 的 `notarytool store-credentials` 交互式建立 Keychain profile，
   例如 `easynode-notary`。密码或 API 私钥不写入仓库或打包命令。
4. 构建并公证（以下 12.0 仅在全部依赖已兼容时可用）：

```sh
python3 tools/macos/package.py --arch arm64 --min-macos 12.0 \
  --notary-profile easynode-notary
```

脚本先公证并 staple App，再制作、签名、公证并 staple DMG。
仅 Apple 返回 `Accepted` 后才继续，失败保留 submission ID 供 `notarytool log` 排查。
此命令会向 Apple 上传应用和 DMG 以进行公证，不发布到官网。
不传 `--notary-profile` 时只生成 `signed-unnotarized` 包，不视为正式发行完成。

可用 `--app /绝对路径/EasyNode.app` 复用已构建的同架构、相同最低系统版本和正确签名
产物。该模式仍检查所有内嵌代码的 Team、证书、签名完整性和（发行签名的）时间戳。
签名按 Xcode 主 App、Framework 和 RDP 子代码执行，不使用 `codesign --deep` 重新签名；
`--deep` 仅用于验证。
打包副本会移除 Xcode / Flutter 附带的开发机绝对 rpath，并按内到外顺序重新签名，
保留原有 entitlements、runtime 和标识；原始构建产物不受此步骤修改。
RDP 许可证和版本文本存放于 `Contents/Resources/rdp`，避免被 Helpers 的代码签名规则误判。

## 自动化检查

```sh
python3 -m unittest discover -s tools/macos -p 'test_*.py'
bash -n tools/rdp/embed-macos.sh
flutter analyze
flutter test
```
