#!/bin/bash

set -e

HEXFILE="$1"
test -r "${HEXFILE}"

RAWFILE="${HEXFILE/.hex/}"
./compile.py "${HEXFILE}"
hd "${RAWFILE}"
wireshark -X lua_script:fileshark_socketipc.lua "${RAWFILE}"
