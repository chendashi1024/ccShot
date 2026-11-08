"""使用真实应用采集基线，不申请权限、不操作剪贴板、不改性能阈值。"""
import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import statistics
import subprocess
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'app'
BINARY = APP / 'build/ccShort.app/Contents/MacOS/CcShot'
FIXTURES = ROOT / 'prototype/local-ocr/results/2026-11-03-native-01/fixtures'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((APP / 'build').resolve()):
        raise ValueError('结果必须写入本项目忽略的构建目录')
    output.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location('ccshot_metrics', ROOT / 'prototype/local-ocr/metrics.py')
    metrics = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(metrics)
    source_files = sorted((APP / 'Sources').glob('*.swift')) + [Path(__file__), APP / 'build.sh', APP / 'check-performance.sh', APP / 'Tests/DisplayFixtureHost.swift']
    sources = {str(p.relative_to(ROOT)): sha(p) for p in source_files}
    metadata = {
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'base_revision': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        'machine': subprocess.check_output(['sysctl', '-n', 'hw.model'], text=True).strip(),
        'memory_bytes': int(subprocess.check_output(['sysctl', '-n', 'hw.memsize'], text=True)),
        'macos': subprocess.check_output(['sw_vers', '-productVersion'], text=True).strip(),
        'architecture': platform.machine(),
        'binary_sha256': sha(BINARY), 'sources': sources,
        'fixture_sha256': {p.name: sha(p) for p in sorted(FIXTURES.glob('*.png')) + [FIXTURES / 'manifest.json']},
    }
    (output / 'environment.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')

    def run(mode, ordinal):
        path = output / f'{mode}-{ordinal:02d}.json'
        completed = subprocess.run([str(BINARY), '--benchmark-report', str(path), '--benchmark-mode', mode,
                                    '--benchmark-fixtures', str(FIXTURES), '--benchmark-display-host', str(APP / 'build/display-fixture-host')], capture_output=True, timeout=120)
        if completed.returncode or not path.exists():
            raise RuntimeError(f'采样失败，保留已有原始文件：{path.name}')
        data = json.loads(path.read_text())
        if not data.get('completed'):
            raise RuntimeError(f'采样未完成：{path.name}')
        return data

    startups = []
    for i in range(1, 11):
        startups.append(run('startup', i))
        if i in (1, 5, 10):
            print(f'启动采样 {i}/10', flush=True)
    first = defaultdict(list)
    for mode in ('first-chinese', 'first-english', 'first-mixed'):
        for i in range(1, 11):
            first[mode].append(run(mode, i))
        print(f'新进程首次识字采样完成：{mode}', flush=True)
    matrix = run('matrix', 1)
    capture = run('capture', 1)
    print('200次真实截图遮罩打开/关闭采样完成', flush=True)
    print('固定32图三轮与1/5/10张钉图内存采样完成', flush=True)
    if sources != {str(p.relative_to(ROOT)): sha(p) for p in source_files}:
        raise RuntimeError('采样期间源码变化，结果不能作为同一版本基线')

    def stats(values):
        return dict(n=len(values), p50=statistics.median(values), p95=metrics.percentile(values, .95), maximum=max(values))

    def accuracy(rows):
        values = [metrics.measure(r['expected'], r['text']) for r in rows]
        strict = [metrics.measure(r['expected'], r['text'], False) for r in rows]
        total = sum(v['reference_characters'] for v in values)
        total_strict = sum(v['reference_characters'] for v in strict)
        return {'samples': len(rows), 'cer_nfc_without_whitespace': sum(v['edits'] for v in values) / max(1, total),
                'cer_strict': sum(v['edits'] for v in strict) / max(1, total_strict),
                'exact_without_whitespace': sum(v['exact'] for v in values),
                'exact_strict': sum(v['exact'] for v in strict)}

    memory_records = [r['idle_after_2s'] for r in startups]
    memory_records += [value for reports in first.values() for r in reports for value in (r['result']['memory_with_editor'], r['memory_after_close'])]
    memory_records += [matrix['idle_before_ocr'], matrix['idle_after_corpus_2s'], matrix['idle_after_pins_closed_2s'], capture['memory_after_2s']]
    memory_records += [r['memory_with_editor'] for r in matrix['results']] + [r['memory'] for r in matrix['pin_memory']] + [r['memory'] for r in matrix['after_close_samples']]
    if not all(m.get('valid') and m.get('phys_footprint_bytes', 0) > 0 for m in memory_records):
        raise RuntimeError('物理内存接口存在无效读数，不能生成有效内存结论')
    english_hashes = {sha(output / f'first-english-{i:02d}.png') for i in range(1, 11)}
    if len(english_hashes) != 1:
        raise RuntimeError('英文输入位图变化，不能合并同图统计')
    if len(capture['results']) != 201 or capture['selection_windows_after'] != 0:
        raise RuntimeError('真实截图次数或收尾窗口状态错误')
    rows = matrix['results']
    warm = [r for r in rows if not r['process_first_analysis']]
    summary = {
        'environment': metadata,
        'startup_process_to_appkit_ready_ms': stats([r['process_start_to_ready_ms'] for r in startups]),
        'fresh_idle_phys_footprint_bytes': stats([r['idle_after_2s']['phys_footprint_bytes'] for r in startups]),
        'first_ocr_by_language_ms': {mode: stats([r['result']['latency_ms'] for r in values]) for mode, values in first.items()},
        'first_ocr_phase_ms': {mode: {phase: stats([r['result'][phase] for r in values]) for phase in ('window_init_ms', 'analysis_wait_ms', 'selection_and_frame_ms')} for mode, values in first.items()},
        'warm_matrix_ms': stats([r['latency_ms'] for r in warm]),
        'warm_matrix_by_condition_ms': {condition: stats([r['latency_ms'] for r in warm if r['condition'] == condition]) for condition in dict.fromkeys(r['condition'] for r in warm)},
        'accuracy_first': {mode: accuracy([r['result'] for r in values]) for mode, values in first.items()},
        'accuracy_matrix': accuracy(rows),
        'idle_after_corpus_2s': matrix['idle_after_corpus_2s'],
        'capture_action_to_frame_ms': stats([r['action_to_submitted_frame_ms'] for r in capture['results'] if not r['priming']]),
        'capture_warm_first_30_ms': stats([r['action_to_submitted_frame_ms'] for r in capture['results'][1:31]]),
        'capture_selection_windows_after': capture['selection_windows_after'],
        'after_pins_closed_samples': matrix['after_close_samples'],
        'pin_memory': matrix['pin_memory'],
        'idle_after_pins_closed_2s': matrix['idle_after_pins_closed_2s'],
        'controller_survivors': matrix['corpus_controller_survivors'] + matrix['pin_controller_survivors'],
        'visible_windows_after': matrix['visible_normal_or_floating_windows'],
        'functional_checks_passed': bool(matrix['checks_passed']) and all(r['ready_state']['ready'] for r in startups),
        'scope': '进程重启，未清系统缓存。普通识字测编辑窗创建至可全选和AppKit提交；没有计入实体按键、选区确认之前或屏幕物理呈现。固定合成样本不等于真实用户截图分布。',
        'not_completed': ['实体热键到交互帧', '30分钟连续交互', '其他硬件/系统与混合缩放', '安装/权限恢复'],
        'english_input_sha256': next(iter(english_hashes)),
        'memory_scope': 'TASK_VM_INFO.phys_footprint，只计本进程；不合计WindowServer及系统媒体分析服务。MB按1000000字节。',
        'clipboard_access': False, 'network_requests_by_test': False,
        'raw_reports': sorted(p.name for p in output.glob('*.json')),
    }
    (output / 'summary.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: summary[k] for k in ('startup_process_to_appkit_ready_ms', 'fresh_idle_phys_footprint_bytes',
          'first_ocr_by_language_ms', 'warm_matrix_ms', 'controller_survivors', 'visible_windows_after', 'functional_checks_passed')}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
