#!/usr/bin/env python3

import json
import re


FILENAME_TEMPLATE = "fileshark_socketipc.in.lua"
FILENAME_IPC_JSON = "../serenity/all.ipc.json"
FILENAME_LUA_SCRIPT = "fileshark_socketipc.lua"
TEMPLATE_NAME_PATTERN = re.compile("^[A-Za-z0-9_]+")
TEMPLATE_DELIMITER_PATTERN = re.compile("^[<>,]")


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


def make_halfmsg(snake_case_name, parameters):
    return dict(snake_case_name=snake_case_name, camel_case_name=camel_casify(snake_case_name), parameters=parameters)


def tokenize(simplified_template_string):
    token_list = []
    remaining = simplified_template_string.strip()
    while remaining:
        match = TEMPLATE_NAME_PATTERN.match(remaining) or TEMPLATE_DELIMITER_PATTERN.match(remaining)
        assert match is not None, f"Cannot parse any further: {remaining=}, {simplified_template_string=}"
        match_text = match.group()
        remaining = remaining[len(match_text) :].strip()
        token_list.append(match_text)
    return token_list


class Typename:
    def __init__(self, name, children=None):
        assert name not in "<,>:_" and len(name) >= 2, f"weird name: {name}"
        self.name = name
        self.children = children or []
        self.hashed = False

    def walk(self, fn):
        fn(self)
        for child in self.children:
            child.walk(fn)

    def to_lua(self):
        # Technically, this could lead to collisions, because some few templates take a variable amount of arguments.
        # However, this is good enough.
        if self.children:
            return self.name + "_" + "_".join(child.to_lua() for child in self.children)
        return self.name

    def __eq__(self, other):
        return self.name == other.name and self.children == other.children

    def __repr__(self):
        return f"{self.name}{self.children}"

    def __hash__(self):
        return hash((self.name, tuple(self.children)))


def parse_typename(cpp_name):
    token_list = tokenize(cpp_name.replace("::", "_"))
    stack = []
    token_list.reverse()  # in-place
    current = Typename(token_list.pop())
    # Invariant: The "current" type is in 'current', as if we were expecting a '<'.
    # Invariant: There is no deferred linking, or reference that will be added later.
    while token_list:
        delimiter = token_list.pop()
        if delimiter == "<":
            assert not current.children, f"Duplicate set of template args?! {cpp_name=}"
            stack.append(current)
            new_type = Typename(token_list.pop())
            current.children.append(new_type)
            current = new_type
        elif delimiter == ",":
            new_type = Typename(token_list.pop())
            stack[-1].children.append(new_type)
            current = new_type
        elif delimiter == ">":
            current = stack.pop()
        else:
            assert False, f"Not a delimiter: '{delimiter}' in {cpp_name}"
    assert not stack, f"Mismatching template parens?! {cpp_name=}"
    return current


def translate(raw_param, params_types):
    translated_type = parse_typename(raw_param["type"])
    translated_type.walk(lambda t: params_types["auto" if t.children else "manual"].add(t))
    return dict(name=raw_param["name"], typename=translated_type, luaname=translated_type.to_lua())


def translate_params(raw_parameters, params_types):
    return [translate(raw_param, params_types) for raw_param in raw_parameters]


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
        for msg_idx_zero, message in enumerate(endpoint["halfmsgs"]):
            msg_idx_serenity = msg_idx_zero + 1
            lines.append(f'        [{msg_idx_serenity}] = "{message["camel_case_name"]}",')

        #-- })
        lines.append('    })')

        #-- endpoint_info[1419546125] = {type_field=f.ep_1419546125_type, types={}}
        lines.append(f'    endpoint_info[{endpoint["magic"]}] = {{type_field=f.ep_{endpoint["magic"]}_type, types={{}}}}')

        #-- f.ep_1419546125_2_content = ProtoField.bytes("ipc.msg.msg_content", "ConfigClient::NotifyChangedI32Value")
        #-- endpoint_info[1419546125].types[2] = {type_field=f.ep_1419546125_2_content, inputs={}}
        for msg_idx_zero, message in enumerate(endpoint["halfmsgs"]):
            msg_idx_serenity = msg_idx_zero + 1
            # The generated name is completely fictional, but it's a bit shorter than the snake_case name, and everyone should be able to immediately understand it.
            lines.append(f'    f.ep_{endpoint["magic"]}_{msg_idx_serenity}_content = ProtoField.bytes("ipc.msg.msg_content", "{endpoint["name"]}::{message["camel_case_name"]}")')
            lines.append(f'    endpoint_info[{endpoint["magic"]}].types[{msg_idx_serenity}] = {{type_field=f.ep_{endpoint["magic"]}_{msg_idx_serenity}_content, parameters={{')
            for param in message["parameters"]:
                #--        {name="domain", parse_fn=parse_DeprecatedString},
                lines.append(f'        {{name="{param["name"]}", parse_fn=parse_{param["luaname"]}}},')
            lines.append('    }}')

        lines.append("")  # Empty line for "readability".
    return "\n".join(lines)


def generate_automatic_types(params_types):
    # Warn on unknown parent types
    print(f'Automatically implementing {len(params_types["auto"])} types: {params_types["auto"]}')
    complaints = set()
    parts = []
    for param_type in params_types["auto"]:
        if param_type.name == "Vector":
            assert len(param_type.children) == 1, param_type
            subtype = param_type.children[0].to_lua()
            parts.append(f"    local function parse_Vector_{subtype}(param_name, buf, empty_buf, tree)")
            parts.append(f"        return helper_parse_Vector(param_name, buf, empty_buf, tree, parse_{subtype} or parse_unimpl)")
            parts.append(f"    end")
        elif param_type.name == "Optional":
            assert len(param_type.children) == 1, param_type
            subtype = param_type.children[0].to_lua()
            parts.append(f"    local function parse_Optional_{subtype}(param_name, buf, empty_buf, tree)")
            parts.append(f"        return helper_parse_Optional(param_name, buf, empty_buf, tree, parse_{subtype} or parse_unimpl)")
            parts.append(f"    end")
        elif param_type.name not in complaints:
            complaints.add(param_type.name)
            parts.append(f"    --FIXME: {param_type.name}")
            print(f"FIXME: Unimplemented automatic type {param_type.name}")
    return "\n".join(parts)


def generate_code_blocks(ipc_data, params_types):
    blocks_by_name = dict()
    blocks_by_name["TABLE_ENDPOINTS"] = generate_table_endpoints(ipc_data)
    blocks_by_name["ENDPOINT_FIELDS_AND_CONTEXT"] = generate_endpoint_fields_and_context(ipc_data)
    blocks_by_name["AUTOMATIC_TYPES"] = generate_automatic_types(params_types)
    return blocks_by_name


def preprocess(ipc_data):
    params_types = dict(seen=set(), auto=set(), manual=set())
    for endpoint in ipc_data:
        endpoint["halfmsgs"] = []
        for message in endpoint["messages"]:
            translated_params = translate_params(message["inputs"], params_types)
            endpoint["halfmsgs"].append(make_halfmsg(message["name"], translated_params))
            if message["is_sync"]:
                translated_params = translate_params(message["outputs"], params_types)
                endpoint["halfmsgs"].append(make_halfmsg(message["name"] + "_response", translated_params))
    return params_types


def process(template, ipc_data, params_types):
    assert all("halfmsgs" in endpoint for endpoint in ipc_data), "Data must be preprocessed first"
    blocks_by_name = generate_code_blocks(ipc_data, params_types)
    used_blocks = set()
    defined_params = set()
    lines = []
    for line in template.split("\n"):
        trimmed = line.strip()
        autogen_magic = "--AUTOGENERATE:"
        typeimpl_magic = "--TYPEIMPL:"
        if trimmed.startswith(autogen_magic):
            block_name = trimmed[len(autogen_magic):]
            assert block_name not in used_blocks, f"Tried to use {block_name} again?!"
            used_blocks.add(block_name)
            block_content = blocks_by_name.get(block_name, None)
            assert block_content is not None, f"Tried to generate unknown block >>{block_name}<<?! Only these blocks are available: {list(blocks_by_name.keys())}"
            lines.append(block_content)
        elif trimmed.startswith(typeimpl_magic):
            typeimpl_name = trimmed[len(typeimpl_magic):]
            defined_params.add(typeimpl_name)
        else:
            lines.append(line)
    # We already checked that no "unknown" block is used, so we only need to check for unused blocks:
    assert blocks_by_name.keys() == used_blocks, f"The blocks {set(blocks_by_name.keys()).difference(used_blocks)} were unused?!"
    expected_params = {param_type.name for param_type in params_types["manual"]}
    underdefined_types = expected_params.difference(defined_params)
    if underdefined_types:
        print(f"WARNING, MISSING: Some types OCCUR in all.ipc.json but are NOT implemented in Lua: {sorted(underdefined_types)}")
    overdefined_types = defined_params.difference(expected_params)
    if overdefined_types:
        print(f"WARNING, UNUSED: Some types do NOT occur in all.ipc.json but ARE implemented in Lua: {sorted(overdefined_types)}")
    return "\n".join(lines)


def run():
    with open(FILENAME_TEMPLATE, "r") as fp:
        template = fp.read()
    with open(FILENAME_IPC_JSON, "r") as fp:
        ipc_data = json.load(fp)
    params_types = preprocess(ipc_data)
    lua_script = process(template, ipc_data, params_types)
    with open(FILENAME_LUA_SCRIPT, "w") as fp:
        fp.write(lua_script)

if __name__ == "__main__":
    run()
