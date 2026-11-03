"""固定真值的 OCR 字符错误率；不折叠标点、大小写、繁简体。"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import statistics
import unicodedata


def normalize(text):
    return ''.join(c for c in unicodedata.normalize('NFC', text) if not c.isspace())


def measure(reference, prediction, remove_whitespace=True):
    if remove_whitespace:
        reference, prediction = normalize(reference), normalize(prediction)
    # 元组为 编辑距离、替换、删除、插入；固定平局顺序，便于复核。
    previous = [(j, 0, 0, j) for j in range(len(prediction) + 1)]
    for i, expected in enumerate(reference, 1):
        current = [(i, 0, i, 0)]
        for j, actual in enumerate(prediction, 1):
            if expected == actual:
                current.append(previous[j - 1])
            else:
                d, s, deletions, ins = previous[j - 1]
                substitution = (d + 1, s + 1, deletions, ins)
                d, s, deletions, ins = previous[j]
                deletion = (d + 1, s, deletions + 1, ins)
                d, s, deletions, ins = current[j - 1]
                insertion = (d + 1, s, deletions, ins + 1)
                current.append(min((substitution, deletion, insertion), key=lambda x: x[0]))
        previous = current
    edits, substitutions, deletions, insertions = previous[-1]
    return dict(reference_characters=len(reference), edits=edits,
                substitutions=substitutions, deletions=deletions, insertions=insertions,
                cer=edits / max(1, len(reference)), exact=reference == prediction)


def percentile(values, q):
    ordered = sorted(values)
    position = (len(ordered) - 1) * q
    lower = int(position)
    return ordered[lower] + (ordered[min(lower + 1, len(ordered) - 1)] - ordered[lower]) * (position - lower)


def aggregate(rows):
    characters = sum(r['metric']['reference_characters'] for r in rows)
    edits = sum(r['metric']['edits'] for r in rows)
    return dict(samples=len(rows), reference_characters=characters, edits=edits,
                cer=edits / max(1, characters), character_accuracy=1 - edits / max(1, characters),
                exact_samples=sum(r['metric']['exact'] for r in rows))


def summarize(manifest, raw):
    truth = {row['id']: row for row in manifest}
    grouped = defaultdict(list)
    for result in raw['results']:
        grouped[result['id']].append(result)
    if set(grouped) != set(truth):
        raise ValueError('结果与真值清单不一致')
    rows = []
    for identity, fixture in truth.items():
        runs = sorted(grouped[identity], key=lambda x: x['repetition'])
        if [r['repetition'] for r in runs] != [1, 2, 3]:
            raise ValueError('每个样本必须有三次独立记录')
        first = runs[0]
        rows.append(dict(id=identity, category=fixture['category'], condition=fixture['condition'],
                         expected=fixture['text'], recognized=first['text'],
                         metric=measure(fixture['text'], first['text']),
                         strict_metric=measure(fixture['text'], first['text'], False),
                         median_ms=statistics.median(r['latency_ms'] for r in runs),
                         all_repetitions_identical=len({r['text'] for r in runs}) == 1,
                         errors=[r['error'] for r in runs if r['error']]))
    conditions = {name: aggregate([r for r in rows if r['condition'] == name])
                  for name in dict.fromkeys(r['condition'] for r in rows)}
    times = [r['latency_ms'] for r in raw['results']]
    summary = dict(overall=aggregate(rows), by_condition=conditions,
                   error_runs=sum(r['error'] is not None for r in raw['results']),
                   repeat_disagreement_samples=sum(not r['all_repetitions_identical'] for r in rows),
                   latency_ms=dict(first_call=times[0], median_all=statistics.median(times),
                                   p95_all=percentile(times, .95),
                                   median_after_first=statistics.median(times[1:]),
                                   p95_after_first=percentile(times[1:], .95)),
                   definition='CER=(替换+删除+插入)/真值字符数。主指标仅去除空白、NFC规范化；保留标点、大小写、繁简体。准确度用每样本第1轮，时延用全部96轮。',
                   scope='32张自写合成样本，8段文本×4种呈现；不是32份独立真实截图。不代表真实用户准确率。',
                   samples=rows)
    return summary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('raw', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    result = summarize(json.loads(args.manifest.read_text()), json.loads(args.raw.read_text()))
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'samples'}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
