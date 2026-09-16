"""Read-only MCP handshake check. Does not submit generation jobs."""
import asyncio
import json
from pathlib import Path
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

ROOT = Path(__file__).resolve().parents[1]

async def main():
    parameters = StdioServerParameters(
        command=str(ROOT / '.tools/tripo-venv/Scripts/tripo-mcp.exe'),
        args=[],
    )
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            init = await session.initialize()
            available = {tool.name for tool in (await session.list_tools()).tools}
            required = {'create_3d_model_from_image', 'get_task_status', 'import_tripo_glb_model'}
            assert required <= available, f'Missing tools: {required - available}'
            scene = await session.call_tool('get_scene_info', {})
            assert not scene.isError, 'Scene query failed'
            text = ''.join(block.text for block in scene.content if hasattr(block, 'text'))
            data = json.loads(text)
            assert 'objects' in data, 'Blender response was not scene information'
            print(json.dumps({'server': init.serverInfo.name, 'tools': len(available),
                              'image_to_model': True, 'blender_connected': True,
                              'scene_objects': len(data['objects']), 'generation_submitted': False}))

asyncio.run(main())
