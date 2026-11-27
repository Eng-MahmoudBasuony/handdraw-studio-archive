#!/usr/bin/env python3
"""Local, authenticated Codex stdio bridge for HandDraw's development mode.

The host runs as the signed-in macOS user, outside the editor's App Sandbox.
Agent edits go to a source snapshot; validated patches are applied only if the
source checkout still exactly matches that snapshot. No account data is logged.
"""
import argparse
import hashlib
import hmac
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import socketserver
import subprocess
import threading
import time


def run(args, cwd=None, timeout=120, data=None):
    result = subprocess.run(args, cwd=cwd, input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout)
    if result.returncode:
        raise RuntimeError('Command failed: ' + str(args[0]))
    return result.stdout


def git(repo, *args, data=None):
    return run(['git', '-c', 'core.hooksPath=/dev/null', '-C', str(repo), *args], data=data)


def source_state(repo):
    patch = git(repo, 'diff', '--binary', 'HEAD')
    paths = git(repo, 'ls-files', '--others', '--exclude-standard', '-z').split(b'\0')
    files = []
    digest = hashlib.sha256(git(repo, 'rev-parse', 'HEAD') + patch)
    for raw in sorted(p for p in paths if p):
        name = os.fsdecode(raw)
        item = repo / name
        if item.is_symlink():
            raise RuntimeError('Untracked symlinks need manual review')
        if not item.is_file():
            continue
        content = item.read_bytes()
        files.append((name, content, item.stat().st_mode & 0o777))
        digest.update(raw + b'\0' + content)
    # Include the index: even a concurrent staging operation invalidates approval.
    digest.update(git(repo, 'diff', '--cached', '--binary'))
    return digest.hexdigest(), patch, files


def commit_snapshot(repo):
    git(repo, 'add', '--all')
    git(repo, '-c', 'user.name=HandDraw Local', '-c', 'user.email=local@handdraw.invalid',
        'commit', '--allow-empty', '-m', 'Local development snapshot')
    return git(repo, 'rev-parse', 'HEAD').decode().strip()


class Workspace:
    def __init__(self, source, storage):
        self.preserve = False
        self.source = Path(source).resolve()
        self.root = Path(storage) / ('run-' + time.strftime('%Y%m%d-%H%M%S') + '-' + secrets.token_hex(4))
        self.path = self.root / 'candidate'
        self.root.mkdir(parents=True, mode=0o700)
        self.fingerprint, patch, files = source_state(self.source)
        run(['git', 'clone', '--shared', '--no-hardlinks', str(self.source), str(self.path)])
        git(self.path, 'remote', 'remove', 'origin')
        if patch:
            git(self.path, 'apply', '--binary', '-', data=patch)
        for name, content, mode in files:
            target = self.path / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            target.chmod(mode)
        if source_state(self.source)[0] != self.fingerprint:
            raise RuntimeError('Source changed while snapshotting')
        self.base = commit_snapshot(self.path)

    def changes(self):
        git(self.path, 'add', '--intent-to-add', '.')
        return git(self.path, 'diff', '--binary', self.base)

    def apply(self, patch):
        if source_state(self.source)[0] != self.fingerprint:
            return False
        git(self.source, 'apply', '--check', '--binary', '-', data=patch)
        git(self.source, 'apply', '--binary', '-', data=patch)
        self.fingerprint = source_state(self.source)[0]
        self.base = commit_snapshot(self.path)
        return True


def test_failures(log, root):
    tests, suites, failed, errors = {}, {}, set(), {}
    saw_done = False
    for line in Path(log).read_text(errors='replace').splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get('type')
        if kind == 'suite':
            suite = event['suite']
            suites[suite['id']] = suite.get('path', '').replace(str(root), '<root>')
        elif kind == 'testStart':
            test = event['test']
            tests[test['id']] = (suites.get(test.get('suiteID'), ''), test['name'].replace(str(root), '<root>'))
        elif kind == 'error':
            errors.setdefault(event.get('testID'), []).append(str(event.get('error', '')).replace(str(root), '<root>'))
        elif kind == 'testDone' and event.get('result') in ('failure', 'error'):
            failed.add((*tests.get(event['testID'], ('unknown', str(event['testID']))), tuple(errors.get(event['testID'], []))))
        elif kind == 'done':
            saw_done = True
    if not saw_done:
        raise RuntimeError('Test runner did not complete')
    return failed


class Verification:
    def __init__(self, workspace, flutter, cancel, notify):
        self.workspace, self.flutter = workspace, flutter
        self.cancel, self.notify = cancel, notify
        self.process = None

    def command(self, directory, label, args, timeout=900):
        if self.cancel.is_set():
            raise RuntimeError('Cancelled')
        self.notify('verifying', label)
        log = self.workspace.root / (label + '.log')
        with log.open('wb') as output:
            self.process = subprocess.Popen(args, cwd=directory, stdout=output,
                                            stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + timeout
            while self.process.poll() is None:
                if self.cancel.wait(.2) or time.monotonic() > deadline:
                    os.killpg(self.process.pid, signal.SIGTERM)
                    try:
                        self.process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(self.process.pid, signal.SIGKILL)
                    raise RuntimeError('Cancelled or timed out')
            return self.process.returncode, log

    def validate(self):
        work = self.workspace
        patch = work.changes()
        if not patch:
            return {'status': 'unchanged'}
        work.preserve = True
        (work.root / 'proposed.patch').write_bytes(patch)
        # Development infrastructure/account policy is outside an image request.
        # Keep such changes reviewable without silently changing spending controls.
        paths = git(work.path, 'diff', '--name-only', work.base).decode().splitlines()
        protected = ('tool/codex_development_', 'lib/features/codex_assistant/domain/codex_account.dart')
        if any(p.startswith(protected) for p in paths):
            return {'status': 'reviewRequired', 'path': str(work.root)}
        baseline = work.root / ('baseline-' + secrets.token_hex(4))
        git(work.path, 'worktree', 'add', '--detach', str(baseline), work.base)
        for folder, label in [(baseline, 'baseline-pub'), (work.path, 'candidate-pub')]:
            code, _ = self.command(folder, label, [self.flutter, 'pub', 'get'])
            if code:
                return {'status': 'checksFailed', 'path': str(work.root)}
        code, _ = self.command(work.path, 'analyze', [self.flutter, 'analyze', '--no-pub'])
        if code:
            return {'status': 'checksFailed', 'path': str(work.root)}
        base_code, base_log = self.command(baseline, 'baseline-tests', [self.flutter, 'test', '--no-pub', '--reporter', 'json'])
        candidate_code, candidate_log = self.command(work.path, 'candidate-tests', [self.flutter, 'test', '--no-pub', '--reporter', 'json'])
        old = test_failures(base_log, baseline)
        new = test_failures(candidate_log, work.path)
        if new - old or (candidate_code and not new) or (base_code and not old):
            return {'status': 'checksFailed', 'path': str(work.root)}
        code, _ = self.command(work.path, 'release-build', [self.flutter, 'build', 'macos', '--release', '--no-pub'])
        if code or self.cancel.is_set():
            return {'status': 'checksFailed', 'path': str(work.root)}
        # Generated changes from tests/build must not bypass the checked patch.
        if work.changes() != patch:
            return {'status': 'changedDuringChecks', 'path': str(work.root)}
        if not work.apply(patch):
            return {'status': 'sourceChanged', 'path': str(work.root)}
        return {'status': 'applied', 'path': str(work.path / 'build/macos/Build/Products/Release/HandDraw Studio.app'),
                'baselineFailures': len(old), 'files': len(paths)}


class Session(socketserver.StreamRequestHandler):
    def handle(self):
        self.lock = threading.Lock()
        self.cancel = threading.Event()
        self.workspace = None
        self.agent = None
        self.alive = True
        self.connection.settimeout(5)
        try:
            hello = json.loads(self.rfile.readline(16384))
            if not hmac.compare_digest(str(hello.get('token', '')), self.server.token):
                return
            self.connection.settimeout(None)
            env = {k: v for k, v in os.environ.items() if not k.startswith(('OPENAI_', 'CODEX_'))}
            env['CODEX_HOME'] = self.server.config['codexHome']
            self.agent = subprocess.Popen([
                self.server.config['codex'], '-c', 'forced_login_method="chatgpt"',
                '-c', 'cli_auth_credentials_store="file"', '-c', 'model_provider="openai"',
                '-c', 'features.shell_tool=true', '-c', 'features.unified_exec=true',
                '-c', 'features.multi_agent=false', '-c', 'features.apps=false',
                '-c', 'features.hooks=false', '-c', 'web_search="disabled"',
                'app-server', '--listen', 'stdio://'],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                cwd=self.server.config['codexHome'], env=env, start_new_session=True)
            threading.Thread(target=self.output, daemon=True).start()
            for raw in self.rfile:
                message = json.loads(raw)
                method = message.get('method')
                if method == 'thread/start':
                    if self.workspace is None:
                        self.notify('preparing', 'snapshot')
                        self.workspace = Workspace(self.server.config['source'], self.server.config['storage'])
                    params = message.setdefault('params', {})
                    params.update(cwd=str(self.workspace.path), sandbox='danger-full-access', approvalPolicy='never')
                elif method == 'turn/start':
                    self.cancel.clear()
                    message.setdefault('params', {}).update(sandboxPolicy={'type': 'dangerFullAccess'}, approvalPolicy='never')
                elif method == 'turn/interrupt':
                    self.cancel.set()
                self.agent.stdin.write((json.dumps(message) + '\n').encode())
                self.agent.stdin.flush()
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError):
            self.notify('connectionFailed', 'local-host')
        finally:
            self.alive = False
            self.cancel.set()
            if self.agent:
                try:
                    os.killpg(self.agent.pid, signal.SIGTERM)
                    self.agent.wait(timeout=3)
                except (OSError, subprocess.TimeoutExpired):
                    try:
                        os.killpg(self.agent.pid, signal.SIGKILL)
                    except OSError:
                        pass
            if self.workspace and not self.workspace.preserve:
                try:
                    if not self.workspace.changes():
                        shutil.rmtree(self.workspace.root)
                except (OSError, RuntimeError, subprocess.SubprocessError):
                    pass

    def send(self, value):
        if not self.alive:
            return
        try:
            with self.lock:
                self.wfile.write((json.dumps(value) + '\n').encode())
                self.wfile.flush()
        except OSError:
            self.cancel.set()

    def notify(self, status, detail):
        self.send({'method': 'handdraw/development', 'params': {'status': status, 'detail': detail}})

    def output(self):
        try:
            for raw in self.agent.stdout:
                message = json.loads(raw)
                if message.get('method') == 'turn/completed' and self.workspace:
                    turn = message.get('params', {}).get('turn', {})
                    if turn.get('status') == 'completed' and not self.cancel.is_set():
                        try:
                            report = Verification(self.workspace, self.server.config['flutter'], self.cancel, self.notify).validate()
                        except Exception:
                            report = {'status': 'checksFailed', 'path': str(self.workspace.root)}
                        self.send({'method': 'handdraw/development', 'params': report})
                self.send(message)
        except (OSError, ValueError):
            self.cancel.set()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = False
    daemon_threads = True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', required=True)
    args = parser.parse_args()
    config = json.loads(Path(args.config).read_text())
    os.umask(0o077)
    endpoint = Path(config['endpoint'])
    with Server(('127.0.0.1', 0), Session) as server:
        server.config = config
        server.token = secrets.token_urlsafe(48)
        endpoint.parent.mkdir(parents=True, exist_ok=True)
        temp = endpoint.with_suffix('.tmp')
        temp.write_text(json.dumps({'port': server.server_address[1], 'token': server.token, 'version': 1}))
        temp.replace(endpoint)
        server.serve_forever()


if __name__ == '__main__':
    main()
