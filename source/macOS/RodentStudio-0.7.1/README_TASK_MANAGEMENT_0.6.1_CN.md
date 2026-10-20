# RodentStudio 0.6.1：任务备注、删除及同名任务合并

这是在 0.6.0 基础上的**小范围功能更新**。两款原有 Core ML 模型、视频追踪和行为学指标计算代码均未更换。

## 新功能

1. 左侧栏 **右键 Task → 添加／编辑备注**。备注保存在原工作区 `workspace.json`，任务行显示简要备注；点击任务后正文顶部可查看和编辑完整备注。
2. 左侧栏 **右键 Task → 删除任务**，二次确认后把该任务及对应 Session 记录从当前 Project 移除。原始视频文件和已有 Runs 文件夹不会被删除；删除正在运行的任务前需要先暂停。此操作不能在 App 内撤销。
3. 同一个 Project 中，**实验类型相同 + Task 名称相同（忽略大小写和首尾空格）+ 两者均无备注**，将在读取旧工作区时合并，视频 Session 关联到保留的 Task ID。备注不为空的 Task 永远独立。
4. 如需两个同名的独立 Task：右键已有 Task → **新建带备注的独立同名任务**，填写备注后创建。若移除备注，可能重新参与自动合并。
5. 若合并会导致同一小鼠的实验次数冲突，或同一小鼠 Group/Sex 非空字段冲突，为避免统计错误，程序**不会自动合并**，而是显示警告。
6. 若启动时需要合并旧数据，将先自动创建 `~/Library/.../RodentDesktopNative/workspace-before-task-merge-*.json` 原工作区备份（位于该 App 的 Application Support 目录）。若备份失败则不会执行迁移。

## 从昨天 0.6.0 继续启动

将 `RodentStudio-0.6.1.zip` 放在 `~/Downloads`，在 Terminal 运行：

```bash
cd ~/Downloads
mkdir -p RodentStudio-0.6.1-Ready
unzip -q -o RodentStudio-0.6.1.zip -d RodentStudio-0.6.1-Ready
cd RodentStudio-0.6.1-Ready/RodentStudio-0.6.1
python3 install_models.py
open -a Xcode RodentStudio.xcodeproj
```

安装器优先复用昨天已安装在 `~/Downloads/RodentStudio-Final/RodentStudio-0.6.0/RodentStudio/Resources/Models/` 的**同两个** `.mlpackage`；不重新训练模型。运行后在 Xcode 选择 **My Mac**，先 `⌘B` 再 `⌘R`。

## 检查范围及局限

- Linux Swift 语法解析通过；Xcode 工程 plist 校验通过；独立 Swift 合并逻辑测试通过 10 项。
- 当前执行环境没有 macOS SDK/Xcode，**没有在 Mac 上完整编译、运行或测试 UI**。首次启动先用副本工作区验证任务增删、备注、统计和导出。
- 两个 `.mlpackage` 大模型因体积及许可未包含在 ZIP，需按以上步骤从旧工程安装。
