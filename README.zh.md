# token-hud

把 AI 用量塞进 MacBook notch，始终可见，零打扰。

[English](README.md) · [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue?style=flat-square)](https://www.apple.com/macos/) [![Swift 6](https://img.shields.io/badge/Swift-6-orange?style=flat-square)](https://swift.org) [![MIT](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

---

<!-- 等 app 界面效果满意后替换为真实截图 -->
> 📸 **截图即将上线** — 准备好后在这里放一张 notch 区域效果图。

---

## 功能

- Claude · OpenAI 用量实时同步
- 5 小时 & 7 天限额倒计时
- Ring · Bar · Text 三种 widget 自由组合
- 完全驻留 notch，不占任何屏幕空间

## 快速开始

**环境要求：** macOS 14+，有刘海的 MacBook，Node.js 18+

**1. 启动数据源**

```bash
npm install -g token-state
token-state
```

**2. 构建 app**

```bash
git clone https://github.com/zkywsg/token-hud.git
open token_hud.xcodeproj   # 然后按 ⌘R 运行
```

**3. 配置服务**

点击菜单栏图标 → **Settings** → 粘贴 API key，或直接从 Safari / Chrome 一键提取 Claude session key。

---

<details>
<summary>架构 & 开发者文档</summary>

token-hud 不直接调用任何 AI API，数据通过本地文件流转：

```
token-state daemon  →  ~/.token-hud/state.json  →  token-hud
```

任何能写入相同 schema 的工具都可以替换 daemon。查看 [state.json schema →](https://github.com/zkywsg/token-state#statejson-schema)

</details>

## License

MIT
