#!/usr/bin/env python3
# Puts the edits made in design/游戏文字.txt back into the scripts, by the ids
# in design/游戏文字.map.json.  Only changed lines are touched; a string that
# moved is looked for near its old line, then anywhere in its file.  Prints
# what it changed and what it could not find.  Run from the project root.
import io, json, re

PLACE = re.compile(r'%[-+0-9.]*[dsf]|\{[a-z_]+\}|\\n')


def main():
    with io.open('design/游戏文字.map.json', encoding='utf-8') as f:
        entries = json.load(f)
    edits = {}
    with io.open('design/游戏文字.txt', encoding='utf-8-sig') as f:
        for line in f.read().split('\n'):
            m = re.match(r'(T\d{4})｜(.*)$', line.rstrip('\r'))
            if m and m.group(1) in entries and m.group(2) != entries[m.group(1)]['text']:
                edits[m.group(1)] = m.group(2)
    done, missing, warned = 0, [], []
    by_file = {}
    for key, text in edits.items():
        by_file.setdefault(entries[key]['file'], []).append((key, text))
    for path, items in by_file.items():
        with io.open(path, encoding='utf-8', newline='') as f:
            src = f.read().split('\n')
        for key, text in items:
            e = entries[key]
            if sorted(PLACE.findall(e['text'])) != sorted(PLACE.findall(text)):
                warned.append(key)
            old = '"%s"' % e['text']
            new = '"%s"' % text.replace('"', '\\"') if '"' not in e['text'] else '"%s"' % text
            order = sorted(range(len(src)), key=lambda k: abs(k - (e['line'] - 1)))
            for k in order:
                if old in src[k]:
                    src[k] = src[k].replace(old, new, 1)
                    e['text'] = text
                    e['line'] = k + 1
                    done += 1
                    break
            else:
                missing.append(key)
        with io.open(path, 'w', encoding='utf-8', newline='') as f:
            f.write('\n'.join(src))
    # (What went in is the new original: the TXT can be edited and imported again.)
    with io.open('design/游戏文字.map.json', 'w', encoding='utf-8') as f:
        json.dump(entries, f, ensure_ascii=False, indent=0)
    print('changed', done, 'of', len(edits))
    if warned:
        print('check the placeholders (%d %s {key} \\n) of:', ' '.join(warned))
    if missing:
        print('not found:', ' '.join(missing))


main()
