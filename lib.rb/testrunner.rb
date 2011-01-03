$: << File.dirname(__FILE__)
require 'parser'

def runtests(filename)
  f = open(filename)
  tests = f.read().split("#data\n")
  errorAmount = index = 0
  errorLog = []
  tests.each_with_index do |test, index|
    next if test == ""
    test = "#data\n" + test
    input, expected, errors = parseTestcase(test)
    parser = XMLParser.new()
    result = parser.parse(input).printTree()
    if result != "#document\n" + expected
      errorAmount += 1
      errorLog << "For:\n" + input + "\nExpected:\n" + expected + "\nGot:\n" + result + "\n\n"
    end
  end
  if errorAmount == 0
    puts "All Good!"
  else
    print "\n" + errorLog.join('')
    puts errorAmount
  end
end

def parseTestcase(testString)
  testString = testString.split("\n")
  begin
    if testString[0] != "#data"
      sys.stderr.write(testString)
    end
    raise Exception.new("AssertionError") unless testString[0] == "#data"
  rescue
    raise
  end
  input = []
  expected = []
  errors = []
  currentList = input
  for line in testString
    if line and not (line =~ /^#errors/ or
      line =~ /^#document/ or line =~ /#data/)
      if currentList == expected
        currentList << line
      else
        currentList << line
      end
    elsif line == "#errors"
      currentList = errors
    elsif line == "#document"
      currentList = expected
    end
  end
  return input.join("\n"), expected.join("\n"), errors
end

if __FILE__ == $0
  runtests("../tests/tree-construction1")
  if ARGV == []
    puts "Run tests that need fixing..."
    runtests("../tests/needs-fixing")
  end
end
