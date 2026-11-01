# 离线检查与边界 | Offline checks and limits

当前模组 **1.1.0**，固定 Mod ID `SuQingMFSFixedBuyback_4221`。这些工具使用用户自己的游戏和 MFS 源码，只调用自制 `KahluaValidation` Java 主类，不启动游戏客户端或进入世界。

Current mod version: **1.1.0**, fixed Mod ID `SuQingMFSFixedBuyback_4221`. These tools use your own game/MFS files and invoke the project-owned `KahluaValidation` Java helper. They do not launch the game client or open a world.

## 前置 | Requirements

Python 3、兼容游戏运行时的 JDK、Build 42.21 游戏文件及 ModernFirearmsSystem 当前版本的 media 目录。源码不随本仓库分发；`tests/` 仅含自制替身和断言。

Requires Python 3, a JDK compatible with the game runtime, Build 42.21 game files and the current ModernFirearmsSystem `media` directory. Upstream sources are not distributed; `tests/` contains only project-owned doubles and assertions.

```sh
javac -d validation tests/java/KahluaValidation.java
python tools/build_catalog.py --game-root "<game-directory>" --check
python tools/run_backend_tests.py --game-root "<game-directory>" --mfs-media "<MFS-version-directory>/media"
python tools/run_ui_tests.py --game-root "<game-directory>" --mfs-media "<MFS-version-directory>/media"
python tools/package_mod.py
```

`--check` 只比对当前原版证据、明确白名单与生成输出；不带 `--check` 会重写仓库内白名单及文档清单，维护前先阅读差异。打包只写本仓库 `releases/` 与 `validation/`，不会部署。

`--check` compares the current vanilla evidence, fixed whitelist and generated output without writing. Omitting it regenerates repository catalog files and evidence, so review differences before doing that. Packaging writes only repository `releases/` and `validation/` outputs and never deploys them.

## 结果解释 | Interpreting results

- 后端检查执行原 MFS 共享交易代码与本补丁；物品、人物和网络边界使用受控替身。
- UI 检查执行原 MFS 界面 Lua 与本补丁；控件、绘制、字体和鼠标投递不是真实客户端。
- 本次 Git 整理可复用既存本地 Java 辅助 class；未重新编译时不得称为 fresh compile。自制 Java 源码保留供有 JDK 时复编译。
- 成功不等于真实游戏画面、原生存档持久化或联机已验收。仍需隔离单人档核对交易余额、收藏/穿戴/手持保护、一键出售及保存重进。

- Backend checks execute original MFS shared trade source and this add-on with controlled inventory, player and network fixtures.
- UI checks execute original MFS UI Lua and this add-on; controls, rendering, fonts and mouse delivery are doubles.
- Existing local helper classes may be reused during Git preparation. Report that limitation rather than claiming a fresh compilation; helper sources are retained for rebuilding with a JDK.
- Passing checks do not establish in-game appearance, real-save persistence or multiplayer acceptance. Use an isolated single-player test save to verify balances, favorite/worn/held protection, bulk sales and saving/reloading.

个人安装、备份、禁用和回滚脚本含本机目标，保留在本地但被 Git 忽略，不属于公开安装流程。原始日志、反编译文件及个人路径记录也不提交。

Machine-specific install, backup, disable and rollback scripts remain local and are ignored by Git. They are not public installation entry points. Raw logs, decompiled game files and personal-path records are excluded as well.
