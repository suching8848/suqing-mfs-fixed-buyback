# 蘇清的枪械商店固定收购模组 / SuQing’s MFS Fixed Buyback Mod

中文 | [English](README.en.md)

![蘇清的枪械商店固定收购封面](publishing/preview.png)

封面采用作者选定的 A 版角色场景，模组现已附带独立图标与封面；美术来源和导出记录见 [美术清单](art/asset-manifest.json)。

Build 42.21 单人本地补丁，当前版本 1.1.0。为 ModernFirearmsSystem 对讲机商店加入 122 项常驻收购，保留原余额、随机装备池和 12 小时刷新规则。手表和贵金属材料默认开启。

入口：随身带对讲机 → 右键枪械「检视武器」→ 对讲机图标。默认只列出可售物品；可取消筛选查看完整清单。

“一键出售”一次结算所有类别中的可售随身物品，显示总件数与预计收入，支持普通背包内部物品。它不受当前分类筛选影响，收藏、佩戴和手持保护仍生效。1.1.0 同时修复单人交易已经完成却等待网络回执、锁住按钮8秒的问题：单人直接运行共享交易逻辑并立即显示真实结果。

钱款固定价：钞票 10、捆装钞票 1000、银币 50、金币 250。完整范围、价格、保护与使用说明见 [本地模组说明](mod/SuQingMFSFixedBuyback_4221/README.txt)。

## 前置、补丁与安装

- 必需原作：[ModernFirearmsSystem / 现代枪械系统](https://steamcommunity.com/sharedfiles/filedetails/?id=3633421539)，Workshop ID `3633421539`，Mod ID `ModernFirearmsSystem`。本模组在原作之后加载，不附带原作源码或资源。
- 本模组固定 ID `SuQingMFSFixedBuyback_4221`，当前版本 **1.1.0**，支持 Build 42.21 单人；[创意工坊条目 3832223597](https://steamcommunity.com/sharedfiles/filedetails/?id=3832223597) 已公开发布，2026-11-03 17:39（北京时间）状态读回仍为公开。
- 完全退出游戏，按需要保护目标存档后，将 `mod/SuQingMFSFixedBuyback_4221` 复制到用户 `Zomboid/mods`。在目标单人档中启用原作与本模组并保持依赖顺序，然后重启游戏；同一 Mod ID 只安装一份来源。
- [蘇清的僵尸毁灭工程补丁合集](https://github.com/suching8848/suqing-project-zomboid-patches/) 是可选补丁集合，**不是本模组前置**。其中 MFS 瞄具、灯光、弹药视觉修复各处理原作的独立问题，不提供本模组的固定收购逻辑；枪械减重挂件也是独立模组，无需为固定收购安装。

## 文件

- `mod/SuQingMFSFixedBuyback_4221/`：可安装模组。
- `tools/build_catalog.py`：从当前原版脚本生成、检查明确物品白名单。
- `tools/run_backend_tests.py`：实际游戏 Kahlua 加载原 MFS 交易源码与补丁进行交易回归。
- `tools/run_ui_tests.py`：实际游戏 Kahlua 加载原 MFS 界面与补丁进行界面逻辑回归。
- `tests/`：自制 Kahlua 辅助源码、受控测试替身和断言，不包含原 MFS 或游戏源码。
- `docs/catalog-manifest.json`：可移植的明确白名单与源文件哈希。
- `docs/TESTING.md`：离线检查命令与验证边界。
- `validation/`、`releases/`：本地检查结果、编译缓存与 ZIP，不提交 Git。旧的个人安装、备份和回滚工具也不提交，不是安装入口。

## 实现边界

固定收购不读取客户端传入的价格；单件与批量交易按实际物品重新计算。收藏、手持和正在佩戴的物品受到保护；收藏容器内物品也受到保护。复用原有角色余额，不新增货币物品。

UI 和物品操作离线测试使用受控替身，不能代替游戏内视觉与真实存读档验收。没有启动游戏，也没有改动 Workshop 源文件或启用其它模组。

停用后恢复 MFS 原始收购行为，已有交易余额保留。

此前 Git 整理保留了原安装包；本次美术更新仅补充图标、封面及其元数据声明，玩法、版本及 Mod ID 不变。离线工具只调用 Kahlua 辅助主类，不启动游戏客户端；构建或打包不会部署到个人存档。

本项目未指定开源许可证。Project Zomboid 与 ModernFirearmsSystem 的原作内容归各自作者，本仓库仅保留独立扩展、自制验证工具及兼容元数据。

## 相关项目与配置快照

[10 个源码仓库与 42 个 Mod ID](docs/project-index.md) · [2026-11-02 01:10 的单人档启用快照（205 项）](docs/current-single-player-modlist.md) · [作者 Steam 合集](https://steamcommunity.com/sharedfiles/filedetails/?id=3823981387)

源码索引涵盖 42 个 Mod ID。Steam 合集不附带独立本地补丁；按各项目的前置和条件兼容说明选择子项。启用快照不代表每个项目或新增版本均已通过游戏内验收。
