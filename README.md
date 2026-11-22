# 绑哪儿 · 账号绑定记录

记清每个邮箱、手机号、微信/QQ 号、Apple/Google 账户注册或绑定了哪些网站和 App。
单文件网页版（PWA），数据只存在使用者自己的设备 + 自己填的 WebDAV 里，不经过任何第三方服务器，不存密码。

- 线上：https://bind.465871.xyz
- 当前版本：见 `VERSION` 文件，历史见 `CHANGELOG.md`

## 目录结构

```
.
├── VERSION            # 当前版本号（构建时读它）
├── CHANGELOG.md       # 版本史
├── README.md
├── build.sh           # 一键构建：校验 → 测试 → 组装 dist → 打包
├── src/               # ★ 唯一源头，改东西只改这里
│   ├── index.html         # 全部代码（HTML/CSS/JS 单文件；关于页版本号是 __VERSION__ 占位符）
│   ├── manifest.webmanifest
│   ├── icon.svg           # 图标矢量源
│   ├── icon-192.png / icon-512.png / apple-touch-icon.png
│   └── favicon.png / favicon.ico
├── tests/             # DOM 桩回归测试（jsdom；test.js 全量、rapid.js 透镜连点）
└── dist/              # 构建产物（不进 git）
    ├── （组装好的 8 个静态文件，index.html 已替换真实版本号）
    ├── atlas-web.zip          # 部署用固定名包
    └── atlas-web-vX.Y.Z.zip   # 同内容的存档包
```

最终产物就是那 8 个静态文件，线上由 nginx 直接 serve，没有后端。

## 怎么构建

```bash
./build.sh
```

它会依次做：

1. 读 `VERSION`，把 `src/index.html` 里的 `__VERSION__` 占位符替换成 `v<版本号>`（src 里永远只留占位符）；
2. 抽出 `<script>` 做 `node --check`，不过就停；
3. 跑 `tests/` 里的回归测试（需要 jsdom：`npm install jsdom`，或让 `NODE_PATH` 能找到 jsdom；缺 jsdom 时构建会报错停下，不会假装通过）；
4. 把 8 个文件组装进 `dist/`；
5. 打两个内容相同的包并打印各自 md5 和大小：`dist/atlas-web.zip`（部署用）、`dist/atlas-web-v<VERSION>.zip`（存档）。

## 怎么部署

线上形态（不要动）：ARM 服务器 `~/bind-atlas/`，nginx:alpine 容器 `bind-atlas` 只绑 `127.0.0.1:5235` serve `site/` 目录，Cloudflare 隧道 arm-sd1 的 `bind.465871.xyz` 指过来，不套 Access。隧道和容器都不用动，更新只是换 `site/` 里的文件。

在 ARM 上（ubuntu 无 docker 组权限，全程不用 docker 命令）：

```bash
# 1) 下载新包（地址是构建后给的 Muse 存储直链，有效期有限）
curl -L -o ~/bind-atlas/atlas-web.zip "下载直链"
# 2) 校验 md5，必须和构建输出的一致
md5sum ~/bind-atlas/atlas-web.zip
# 3) 解压覆盖 site/
cd ~/bind-atlas && python3 -m zipfile -e atlas-web.zip site/
# 4) 本机先验新版字样（按版本换关键词，如关系图/版本号）
curl -s http://127.0.0.1:5235/ | grep -o '换绑清单' | head -1
```

然后从外网打开 https://bind.465871.xyz 验证（状态 200 + 新版字样在）。nginx 直接读 `site/` 文件，不用重启容器。手机端若看到旧版，把页面彻底关掉重开清缓存。

## 怎么发新版

1. 改 `src/` 里的文件（只改 src，dist 是产物不要手改）；
2. 改 `VERSION`（递增版本号），在 `CHANGELOG.md` 顶部补一节新版说明；
3. `./build.sh`，全绿才算数；
4. 把 `dist/atlas-web.zip` 传一份到 Muse 存储拿直链，按上面的部署流程替换，md5 对上才解压；
5. `git add -A && git commit` 记下这次发版（dist 和 zip 不进 git，靠构建再生）。
