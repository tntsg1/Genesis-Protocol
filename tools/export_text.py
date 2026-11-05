#!/usr/bin/env python3
# Every string a player can see, out to one TXT to edit (design/游戏文字.txt),
# with a map beside it (design/游戏文字.map.json) that tools/import_text.py
# uses to put the edits back.  Run from the project root.
import io, json, os, re

CJK = re.compile(r'[一-鿿]')
GROUPS = [
    ('关卡：名字、简报、目标、提示', ['scripts/campaign/levels.gd']),
    ('章节与关卡页', ['scripts/ui/campaign_chapters.gd', 'scripts/ui/campaign_page.gd', 'scripts/ui/campaign_model.gd', 'scripts/ui/campaign_scene.gd']),
    ('引导', ['scripts/campaign/tutorial.gd']),
    ('规则卡、状态、器官、性格', ['scripts/rules.gd', 'scripts/organs.gd', 'scripts/personas.gd']),
    ('生命设计器', ['scripts/ui/designer.gd', 'scripts/ui/deck_editor.gd', 'scripts/ui/organ_bay.gd', 'scripts/ui/state_bar.gd', 'scripts/ui/persona_picker.gd']),
    ('培养皿界面', ['scripts/ui/eco_hud.gd', 'scripts/showcase.gd', 'scripts/ui/tool_tray.gd', 'scripts/interventions.gd', 'scripts/dish_marks.gd', 'scripts/dish_pointer.gd',
        'scripts/analysis_layer.gd', 'scripts/lab_marks.gd', 'scripts/ui/magnifier.gd', 'scripts/ui/visor.gd', 'scripts/ui/widgets.gd', 'scripts/ecology.gd', 'scripts/keys.gd']),
    ('结算与报告', ['scripts/ui/level_report.gd', 'scripts/ui/report.gd', 'scripts/ui/compare_bench.gd', 'scripts/ui/prediction_card.gd', 'scripts/campaign/level_runner.gd', 'scripts/campaign/level_eval.gd']),
    ('主菜单与暂停', ['scripts/ui/main_menu.gd', 'scripts/ui/pause_menu.gd']),
    ('世界与原生物种', ['scripts/worlds.gd', 'scripts/natives.gd']),
]
SKIP_CALLS = ('print(', 'push_error(', 'push_warning(', 'printerr(', 'assert(')
SECTION = {
    'scripts/campaign/levels.gd': re.compile(r'id = "(\d-\d)", index = \d+, name = "([^"]+)"'),
    'scripts/campaign/tutorial.gd': re.compile(r'^\t"(\d-\d)": \{'),
}


# The double-quoted literals of a line of GDScript, comments skipped:
# [(start, end, raw text between the quotes)].
def literals(line):
    out, i, n = [], 0, len(line)
    while i < n:
        c = line[i]
        if c == '#':
            break
        if c == "'":
            j = i + 1
            while j < n and line[j] != "'":
                j += 2 if line[j] == '\\' else 1
            i = j + 1
            continue
        if c == '"':
            j = i + 1
            while j < n and line[j] != '"':
                j += 2 if line[j] == '\\' else 1
            out.append((i + 1, j, line[i + 1:j]))
            i = j + 1
            continue
        i += 1
    return out


def main():
    lines_out = [
        '创生协议 · 玩家能看到的全部文字',
        '',
        '怎么改：每行是“编号｜文字”。只改竖线 ｜ 后面的文字，编号和竖线不要动，也不要增删行。',
        '要保留的记号：%d %s %.2f 这类是程序填进去的数字或名字（个数和顺序不能变）；{track} {faster} 这类是按键名；\\n 是换行。',
        '改完告诉我，我用工具按编号写回游戏。没改的行不受影响。',
        '开发者面板等玩家看不到的文字没有收进来。',
        '',
    ]
    entries = {}
    n = 0
    for title, files in GROUPS:
        lines_out += ['=' * 12 + ' ' + title + ' ' + '=' * 12, '']
        for path in files:
            if not os.path.exists(path):
                continue
            lines_out.append('—— ' + path + ' ——')
            sec = SECTION.get(path)
            with io.open(path, encoding='utf-8') as f:
                src = f.read().split('\n')
            for ln, line in enumerate(src, 1):
                if sec:
                    m = sec.search(line)
                    if m:
                        lines_out.append('')
                        lines_out.append('# 第 %s 关 %s' % (m.group(1), m.group(2) if m.lastindex > 1 else ''))
                if line.lstrip().startswith(SKIP_CALLS):
                    continue
                for _, _, raw in literals(line):
                    if not CJK.search(raw):
                        continue
                    n += 1
                    key = 'T%04d' % n
                    entries[key] = {'file': path, 'line': ln, 'text': raw}
                    lines_out.append('%s｜%s' % (key, raw))
            lines_out.append('')
    os.makedirs('design', exist_ok=True)
    with io.open('design/游戏文字.txt', 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write('\n'.join(lines_out) + '\n')
    with io.open('design/游戏文字.map.json', 'w', encoding='utf-8') as f:
        json.dump(entries, f, ensure_ascii=False, indent=0)
    print(n, 'strings')


main()
