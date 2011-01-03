from parser import XMLParser
import sys

def test(string):
    x = XMLParser()
    tree = x.parse(string)
    print tree.printTree()

if __name__ == "__main__":
    if sys.argv[-1] != "test.py":
        test(sys.argv[-1])
    else:
        test("<!DOCTYPE test [<!ENTITY % xx '&#37;zz;'><!ENTITY % zz '&#60;!ENTITY tricky \"error-prone\" >' > %xx; ]><test>This sample shows a &tricky; method.</test>")
