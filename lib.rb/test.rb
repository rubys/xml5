$: << File.dirname(__FILE__)

require 'parser'

def test(string)
  x = XMLParser.new()
  tree = x.parse(string)
  puts tree.printTree()
end

if __FILE__ == $0
  if ARGV.last
    test(ARGV.last)
  else
    test("<!DOCTYPE test [<!ENTITY % xx '&#37;zz;'><!ENTITY % zz '&#60;!ENTITY tricky \"error-prone\" >' > %xx; ]><test>This sample shows a &tricky; method.</test>")
  end
end
