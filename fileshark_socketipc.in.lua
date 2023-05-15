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
    f.direction = ProtoField.uint8("ipc.direction", "Direction", base.DEC, tab_directions)
    f.message = ProtoField.bytes("ipc.message", "Message content")
    -- FIXME: Bad format?! DEC=decimal, HEX=hex, DEC_HEX=deconly, HEX_DEC=hexonly???
    f.endpoint = ProtoField.uint32("ipc.msg.endpoint", "Endpoint magic", base.HEX_DEC, tab_endpoints)

    --AUTOGENERATE:ENDPOINT_FIELDS_AND_CONTEXT
    -- Example:
    -- f.ep_1419546125_type = ProtoField.uint32("ipc.msg.msg_type", "ConfigClient Message Type (enum)", base.DEC, {
    --     [2] = "NotifyChangedI32Value",
    -- })
    -- endpoint_info[1419546125] = {type_field=f.ep_1419546125_type, types={}}
    -- f.ep_1419546125_2_content = ProtoField.bytes("ipc.msg.msg_type_1419546125_2", "ConfigClient::NotifyChangedI32Value")
    -- endpoint_info[1419546125].types[2] = {type_field=f.ep_1419546125_2_content, parameters={}}

    function IPC.dissector(buf, pinfo, tree)
        -- Parse direction
        tree:add(f.direction, buf(0,1))
        pinfo.p2p_dir = buf(0,1):le_uint(); -- Hopefully P2P_DIR_SENT or P2P_DIR_RECV
        local buf = buf(1)
        local message_tree = tree:add(f.message, buf)

        -- Parse endpoint
        if buf:len() < 4 then
            -- FIXME: Report invalid packet, as it is missing the endpoint
            return -1
        end
        message_tree:add_le(f.endpoint, buf(0,4))
        local endpoint_value = buf(0,4):le_uint()
        local endpoint_ctx = endpoint_info[endpoint_value]
        if endpoint_ctx == nil then
            -- FIXME: Report invalid endpoint magic
            return -1
        end
        local buf = buf(4)

        -- Parse message type
        if buf:len() < 4 then
            -- FIXME: Report invalid packet, as it is missing the message type
            return -1
        end
        message_tree:add_le(endpoint_ctx.type_field, buf(0,4))
        local message_ctx = endpoint_ctx.types[buf(0,4):le_uint()]
        if message_ctx == nil then
            -- FIXME: Report invalid message type for this endpoint
            return -1
        end
        local buf = buf(4)
        local message = message_tree:add(message_ctx.type_field, buf)

        -- FIXME: Parse 'message' according to 'message_ctx.parameters'
    end

    DissectorTable.get("wtap_encap"):add(wtap.USER13, IPC)
end
