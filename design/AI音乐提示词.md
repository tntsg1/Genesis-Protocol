# 创生协议 · AI 音乐生成提示词

现在游戏里的配乐是用 Sonniss 音效库的真实录音垫音编排的临时版（`tools/compose_music.py`，输出 `assets/audio/music/`）。
用下面的提示词在 Suno / Udio 等工具生成正式曲目后，按同名文件放进 `assets/audio/music/`（OGG 或 WAV 均可，我来转换和做无缝循环）。

通用要求（每首都加上）：
> instrumental only, no vocals, no drums kit, seamless loop friendly (no hard ending, no fade-out), mixed quiet and spacious for background under gameplay, high fidelity, 48 kHz

## 1. menu.ogg — 主菜单（约 2–3 分钟，可循环）

> ambient microscopy wonder, bright and hopeful, slow evolving warm pads, glassy harp and celesta glints, soft granular shimmer like light through water, gentle sub bass swells, sense of discovering life under the ice of Europa, cinematic but calm, 60 bpm feel, key of D major pentatonic

## 2. dish.ogg — 培养皿观察（约 3 分钟，可循环，最常听到的一首）

> calm underwater laboratory ambient, translucent and airy, slowly breathing pads, sparse marimba and kalimba droplets, subtle bubbling textures, organic and alive but unobtrusive, long reverb tails, no strong melody, focus music for watching cells grow, key of D, 55–65 bpm

## 3. lab.ogg — 生命设计器（约 2–3 分钟，可循环）

> futuristic biotech lab ambient, clean white laboratory, precise and focused, soft analog arpeggio far in the background, glassy plucks, low warm drone, hints of DNA helix rotation (rising motifs), elegant and high-tech but not dark or scary, key of A minor, 70 bpm

## 4. result.ogg — 结算点星（6–10 秒短乐句）

> short triumphant ambient sting, warm pad swell with three rising harp notes and a soft glassy chime, hopeful resolution, ends gently, key of D major

## 5. 以后可能需要

- 捕食压力 / Boss 关（第二章起）：`tense ambient pulse, low organic heartbeat, eerie microscopic world, not horror, key of D minor`
- 长局 / 星图：`vast cosmic ambient, seeding ship drifting between exoplanets, wide pads, distant choir texture without words`
