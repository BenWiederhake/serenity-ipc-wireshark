#!/bin/sh

set -e

HEXFILE="$1"
RAWFILE="${HEXFILE/.hex/}"

test -r "${HEXFILE}"
./compile.py "${HEXFILE}"
hd "${RAWFILE}"
wireshark -X lua_script:fileshark_socketipc.lua "${RAWFILE}"
