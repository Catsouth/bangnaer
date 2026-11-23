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

绑哪儿自研新增（不在上游内，swiftc 通配 `native/*.swift` 自动纳入构建，
无需改工程文件）：WebDAV.swift（WebDAV 备份 + Keychain 封装）、Trash.swift
（回收站）、Lock.swift（PIN 屏幕锁），2026-11-23 第一批功能移植时加入；
SmartImport.swift（智能导入：识别引擎 + 候选预览页），2026-11-23 第二批
功能移植时加入；三套 lproj 各补 Localizable.strings（新功能主要文案）。

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

我方 GitHub 快照推送通道只接受 UTF-8 文本文件，以下 31 条为 native-app/
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
25. `native-app/native/Lock.swift`（第一批移植新增：PIN 屏幕锁）
26. `native-app/native/Trash.swift`（第一批移植新增：回收站）
27. `native-app/native/WebDAV.swift`（第一批移植新增：WebDAV 备份）
28. `native-app/native/lproj/Base.lproj/Localizable.strings`
29. `native-app/native/lproj/en.lproj/Localizable.strings`
30. `native-app/native/lproj/zh-Hans.lproj/Localizable.strings`
31. `native-app/native/SmartImport.swift`（第二批移植新增：智能导入）

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

## 功能移植进度

用户已拍板十项功能全加（2026-11-23），分批移植。行为基准为网页版
`src/index.html` 的对应实现，数据模型基准为上游 `native/Model.swift`。

### 第一批（已实现，2026-11-23，本地提交未推送）

1. **WebDAV 备份**（新增 `native-app/native/WebDAV.swift`）
   - 与上游加密 Gist 同步**并存**：Gist 是逐条合并 + 端到端加密；WebDAV 是
     整份明文备份/整表恢复，UI 文案已写清区别。`Store.onSaved` 同时挂两边调度。
   - 配置：服务器地址/用户名/文件路径存 UserDefaults，**密码只进 Keychain**
     （Security 框架小封装，同文件内）；设置页有「填入 465871.xyz 预设」
     （地址 https://dav.465871.xyz/dav + 路径 account-atlas/atlas.json，
     用户名密码仍手填）。
   - 策略与网页版一致：零轮询；变更后 2 秒防抖 + 内容哈希（sortedKeys 编码的
     SHA256）比对，没变不传；拉取只在手动「从云端恢复」。恢复前先把本机数据
     写一份 `atlas-before-restore.json` 快照再整表替换（Store.adopt）。
   - PUT 遇 404/409 先 MKCOL 父目录再重试一次；PROPFIND 测试连接如实报状态码；
     401/403/404/405 都有人话提示。失败只记状态行，不阻塞、不丢本地数据。
   - 示例数据（demo）不备份，与网页版护栏一致。
2. **回收站**（新增 `native-app/native/Trash.swift`；`Model.swift` 的
   AtlasData 加 `trash` 字段，旧数据缺省为空、解码兼容）
   - 条目两种形状对齐网页版：account = 单条服务快照；identity = 身份快照 +
     其引用到的服务快照（links）+ via 指向它的登录卡 id（viaFrom）。
   - 删除路径收口：详情页删账号/删身份都走 `deleteAccountToTrash` /
     `deleteIdentityToTrash`（身份删除保持上游语义：账号保留、只解绑）；
     删除仍写墓碑（stamp 机制不变，同步合并语义保持）；`Sync.merge` 对
     trash 按条目 id 做并集，避免 adopt 时被冲掉。
   - **取舍：删除不再提供撤销 toast**——回收站是唯一恢复通道，避免与撤销的
     整表快照回滚双轨冲突（网页版同理）。其他编辑类操作仍保留撤销。
   - 界面：设置页入口（带计数）→ 列表（名称/类型/删除时间），支持恢复
     （id 冲突跳过并计数提示；恢复身份时重新挂回 links 的绑定与 via）、
     彻底删除（只删条目、墓碑保留）、一键清空（带确认）。清空全部数据
     时回收站一并清空。
3. **PIN 屏幕锁**（新增 `native-app/native/Lock.swift`；Info.plist 模板补
   NSFaceIDUsageDescription「用于解锁绑哪儿」）
   - PIN 4–6 位，只存**加盐 SHA256**（随机 16 字节盐）+ 位数，存
     UserDefaults；设置/修改/关闭都在设置页「屏幕锁」，关闭与修改须先验
     当前 PIN。
   - 锁定时机：冷启动即锁（AppLock 初始化，锁屏盖在展示层之上，锁定时
     还会关掉已打开的 route/sheet）；切后台超过 60 秒返回时再锁。
   - 数字键盘 UI：圆点指示、输满位数自动校验、输错震动 + 摇晃动画；
     连续错 5 次冷却 30 秒（截止时间落盘，重启不能绕）。
   - 可选面容 ID：开启 PIN 后可在设置里开「面容 ID 解锁」（LocalAuthentication，
     锁屏出现时自动尝试一次 + 键盘区有按钮重试），失败回落 PIN。

### 第二批（已实现，2026-11-23，本地提交未推送）

1. **自动识别导入**（新增 `native-app/native/SmartImport.swift`；入口在设置页
   与「导入备份」同区，名为「智能导入」）
   - 行为对齐网页版识别引擎（identityFor / addCandidate / parseVault /
     parseCsv / parseText）：身份判定顺序含 @ → 邮箱、1 开头 11 位 → 手机号
     （先于 QQ）、纯数字 + 来源 qq.com → QQ、其余号码形 → 手机号。
   - 三路来源：①文件——Vaultwarden/Bitwarden 未加密导出 JSON（items[].login
     的 uris + username；加密导出与绑哪儿自身备份都有人话拦截提示）、浏览器
     密码 CSV（Chrome/Edge 的 name,url,username,password 与 Safari 的
     Title,URL,Username,… 都按表头取列，无表头退回网页版的列猜测；自写规范
     CSV 分词处理引号/逗号转义）；②粘贴文本（邮箱/手机号正则 + 预设目录扫描，
     文本猜的标低置信默认不勾）；③剪贴板（进页只查 hasStrings 不触发隐私
     提示，点按钮才读内容并直接扫描）。
   - **密码零接触**：login.password 键与 CSV 的 password 列从不读取、从不存储。
   - 候选先预览后落库：逐条可勾选、可改服务名、可改绑定的身份（已有身份 /
     本次新认出的身份 / 先不绑）；新身份单独成卡列出，勾选确认后才建卡
     （标签「自动识别」），未勾选的新身份被引用时该条绑定跳过并计数（网页版
     同口径）。
   - **去重口径**（与网页版的静默跳过不同，按产品要求显式标注）：同域名 +
     同身份已存在 → 「已绑定」默认不勾、落库跳过；同域名不同身份 →
     「新增绑定」（往已有 Account 的 identityIds 追加，handle 为空时才用
     识别到的账号名补）；无同域名服务 → 「新服务」（按预设分类建 Account，
     无预设归「其他」）。候选内部再按 域名|身份|账号名 去重；整批一次
     Store.mutate 落库（撤销、盖戳、墓碑语义不变）。示例数据按网页版口径：
     识别与去重对着空库算，落库前先清示例。
2. **身份卡扩类型**（存储不变：type 仍是 email/phone/login，provider 仍是
   自由字符串；只扩集合与 UI，`Model.swift` 新增 LoginProviders 元数据表）
   - provider 五种：wechat 微信 #07c160 / apple Apple 账户 #1d1d1f / qq QQ
     #12b7f5 / google Google #4285f4 / custom 自定义 #8e8e93。默认色参照
     网页版类型色（QQ 蓝、Google 蓝取网页值）；**自定义与网页版不同**：
     网页版是紫 #b44fe8，本批按产品口径用中性灰，一行可改回。
   - 符号：微信双气泡、Apple 用 apple.logo（沿用既有画法），QQ / Google 用
     字母圆标（q.circle.fill / g.circle.fill），自定义与未知值用
     person.badge.key.fill——都是 SF Symbol，不用官方 logo 图。
   - 校验：apple 沿用邮箱或手机号；google 须邮箱形态；qq 宽松（数字或邮箱
     均可，非空即可）；wechat / custom 不限。隐私打码：邮箱形态的登录账号
     （Google 等）按邮箱规则打码。
   - **分组修正**：kindName 改为按 provider 返回（此前非 apple 的 login 一律
     显示「微信」是错的）；未知 provider 回退显示「登录账号」不崩，编辑表单
     里原样保留、点选已知类型才改。卡片顺序页（OrderView）把原「登录」一
     组拆成按 provider 分组，各组内拖动只动本组槽位，不再重排整个数组。
   - 表单：新建/编辑身份给出五种 provider 选择（3 列胶囊）；custom 时标签
     字段即平台名（存 label，卡片显示「自定义 · 平台名」）；占位文案、
     字段标题、键盘类型、校验提示都按 provider 分开。LOGIN_SKINS 补
     QQ 蓝 / 谷歌蓝 / 云灰三款，切 provider 时卡面跟随换色。
   - 详情页「通过 X 登录的网站」改用 kindName（此前写死微信/Apple）；
     卡包菜单与空卡文案「添加微信或 Apple 账号」改为「添加登录账号」。
   - 数据衔接：转换器已写入的 3 张 provider="qq" 身份卡，本批后正确显示
     为 QQ 卡（蓝色、QQ 分组）；extra.bindType 未动。

### 追加（第三批同期，2026-11-23）：「用绑哪儿打开」导入通道

- Info.plist 声明 CFBundleDocumentTypes（public.json / public.data，Viewer +
  Alternate，只读不抢默认应用）+ LSSupportsOpeningDocumentsInPlace=true；
  AtlasApp 的 onOpenURL 接住从「文件」/分享进来的备份（security-scoped 读后走
  Store.importBackup，成败都用现有 toast 口径）。起因：真机导入备份时系统文件
  选择器对本地 json 反复点不动（已复现三次），绕开选择器；智能导入格式不在此
  通道处理。

### 补丁批（已实现，2026-11-23，第三批真机验收反馈，共七条，本地提交未推送）

1. **服务行左滑/长按三动作**（Components.swift 新增 `AccountRow` / `AccountMenu` /
   `AccountSwipeActions`；SitesView、WalletView Timeline、Details 身份详情换用）
   - ScrollView 系列表（全部 App、卡包时间线、身份详情的服务列表）没有原生
     swipeActions，用自绘 `AccountRow`：行内 Button 外包一层水平 DragGesture
     （纵向占优的拖动忽略、归还滚动），左滑露出纯图标按钮（54pt/个）——
     打开网站（safari，蓝）/ 编辑（pencil，灰）/ 删除（trash，红，走
     `deleteAccountToTrash` 进回收站）；按钮只带无障碍标签、无可见文字。
     ReelRow 的玻璃底是半透明的，行底垫了一层不透明 systemBackground 圆角，
     防止关闭时按钮透出。无域名时打开网站不出现、条宽按 2 个按钮算（与详情页
     「前往登录」同口径：cleanDomain 为空即禁用）。
   - List 系列表（全局搜索、账号体检明细）用原生 `.swipeActions` 同构实现
     （声明顺序保证视觉左→右同为 打开网站/编辑/删除，allowsFullSwipe 关）。
   - 长按统一挂 `AccountMenu`（contextMenu，带文字三项）；卡包 AppGrid 的
     图标格也补了同一长按菜单。行点按进详情不变；滑动条打开时点行只关条。
   - **取舍**：换绑清单的行是勾选语义（一行=一个待换绑项，点按切换完成态），
     不是普通服务行，未加滑动/长按删除，避免误触把清单项删掉。
2. **关系图页头部**（SphereMap.swift）
   - `.navigationTitle("关系图")` 改为空标题（其他页标题不受影响，顶栏 + 菜单保留）；
     图例 chip 从底部移到球体上方安全区内（topLeading，顶距 10），字号 12→13、
     圆点 8→9、内边距加大；提示文案随图例一起上移（只出现一次）。
3. **底栏改造**（AtlasApp.swift RootView；Settings.swift 加 `embedded` 标志）
   - 胶囊内四个页签：卡包 / 全部 App / 关系图 / **设置**（gear 图标下带「设置」
     二字，与其余页签同为图标+10pt 文字）；右侧圆钮只剩搜索，设置圆钮删除。
   - 设置改为 TabView 第四个 tab 的根视图（SettingsSheet(embedded: true)，
     embedded 时不显示 sheet 用的「完成」按钮）；原 `Route.settings` 与
     SheetHost 分支保留未删（已无入口指向，截图启动参数 -atlasRoute settings
     改为直接选第 4 页签）。
   - 选中药丸：matchedGeometryEffect 沿用，胶囊容器加 `.animation(snappy,
     value: tab)` 保证任何路径切页药丸都滑动；页签本身不再是 Button，整条
     胶囊挂一个 DragGesture(minimumDistance: 0)：点按=定位选中，按住横拖=
     逐格跟随（64pt 步距：4 内边距 + 62 格宽 + 2 间隔），RootView 既有的
     `.sensoryFeedback(.selection, trigger: tab)` 给每格轻触觉。iOS 17 无
     Liquid Glass API，仍是 ultraThinMaterial + 高光描边近似，无折射。
4. **系统底栏彻底隐藏**：`.toolbar(.hidden, for: .tabBar)` 从 TabView 容器
   （不生效、截图里透出原底栏）改落到四个 tab 各自 NavigationStack 的根内容上
   （WalletView / SitesView 的 ScrollView、MapView 的 GeometryReader、
   SettingsSheet 的 Form）；TabView 上的旧修饰已删除。内容区原有 96pt 底部
   留白是为悬浮玻璃栏留的，不变。
5. **球体图标缩放与光晕**（SphereMap.swift Canvas）
   - 图标半径乘系数 `min(1, zoom)`：捏合缩小时图标随球一起小，放大时封顶
     1 倍正常大小；位置投影仍用真实 zoom。命中测试（tap）用同一封顶后半径，
     绘制与可点区域一致。
   - 删掉每个图标外 1.5 倍半径的分组色光晕椭圆填充；分组区分只靠圆环描边。
6. **搜索打开自动聚焦**（AtlasApp.swift SearchView）
   - `.searchable` 改用 `isPresented: $searchActive` 绑定；页面 onAppear 后
     延迟 350ms 置 true（避开 sheet 呈现动画抢焦点——同帧设置会被系统丢弃，
     这是真机上键盘不弹的根因）；用户点搜索栏「取消」使 isPresented 变 false
     时顺手 dismiss 整个搜索页。验收口径：点底栏搜索圆钮 → 页面出现 → 键盘
     随即弹出、光标在输入框，一次点按完成。
7. **图例 chip 点按聚焦 + 长按丝滑化**（SphereMap.swift）
   - focus 状态统一为一个枚举 `SphereFocus`（.identity(String) / .group(
     SphereGroup)）：演示脚本经 demoFocus 写的还是 identity 分支，chip 点按
     写 group 分支，Canvas 淡化（非聚焦 0.22）只读这一个状态，不再有两套。
     点 chip = 聚焦该组（chip 呈选中态：组色 28% 底 + 组色描边），再点同一
     chip 或点球面空白处（tap 未命中任何气泡时）取消聚焦。
   - 长按卡顿根因是手势抢识别：原先拖动/捏合/长按三个 simultaneousGesture
     挂在整个 ZStack 上，长按 chip 时 chip 的 contextMenu 与整页长按（弹
     confirmationDialog）同时触发、互相闪。现在：手势只挂球体本身，图例在
     手势区之外、chip 的 contextMenu 独立工作；球面长按改 highPriorityGesture
     （拖动等它落判）+ GestureState 的 updating，**识别成功的一刻**（手指未抬）
     经 onChange 触发 fireAddMenu（先 commitSpin 冻住球、清手势状态再呈现），
     全程只有一个呈现路径。拖动侧配套加了起始位移补偿（dragOrigin）：等长按
     落判的那段位移不计入旋转，球不会在起转瞬间跳一下。

### 第二轮细化（已实现，2026-11-23，构建号 1025 真机验收反馈，共六条，本地提交未推送）

1. **关系图图例改分段控件 + 第三组改名**（SphereMap.swift / WalletView.swift）
   - 图例从三个独立 chip 改为卡包页 KindSwitch 同款分段控件：等宽三段
     （图标+名称+计数横排）装进一个玻璃胶囊，选中段以组色 30% 填充 + 组色
     描边，matchedGeometryEffect 滑动（segNS）。点按聚焦/再点取消仍走
     SphereFocus.group，未改状态机制；提示文案保留在分段条下方。
   - 第三组名称统一为「自定义」：球体图例 SphereGroup.custom 本就显示
     「自定义」，本次把卡包页分段控件的「登录」段改名为「自定义」，两处
     一致。前往登录、登录方式、IdentityForm 类型选择器里的「登录」等无关
     文案未动。
2. **长按菜单按组精简**（SphereMap.swift `addMenu(for:)`）
   - 自定义段：添加邮箱/添加手机号/添加登录账号三项不变；Email 段只留
     「添加邮箱」；SIM 段只留「添加手机号」；未绑定段（有未绑定服务时才
     出现）保留三项。球面空白处长按的 confirmationDialog 三项不变。
3. **添加表单带自动识别候选**（Forms.swift IdentityForm / SmartImport.swift）
   - SmartImport 的自由文本识别抽出共用函数 `recognizedContacts(in:)`
     （邮箱/手机号两条正则、+86 归一化、去重），parseFreeText 改为复用它，
     识别口径单一来源。
   - 新建身份时（编辑已有身份不出），IdentityForm 在值输入框上方加一行
     「自动识别 · 来自剪贴板」候选 chip：onAppear 及类型/provider 变化时扫
     剪贴板，按表单类型过滤（邮箱表单只列邮箱、手机号表单只列手机号；
     登录表单仅 Apple/Google 这类邮箱形态 provider 列邮箱，微信/QQ/自定义
     不出），已存在同类身份的值不再出现，点 chip 直接填入值输入框；剪贴板
     无可识别内容时整行不出现。不读密码、不新造识别引擎。
4. **卡包滑卡重影修复**（WalletView.swift deck）
   - 根因：scrollTransition 里的 rotation3DEffect（perspective 0.6）会把卡面
     投影到布局框**之外**（朝向观众的一边被透视放大、越出原框），deck 又开
     了 scrollClipDisabled 没有任何裁剪，同时 opacity 随 phase 压到 0.65 使
     两张卡都半透明——相邻卡的投影在屏幕上重叠、彼此透印，就是录屏里的
     重影叠字。修法：过渡只保留 scale（1→0.94），去掉旋转与透明度；缩放不
     出布局框、卡面保持不透明，两张卡在物理上不可能再叠印。AddCard 同步
     改为只缩放。
5. **捏合误弹菜单修复**（SphereMap.swift 手势仲裁）
   - 机制：SwiftUI 手势数不到触点数，长按只盯它那根触点——双指落下时第一指
     在第二指到位前静止满 0.45s、或捏合收尾手指变慢，都会让被盯的触点停在
     12pt/0.45s 窗口内完成长按识别。修法：捏合每次 onChanged/onEnded 都打
     时间戳 lastPinchAt；fireAddMenu 在 pinch 活跃中（pinchBase != nil）或
     距最后一次捏合活动 0.35s 内直接不弹；若菜单已在落指阶段误弹，捏合一
     开始（首次 onChanged）立即把它收掉。单指长按不受影响：捏合之后真正
     开始的长按要 0.45s 后才完成识别，早已过 0.35s 守卫窗。
6. **底栏照参考图改版**（AtlasApp.swift RootView）
   - 四个页签图标放大到 27pt（原 19）、文字 11pt，格子 64×58（原 62×46），
     胶囊随之增高；选中项改为深色实心药丸（white 0.10 近黑填充、双色模式
     一致，与玻璃胶囊形成对比），图标+文字染 Color.accentColor；未选项改
     为 .primary（原 .secondary，对照参考图未选为白色/主色）。滑动药丸的
     matchedGeometry 与按住拖动切页保留，拖动步距按新几何改为 66pt；搜索
     圆钮放大到 60 直径、图标 23pt。设置页作为 tab 时 Form 加 88pt 底部
     contentMargins 防新栏遮尾（sheet 模式不加）。卡包/全部 App 原有 96pt
     底部留白仍大于新栏总高（约 74pt），未动。

### 第三轮细化（进行中，2026-11-23，构建号 1026 真机验收反馈，本地提交未推送）

1. **底栏 Liquid Glass 透明化**（AtlasApp.swift glassFill/glassThumb）
   - 用户批示「改成 ios27 透明」：原胶囊 ultraThinMaterial 满不透明度 +
     选中药丸 Color(white: 0.10) 实心，深色下是一坨实心黑。iOS 17 无系统
     Liquid Glass API，改手工分层近似：材质层 opacity 降到 0.72（内容在
     玻璃下明显透出、滚动时可见流动）；叠一层竖直光泽渐变（顶部白 0.20 →
     0.45 处 0.05 → 0.7 处透明 → 底部黑 0.05 的微影）模拟光线穿过玻璃；
     描边改镜面边缘渐变（顶部白 0.75 → 0.22 → 0.10），即顶部高光线 +
     两侧渐隐。胶囊与搜索圆钮共用同一 glassFill，只是形状不同。
   - 选中药丸去实心，改「玻璃透镜」glassThumb：半透明白霜填充（浅色
     0.50 / 深色 0.20，深色下保持黑玻璃不发灰）+ 顶部高光渐变 + 镜面
     描边（0.85→0.30）+ 柔和抬升阴影（黑 0.16、r7、y2.5）；滑动跟随
     （matchedGeometryEffect）与拖动切页逻辑未动，选中图标/文字仍染
     accentColor。可读性靠材质自身的背景模糊，不靠不透明填充。

2. **捏合误弹复修：时间窗改状态机**（SphereMap.swift）
   - 第二轮的 lastPinchAt + 0.35s 守卫窗真机仍漏：捏合收尾后留一指静止，
     长按在窗外完成识别照样弹。根因不变（SwiftUI 手势数不到触点数，
     长按只盯一根触点），口径改为序列级标志 pinchSeenInSequence：
     捏合 onChanged 一动就置位并收掉已弹菜单；fireAddMenu 见标志直接
     不弹，且该次识别会把标志消费掉（吞一次、清一次）。
   - 「全部离屏」SwiftUI 拿不到触点数，用手势结束信号组合近似清标志：
     拖动 onEnded 且无捏合进行中；捏合 onEnded 且无拖动/长按识别占用；
     长按 pressHeld 回落（该触点序列结束）；一次点按完成（tap 入口）。
   - 残留边界：捏合后一根手指完美静止、且整段序列里没有任何结束信号
     触发时，标志保留到那根手指自己的迟到识别来消费它——最坏结果是
     一次长按被吞，绝不会把菜单漏进下一次干净的触摸序列。单指长按
     （序列内无捏合）路径完全不变，不误伤。

3. **分段长按出身份列表表单**（SphereMap.swift segment/GroupIdentitiesSheet）
   - 原落点是 segment 的 .contextMenu { addMenu(for:) }，只有添加项。
     改为长按弹 sheet（.medium/.large 两档）：先列该组现有身份卡——
     IdentityGlyph + skinGradient(identity.color) 着色，标题 store.title
     （备注名、无备注回退值），副行值（无备注时显示类型名），尾部绑定数
     角标走 store.accounts(of:) 计数、染身份色；点某张卡 → SphereFocus
     .identity 聚焦（带第 4 条连线）并关表单。添加入口保留在表单底部
     独立 Section，按组精简规则抽成共用函数 groupAddOptions（Email 只
     加邮箱、SIM 只加手机号、自定义/未绑定三项）；该组无身份时显示
     空态文案「这一组还没有身份卡」+ 添加入口。
   - 呈现路径隔离：添加的 route 不能叠在组表单之上，onAdd 只记
     pendingAdd，组表单 onDismiss 后才 store.route 跳转。
   - segment 本体由 Button 改为普通视图 + onTapGesture/onLongPressGesture
     组合：Button 在长按识别完成后抬手仍会触发 action，会在表单背后
     把聚焦切掉；手势对则天然互斥。无障碍补回 .isButton/.isSelected
     traits 与合并标签。捏合误触不波及此路径：表单只由分段长按打开，
     分段在球面手势区之外（补丁批已隔离），且第 2 条状态机管的是球面
     空白长按菜单。

4. **身份聚焦连线**（SphereMap.swift Canvas）
   - focus 为某个身份（.identity）时，从球心向该身份绑定的每个服务气泡画
     一条连线，颜色取该身份自己的 color；端点用气泡的投影坐标，在气泡
     绘制之前画（线在气泡下层），Canvas 本就不参与点按、无遮挡问题。连线
     透明度沿用气泡的深度曲线（0.10+0.90·t^1.4）再乘 0.55，背面气泡的线
     随其一起淡出；旋转/缩放/惯性滚动时随投影逐帧重绘。组聚焦（.group，
     点按分段）不画线——整组连线是满屏线团；取消聚焦（点球面空白）线条
     随 focus 清空自动消失。演示脚本经 demoFocus 聚焦身份时同样出线。

### 第四轮细化（进行中，2026-11-23，构建号 1028 真机验收反馈，本地提交未推送）

1. **彻底移除球面空白处长按弹「添加身份」菜单**（SphereMap.swift）
   - 决策与原因：真机录屏实锤——球面空白长按与拖动旋转根本分不开（手指
     落下稍停顿即完成长按识别），第二轮 0.35s 时间窗、第三轮序列级状态机
     （pinchSeenInSequence）两轮守卫都没压住，一碰空白就弹、还叠弹两层。
     父代理拍板不再修补、直接删手势：添加身份的入口已有右上角「+」与
     分段长按身份列表两个正道，空白长按纯属重复入口。
   - 删除清单：`longPressGesture` 定义与 `.highPriorityGesture` 挂载、
     `fireAddMenu()` 函数、`showAddMenu` 状态与 `.confirmationDialog
     （"添加身份"）` 呈现块；守卫状态 `pressHeld`（@GestureState）、
     `pinchSeenInSequence`、`lastLongPress` 及其在 drag/pinch/tap/body
     onChange 中的全部读写（捏合 onChanged 的关菜单逻辑、tap 入口 0.6s
     防抖一并删，tap 改为直接处理点按）。`pressTick` 保留——分段长按与
     拖动起转的震动还在用。文件头注释与 groupAddOptions 注释同步改掉。
   - 文案：球页提示「拖动旋转 · 捏合缩放 · 长按添加身份」改为「拖动
     旋转 · 捏合缩放 · 长按分段查看身份」，三套 Localizable.strings 已
     补该键（旧键此前未入表、一直走字面回退；en 译 "Drag to rotate ·
     Pinch to zoom · Long-press a segment to view identities"）。
   - 删除后球面手势只剩：拖动旋转+惯性、捏合缩放、点按气泡进详情、
     点空白清聚焦。分段长按弹身份列表（第三轮第 3 条）与右上「+」未动。

2. **设置页「数据」区行顺序调整**（Settings.swift）
   - 用户截图批示并改口定版：回收站、智能导入提到该区最前（回收站在
     智能导入前面）。最终顺序为 回收站 / 智能导入 / 导出备份 / 导入备份 /
     载入示例（载入示例仍是未开同步时才出现、仍居最后）。仅整块移动行
     顺序，各行实现与文案未动，其他 Section 未动。

### 第五轮细化（2026-11-23，构建号 1029 真机验收反馈，本地提交未推送）

1. **身份聚焦改版：只显示选中身份绑定的气泡**（SphereMap.swift）
   - 此前（第三轮）：长按分段选身份后，其他气泡变淡 + 球心拉连线。用户
     改为：选好身份后球面只出现该身份绑定的软件气泡，其余气泡完全隐藏
     （不画、不可点）；连线保留（球心→显示中的气泡）；点空白恢复全部。
   - 实现口径：focus 为 .identity(fid) 时，canvas 在投影排序后先按
     `account.identityIds.contains(fid)` 过滤绘制集合，连线与气泡绘制
     随集合走；tap 命中测试跳过未绑定气泡，未命中即走现有点空白清
     focus 逻辑恢复全部。原 .identity 的变淡分支随之失效（绘制集合里
     已无未绑定气泡），dimmed 对 .identity 恒为 false。
   - **组聚焦（.group）不变**：仍是整球绘制 + 非本组变淡，用户只改了
     身份聚焦这一条，未顺手改动。

2. **去掉滑动球后的震动**（SphereMap.swift）
   - 用户原话「去掉滑动球后的震动效果」：dragGesture onEnded 起转时
     的 `pressTick &+= 1` 已移除，拖动旋转/松手起转不再触发触感。
   - 保留：分段长按弹身份列表的震动（pressTick 唯一剩余触发源，变量
     与 .impact 修饰符保留）、气泡点按与分段点按的 tapTick 选择反馈。

### 第六轮细化（2026-11-23，构建号 1030 真机验收反馈，本地提交未推送）

用户录屏反馈两点：153 个气泡的球拖动明显卡顿；转动有「死角」——竖直
方向转到头就顶死（旧实现 pitch 被 clampPitch 限在 ±1.25 rad）。

1. **转动改四元数 trackball，取消一切角度上限**（SphereMap.swift）
   - 数学表示：新增 `Quat`（单位四元数，Hamilton 积 + 轴角构造 +
     归一化 + 展开式旋转向量）。姿态状态由 `@State yaw/pitch` 改为
     单个 `@State q: Quat`；初值 = Rx(-0.3)∘Ry(0.6)，与旧开局视角
     （yaw 0.6、pitch -0.3）逐点一致。
   - 拖动：增量式合成——每个 onChanged 样本按「绕屏幕空间中与拖动
     方向垂直的轴（轴 = (dy, dx, 0)，y-up 口径下右拖绕 +Y、下拖绕
     +X、斜拖自然合成）、角度 = 步长 × radPerPoint（0.0055 不变）」
     生成 dq，前乘到 q 上并归一化防漂移。首样本仍只作基线不旋转
     （承接补丁批的 minimumDistance 吸收，无跳变）。屏幕空间前乘是
     无死角的关键：任何方向滚到底都不存在被夹住的角度。
   - 惯性：`SphereSpin` 按新表示重写——存 q0 + 固定屏幕空间轴 +
     初角速度 omega（分量上限 ±9、起转阈值 0.25 与旧口径一致），
     角度按 omega·(1-exp(-1.8t))/1.8 推进（衰减常数不变），结束时
     commitSpin 把姿态折回 q。
   - 投影：`SphereMath.project` 改吃 Quat（内部 q.rotate 后同旧
     focal 3.2 透视），focal/缩放/深度 alpha 口径全不变；tap 命中
     测试与 canvas 共用同一 project + 同一 q（惯性未停时取 spin 的
     实时姿态），点哪算哪。
   - 删除清单：`clampPitch`、`pitchLimit`、`SphereMath.rotate(yaw:pitch:)`、
     旧 SphereSpin 的 yaw0/vx/vy 表示、MapView 的 yaw/pitch/dragBase/
     dragOrigin 状态。外部入口（demoFocus/onChange）只动 focus 不动
     姿态，无影响。

2. **流畅度治理（只做三件，不推翻渲染层）**（SphereMap.swift）
   - 气泡规格缓存：`bubbles` 原为计算属性，body 每次求值（含拖动
     每一帧）都从 index 重算，canvas/tap/groupCounts 多处重复调用。
     改为 `@State cachedBubbles` + 静态 `computeBubbles(index)`；
     canvas/tap/counts 统一读缓存（未填充时回退现算，保证首帧正确）。
     刷新信号用 Store 现有机制：index 在 data 的 didSet 里同步重建，
     故挂 `.onChange(of: store.data.accounts)` 与
     `.onChange(of: store.data.identities)` 两个钩子（Account/Identity
     均 Hashable）+ onAppear 首填——computeBubbles 的全部输入（账户
     顺序、绑定、身份类型）都被覆盖；无关编辑最多多刷新一次，不会
     出现陈旧球。
   - 运动中降载：canvas 新增 `moving` 入参——有 drag 活跃、pinch
     存活或 spin 播放时为 true，此时跳过气泡名称文字绘制（逐帧
     Text 解析是 153 气泡下的一大头）；静止时恢复。连线、图标、
     圆环照常绘制。
   - 投影单次计算：核对 canvas 每帧每气泡只投影一次（原实现已
     如此），tap 与 canvas 共用同一 project 函数，未引入重复投影。

3. **保持不变**：深度 alpha 曲线（0.10+0.90·t^1.4）、背面不可点、
   图标尺寸 min(1, zoom) 上限、身份聚焦只显绑定气泡、组聚焦变淡、
   点空白清聚焦、分段与底栏等其他全部行为。

4. **残余风险**：153 个图标逐帧 `ctx.draw(Image)`（含裁剪与 favicon
   白底）是 Canvas 渲染的固有成本，本轮未动渲染层，只能靠上面三件
   压低每帧的非绘制开销；若真机仍卡，下一步才考虑图标预合成/
   离屏缓存。本地无 Xcode 未编译验证，待 CI 一轮确认（改动自包含
   于 SphereMap.swift，无跨文件引用）。

### 第七轮细化（2026-11-23，构建号 1031 真机验收反馈，本地提交未推送）

用户原话：「停下来，出名字的时候会卡顿下，能名字一直显示，不要
出现网址吗」。两条（SphereMap.swift）：

1. **名称常显，撤销第六轮的运动降载跳名**：第六轮「运动中跳过名称
   绘制、停下才画」在真机上适得其反——停下那一刻全部名称齐刷刷
   出现，反而卡一下。本轮删除 canvas 的 `moving` 入参及两处调用点
   的传参，名称恢复为通过门槛（沿用旧口径 r>=16 且 z>0.1）即任何
   时候都画。防停下卡顿改走「不许显隐切换」的路子：① 名称字符串
   在规格缓存阶段（computeBubbles）预计算为 `SphereBubble.displayLabel`，
   逐帧绘制零字符串处理；② 每帧名称绘制设上限——ps 已按 z 升序
   （背面在前），从最前（z 最大）往后数，通过门槛者最多画 48 个
   （labelIndices 集合，绘制循环按下标查）；③ 核实 commitSpin 只把
   spin 姿态折回 q、置空 spin，从不碰 cachedBubbles，规格刷新只挂
   onAppear 与 accounts/identities 的 onChange，spin 结束不触发
   规格重算（无改动，仅确认）。

2. **标签只出名字、不出网址（SphereLabel）**：这批服务入库时 name
   字段就是原始域名（binance.com、zhj.sccchina.net、xn--…），球面
   原样画出来像网址。displayLabel 在规格计算阶段生成，规则：
   - name 是正常名称（含空格、或含非 ASCII 字符、或非域名形态）
     → 直接用 name；
   - name 是域名形态（等于 domain、以 `.`+domain 结尾、或纯 ASCII
     点分主机串且末段为 ≥2 位字母）→ 从 domain（domain 为空时用
     name 本身）派生友好名：按双段后缀表（co.cn/com.cn/gov.cn/
     org.cn/net.cn/edu.cn/ac.cn、com.au/gov.au 等 au/uk/hk/tw/sg/
     jp/kr 系列，共 39 条）定位注册域主标签——普通后缀取倒数第二
     段、双段后缀取倒数第三段，前面的子域天然被忽略
     （binance.com→binance、zhj.sccchina.net→sccchina、
     online.immi.gov.au→immi）；主标签以 xn-- 开头时用内置 RFC 3492
     punycode 解码（`Punycode.decode`，含溢出与非法码点防护，自检
     向量 fiqs8s→中国、bcher-kva→bücher、fiq228c→中文，注释在
     代码里）；其余首字母大写（Binance、Sccchina）；
   - 派生不出（主机为空、主标签纯数字、punycode 解码失败）→ 回退
     name 原样截断至 16 字。
   无图标时的字母块首字母同步改读 displayLabel（域名名的气泡显示
   友好名首字母/解码汉字，不再露原始主机首字母）。**只改球面显示，
   不动数据**：全部 App 列表等其他页面照旧用 account.name。

3. **保持不变**：四元数 trackball 转动与惯性、身份/组聚焦行为、
   深度 alpha 曲线、图标绘制与 min(1, zoom) 尺寸上限、点按命中
   测试等其余全部。

4. **残余风险**：本地无 Xcode 未编译验证，待 CI 一轮确认（改动自
   包含于 SphereMap.swift；SphereBubble 新增字段仅 computeBubbles
   一处构造）。常显后每帧最多 48 个 Text 绘制是新增的恒定成本，
   若真机拖动帧率仍不理想，下一步才考虑名称预渲染为图片。友好名
   派生是启发式：双段后缀表未覆盖的小众后缀（如 .com.br）会取错
   一段，属可接受偏差，后续按真机样本补表。

### 第八轮细化（2026-11-24，构建号 1032 真机验收反馈，本地提交未推送）

用户原话：「滑着滑着还是会停顿，你分析下」。第七轮后真机拖动仍有
周期性停顿。病因确诊：前七轮的规格缓存只省了数据计算，省不了绘制
本身——Canvas 逐帧对约 153 个气泡做「裁圆 + 缩放绘制原始大图
（图标原图可达 288px 解码上限）+ 描边 + Text 排版」，120Hz 屏幕
每秒重做一万多次，帧预算爆掉。本轮全部改动在 SphereMap.swift，
走「规格阶段预合成、逐帧只剩 drawImage」的路子：

1. **图标预合成（SphereBaker + BubbleFace）**：computeBubbles 阶段
   把每个气泡的脸离屏预渲染成位图存入 `SphereBubble.baked`：
   ImageRenderer 渲染 BubbleFace（80pt 直径 @2x = 160px；气泡最大
   绘制直径 = 2×baseR(≤24)×投影 scale(≤1.45) ≈ 70pt，此口径覆盖，
   @3x 极端时 GPU 轻微放大）。烘焙内容 = 圆形裁剪后的图标（favicon
   白底盘 + 0.14 直径内缩、内置/自定义图标铺满）或品牌色字母块
   （色盘 + displayLabel 首字母），组色描边一并烘焙（strokeBorder
   内描边 2.5pt）。逐帧只剩对预合成位图的一次 drawImage + 深度/
   聚焦 alpha 经 `GraphicsContext.opacity` 施加——顺带统一了旧的
   不对称：图标本体过去在背面不跟随 alpha 变淡（只有描边淡），
   现在整颗气泡一致变淡；字母块底色过去有 (0.30+0.70t) 的深度
   因子，烘焙后取满值、只走 alpha，正面观感不变、背面略实。
   图标 key 也在规格阶段算好（过去逐帧逐气泡算）。烘焙缓存
   （SphereBaker.bubbleCache）键含账号 id/图标 key+有无/名称/域名/
   组/首字母，任一输入变化自动烘新图；缓存不淘汰（一账号状态
   一张小图，账号编辑稀少）。
2. **图标未就绪的补烘焙**：规格计算时图标还在途的，先烘字母块，
   并经 `SphereBaker.ensureLoad` 挂 IconStore 现有 load 回调
   （每 key 只挂一次，failed 的不挂）；图标落地后回调把一波到达
   合并成一次 revision 自增（150ms 去抖），MapView 的
   `onChange(of: baker.revision)` 触发 refreshBubbles 补烘——已烘
   的全走缓存命中，只有新图标真正重烘。不新造加载机制，Model 的
   prefetch 仍是主通道。
3. **标签预渲染**：displayLabel 在规格阶段按固定字号（9pt medium，
   @3x）预渲染成透明底位图，明暗各一张存入规格（黑字/白字，对应
   逐帧 .primary），canvas 按 colorScheme 选图 drawImage，替代
   逐帧 Text 排版；每帧最多画 48 个的上限口径保留（r>=16、z>0.1、
   按 z 取最前）。
4. **帧率上限**：spin 的 TimelineView 加
   `minimumInterval: 1/60`，120Hz 降 60fps，单帧预算翻倍；拖动与
   惯性是手势/事件驱动，手感不受影响。
5. **背面剔除**：投影半径 < 4pt 的气泡逐帧只画一个组色小圆点，
   不画位图与标签。点击命中不受影响——tap() 本就基于规格数据
   投影判定，不依赖绘制内容。
6. **顺手小修**：SphereLabel 主标签纯数字时（yun.139.com 取到
   139）不再回退原始域名串，改取最左段派生（→Yun；最左段为
   www 或同样纯数字才放弃）；friendlyName 拆出 friendlyLabel
   复用 xn-- 解码/首字母大写逻辑。

保持不变：四元数转动与惯性、聚焦/连线、名称常显口径、其余页面。

残余风险：本地无 Xcode 未编译验证，待 CI 一轮确认（改动自包含于
SphereMap.swift；SphereBubble 新增三个字段仅 computeBubbles 一处
构造；ImageRenderer/@ObservedObject 的隔离标注按本仓既有
IconStore 调用惯例处理）。烘焙图内存约 153×160×160×4B ≈ 16MB，
可接受。若真机仍卡，下一招是 Metal/SpriteKit 级重写（脱离 Canvas
逐帧绘制模型），本轮未做。

### 后续批次（待做）

- 第三批：三维球形星系（替/补上游双列连线图）；登录方式标记显示 + 前往登录；
  服务状态标记与筛选；换绑清单；账号体检。
- 数据转换器反向（atlas 原生 → 网页版格式，如需双向迁移再补）。

## 后续阶段清单（待移植/待建功能，旧）

1. 球形星系关系图（v1.10.6 在壳原型里验证中的球形视图，移植为原生视图；
   上游原生关系图是双列连线图，不满足我们的星系形态）→ 已排入第三批
2. WebDAV 备份 → **已完成（第一批）**
3. 自动识别导入（Vaultwarden/Bitwarden 导出、浏览器密码 CSV、粘贴文本识别——
   网页版已有，原生端移植）→ **已完成（第二批）**
4. 回收站 → **已完成（第一批）**
5. PIN 屏幕锁 → **已完成（第一批）**
6. 换绑清单、账号体检、服务状态（绑哪儿独有功能，原生端按网页版逻辑移植）
   → 已排入第三批
7. 数据转换器反向（atlas 原生 → 网页版格式，如需双向迁移再补）

## 安全确认与阻塞（已解决）

- 上游克隆内容未通过运行环境执行风险检查（其文件在被复制/处理时存在触发
  代码执行的可能），引入前两轮被安全规则拦下。用户在被完整告知风险后，
  于 2026-11-23 06:20 回复「确认引入上游源码，继续改造」、06:21 再次明确
  「明白风险，确认继续引入他的源码」，知情确认齐备后已引入。本阶段全程只把
  上游文件当文本/资源处理，未运行上游任何脚本（tools/appicons.py 只复制）。
- 剩余手动事项（用户操作）：仓库转公开、把 native-app/ios.yml.adapted
  上传为 .github/workflows/ios.yml（推送通道写不了该目录）。
