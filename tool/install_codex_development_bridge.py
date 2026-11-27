#!/usr/bin/env python3
"""Install the current user's local HandDraw development host; no root access."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import time


def install():
    home = Path.home()
    source = Path(__file__).resolve().parents[1]
    storage = home / 'Library/Application Support/HandDraw Studio Developer'
    app_support = home / 'Library/Containers/com.mahmoudbasuony.handdrawStudio/Data/Library/Application Support/HandDraw Studio'
    codex_home = app_support / 'codex'
    flutter = shutil.which('flutter')
    codex = next((p for p in ['/Applications/ChatGPT.app/Contents/Resources/codex', '/Applications/Codex.app/Contents/Resources/codex', shutil.which('codex')] if p and Path(p).is_file()), None)
    if not flutter or not codex:
        raise RuntimeError('Install official Codex and Flutter first')
    os.umask(0o077)
    storage.mkdir(parents=True, exist_ok=True)
    codex_home.mkdir(parents=True, exist_ok=True)
    program = storage / 'bridge.py'
    shutil.copyfile(source / 'tool/codex_development_bridge.py', program)
    config = storage / 'config.json'
    config.write_text(json.dumps(dict(source=str(source), storage=str(storage / 'workspaces'), codexHome=str(codex_home),
        codex=codex, flutter=str(Path(flutter).resolve()), endpoint=str(app_support / 'codex-development-bridge.json'))))
    label = 'com.handdrawstudio.codex-development'
    agent = home / 'Library/LaunchAgents' / (label + '.plist')
    agent.parent.mkdir(parents=True, exist_ok=True)
    data = dict(Label=label, ProgramArguments=[sys.executable, str(program), '--config', str(config)],
        RunAtLoad=True, KeepAlive=True, ProcessType='Background',
        StandardOutPath=str(storage / 'host.log'), StandardErrorPath=str(storage / 'host-error.log'),
        EnvironmentVariables={'PATH': os.environ.get('PATH', '/usr/bin:/bin:/usr/sbin:/sbin')})
    endpoint = app_support / 'codex-development-bridge.json'
    subprocess.run(['launchctl', 'bootout', 'gui/' + str(os.getuid()) + '/' + label], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if endpoint.exists():
        endpoint.unlink()
    agent.write_bytes(plistlib.dumps(data))
    subprocess.run(['launchctl', 'bootstrap', 'gui/' + str(os.getuid()), str(agent)], check=True)
    for _ in range(50):
        if endpoint.exists():
            print('Development host installed for this user. Endpoint is ready.')
            return
        time.sleep(.1)
    raise RuntimeError('Host did not create its endpoint; inspect local host-error.log')


if __name__ == '__main__':
    install()
