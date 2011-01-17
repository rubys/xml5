var XML5 = exports.XML5 = require('./index.js');

var events = require('events');

require('./tokenizer');

var Parser = XML5.Parser = function XML5Parser(options) {
	events.EventEmitter.apply(this);
	this.strict = false;
	this.errors = [];

	if(options) for(o in options) {
		this[o] = options[o];
	}

	if(!this.document) {
		var l2 = require('jsdom/level2/core').dom.level2.core;
		var browser = require('jsdom/browser')
		var DOM = browser.browserAugmentation(l2)
		this.document = new DOM.Document();
	}

	this.node = this.document;
}

Parser.prototype = new events.EventEmitter;

Parser.prototype.parse = function(source) {
	if(!source) throw(new Error("No source to parse"));
	XML5.debug('parser.parse', source)
	this.tokenizer = new XML5.Tokenizer(source, this.document);
	this.setup();
	this.tokenizer.tokenize();
}

Parser.prototype.do_token = function(token) {
	switch(token.type) {
	case 'EmptyTag':
	case 'StartTag':
		var child = this.document.createElement(token.name);
		for(var i=token.attributes.length-1; i>=0; i--) {
			child.setAttribute(token.attributes[i][0], token.attributes[i][1]);
		}

		this.node.appendChild(child);

		if(token.type == 'StartTag') this.node = child;
		break;

	case 'EndTag':
		node = this.node;
		while(node && node.nodeName.toLowerCase() != token.name.toLowerCase()) {
		      node = node.parentNode;
		}

		if(node) {
			this.node = node.parentNode;
		} else {
			this.parse_error('unmatched close', token.name);
		}
		break;

	case 'EndTagShort':
		if (this.node != this.document) {
		      this.node = this.node.parentNode;
		}
		break;

	case 'Pi':
		var pi = this.document.createProcessingInstruction(token.name, token.data);
		this.node.appendChild(pi);
		break;

	case 'Comment':
		var comment = this.document.createComment(token.data);
		this.node.appendChild(comment);
		break;

	case 'Characters':
		var length = this.node.childNodes.length;
		var last = (length == 0 ? null : this.node.childNodes[length-1]);
		if(last && last.nodeType==this.node.TEXT_NODE) {
			var text = this.document.createTextNode(last.value+token.data);
			this.node.replaceChild(text, last);
		} else {
			var text = this.document.createTextNode(token.data);
			this.node.appendChild(text);
		}
		break;

	default:
		console.log(token);
		this.parse_error('Unrecognized token type', token.type)
	}
}

Parser.prototype.setup = function(container, encoding) {
	this.tokenizer.addListener('token', function(t) {
		return function(token) { t.do_token(token); };
	}(this));
	this.tokenizer.addListener('end', function(t) {
		return function() { t.emit('end'); };
	}(this));
	this.emit('setup', this);
}

Parser.prototype.parse_error = function(code, data) {
	// FIXME: this.errors.push([this.tokenizer.position, code, data]);
	this.errors.push([code, data]);
	if(this.strict) throw(this.errors.last());
}

if(__filename == process.argv[1]) {
	var HTML5 = require('html5');
	var fs = require('fs');
	var jsdom = require('jsdom');
	var window = jsdom.jsdom(null, null, {parser: HTML5}).createWindow()
	var parser = new XML5.Parser({document: window.document});

	parser.parse(fs.createReadStream(process.argv[2], {flags: 'r'}));
	parser.on('end', function() {
		console.log(window.document.innerHTML);
	});
}
