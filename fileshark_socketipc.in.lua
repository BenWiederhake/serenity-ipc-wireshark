do
    local IPC = Proto("ipc", "Serenity Ipc")

    local tab_directions = {
        [P2P_DIR_SENT] = "outgoing",
        [P2P_DIR_RECV] = "incoming",
    }

    local tab_endpoints = {
        --AUTOGENERATE:TABLE_ENDPOINTS
        -- Example:
        -- [1419546125] = "ConfigClient.ipc",
    }

    local endpoint_info = {}
    local f = IPC.fields
    f.unimpl_params = ProtoField.bytes("ipc.unimpl", "Unimplemented parameters")
    f.unexpected_padding = ProtoField.bytes("ipc.unexpected_padding", "Unexpected padding")
    f.direction = ProtoField.uint32("ipc.direction", "Direction", base.DEC, tab_directions)
    f.message = ProtoField.bytes("ipc.message", "Actual on-wire message content (minus leading message size)")
    -- FIXME: Bad format?! DEC=decimal, HEX=hex, DEC_HEX=deconly, HEX_DEC=hexonly???
    f.endpoint = ProtoField.uint32("ipc.msg.endpoint", "Endpoint magic", base.HEX_DEC, tab_endpoints)

    local function snip(buf, empty_buf, to_snip)
        if buf:len() == to_snip then
            -- Wireshark forbids us from taking zero-length buffers, so use the start of the original buffer:
            return empty_buf
        else
            return buf(to_snip)
        end
    end

    local function parse_unimpl(param_name, buf, empty_buf, tree)
        local unimpl_buf;
        if buf:len() > 0 then
            unimpl_buf = buf
        else
            unimpl_buf = empty_buf
        end
        local param_tree = tree:add(f.unimpl_params, unimpl_buf)
        param_tree:prepend_text(string.format("%s: ", param_name))
        param_tree:append_text(" (UNIMPLEMENTED)")
        return buf:len()
    end

    f.str_buf = ProtoField.string("ipc.type.str", "String content", base.UNICODE)
    f.str_len = ProtoField.uint32("ipc.type.str.len", "String length", base.DEC)
    f.str_null = ProtoField.bytes("ipc.type.str.null", "String NULL", base.NONE)
    local function parse_DeprecatedString(param_name, buf, empty_buf, tree)
        --TYPEIMPL:DeprecatedString
        -- FIXME: Deal with insufficiently small buffers
        local str_len = buf(0, 4):le_uint()
        local orig_buf = buf(0, 4)
        buf = snip(buf, empty_buf, 4)
        local content_buf = empty_buf
        if str_len == 0xFFFFFFFF then
            -- This is so weird, handle it separately.
            local param_tree = tree:add(f.str_null, content_buf)
            param_tree:prepend_text(string.format("%s: ", param_name))
            param_tree:add(f.str_len, orig_buf)
            return 4
        elseif str_len ~= 0 then
            content_buf = buf(0, str_len)
        end
        local param_tree = tree:add(f.str_buf, content_buf)
        param_tree:prepend_text(string.format("%s: ", param_name))
        param_tree:add_le(f.str_len, orig_buf)
        return 4 + str_len
    end

    f.vec_generic = ProtoField.uint32("ipc.type.vec", "Vector<...>")
    local function helper_parse_Vector(param_name, buf, empty_buf, tree, parse_element_fn)
        -- FIXME: Deal with insufficiently small buffers
        local num_elements = buf(0,4):le_uint()
        local elements_tree = tree:add_le(f.vec_generic, buf(0, 4))
        elements_tree:prepend_text(string.format("%s: ", param_name))
        local consumed_bytes = 4
        buf = snip(buf, empty_buf, 4)

        for i=1,num_elements do
            local parsed_bytes = parse_element_fn(string.format("#%d", i - 1), buf, empty_buf, elements_tree)
            if parsed_bytes < 0 then
                return -1
            else
                buf = snip(buf, empty_buf, parsed_bytes)
                consumed_bytes = consumed_bytes + parsed_bytes
            end
        end
        elements_tree:set_len(consumed_bytes)
        return consumed_bytes
    end

    f.optional = ProtoField.bytes("ipc.type.opt", "Optional<...>::None", base.NONE)
    local function helper_parse_Optional(param_name, buf, empty_buf, tree, parse_element_fn)
        -- FIXME: Deal with insufficiently small buffers
        local orig_buf = buf(0,1)
        local has_value = orig_buf:le_uint()
        local consumed_bytes = 1
        buf = snip(buf, empty_buf, 1)

        if has_value ~= 0 then
            local parsed_bytes = parse_element_fn(param_name, buf, empty_buf, tree)
            if parsed_bytes < 0 then
                return -1
            else
                consumed_bytes = consumed_bytes + parsed_bytes
            end
        else
            local none_tree = tree:add_le(f.optional, orig_buf)
            none_tree:prepend_text(string.format("%s: ", param_name))
        end
        return consumed_bytes
    end

    f.hashmap_generic = ProtoField.bytes("ipc.type.hashmap", "HashMap<...>", base.NONE)
    local function helper_parse_HashMap(param_name, buf, empty_buf, tree, parse_key_fn, parse_value_fn)
        -- FIXME: Deal with insufficiently small buffers
        local num_elements = buf(0,4):le_uint()
        local elements_tree = tree:add_le(f.hashmap_generic, buf(0, 4))
        elements_tree:prepend_text(string.format("%s: ", param_name))
        local consumed_bytes = 4
        buf = snip(buf, empty_buf, 4)

        for i=1,num_elements do
            local parsed_bytes = parse_key_fn(string.format("key #%d", i - 1), buf, empty_buf, elements_tree)
            if parsed_bytes < 0 then
                return -1
            else
                buf = snip(buf, empty_buf, parsed_bytes)
                consumed_bytes = consumed_bytes + parsed_bytes
            end
            local parsed_bytes = parse_value_fn(string.format("value #%d", i - 1), buf, empty_buf, elements_tree)
            if parsed_bytes < 0 then
                return -1
            else
                buf = snip(buf, empty_buf, parsed_bytes)
                consumed_bytes = consumed_bytes + parsed_bytes
            end
        end
        elements_tree:set_len(consumed_bytes)
        return consumed_bytes
    end

    f.bool = ProtoField.bool("ipc.type.bool", "Boolean")
    local function parse_bool(param_name, buf, empty_buf, tree)
        --TYPEIMPL:bool
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add(f.bool, buf(0, 1))
        param_tree:prepend_text(string.format("%s: ", param_name))
        return 1
    end

    f.type_file = ProtoField.bytes("ipc.type.file", "File (contents aren't logged)")
    local function parse_IPC_File(param_name, buf, empty_buf, tree)
        --TYPEIMPL:IPC_File
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add(f.type_file, empty_buf)
        param_tree:prepend_text(string.format("%s: ", param_name))
        return 0
    end

    f.type_anon_buf = ProtoField.bytes("ipc.type.anon_buf", "Core::AnonymousBuffer")
    f.type_anon_buf_validity = ProtoField.bool("ipc.type.anon_buf.valid", "valid")
    f.type_anon_buf_size = ProtoField.uint32("ipc.type.anon_buf.size", "size")
    local function parse_Core_AnonymousBuffer(param_name, buf, empty_buf, tree)
        --TYPEIMPL:Core_AnonymousBuffer
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add(f.type_anon_buf, buf(0, 1))
        param_tree:prepend_text(string.format("%s: ", param_name))
        param_tree:add_le(f.type_anon_buf_validity, buf(0, 1))
        local is_valid = buf(0, 1):uint()
        if is_valid == 0 then
            return 1
        end
        buf = snip(buf, empty_buf, 1)
        param_tree:add_le(f.type_anon_buf_size, buf(0, 4))
        -- FIXME: Check call?
        parse_IPC_File("file", empty_buf, empty_buf, param_tree)
        param_tree:set_len(1 + 4)
        return 1 + 4
    end

    f.type_u32 = ProtoField.uint32("ipc.type.u32", "value")
    local function parse_u32(param_name, buf, empty_buf, tree)
        --TYPEIMPL:u32
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add_le(f.type_u32, buf(0, 4))
        param_tree:prepend_text(string.format("%s: ", param_name))
        return 4
    end

    f.type_i32 = ProtoField.int32("ipc.type.i32", "value")
    local function parse_i32(param_name, buf, empty_buf, tree)
        --TYPEIMPL:i32
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add_le(f.type_i32, buf(0, 4))
        param_tree:prepend_text(string.format("%s: ", param_name))
        return 4
    end

    f.type_int_rect = ProtoField.bytes("ipc.type.int_rect", "Gfx::IntRect")
    local function parse_Gfx_IntRect(param_name, buf, empty_buf, tree)
        --TYPEIMPL:Gfx_IntRect
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add(f.type_int_rect, buf(0, 16))
        param_tree:prepend_text(string.format("%s: ", param_name))
        parse_i32("x", buf(0, 4), empty_buf, param_tree)
        parse_i32("y", buf(4, 4), empty_buf, param_tree)
        parse_i32("w", buf(8, 4), empty_buf, param_tree)
        parse_i32("h", buf(12, 4), empty_buf, param_tree)
        return 16
    end

    f.type_float = ProtoField.float("ipc.type.float", "float")
    local function parse_float(param_name, buf, empty_buf, tree)
        --TYPEIMPL:float
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add_le(f.type_float, buf(0, 4))
        param_tree:prepend_text(string.format("%s: ", param_name))
        return 4
    end

    f.type_int_size = ProtoField.bytes("ipc.type.int_size", "Gfx::IntSize")
    local function parse_Gfx_IntSize(param_name, buf, empty_buf, tree)
        --TYPEIMPL:Gfx_IntSize
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add(f.type_int_size, buf(0, 8))
        param_tree:prepend_text(string.format("%s: ", param_name))
        parse_i32("w", buf(0, 4), empty_buf, param_tree)
        parse_i32("h", buf(4, 4), empty_buf, param_tree)
        return 8
    end

    --AUTOGENERATE:AUTOMATIC_TYPES
    -- Example:
    -- local function parse_Vector_DeprecatedString(param_name, buf, empty_buf, tree)
    --     return helper_parse_Vector(param_name, buf, empty_buf, tree, parse_DeprecatedString)
    -- end

    --AUTOGENERATE:ENDPOINT_FIELDS_AND_CONTEXT
    -- Example:
    -- f.ep_1419546125_type = ProtoField.uint32("ipc.msg.msg_type", "Message Type (enum)", base.DEC, {
    --     [2] = "ConfigClient::NotifyChangedI32Value",
    -- })
    -- endpoint_info[1419546125] = {type_field=f.ep_1419546125_type, types={}}
    -- f.ep_1419546125_2_content = ProtoField.bytes("ipc.msg.msg_type_1419546125_2", "ConfigClient::NotifyChangedI32Value")
    -- endpoint_info[1419546125].types[2] = {type_field=f.ep_1419546125_2_content, parameters={
    --     {name="domain", parse_fn=parse_DeprecatedString},
    --     {name="group", parse_fn=parse_DeprecatedString},
    --     {name="key", parse_fn=parse_DeprecatedString},
    --     {name="value", parse_fn=parse_i32},
    -- }}

    function IPC.dissector(buf, pinfo, tree)
        -- Necessary for trailing "empty" parameters, sigh
        local empty_buf = buf(0,0)

        -- Parse direction
        tree:add_le(f.direction, buf(0,4))
        pinfo.p2p_dir = buf(0,4):le_uint(); -- Hopefully P2P_DIR_SENT or P2P_DIR_RECV
        buf = snip(buf, empty_buf, 4)
        tree:add(f.message, buf)

        -- Parse endpoint
        if buf:len() < 4 then
            -- FIXME: Report invalid packet, as it is missing the endpoint
            return -1
        end
        tree:add_le(f.endpoint, buf(0,4))
        local endpoint_value = buf(0,4):le_uint()
        local endpoint_ctx = endpoint_info[endpoint_value]
        if endpoint_ctx == nil then
            -- FIXME: Report invalid endpoint magic
            return -1
        end
        buf = snip(buf, empty_buf, 4)

        -- Parse message type
        if buf:len() < 4 then
            -- FIXME: Report invalid packet, as it is missing the message type
            return -1
        end
        tree:add_le(endpoint_ctx.type_field, buf(0,4))
        local message_ctx = endpoint_ctx.types[buf(0,4):le_uint()]
        if message_ctx == nil then
            -- FIXME: Report invalid message type for this endpoint
            return -1
        end
        buf = snip(buf, empty_buf, 4)
        local message = tree:add(message_ctx.type_field, buf)

        -- FIXME: Parse 'message' according to 'message_ctx.parameters'
        local broke = false;
        for _, param in ipairs(message_ctx.parameters) do
            local parse_fn = param.parse_fn or parse_unimpl;
            local parsed_bytes = parse_fn(param.name, buf, empty_buf, message)
            if parsed_bytes < 0 then
                broke = true
                break
            else
                buf = snip(buf, empty_buf, parsed_bytes)
            end
        end

        if not broke and buf:len() > 0 then
            tree:add(f.unexpected_padding, message)
        end
    end

    DissectorTable.get("wtap_encap"):add(wtap.USER13, IPC)
end
