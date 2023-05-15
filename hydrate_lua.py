#!/usr/bin/env python3

import json


FILENAME_TEMPLATE = "fileshark_socketipc.in.lua"
FILENAME_IPC_JSON = "../serenity/all.ipc.json"
FILENAME_LUA_SCRIPT = "fileshark_socketipc.lua"


def camel_casify(snake_case_name):
    letters = []
    should_capitalize = True
    for letter in snake_case_name:
        if letter == "_":
            should_capitalize = True
        elif should_capitalize:
            letters.append(letter.upper())
            should_capitalize = False
        else:
            letters.append(letter)
    return "".join(letters)


def generate_table_endpoints(ipc_data):
    lines = []
    for endpoint in ipc_data:
        lines.append(f'        [{endpoint["magic"]}] = "{endpoint["name"]}.ipc",')
    return "\n".join(lines)


def generate_endpoint_fields_and_context(ipc_data):
    lines = []
    for endpoint in ipc_data:
        #-- f.ep_1419546125_type = ProtoField.uint32("ipc.msg.msg_type", "ConfigClient Message Type (enum)", base.DEC, {
        lines.append(f'    f.ep_{endpoint["magic"]}_type = ProtoField.uint32("ipc.msg.msg_type", "{endpoint["name"]} Message Type (enum)", base.DEC, {{')

        #--     [2] = "NotifyChangedI32Value",
        for msg_idx_zero, message in enumerate(endpoint["messages"]):  # FIXME: Use half-messages!
            msg_idx_serenity = msg_idx_zero + 1
            lines.append(f'        [{msg_idx_serenity}] = "{camel_casify(message["name"])}",')

        #-- })
        lines.append('    })')

        #-- endpoint_info[1419546125] = {type_field=f.ep_1419546125_type, types={}}
        lines.append(f'    endpoint_info[{endpoint["magic"]}] = {{type_field=f.ep_{endpoint["magic"]}_type, types={{}}}}')

        #-- f.ep_1419546125_2_content = ProtoField.bytes("ipc.msg.msg_content", "ConfigClient::NotifyChangedI32Value")
        #-- endpoint_info[1419546125].types[2] = {type_field=f.ep_1419546125_2_content, inputs={}}
        for msg_idx_zero, message in enumerate(endpoint["messages"]):  # FIXME: Use half-messages!
            msg_idx_serenity = msg_idx_zero + 1
            # The generated name is completely fictional, but it's a bit shorter than the snake_case name, and everyone should be able to immediately understand it.
            lines.append(f'    f.ep_{endpoint["magic"]}_{msg_idx_serenity}_content = ProtoField.bytes("ipc.msg.msg_content", "{endpoint["name"]}::{camel_casify(message["name"])}")')
            lines.append(f'    endpoint_info[{endpoint["magic"]}].types[{msg_idx_serenity}] = {{type_field=f.ep_{endpoint["magic"]}_{msg_idx_serenity}_content, inputs={{}}}}')

        lines.append("")  # Empty line for "readability".
    return "\n".join(lines)


def generate_code_blocks(ipc_data):
    blocks_by_name = dict()
    blocks_by_name["TABLE_ENDPOINTS"] = generate_table_endpoints(ipc_data)
    blocks_by_name["ENDPOINT_FIELDS_AND_CONTEXT"] = generate_endpoint_fields_and_context(ipc_data)
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
