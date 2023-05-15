#!/usr/bin/env python3

import json


FILENAME_TEMPLATE = "fileshark_socketipc.in.lua"
FILENAME_IPC_JSON = "../serenity/all.ipc.json"
FILENAME_LUA_SCRIPT = "fileshark_socketipc.lua"


def generate_table_endpoints(ipc_data):
    lines = []
    for endpoint in ipc_data:
        lines.append(f'        [{endpoint["magic"]}] = "{endpoint["name"]}.ipc",')
    return "\n".join(lines)

def generate_code_blocks(ipc_data):
    blocks_by_name = dict()
    blocks_by_name["TABLE_ENDPOINTS"] = generate_table_endpoints(ipc_data)
    # FIXME: More
    return blocks_by_name


def process(template, ipc_data):
    blocks_by_name = generate_code_blocks(ipc_data)
    used_blocks = set()
    lines = []
    for line in template.split("\n"):
        trimmed = line.strip()
        magic = "--AUTOGENERATE:"
        if trimmed.startswith(magic):
            block_name = trimmed[len(magic):]
            assert block_name not in used_blocks, f"Tried to use {block_name} again?!"
            used_blocks.add(block_name)
            block_content = blocks_by_name.get(block_name, None)
            assert block_content is not None, f"Tried to generate unknown block >>{block_name}<<?! Only these blocks are available: {list(blocks_by_name.keys())}"
            lines.append(block_content)
        else:
            lines.append(line)
    # We already checked that no "unknown" block is used, so we only need to check for unused blocks:
    assert blocks_by_name.keys() == used_blocks, f"The blocks {set(blocks_by_name.keys()).difference(used_blocks)} were unused?!"
    return "\n".join(lines)


def run():
    with open(FILENAME_TEMPLATE, "r") as fp:
        template = fp.read()
    with open(FILENAME_IPC_JSON, "r") as fp:
        ipc_data = json.load(fp)
    lua_script = process(template, ipc_data)
    with open(FILENAME_LUA_SCRIPT, "w") as fp:
        fp.write(lua_script)

if __name__ == "__main__":
    run()
