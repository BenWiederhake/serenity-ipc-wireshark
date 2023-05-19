#!/usr/bin/env python3

import hydrate_lua
from hydrate_lua import Typename
import unittest


class TemplateParsing(unittest.TestCase):
    def test_tokenizer(self):
        self.assertEqual(hydrate_lua.tokenize("asdf,qwer<kjh"), ["asdf", ",", "qwer", "<", "kjh"])
        self.assertEqual(hydrate_lua.tokenize("HashMap<String, String>"), ["HashMap", "<", "String", ",", "String", ">"])

    def test_parser(self):
        self.assertEqual(hydrate_lua.parse_typename("i32"), Typename("i32"))
        self.assertEqual(hydrate_lua.parse_typename("::Complicated::Namespace"), Typename("_Complicated_Namespace"))
        self.assertEqual(hydrate_lua.parse_typename("Vector<Foo>"), Typename("Vector", [Typename("Foo")]))
        self.assertEqual(hydrate_lua.parse_typename("HashMap<String, String>"), Typename("HashMap", [Typename("String"), Typename("String")]))


if __name__ == "__main__":
    unittest.main()
