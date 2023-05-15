do
    local IPC = Proto("ipc", "Serenity Ipc")

    local tab_directions = {
        [P2P_DIR_SENT] = "outgoing",
        [P2P_DIR_RECV] = "incoming",
    }

    local tab_endpoints = {
        -- jq -r '.[] | "        [\(.magic)] = \"\(.name).ipc\","' < all.ipc.json
        [2714249765] = "NotificationServer.ipc",
        [1502652576] = "RequestClient.ipc",
        [1270977860] = "RequestServer.ipc",
        [2565717604] = "WebContentClient.ipc",
        [4289017466] = "WebContentServer.ipc",
        [2244075654] = "WebDriverServer.ipc",
        [4284153835] = "WebDriverClient.ipc",
        [3887509455] = "AudioServer.ipc",
        [1126638765] = "AudioClient.ipc",
        [945471142] = "ImageDecoderClient.ipc",
        [3964467294] = "ImageDecoderServer.ipc",
        [531353361] = "SQLClient.ipc",
        [3731107876] = "SQLServer.ipc",
        [3157685592] = "WebSocketClient.ipc",
        [1144104864] = "WebSocketServer.ipc",
        [3613307456] = "LookupServer.ipc",
        [3540717142] = "LookupClient.ipc",
        [3317521970] = "WindowManagerClient.ipc",
        [471012077] = "WindowManagerServer.ipc",
        [2938215075] = "WindowServer.ipc",
        [3794023488] = "WindowClient.ipc",
        [4008793515] = "ClipboardClient.ipc",
        [1329211611] = "ClipboardServer.ipc",
        [729082329] = "FileSystemAccessServer.ipc",
        [3747304165] = "FileSystemAccessClient.ipc",
        [1706997054] = "LaunchClient.ipc",
        [1140813104] = "LaunchServer.ipc",
        [1419546125] = "ConfigClient.ipc",
        [252595060] = "ConfigServer.ipc",
        [3294800782] = "LanguageServer.ipc",
        [114752332] = "LanguageClient.ipc",
--        [0x549c8e0d] = "ConfigServer/ConfigClient.ipc",
        [1419546126] = "IMAGINARY.ipc",
    }

    -- Won't work for more than one endpoint
    local tab_message_type_1419546125 = {
        [2] = "NotifyChangedI32Value",
    }
    local tab_message_type_1419546126 = {
        [2] = "FooBarThing",
    }
    local endpoint_info = {}

    local f = IPC.fields
    f.direction = ProtoField.uint8("ipc.direction", "Direction", base.DEC, tab_directions)
    f.message = ProtoField.bytes("ipc.message", "Message content")
    -- DEC=decimal, HEX=hex, DEC_HEX=deconly, HEX_DEC=hexonly???
    f.endpoint = ProtoField.uint32("ipc.msg.endpoint", "Endpoint magic", base.HEX_DEC, tab_endpoints)  -- FIXME: Bad format?!

    f.ep_1419546125_type = ProtoField.uint32("ipc.msg.msg_type", "ConfigClient Message Type (enum)", base.DEC, tab_message_type_1419546125)
    endpoint_info[1419546125] = {type_field=f.ep_1419546125_type, types={}}
    f.ep_1419546125_2_content = ProtoField.bytes("ipc.msg.msg_type_1419546125_2", "ConfigClient::NotifyChangedI32Value")
    endpoint_info[1419546125].types[2] = {type_field=f.ep_1419546125_2_content, inputs={}}

    f.ep_1419546126_type = ProtoField.uint32("ipc.msg.msg_type", "FooBar Message Type (enum)", base.DEC, tab_message_type_1419546126)
    endpoint_info[1419546126] = {type_field=f.ep_1419546126_type, types={}}


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

        -- FIXME: Parse 'message' according to 'message_ctx.inputs'
    end

    --register_postdissector(IPC)
    DissectorTable.get("wtap_encap"):add(wtap.USER13, IPC)
end
