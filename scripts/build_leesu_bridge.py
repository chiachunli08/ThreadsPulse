#!/usr/bin/env python3
"""Bundle the MIT parser and dedicated WKWebView bridge without npm dependencies."""
from pathlib import Path
import re
root = Path(__file__).resolve().parent.parent
sources = []
for name in ('profileParser.js', 'dateParser.js'):
    source = (root / 'vendor/lee-su-threads' / name).read_text()
    source = re.sub(r'^export \{[^\n]+\};\s*$', '', source, flags=re.M)
    source = source.replace('export function ', 'function ')
    sources.append(source)
sources.append((root / 'scripts/leesu_bridge.js').read_text())
bundle = root / 'layout/Library/Application Support/ThreadsPulse/ThreadsPulse.bundle'
(bundle / 'LeeSuBridge.js').write_text('// Lee-Su-Threads: MIT license in LeeSu-LICENSE.txt\n(() => {\n' + '\n'.join(sources) + '\n})();\n')
(bundle / 'LeeSu-LICENSE.txt').write_text((root / 'vendor/lee-su-threads/LICENSE').read_text())
