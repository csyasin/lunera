# Lunera

一款原生 macOS 菜单栏日历。Lunera 以纯黑刘海面板展示月历、农历与系统日历事件。

## 环境与构建

- macOS 14 或更新版本；使用 Xcode 打开 `Lunera.xcodeproj`，选择 `Lunera` scheme 运行。
- 也可在终端执行 `./Scripts/build.sh`，Release 应用将生成在 `build/Build/Products/Release/Lunera.app`。
- 日期悬浮变形使用 Metal 着色器；若 Xcode 提示缺少 Metal Toolchain，可执行 `xcodebuild -downloadComponent MetalToolchain` 安装官方编译组件。发布流程会在缺少时自动安装。
- `project.yml` 是 XcodeGen 项目定义；修改源文件结构后，可运行 `xcodegen generate` 重新生成工程。项目通过 Swift Package Manager 引入 Sparkle 2.10.0，首次构建需要获取依赖。
- 运行 `./Scripts/test-calendar.sh` 可检查农历日期、闰年、月历导航和跨日事件的计算；`./Scripts/test-layout.sh` 检查日程区可见性、内容高度及屏幕高度上限。

## 使用

打开 `Lunera.app` 后，点击屏幕菜单栏里的图标展开或收起面板。面板中的箭头用于切换月份，点击日期查看当日事件。面板获得键盘焦点时，按上箭头、左箭头、`k`、`p` 或 `h` 切换到上个月，按下箭头、右箭头、`j`、`n` 或 `l` 切换到下个月；按空格键回到今天。在面板内用触摸板向右滑动切换到上个月，向左滑动切换到下个月，每次手势翻一个月，纵向滚动仍用于浏览日程。按 Escape 或点击面板外部可收起。右键菜单栏图标可打开偏好设置或退出应用。

鼠标停留或移动到日期上时，会产生以该日期为中心、向邻近日期连续衰减的局部放大效果，中心最高约放大至 1.45 倍；点击位置按相同的变形公式映射到实际日期。进入、移动、退出和翻月时均平滑过渡，快速重新进入会延续当前状态；系统开启“减少动态效果”时收回该效果。选中日期直接显示主题色底色。

外部可通过 `lunera://open` 展开日历面板，也可在终端执行 `open 'lunera://open'`。应用未运行时会先启动；面板已展开时会将其置前。右键菜单栏图标，选择 **Copy Launch Link** 可复制该链接。首次使用需先打开一次应用，让 macOS 注册这个 URL Scheme。

## 日历权限

启动时会自动请求日历完整访问权限，无需点击连接按钮。尚未选择权限时，macOS 会弹出授权对话框；已拒绝或受限时不反复弹窗。系统的此权限同时涵盖读取和修改；Lunera 仅用它读取并显示事件，不会写入日历。拒绝后可在“系统设置 → 隐私与安全性 → 日历”中重新允许。未获得完整访问权限时不显示日程区；授权后按所选日期的日程数量自动调整面板高度，达到屏幕可用高度时日程列表可滚动。日程内容来自系统日历，云端同步由系统日历及其账户负责。

## 签名

工程默认使用 ad-hoc 签名，尚未使用 Developer ID 签名或 Apple 公证；下载后 macOS 可能阻止首次打开。由于 ad-hoc 签名没有 Team ID，当前构建为加载 Sparkle 使用 `disable-library-validation` entitlement，关闭了硬化运行时的动态库团队校验；沙盒及其余硬化运行时保护仍启用。配置正式 Apple 签名后，应使用同一 Team ID 签署应用及内嵌 Sparkle 并移除该例外，再调整发布校验。移动应用或重新签名后，macOS 可能需要重新确认权限。

## 构建、发布和应用内更新

GitHub Actions 仅在推送 `vX.Y.Z` 版本标签时运行检查并构建 Apple Silicon 版本，随后发布 `Lunera.dmg`、SHA-256 文件和 Sparkle `appcast.xml`；分支推送和 Pull Request 不会自动触发构建。CI 只接受与 `project.yml` 中 `MARKETING_VERSION` 一致的正式版本标签。

更新清单地址是 `https://github.com/csyasin/lunera/releases/latest/download/appcast.xml`，因此该仓库的 Release 资产必须允许未登录用户读取。CI 检查仓库为公开状态后才会发布；如需要保持源码私有，应先配置独立的公开发布源，并同步调整应用和发布脚本。发布包使用独立的 Sparkle EdDSA 密钥；它与 Apple 的代码签名和公证是不同机制。

首次配置（需要 XcodeGen、Xcode、网络和已登录且具备仓库管理权限的 GitHub CLI）：

```bash
xcodegen generate
xcodebuild -resolvePackageDependencies -project Lunera.xcodeproj -scheme Lunera -derivedDataPath build
./Scripts/setup-updates.py --create --github
```

脚本使用 `dev.yasin.lunera` 钥匙串账号生成专用于 Lunera 的私钥，将公钥写入 GitHub Actions 变量 `LUNERA_SPARKLE_PUBLIC_KEY`，将私钥通过标准输入写入 Secret `SPARKLE_PRIVATE_KEY`；临时导出的私钥文件会删除。已有线上密钥时，必须在钥匙串恢复**原有**私钥后运行 `./Scripts/setup-updates.py --github`，不要使用 `--create` 重新生成；脚本会拒绝替换不匹配的已配置公钥。请妥善备份原始密钥，丢失后已安装的版本无法验证新密钥签名的更新。

完成配置、检查并提交源码后，可以用 `./Scripts/release.py patch --dry-run` 预览，或将 `patch` 换为 `minor`、`major`、`current` 或指定版本号。去掉 `--dry-run` 会修改版本、创建提交和标签，并将分支与标签原子推送到 `origin`，随后触发发布。工具要求工作区干净、检查远端分支与已有标签；它不会包含尚未提交的应用修改。CI 会在签名前将版本、公钥、feed 和启用标记写入应用，再检查签名、沙盒和 Sparkle XPC，验证 DMG 哈希以及更新包与更新清单签名；任何一步失败都不会发布。应用内跨版本安装仍需通过实际后续版本验证。

本地开发构建默认关闭应用内更新；应首次手动安装包含更新功能的正式版，之后才能通过 Sparkle 检查后续版本。更新公钥放在 Actions 变量中，不含私钥。发行时的私钥从 Secret 传入签名工具的标准输入，不写入命令参数或发布产物。
