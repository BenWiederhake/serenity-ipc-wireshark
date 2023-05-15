local float = 0.1
local float_bytes = ByteArray.new(Struct.pack('>f', float), true)

IPC = Proto("ipc", "Ipc")

f = IPC.fields
f.float = ProtoField.float("ipc.float", "Float")

function IPC.dissector(buffer, pinfo, tree)
    local float_tvb = float_bytes:tvb("Float2"):range()
    tree:add(f.float, float_tvb)
end

register_postdissector(IPC)
