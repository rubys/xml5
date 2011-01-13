var fs = require('fs');

function runtests(filename) {
  var tests = fs.readFileSync(filename, 'utf-8').split("#data\n");
  for (var i in tests) {
    exports['test' + i] = function() {
      var testcase = parseTestcase(tests[i]);
      return function(test) {
	test.equal(0, testcase.errors.length);
	test.done();
      }
    }();
  }
}

function parseTestcase(testString) {
  testString = testString.split("\n");
  var input = [];
  var expected = [];
  var errors = [];
  var currentList = input;

  while (testString.length > 0) {
    var line = testString.shift();
    if (line == '#errors') {
      currentList = errors;
    } else if (line == '#document') {
      currentList = expected;
    } else {
      currentList.push(line);
    }
  }

  return {
    input: input.join("\n"),
    expected: expected.join("\n"),
    errors: errors
  };
}

runtests("../tests/tree-construction1");
runtests("../tests/needs-fixing")
