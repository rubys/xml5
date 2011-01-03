#!/usr/bin/env python
import string

EOF = None
spaceCharacters = frozenset((
    u"\t",
    u"\n",
    u"\u000B",
    u"\u000C",
    u" ",
    u"\r"
))
digits = frozenset(string.digits)
hexDigits = frozenset(string.hexdigits)
