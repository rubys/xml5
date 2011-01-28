var fs = require('fs');
var HTML5 = require('html5');
var jsdom = require('jsdom');
var XML5 = require('./index.js');
require('./parser.js');

// monkey patch jsdom
function monkey_patch() {
  var Attr = jsdom.dom.level3.core.Attr;
  var Element = jsdom.dom.level3.core.Element;
  Element.prototype.__defineGetter__('localName', function() {
    // no localName: https://github.com/tmpvar/jsdom/issues/issue/124
    return this._nodeName;
  });
  Attr.prototype.__defineGetter__('localName', function() {
    // no localName (similar issue)
    return this._nodeName;
  });
}

function runtests(filename) {
  var tests = fs.readFileSync(filename, 'utf-8').split("#data\n");
  for (var i=1; i<tests.length; i++) {
    exports['test' + i] = function() {
      var testcase = parseTestcase(tests[i]);
      return function(test) {
        var document = new (jsdom.dom.level3.core.Document)();
        var parser = new XML5.Parser({document: document});
        monkey_patch();
        parser.on('end', function() {
	  test.equal(testcase.expected, printTree(document, ''),
            testcase.input);
	  test.done();
        });
        parser.parse(testcase.input);
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
    } else if (line != '') {
      currentList.push(line);
    }
  }

  return {
    input: input.join("\n"),
    expected: "#document\n" + expected.join("\n"),
    errors: errors
  };
}

function printTree(node, indent) {
  tree = '';

  switch (node.nodeType) {
  case node.ELEMENT_NODE:
    var name = node.nodeName;
    var prefix = node.prefix;
    if(node._prefix != undefined) { // jsdom HACK
        prefix = node._prefix;
        name = prefix + ':' + name;
    }
    tree += '\n| ' + indent + '<' + name +  '> (' + 
            (prefix||'') + ', ' + (node.localName||'') + ', ' + 
            (node.namespaceURI||'') + ')';

    names = [];
    values = {}
    for (var i=0; i<node.attributes.length; i++) {
      names.push(node.attributes[i].name);
      values[node.attributes[i].name] = node.attributes[i];
    }
    names = names.sort();

    for (var i=0; i<names.length; i++) {
      var attr = values[names[i]];
      // jsdom HACK: _localName
      tree += '\n|   ' + indent + names[i] + '="' + attr.value + '" (' + 
              (attr.prefix||'') + ', ' + (attr._localName||attr.localName||'') + ', ' + 
              (attr.namespaceURI||'') + ')';
    }

    for (var i=0; i<node.childNodes.length; i++) {
      tree += printTree(node.childNodes[i], indent+'  ');
    }
    break;

  case node.TEXT_NODE:
    tree += '\n| ' + indent + '"' + node.value +  '"'
    break;

  case node.DOCUMENT_NODE:
    tree = node.nodeName;
    for(var i=0; i<node.childNodes.length; i++) {
      if(node.childNodes[i].nodeType == node.TEXT_NODE) continue; // XXX Hack
      tree += printTree(node.childNodes[i], indent);
    }
    break;

  case node.COMMENT_NODE:
    tree += "\n| " + indent + '<!-- ' + node.value + ' -->'
    break;

  default:
    console.log('unknown node type: ' + node.nodeType);
  }

  return tree;
}

runtests("../tests/tree-construction1");
runtests("../tests/needs-fixing")
