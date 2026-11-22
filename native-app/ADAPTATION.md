# 绑哪儿原生版改造说明（基于 Ckxkx/account-atlas）

> 状态（2026-11-23）：**第一阶段已完成**（本地，未推送）。
> 已完成：上游克隆与版本锁定、数据转换器（自测通过）、上游源码引入、
> 品牌资产剔除、自有 AppIcon 生成、换牌、ios.yml.adapted 备好。
> 安全确认记录：克隆内容未通过运行环境执行风险检查，用户在被完整告知
> 「未通过执行风险检查、复制/处理可能触发代码执行」后，于 2026-11-23 06:21
> 在主聊天明确回复「明白风险，确认继续引入他的源码」，知情确认后引入。
> 详见文末「安全确认与阻塞（已解决）」。

## 基线

- 上游仓库：https://github.com/Ckxkx/account-atlas （作者 Ckxkx / huichen）
- 锁定提交：`9349de429f35ac595dc5524f78de17f15b19fbd4`（2026-11-22，提交信息「v2.2：合并 dev（#2）」）
- 上游版本：v2.2；本地克隆在 `~/workspace/account-atlas-upstream`（只读参考，不在本仓库内）
- 许可：代码 GPL-3.0；品牌资产保留所有权利（见 NOTICE.md）。用户已拍板：
  绑哪儿整体转 GPL-3.0 开源，拿上游原生源码做底改。

## 引入的文件（已完成，2026-11-23）

已从上游 `native/` 引入到 `native-app/native/`（iOS 原生本体，13 个 Swift 文件）：
AppStore.swift、AtlasApp.swift、Components.swift、Details.swift、Forms.swift、
MapView.swift、Model.swift、Presets.swift、Settings.swift、SitesView.swift、
Sync.swift、WalletView.swift，外加 Info.plist 与 lproj/ 本地化目录
（Base / en / zh-Hans 三套，各含 InfoPlist.strings）。

一并引入：
- `icons/` → `native-app/icons/`（实测 112 个第三方服务图标，按域名命名，
  识别用途；权利归各服务商，与上游同样的使用方式，不声称为我方资产）
  ※ 2026-11-23 修订：这批 PNG 只留本地工作区，**不进 git 快照**（推送通道只
  收 UTF-8 文本）；且图标来源已改策略——CI 生成时以用户 Lige 包为主来源、
  appicons.py 为回退，详见下文「图标来源（CI 生成，不入库）」
- `tools/` → `native-app/tools/`（appicons.py + appicons.json + appicons.log，
  只复制未运行；与我方 convert-our-export.py 同目录共存）
- `LICENSE`（GPL-3.0 全文）与 `NOTICE.md` 已放**仓库根目录**
- `ios/Assets.xcassets` 的目录结构（Contents.json）→ `native-app/ios/Assets.xcassets/`，
  仅结构；AppIcon 图片为我方自有（见下节）

不引入：
- 安卓端 `android/`（本阶段只做 iOS）
- 上游网页版（index.html / app.js / styles.css 等）——绑哪儿网页版是自研的 src/，不动
- 上游 `ios/Info.plist` 与 `ios/main.swift`（壳时代文件，原生构建不用；
  构建用的是 native/Info.plist 模板）

## 品牌资产处理（已落实）

以下上游资产保留所有权利，**未复制、未使用**（已逐项核对，native-app/ 与
仓库根目录均无这些文件）：
logo.svg、icon.png、icon-512.png、android/icon-src/icon-1024.png、
ios/Assets.xcassets 内的上游 AppIcon 图片（icon-1024.png）、docs/wechat-reward.jpg。

App 图标为绑哪儿自有：源图 `src/icon.svg`，用仓库既有脚本
`scripts/gen-icons.py --appicon` 生成 1024×1024 全出血不透明（RGB）AppIcon。
本地已生成一份在 `native-app/ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png`
（生成时本机无 cairosvg/rsvg-convert，临时在 /tmp venv 装 cairosvg 渲染，
未动系统环境），但该 PNG **不进 git 快照**（二进制限制）——正式构建时由 CI
用同一脚本现生成到同一位置（ios.yml.adapted 的「Generate AppIcon」步骤，
与 build-ipa.yml 既有做法一致）；入库的只有 appiconset 的 Contents.json
（沿用上游单尺寸结构）。

## 换牌改造（已完成，只改标识与配置、未改功能逻辑）

实际改动点（逐项核对，native-app/native/ 内已无「账号星图 / huichen / Ckxkx」残留）：

- Bundle ID：`dev.huichen.atlas` → `xyz.465871.bind`（native/Info.plist；
  与现有壳 App 一致，保证覆盖安装、数据不丢）
- 显示名：CFBundleDisplayName / CFBundleName `Atlas` / `账号星图` → 「绑哪儿」
  （Info.plist + 三套 lproj 的 InfoPlist.strings；en 的 CFBundleName 用 `BangNaEr`，
  显示名仍为「绑哪儿」，与上游 en 保留中文显示名的做法一致）
- 可执行名：CFBundleExecutable `Atlas` → `BindAtlas`（构建产物 BindAtlas.app，
  见 ios.yml.adapted；纯内部标识，用户不可见）
- 源码用户可见文案：「账号星图」→「绑哪儿」，共 4 处——
  AtlasApp.swift 标题、Settings.swift 标题、Settings.swift 导入报错
  「这不是绑哪儿的备份文件」、Settings.swift GitHub 令牌链接 description 参数
- 同步 Gist 描述：Sync.swift 的 DESC「账号星图 · 加密数据…」→「绑哪儿 · 加密数据…」
  （Gist 定位靠文件名 atlas.enc.json，不靠描述，改文案不影响同步逻辑）
- 设置页「下载新版本」链接：`github.com/Ckxkx/account-atlas/releases/latest`
  → `github.com/Catsouth/bangnaer/releases/latest`（指向我方仓库发行版）
- 同步（加密 Gist / Gitee）功能代码完整保留，配置默认中性，
  未预置任何与原作者相关的服务痕迹；用户日后可自选
- **未改**（内部功能标识，改动即破坏数据/格式兼容）：
  UserDefaults 键 `atlas.*`、本地数据文件名 `atlas.json`、同步文件名
  `atlas.enc.json`、导出 JSON 的 `"app": "atlas"`、类型名 AtlasApp/AtlasData/AtlasIndex、
  截图启动参数 `-atlasTab`/`-atlasRoute`/`-atlas.theme`
- 代码注释原样保留；上游 Swift 文件本身无版权头注释，GPL 署名义务由
  仓库根 LICENSE + NOTICE.md 承担（见合规清单）
- deployment target 保持 iOS 17（上游 swiftc 目标），未降

## 构建管线（已备好，待用户上传）

上游 `.github/workflows/ios.yml` 的改造版已生成：`native-app/ios.yml.adapted`
（**未放 .github/workflows/**——我方推送通道写不了该目录，由用户在 GitHub
网页端上传为 `.github/workflows/ios.yml`；上传后建议删除旧 build-ipa.yml）：
- 源码/资源路径整体加 `native-app/` 前缀；触发 paths 改为
  `native-app/**` 与 `.github/workflows/ios.yml`
- App 名/可执行名 BindAtlas，产物名 `bangnaer-unsigned.ipa`，artifact 名 `bangnaer-ipa`
- 截图 job 的 simctl 目标 Bundle ID 改为 `xyz.465871.bind`
- 去掉上游 `$APP/www` 的 mkdir/rmdir 壳时代残留
- 保留上游结构：swiftc 直编 + 手工组装 .app + Info.plist 放在 zip 第一位
  + 模拟器截图 job + 构建号 = git 提交数 + 1000
- 文件头注释已列明与上游的全部差异点与上传方式
- 图标改 CI 现场生成（2026-11-23 修订）：两个 job 在组装前各加两步——
  「Generate service icons」（Lige 优先 + appicons.py 回退）与
  「Generate AppIcon from src/icon.svg」；触发 paths 相应增加
  `src/icon.svg`、`scripts/gen-icons.py`
- 注意：备稿初版 YAML 缩进丢失、解析不过，2026-11-23 已整体规范化为
  2 空格缩进并通过 yaml 解析校验（逻辑与上游一致，PlistBuddy/zip 命令
  保持上游原样）

## 图标来源（CI 生成，不入库）

2026-11-23 用户指示（原话：「图标可以用我那个仓库里的 lige」）：服务图标
主来源改为用户自己的 Lige 图标包，不再以他的 appicons.py 为主来源。

键对齐问题（映射设计的前提）：
- 原生端 IconStore（native/Components.swift）按**预设 domain**取包内图标：
  文件必须是 `icons/{preset.domain}.png`，目标清单 = Presets.swift 的
  111 个预设（name + domain）；包内没有时运行时自动回退 favicon.im 抓取 /
  首字母块，所以缺图标不致命。
- Lige 索引（https://raw.githubusercontent.com/Catsouth/lige_icon/main/ligeicon.json，
  基线见 ~/workspace/lige-icon/sync-state.json：版本 261119、1032 个图标）
  结构为 `{name, description, icons:[{name, url}]}`，按**服务名 slug**
  （英文/拼音，如 wechat、jingdong）键控，url 为图标直链。

实现：`native-app/tools/lige-icons.py`（仅标准库；CI 与本地同命令）。
对每个预设依次尝试候选 slug——别名表（weixin.qq.com→wechat、jd.com→jingdong、
pan.baidu.com→baidunetdisk、x.com→twitter、douyin.com→tiktok、apple.com /
icloud.com→apple、aliyun.com→alicloud 等，脚本内 ALIASES）→ 预设名 slug →
appicons.json 搜索词 → 域名首段 → 父域段；先精确名、再变体名
（wechat(1) 之类，偏好 原名 > (1) > 其余最短）。命中即下载为
`{domain}.png`（macOS 有 sips 时缩到 192×192，与上游产物同规格）。
没命中的预设把其 appicons.json 条目写出为 missing 清单，CI 下一步把
appicons.py 放进临时目录、只对这批缺失条目跑 iTunes 抓图回退
（appicons.py 接口：相对路径读 tools/appicons.json、输出 icons/{domain}.png、
仅标准库 + 系统 sips；全量 112 条约需数分钟，故只补缺失）。
全量覆盖率未实测（未全量下载）；样本自测 7 个域名命中 6（github / 微信 /
京东 / ChatGPT 变体 / X / 阿里云），music.163.com 正确落入回退清单。

不入库范围：`native-app/icons/` 全部 PNG（112 个）与 AppIcon 的
icon-1024.png 只保留在本地工作区，推送清单排除（见下节）；CI 构建时
按上述流程在 runner 上重新生成，组装步骤 `cp -R native-app/icons`
与 actool 步骤不变。

## 文本推送清单（native-app/，最终版）

我方 GitHub 快照推送通道只接受 UTF-8 文本文件，以下 24 条为 native-app/
下应推送的全部文本路径（父代理照单推送；LICENSE 与 NOTICE.md 在仓库
根目录、属仓库级文件，不在本清单内）：

1. `native-app/ADAPTATION.md`
2. `native-app/ios.yml.adapted`
3. `native-app/ios/Assets.xcassets/Contents.json`
4. `native-app/ios/Assets.xcassets/AppIcon.appiconset/Contents.json`
5. `native-app/native/AppStore.swift`
6. `native-app/native/AtlasApp.swift`
7. `native-app/native/Components.swift`
8. `native-app/native/Details.swift`
9. `native-app/native/Forms.swift`
10. `native-app/native/Info.plist`
11. `native-app/native/MapView.swift`
12. `native-app/native/Model.swift`
13. `native-app/native/Presets.swift`
14. `native-app/native/Settings.swift`
15. `native-app/native/SitesView.swift`
16. `native-app/native/Sync.swift`
17. `native-app/native/WalletView.swift`
18. `native-app/native/lproj/Base.lproj/InfoPlist.strings`
19. `native-app/native/lproj/en.lproj/InfoPlist.strings`
20. `native-app/native/lproj/zh-Hans.lproj/InfoPlist.strings`
21. `native-app/tools/appicons.json`
22. `native-app/tools/appicons.py`
23. `native-app/tools/convert-our-export.py`
24. `native-app/tools/lige-icons.py`

明确排除（勿推）：`native-app/icons/*.png`（112 个，CI 生成）、
`native-app/ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png`（CI 生成）、
`native-app/tools/appicons.log`（上游运行日志，无推送价值）。

## GPL 合规清单

- [x] LICENSE（GPL-3.0 全文）与 NOTICE.md 已放到仓库根目录（2026-11-23）
- [x] 源码内原作者内容保留原样：上游 Swift 文件无版权头注释，代码注释未删改；
  换牌仅动标识/文案（逐项见上），类型名与内部标识未改
- [x] 品牌资产已剔除，App 图标与名称为绑哪儿自有（见上）
- [ ] 仓库转公开（用户手动操作）——GPL 分发义务：发布 IPA 时必须能取得对应源码
- [ ] 发版说明中注明「基于 Ckxkx/account-atlas（GPL-3.0）改造」及上游链接
- [x] 本文件记录基线提交与改造范围

## 数据迁移（已完成）

`native-app/tools/convert-our-export.py`：绑哪儿网页版导出 JSON
（bind-backup-*.json）→ atlas 原生整表导入格式
`{app:"atlas", version:1, identities, accounts, deleted}`，
字段对齐上游 `native/Model.swift`（基线 9349de4）。

- 身份：email/phone 直通；wechat/apple 转 login+provider；
  google/qq/custom 并入 email/login，原类型存 extra.bindType 往返可还原；
  color 按网页版类型色补；数组下标写 order 保顺序。
- 服务：link → account，username → handle，identityId → identityIds[单元素]；
  method/status/rebindDone 进 extra 透传（bindMethod/bindStatus/bindRebindDone）；
  category 按域名小表启发式推断，默认「其他」。
- 回收站：trash 快照转 deleted 墓碑（原生端无回收站，快照内容不保留）。
- 已知丢失项（脚本 docstring 有全表）：trash 快照内容、method/status 在
  原生 UI 不展示、登录卡 via 无数据、notes/esim 无数据。
- 自测（仿网页版 buildDemoDB 样本 + 1 条 trash）：身份 4→4、服务 11→11、
  绑定 11→11、墓碑 1，字段级断言 9 项全过；文件模式端到端亦通过。

## 后续阶段清单（待移植/待建功能）

1. 球形星系关系图（v1.10.6 在壳原型里验证中的球形视图，移植为原生视图；
   上游原生关系图是双列连线图，不满足我们的星系形态）
2. WebDAV 备份（网页版已有实现与服务端通道，原生端新写；上游只有加密 Gist 同步）
3. 自动识别导入（Vaultwarden/Bitwarden 导出、浏览器密码 CSV、粘贴文本识别——
   网页版已有，原生端移植）
4. 回收站（上游只有墓碑 + 单步撤销；网页版有完整回收站，需在原生端新做，
   数据层可借墓碑 + 快照扩展）
5. PIN 屏幕锁（网页版已有，原生端用本地校验 + 可选生物识别）
6. 换绑清单、账号体检、服务状态（绑哪儿独有功能，原生端按网页版逻辑移植）
7. 数据转换器反向（atlas 原生 → 网页版格式，如需双向迁移再补）

## 安全确认与阻塞（已解决）

- 上游克隆内容未通过运行环境执行风险检查（其文件在被复制/处理时存在触发
  代码执行的可能），引入前两轮被安全规则拦下。用户在被完整告知风险后，
  于 2026-11-23 06:20 回复「确认引入上游源码，继续改造」、06:21 再次明确
  「明白风险，确认继续引入他的源码」，知情确认齐备后已引入。本阶段全程只把
  上游文件当文本/资源处理，未运行上游任何脚本（tools/appicons.py 只复制）。
- 剩余手动事项（用户操作）：仓库转公开、把 native-app/ios.yml.adapted
  上传为 .github/workflows/ios.yml（推送通道写不了该目录）。
