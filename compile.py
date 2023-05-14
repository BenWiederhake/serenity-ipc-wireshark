#!/usr/bin/env python3

import codecs
import sys


class Assembler:
    def __init__(self):
        self.buffer = bytearray()

    def update(self, lines):
        for line in lines.split("\n"):
            self.update_line(line)

    def update_line(self, line):
        line = line.lstrip()
        if not line or line.startswith("#"):
            return
        if line.startswith("h "):
            self.update_hex(line[len("h "):])
            return
        if line.startswith("utf8 "):
            self.update_utf8(line[len("utf8 "):])
            return
        print(f"Unknown command: {line}", file=sys.stderr)
        exit(1)

    def update_utf8(self, utf8_data):
        self.buffer.extend(utf8_data.encode())

    def update_hex(self, hex_data):
        self.buffer.extend(codecs.decode(hex_data.replace(" ", ""), "hex"))

    def digest(self):
        return self.buffer


def run_on(input_filename, output_filename):
    with open(input_filename, "r") as fp:
        hex_data = fp.read()
    assembler = Assembler()
    assembler.update(hex_data)
    bytes_data = assembler.digest()
    with open(output_filename, "wb") as fp:
        fp.write(bytes_data)


def run(argv):
    if len(argv) < 2:
        print(f"USAGE: {argv[0]} FILE1.pcap.hex [FILE2.pcap.hex ...]", file=sys.stderr)
        print("For each input file like FILE1.pcap.hex, the output is written to a file like FILE1.pcap", file=sys.stderr)
        exit(1)
    for filename in argv[1 :]:
        if not filename.endswith(".pcap.hex"):
            print(f"Refusing to process file '{filename}': Filename does not end in .pcap.hex", file=sys.stderr)
            exit(1)
        run_on(filename, filename[:-len(".hex")])


if __name__ == "__main__":
    run(sys.argv)
