# serenity-ipc-wireshark

Visualize Serenity IPC traces in Wireshark.

This collection of tools enables you to inspect a `.pcap` trace that gets generated when you run a serenity IPC server with the patches in `patches/`.

Only a small set of primitives has to be manually implemented (integers, enums, Strings, etc.), and most of them already are implemented. A missing type only results in the rest of the block being unreadable, so not too much is lost. All constructed types are read and compiled from `all.ipc.json`.

Things you probably need:
- `fileshark_socketipc.in.lua`: Raw unrunnable Lua script. Implement base-types here.
- `hydrate_lua.py`: Generates the runnable lua script from `fileshark_socketipc.in.lua` and `all.ipc.json`
- `COMMANDS.txt`: Shows you how to invoke it.

Other files:
- `compile.py`: Self-rolled micro-assembler for binary data
- `compile_and_run.sh`: Wrapper that invokes Wireshark on the newly-assembled file
- `*.pcap.hex`: Some hand-crafted example files
- `*_ipc_traffic.tar.gz`: Some actual traces that mostly work

This is an incomplete project that I'm only sharing because someone else wanted to take it further. Go ahead, friend! :)

## Contribute

Feel free to dive in! [Open an issue](https://github.com/BenWiederhake/serenity-ipc-wireshark/issues/new) or submit PRs.
