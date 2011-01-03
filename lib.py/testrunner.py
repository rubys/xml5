from parser import XMLParser
def runtests(filename):
    f = open(filename)
    tests = f.read().split("#data\n")
    errorAmount = index = 0
    errorLog = []
    for index, test in enumerate(tests):
        if test == "": continue
        test = "#data\n" + test
        input, expected, errors = parseTestcase(test)
        parser = XMLParser()
        result = parser.parse(input).printTree()
        if result != "#document\n" + expected:
            errorAmount += 1
            errorLog.append("For:\n" + input + "\nExpected:\n" + expected + "\nGot:\n" + result + "\n\n")
    if errorAmount == 0:
        print "All Good!"
    else:
        print "\n" + "".join(errorLog)

def parseTestcase(testString):
    testString = testString.split("\n")
    try:
        if testString[0] != "#data":
            sys.stderr.write(testString)
        assert testString[0] == "#data"
    except:
        raise
    input = []
    expected = []
    errors = []
    currentList = input
    for line in testString:
        if line and not (line.startswith("#errors") or
          line.startswith("#document") or line.startswith("#data")):
            if currentList is expected:
                currentList.append(line)
            else:
                currentList.append(line)
        elif line == "#errors":
            currentList = errors
        elif line == "#document":
            currentList = expected
    return "\n".join(input), "\n".join(expected), errors

if __name__ == "__main__":
    import sys
    runtests("../tests/tree-construction1")
    if sys.argv[-1] == "testrunner.py":
        print "Run tests that need fixing..."
        runtests("../tests/needs-fixing")
