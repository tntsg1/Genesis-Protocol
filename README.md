# 创生协议 GENESIS PROTOCOL

设计微生物、在培养皿里看它们演化的策略游戏。Godot 4.7 + C++ GDExtension（模拟内核）。

## 运行
1. 克隆时带上子模块：`git clone --recursive https://github.com/tntsg1/Genesis-Protocol.git`
2. 用 Godot 4.7 打开工程。`bin/` 里已有编好的 Windows 调试版和发布版 DLL，可以直接运行。

## 重新编译内核（native/）
```
cd native
scons platform=windows use_mingw=yes api_version=4.7 target=template_debug -j12
```
发布版把 `target` 换成 `template_release`。

## 目录
- `scripts/` 游戏逻辑（`campaign/` 战役关卡与引导，`ui/` 界面）
- `native/src/` C++ 模拟内核（`sim_core.cpp`）
- `shaders/` 着色器
- `design/` 策划与定案（`CAMPAIGN.md` 十章目录，`DECISIONS.md` 全部决定）
- `tests/` 测试与关卡机器人（用 `tools/run_test.sh` 运行）
