"""Prepare the official Tripo add-on to coexist with Blender MCP.

Run after downloading the official ZIP into .tools/tripo-addon-inspect.
No generation or account calls are made.
"""
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
source = ROOT / '.tools/tripo-addon-inspect/tripo-3d-for-blender'
archive = ROOT / '.tools/tripo3d-blender-local.zip'
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as output:
    for file in source.rglob('*'):
        if not file.is_file() or '__pycache__' in file.parts:
            continue
        data = file.read_bytes()
        if file.suffix == '.py':
            code = data.decode('utf-8')
            for old, new in [('blendermcp', 'tripomcp'), ('BLENDERMCP', 'TRIPOMCP'),
                             ('BlenderMCP', 'TripoMCP'), ('9876', '9877'),
                             ('Claude', 'Tripo MCP')]:
                code = code.replace(old, new)
            # Passwords must not be serialized into shared .blend files.
            code = code.replace('default="", subtype="PASSWORD"',
                                'default="", subtype="PASSWORD", options={"SKIP_SAVE"}')
            data = code.encode('utf-8')
        output.writestr('tripo3d_blender/' + file.relative_to(source).as_posix(), data)

server = ROOT / '.tools/tripo-mcp/src/server.py'
code = server.read_text(encoding='utf-8')
code = code.replace('BlenderConnection(host="localhost", port=9876)',
                    'BlenderConnection(host="127.0.0.1", port=9877)')
server.write_text(code, encoding='utf-8')
print(f'Prepared {archive.name}; Tripo uses loopback port 9877.')
