import importlib.util
from pathlib import Path
import tempfile
import unittest
import threading
import json

spec = importlib.util.spec_from_file_location('bridge', Path(__file__).with_name('codex_development_bridge.py'))
bridge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bridge)


class WorkspaceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'
        self.source.mkdir()
        bridge.git(self.source, 'init')
        (self.source / 'app.txt').write_text('original\n')
        bridge.commit_snapshot(self.source)
        (self.source / 'app.txt').write_text('existing user edits\n')
        (self.source / 'new.txt').write_text('untracked user work\n')

    def tearDown(self):
        self.temp.cleanup()

    def test_snapshot_preserves_dirty_and_untracked_work_then_applies_delta(self):
        work = bridge.Workspace(self.source, self.root / 'runs')
        self.assertEqual((work.path / 'app.txt').read_text(), 'existing user edits\n')
        self.assertEqual((work.path / 'new.txt').read_text(), 'untracked user work\n')
        (work.path / 'feature.txt').write_text('new feature\n')
        self.assertFalse((self.source / 'feature.txt').exists())
        self.assertTrue(work.apply(work.changes()))
        self.assertEqual((self.source / 'app.txt').read_text(), 'existing user edits\n')
        self.assertEqual((self.source / 'new.txt').read_text(), 'untracked user work\n')
        self.assertEqual((self.source / 'feature.txt').read_text(), 'new feature\n')
        self.assertEqual(work.changes(), b'')

    def test_concurrent_edit_prevents_application(self):
        work = bridge.Workspace(self.source, self.root / 'runs')
        (work.path / 'app.txt').write_text('agent edit\n')
        (self.source / 'app.txt').write_text('later user edit\n')
        self.assertFalse(work.apply(work.changes()))
        self.assertEqual((self.source / 'app.txt').read_text(), 'later user edit\n')

    def test_agent_commits_still_compared_with_original_baseline(self):
        work = bridge.Workspace(self.source, self.root / 'runs')
        (work.path / 'feature.txt').write_text('committed feature\n')
        bridge.commit_snapshot(work.path)
        self.assertIn(b'committed feature', work.changes())

    def test_failed_checks_leave_original_source_untouched(self):
        work = bridge.Workspace(self.source, self.root / 'runs')
        (work.path / 'feature.txt').write_text('feature needing repair\n')
        verification = bridge.Verification(work, 'flutter', threading.Event(), lambda *_: None)
        verification.command = lambda folder, label, args: (1, work.root / 'failure.log')
        report = verification.validate()
        self.assertEqual(report['status'], 'checksFailed')
        self.assertFalse((self.source / 'feature.txt').exists())
        self.assertTrue(work.preserve)
        self.assertTrue((work.root / 'proposed.patch').exists())

    def test_new_error_in_same_failing_test_is_detectable(self):
        log = self.root / 'tests.jsonl'
        def failures(message):
            events = [dict(type='suite', suite=dict(id=1, path=str(self.root / 'test.dart'))),
                      dict(type='testStart', test=dict(id=2, suiteID=1, name='golden')),
                      dict(type='error', testID=2, error=message),
                      dict(type='testDone', testID=2, result='failure'), dict(type='done')]
            log.write_text('\n'.join(json.dumps(e) for e in events))
            return bridge.test_failures(log, self.root)
        self.assertNotEqual(failures('80px diff'), failures('900px diff'))

    def test_incomplete_test_output_is_never_success(self):
        log = self.root / 'tests.jsonl'
        log.write_text('{"type":"start"}\n')
        with self.assertRaises(RuntimeError):
            bridge.test_failures(log, self.root)


if __name__ == '__main__':
    unittest.main()
