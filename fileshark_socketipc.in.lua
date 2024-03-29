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
    f.message = ProtoField.none("ipc.message", "Actual on-wire message content (minus leading message size)")
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
    f.str_null = ProtoField.none("ipc.type.str.null", "String NULL", base.NONE)
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
    --TYPEIMPL:String
    local parse_String = parse_DeprecatedString
    --TYPEIMPL:URL
    local parse_URL = parse_DeprecatedString

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

    f.optional = ProtoField.none("ipc.type.opt", "Optional<...>::None", base.NONE)
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

    f.hashmap_generic = ProtoField.none("ipc.type.hashmap", "HashMap<...>", base.NONE)
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

    f.type_file = ProtoField.none("ipc.type.file", "File (contents aren't logged)")
    local function parse_IPC_File(param_name, buf, empty_buf, tree)
        --TYPEIMPL:IPC_File
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add(f.type_file, empty_buf)
        param_tree:prepend_text(string.format("%s: ", param_name))
        return 0
    end

    f.type_anon_buf = ProtoField.none("ipc.type.anon_buf", "Core::AnonymousBuffer")
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
    --TYPEIMPL:unsigned
    local parse_unsigned = parse_u32

    f.type_i32 = ProtoField.int32("ipc.type.i32", "value")
    local function parse_i32(param_name, buf, empty_buf, tree)
        --TYPEIMPL:i32
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add_le(f.type_i32, buf(0, 4))
        param_tree:prepend_text(string.format("%s: ", param_name))
        return 4
    end
    --TYPEIMPL:int
    local parse_int = parse_i32

    f.type_u64 = ProtoField.uint64("ipc.type.u64", "value")
    local function parse_u64(param_name, buf, empty_buf, tree)
        --TYPEIMPL:u64
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add_le(f.type_u64, buf(0, 8))
        param_tree:prepend_text(string.format("%s: ", param_name))
        return 8
    end
    --TYPEIMPL:size_t
    local parse_size_t = parse_u64

    f.type_int_rect = ProtoField.none("ipc.type.int_rect", "Gfx::IntRect")
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

    f.type_int_size = ProtoField.none("ipc.type.int_size", "Gfx::IntSize")
    local function parse_Gfx_IntSize(param_name, buf, empty_buf, tree)
        --TYPEIMPL:Gfx_IntSize
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add(f.type_int_size, buf(0, 8))
        param_tree:prepend_text(string.format("%s: ", param_name))
        parse_i32("w", buf(0, 4), empty_buf, param_tree)
        parse_i32("h", buf(4, 4), empty_buf, param_tree)
        return 8
    end

    f.type_int_point = ProtoField.none("ipc.type.int_point", "Gfx::IntPoint")
    local function parse_Gfx_IntPoint(param_name, buf, empty_buf, tree)
        --TYPEIMPL:Gfx_IntPoint
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add(f.type_int_point, buf(0, 8))
        param_tree:prepend_text(string.format("%s: ", param_name))
        parse_i32("x", buf(0, 4), empty_buf, param_tree)
        parse_i32("y", buf(4, 4), empty_buf, param_tree)
        return 8
    end

    f.type_sql = ProtoField.none("ipc.type.sql", "SQL::Value")
    -- Wireshark already unshifts the value for us.
    -- In a way that's nice and helpful, but it also means we have to intentionally desync from the C++ implementation.
    -- Since we *also* need to actually parse the values, and I want to avoid using magic numbers in the code, this initial table is damn ugly.
    local CONST_SQL_TYPE_DATA_SQL_Null = 0x1
    local CONST_SQL_TYPE_DATA_SQL_Int8 = 0x2
    local CONST_SQL_TYPE_DATA_SQL_Int16 = 0x3
    local CONST_SQL_TYPE_DATA_SQL_Int32 = 0x4
    local CONST_SQL_TYPE_DATA_SQL_Int64 = 0x5
    local CONST_SQL_TYPE_DATA_SQL_Uint8 = 0x6
    local CONST_SQL_TYPE_DATA_SQL_Uint16 = 0x7
    local CONST_SQL_TYPE_DATA_SQL_Uint32 = 0x8
    local CONST_SQL_TYPE_DATA_SQL_Uint64 = 0x9
    local tab_sql_type_data = {
        [CONST_SQL_TYPE_DATA_SQL_Null] = "Null",
        [CONST_SQL_TYPE_DATA_SQL_Int8] = "Int8",
        [CONST_SQL_TYPE_DATA_SQL_Int16] = "Int16",
        [CONST_SQL_TYPE_DATA_SQL_Int32] = "Int32",
        [CONST_SQL_TYPE_DATA_SQL_Int64] = "Int64",
        [CONST_SQL_TYPE_DATA_SQL_Uint8] = "Uint8",
        [CONST_SQL_TYPE_DATA_SQL_Uint16] = "Uint16",
        [CONST_SQL_TYPE_DATA_SQL_Uint32] = "Uint32",
        [CONST_SQL_TYPE_DATA_SQL_Uint64] = "Uint64",
    }
    f.type_sql_type_data = ProtoField.uint8("ipc.type.sql.type_data", "SQL::TypeData", base.HEX, tab_sql_type_data, 0xF0)
    local CONST_SQL_SQL_TYPE_null = 0x0
    local CONST_SQL_SQL_TYPE_text = 0x1
    local CONST_SQL_SQL_TYPE_int = 0x2
    local CONST_SQL_SQL_TYPE_float = 0x3
    local CONST_SQL_SQL_TYPE_bool = 0x4
    local CONST_SQL_SQL_TYPE_tuple = 0x5
    local tab_sql_sql_type = {
        [CONST_SQL_SQL_TYPE_null] = "null",
        [CONST_SQL_SQL_TYPE_text] = "text",
        [CONST_SQL_SQL_TYPE_int] = "int",
        [CONST_SQL_SQL_TYPE_float] = "float",
        [CONST_SQL_SQL_TYPE_bool] = "bool",
        [CONST_SQL_SQL_TYPE_tuple] = "tuple",
    }
    f.type_sql_sql_type = ProtoField.uint8("ipc.type.sql.sql_type", "SQL::SQLType", base.HEX, tab_sql_sql_type, 0x0F)
    local function parse_SQL_Value(param_name, buf, empty_buf, tree)
        --TYPEIMPL:SQL_Value
        -- FIXME: Deal with insufficiently small buffers
        local element_tree = tree:add(f.type_sql, buf(0, 1))
        element_tree:prepend_text(string.format("%s: ", param_name))

        -- TODO: Maybe use add_packet_field instead?
        element_tree:add(f.type_sql_type_data, buf(0, 1))
        element_tree:add(f.type_sql_sql_type, buf(0, 1))
        local type_data = math.floor(buf(0, 1):uint() / 16)
        local sql_type = buf(0, 1):uint() % 16

        local consumed_bytes = 1
        buf = snip(buf, empty_buf, 1)

        if type_data == CONST_SQL_TYPE_DATA_SQL_Null then
            -- noop
        elseif sql_type == CONST_SQL_SQL_TYPE_null then
            -- noop
        elseif sql_type == CONST_SQL_SQL_TYPE_text then
            local parsed_bytes = parse_String("content", buf, empty_buf, element_tree)
            if parsed_bytes == -1 then
                return -1
            end
            consumed_bytes = consumed_bytes + parsed_bytes
        elseif sql_type == CONST_SQL_SQL_TYPE_int then
            if type_data == CONST_SQL_TYPE_DATA_SQL_Int8 then
                return -1 -- FIXME Not implemented
            elseif type_data == CONST_SQL_TYPE_DATA_SQL_Int16 then
                return -1 -- FIXME Not implemented
            elseif type_data == CONST_SQL_TYPE_DATA_SQL_Int32 then
                local parsed_bytes = parse_i32("content", buf, empty_buf, element_tree)
                if parsed_bytes == -1 then return -1 end
                consumed_bytes = consumed_bytes + parsed_bytes
            elseif type_data == CONST_SQL_TYPE_DATA_SQL_Int64 then
                local parsed_bytes = parse_u64("content", buf, empty_buf, element_tree) -- FIXME should be signed
                if parsed_bytes == -1 then return -1 end
                consumed_bytes = consumed_bytes + parsed_bytes
            elseif type_data == CONST_SQL_TYPE_DATA_SQL_Uint8 then
                return -1 -- FIXME Not implemented
            elseif type_data == CONST_SQL_TYPE_DATA_SQL_Uint16 then
                return -1 -- FIXME Not implemented
            elseif type_data == CONST_SQL_TYPE_DATA_SQL_Uint32 then
                local parsed_bytes = parse_u32("content", buf, empty_buf, element_tree)
                if parsed_bytes == -1 then return -1 end
                consumed_bytes = consumed_bytes + parsed_bytes
            elseif type_data == CONST_SQL_TYPE_DATA_SQL_Uint64 then
                local parsed_bytes = parse_u64("content", buf, empty_buf, element_tree)
                if parsed_bytes == -1 then return -1 end
                consumed_bytes = consumed_bytes + parsed_bytes
            end
        elseif sql_type == CONST_SQL_SQL_TYPE_float then
            local parsed_bytes = parse_float("content", buf, empty_buf, element_tree)
            if parsed_bytes == -1 then return -1 end
            consumed_bytes = consumed_bytes + parsed_bytes
        elseif sql_type == CONST_SQL_SQL_TYPE_bool then
            local parsed_bytes = parse_bool("content", buf, empty_buf, element_tree)
            if parsed_bytes == -1 then return -1 end
            consumed_bytes = consumed_bytes + parsed_bytes
        elseif sql_type == CONST_SQL_SQL_TYPE_tuple then
            local parsed_bytes = parse_Vector_SQL_Value("content", buf, empty_buf, element_tree)
            if parsed_bytes == -1 then return -1 end
            consumed_bytes = consumed_bytes + parsed_bytes
        else
            -- Not recognized, give up
            return -1
        end

        element_tree:set_len(consumed_bytes)
        return consumed_bytes
    end

    f.type_sbm = ProtoField.none("ipc.type.sbm", "Gfx::ShareableBitmap")
    local tab_bitmap_format = {
        [0] = "Invalid",
        [1] = "Indexed1",
        [2] = "Indexed2",
        [3] = "Indexed4",
        [4] = "Indexed8",
        [5] = "BGRx8888",
        [6] = "BGRA8888",
        [7] = "RGBA8888",
    }
    f.type_sbm_format = ProtoField.uint32("ipc.type.sbm.format", "Format", base.DEC, tab_bitmap_format)
    local function parse_Gfx_ShareableBitmap(param_name, buf, empty_buf, tree)
        --TYPEIMPL:Gfx_ShareableBitmap
        -- FIXME: Deal with insufficiently small buffers
        local param_tree = tree:add_le(f.type_sbm, buf(0, 1))
        param_tree:prepend_text(string.format("%s: ", param_name))
        local is_valid = buf(0, 1):le_uint()
        if is_valid == 0 then
            return 1
        end
        local consumed_bytes = 1
        buf = snip(buf, empty_buf, 1)
        parse_IPC_File("bitmap data", buf, empty_buf, param_tree)
        -- buf = snip(buf, empty_buf, 0)

        parsed_bytes = parse_Gfx_IntSize("bitmap data", buf, empty_buf, param_tree)
        if parsed_bytes < 0 then
            return -1
        end
        consumed_bytes = consumed_bytes + parsed_bytes
        buf = snip(buf, empty_buf, parsed_bytes)

        parsed_bytes = parse_u32("scale", buf, empty_buf, param_tree)
        if parsed_bytes < 0 then
            return -1
        end
        consumed_bytes = consumed_bytes + parsed_bytes
        buf = snip(buf, empty_buf, parsed_bytes)

        elements_tree = param_tree:add_le(f.type_sbm_format, buf(0, 4))
        local bitmap_format = buf(0, 4):le_uint()
        consumed_bytes = consumed_bytes + 4
        buf = snip(buf, empty_buf, parsed_bytes)

        if bitmap_format >= 1 and bitmap_format <= 4 then
            parsed_bytes = parse_Vector_u32("palette", buf, empty_buf, param_tree)
            if parsed_bytes < 0 then
                return -1
            end
            consumed_bytes = consumed_bytes + parsed_bytes
        elseif bitmap_format < 1 or bitmap_format > 7 then
            -- Unknown format, cannot know for sure whether a palette follows
            return -1
        end

        param_tree:set_len(consumed_bytes)
        return consumed_bytes
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
    -- f.ep_1419546125_2_content = ProtoField.none("ipc.msg.msg_type_1419546125_2", "ConfigClient::NotifyChangedI32Value")
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

        if buf:len() > 0 then
            tree:add(f.unexpected_padding, buf)
        end
    end

    DissectorTable.get("wtap_encap"):add(wtap.USER13, IPC)
end
