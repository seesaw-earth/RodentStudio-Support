# RodentStudio 官网与 Mac App Store 发布核对表

## 已包含

- [x] 英文首页（`index.html`）和中文首页（`zh/index.html`）
- [x] Support / FAQ / Guide / Privacy Policy / Legal / Accessibility / Release Notes，均有中英文版本
- [x] 公开 GitHub Issues 支持入口
- [x] GitHub Pages 静态部署，无数据库、无需 Node.js 及云后端
- [x] app 图标、响应式手机 / 桌面布局、无障碍 HTML 导航、SEO 基础标签
- [x] App Store Connect URL 对照表

## 发布前必查

- [ ] 确认 GitHub `seesaw-earth` 账户有权限建立 `RodentStudio-Support` Public 仓库，并启用 GitHub Pages。
- [ ] 在无 GitHub 登录的浏览器中检查 Support URL 和 Privacy Policy URL 均显示正常（不是 404）。
- [ ] 在 App Store Connect 核对准确的法律主体/开发者名称、Bundle ID、Version / Build。
- [ ] 核对 **最终 Archive 的真实网络行为、SDK、隐私清单、文件存储和删除方式**；如有任何云端分析或诊断功能，修改网页。
- [ ] 为需要保密的隐私咨询安排经开发者确认的**非公开联系方式（建议专用支持邮箱）**；当前仅使用公开 Issues + 私下联系请求的方式，不应在 issue 公开任何敏感信息。
- [ ] 审查源代码 AGPL-3.0 授权、两个内置 Core ML 模型和训练数据权利；模型 Public Repo 不等于可以随意再分发。
- [ ] 完成 Mac Release Archive、TestFlight 实机测试和 App Store Connect 上架内容审核。
- [ ] 上架后把首页“准备发布中”改为实际发布状态，添加真实 Mac App Store URL。
- [ ] 如更新数据处理方式、支持邮箱或模型功能，同步更新中英文页面。

## 关键链接

- GitHub 预定仓库：https://github.com/seesaw-earth/RodentStudio-Support
- 英文支持 URL：https://seesaw-earth.github.io/RodentStudio-Support/support.html
- 英文隐私 URL：https://seesaw-earth.github.io/RodentStudio-Support/privacy.html
- App Store 隐私官方说明：https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy

## 上传和发布

Mac 的 `Downloads` 解压网站 ZIP 后：

```bash
cd ~/Downloads/RodentStudio-Support
gh auth status
git init -b main
git add .
git commit -m "Create RodentStudio support pages"
gh repo create seesaw-earth/RodentStudio-Support --public --source=. --remote=origin --push
```

之后进入 GitHub 仓库 **Settings → Pages → Deploy from a branch → main / (root) → Save**。
