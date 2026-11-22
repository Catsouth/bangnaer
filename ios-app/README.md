# 绑哪儿 · iOS 壳工程（未签名 IPA）

一个极简原生壳：SwiftUI + WKWebView 全屏打开**打包在 App 内的本地网页**（就是网页版的那 8 个文件），
在 GitHub Actions 的 macOS 机器上编译成**未签名 IPA**，签名由你自己用证书完成（本工程不管签名）。

线上网页版照常发版（`src/` → `./build.sh` → 部署 bind.465871.xyz），两者互不影响；
壳 App 里装的是构建那一刻的网页快照，网页更新后想同步进 App，重新跑一次下面的构建即可。

## 目录

```
ios-app/
├── BindAtlas.xcodeproj/        手写极简工程（无 XcodeGen 依赖，ID 已本地静态校验）
└── BindAtlas/
    ├── BindAtlasApp.swift      @main 入口
    ├── ContentView.swift       全屏 WebView + 外链的 SFSafariViewController 弹层
    ├── WebView.swift           WKWebView 配置与桥（见下）
    ├── ExportBridge.js         注入脚本：把 blob 导出转成原生分享（见下）
    ├── Info.plist              显示名「绑哪儿」，无 ATS 例外（全站 https，不需要）
    ├── Assets.xcassets/        AppIcon（1024，CI 由 src/icon.svg 现生成，见下节）
    └── Web/                    网页文件落位点：仓库里只有 .gitkeep，
                                CI 构建时从 dist 组装结果拷入 8 个文件，不在 git 里存副本
.github/workflows/build-ipa.yml  CI 流水线（仓库根目录）
```

## 壳比 PWA 多了什么 / 补了什么

- **导出备份真能存文件**：网页版导出是 blob 下载，WKWebView 默认静默失败。
  壳注入 `ExportBridge.js` 拦截 blob 下载 → 原生写临时文件 → 弹系统分享面板，自己选「存到文件」。
- **外链不困在壳里**：「前往登录」的 https 链接（window.open）改用 SFSafariViewController 打开。
- 文件导入（密码库 JSON / CSV）走 WKWebView 自带的系统文件选择器，原生支持。
- JavaScript、localStorage（DOM 存储）已打开；WebDAV 是 https 且服务端有 CORS `*`，壳内可直连。

## 图标不入 GitHub 快照，由 CI 从 icon.svg 生成

通过 Muse 的 GitHub 通道推送只能传 UTF-8 文本文件，二进制（png/ico）会被整单拒绝。
所以推 GitHub 时**不要带上任何图标二进制**：`src/` 里的 png/ico、以及
`BindAtlas/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 都会被排除在快照之外
（它们在本地仓库里照旧保留，本地 `./build.sh` 发版继续用现成的）。
图标的唯一源头是 `src/icon.svg`：CI 在组装 dist 后跑
`scripts/gen-icons.py`（Pillow + cairosvg），现生成全套网页图标补齐 dist 的 8 个文件，
并把全出血不透明的 AppIcon 1024 直接生成进 xcassets。改图标只改 `src/icon.svg`，
本地想预览生成效果：`python3 scripts/gen-icons.py --out /tmp/genicons --appicon /tmp/genicons/appicon-1024.png`。

## 怎么触发构建、去哪下 IPA

1. 仓库推上 GitHub 后（建仓/推送不在本工程范围内），满足任一条件触发：
   - GitHub 网页/App：仓库 → Actions → 「Build unsigned IPA」→ Run workflow（手动触发）；
   - 或推送任何 `ios-app/**` 的变更（自动触发）。
2. 构建跑在 `macos-latest`：组装网页文件 → 拷进 `BindAtlas/Web/` →
   `xcodebuild` 关签名构建 Release → 把 `.app` 按 Payload 结构压成 `bangnaer-unsigned.ipa`。
3. 下载：该次 Actions 运行页面底部 Artifacts → `bangnaer-unsigned-ipa`，解压得到 `bangnaer-unsigned.ipa`。

## 拿证书签名（ESign / 轻松签，大致步骤）

1. 在 ESign（或轻松签）里导入你的**证书（.p12）+ 密码**和**描述文件（.mobileprovision）**。
2. 在文件页找到 `bangnaer-unsigned.ipa` → 长按/选中 → 签名 → 选刚导入的证书。
3. Bundle ID 现在是 `xyz.465871.bind`：描述文件若绑了别的 App ID，
   在签名时把 Bundle ID 改成描述文件对应的那个即可（壳工程里改的话在
   `project.pbxproj` 的 `PRODUCT_BUNDLE_IDENTIFIER`，改完要重新构建）。
4. 签名完成 → 安装到本机（证书信任按 ESign 提示在「设置 → 通用 → VPN 与设备管理」里信任）。

## ⚠️ 重要提醒：数据不互通

- 壳 App 的 localStorage 与 Safari / PWA 版**互相隔离、不会自动同步**（WKWebView 与 Safari 各存各的）。
- 第一次打开壳 App 是空的：在 App 里打开「设置 → WebDAV 备份」，填你自己的 WebDAV 地址/账号，
  **拉取一次**云端备份（或用「导入备份」选你导出的 JSON），你的数据就进来了；
  之后 App 内独立按原策略同步（有改动才上传），网页版和 App 版共用同一份云端备份文件时，
  以最后上传的一方为准，别两边同时改同一批数据。
- App 里的网页是构建时的快照：网页版升了新版本，App 不会自动跟着升，重跑构建、重签、覆盖安装即可（数据在 localStorage 里，覆盖安装不丢）。

## 本地能验的都验了（Linux 无 Xcode，以下为静态校验）

- `project.pbxproj`：对象 ID 全 hex/24 位、引用闭合、括号平衡、scheme 的 BlueprintIdentifier 与 target 一致（脚本校验）。
- `Info.plist`：plistlib 解析通过；无 `NSAppTransportSecurity` 例外。
- workflow YAML：解析通过。
- `icon-1024.png`：由 `src/icon.svg` 渲染，尺寸 1024×1024 已验。
- 真正的编译结果只能等 GitHub Actions 首跑验证（本机没有 Xcode）。

<!-- CI 首跑触发标记 2026-11-23：workflow 上线后的第一次构建 -->
