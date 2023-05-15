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
    local message_type_info_by_endpoint = {}

    local f = IPC.fields
    f.direction = ProtoField.uint8("ipc.direction", "Direction", base.DEC, tab_directions)
    f.message = ProtoField.bytes("ipc.message", "Message content")
    f.endpoint = ProtoField.uint32("ipc.msg.endpoint", "Endpoint magic", base.DEC_HEX, tab_endpoints)  -- FIXME: Bad format?!
    f.message_type_1419546125 = ProtoField.uint32("ipc.msg.msg_type", "ConfigClient Message Type (enum)", base.DEC, tab_message_type_1419546125)
    message_type_info_by_endpoint[1419546125] = {field=f.message_type_1419546125}
    f.message_type_1419546126 = ProtoField.uint32("ipc.msg.msg_type", "FooBar Message Type (enum)", base.DEC, tab_message_type_1419546126)
    message_type_info_by_endpoint[1419546126] = {field=f.message_type_1419546126}


    function IPC.dissector(buf, pinfo, tree)
        tree:add(f.direction, buf(0,1))
        pinfo.p2p_dir = buf(0,1):le_uint(); -- Hopefully P2P_DIR_SENT or P2P_DIR_RECV
        local message_buf = buf(1, buf:len() - 1)
        local message = tree:add(f.message, message_buf)
        if buf:len() < 9 then
            -- FIXME: Report invalid packet
            return -1
        end
        message:add_le(f.endpoint, message_buf(0,4))
        local endpoint_value = message_buf(0,4):le_uint()
        local message_type_info = message_type_info_by_endpoint[endpoint_value]
        if message_type_info == nil then
            -- FIXME: Report invalid packet
            return -1
        end
        message:add_le(message_type_info.field, message_buf(4,4))
    end

    --register_postdissector(IPC)
    DissectorTable.get("wtap_encap"):add(wtap.USER13, IPC)
end
