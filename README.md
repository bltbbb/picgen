# 生图（PicGen）

极简 iOS 生图客户端：输入提示词 → 调你自己的 AxonHub / OpenAI 兼容中转（如 `grok-imagine-image-2.0`）→ 看图 / 存相册 / 分享 / 本地历史。端点和 Key 全在 App 里自己填，仓库不含任何凭据。没有 Mac 也能出包：GitHub Actions 的 macOS runner 负责编译并组装**无签名 IPA**（TrollStore / Sideloadly 可用）。

## 构建

推代码即构建，产物在仓库 Actions 里：

| 触发 | 产物 |
|---|---|
| push 到 `main` / 手动 `workflow_dispatch` | artifact `PicGen-unsigned-ipa`（含 `.ipa` + sha256） |
| 打 tag（如 `v0.1.0`） | 自动发 Release，附件直接是 `PicGen.ipa` |

```bash
git tag v0.1.0 && git push origin v0.1.0     # 想要 Release 就打个 tag
```

## 安装

| 方式 | 说明 |
|---|---|
| TrollStore | 直接装 `.ipa`（可用 Release 里的直链）；不需要 Apple ID |
| Sideloadly / AltStore / SideStore | 用 Apple ID 签名安装（免费账号 7 天，到期重签）；需要开 设置 → 隐私与安全性 → 开发者模式 |
| 自签 | 拿 `Payload/PicGen.app` 自己用证书签 |

首次运行如果提示“不受信任的开发者”，去 设置 → 通用 → VPN 与设备管理 里信任。

## 使用

首次打开会直接弹出设置页，自己填**端点**和 **API Key**（仓库里不含任何凭据，也不会随代码上传）：

```text
端点    https://你的中转          （可以带 /v1，也可以不带）
Key     你自己的 API Key
模型    grok-imagine-image-2.0   （可快捷选，也可以自己输）
代理    留空（直连）；手机连不上时才填 127.0.0.1:7890 这类本机代理
```

填完点「测试连接」（打 `GET {端点}/v1/models`）验证，再回首页生成。凭据只留在本机 App 沙盒（UserDefaults），「清空端点与 Key」可随时清掉。

- 首页输入提示词 → 「生成图片」；出图后可以 **存相册 / 分享 / 再来一张**，点图看大图。
- **模型列表从上游拉**：设置页打开时（或点「拉取上游列表」）会自动请求 `GET {端点}/v1/models`，把模型填进 ☰ 菜单；模型栏是自由输入框，随时可手输。
- 左上角快速切模型，右上角 ⚙️ 进设置。
- 历史存在 App 沙盒里（`Documents/images/` + `Documents/history.json`），左滑可删、可复用提示词。

## 接口要点

- 接口按 AxonHub 中继的实测行为：标准 `POST /v1/images/generations` 不可用（400 `messages are required`），生图必须走 `POST {端点}/v1/chat/completions`：
  ```json
  {"model":"grok-imagine-image-2.0","messages":[{"role":"user","content":"生成一张图片：…"}],"n":1}
  ```
- 响应 `choices[0].message.content` 是一行 markdown：`![image](https://aoij.cc.cd/…)`，App 会把链接抠出来下载。
- 单次约 14~17s；提示词违规会被上游 400 挡掉。

## 目录

| 路径 | 作用 |
|---|---|
| `Package.swift` | SwiftPM 可执行包（iOS 16+，无第三方依赖） |
| `Sources/PicGenApp/` | 全部源码：App 入口 / 设置 / API 客户端 / 图库 / 界面 |
| `Info.plist` | 打包时复制进 `.app` 的 Info.plist |
| `Assets.xcassets/` | App 图标（1024 单尺寸，workflow 里用 `actool` 编译） |
| `.github/workflows/ios.yml` | 编译 + 组装无签名 IPA + 上传 artifact / Release |

本地没有 Xcode 时不用管；改动 Swift 直接 push，看 Actions 结果就行。
