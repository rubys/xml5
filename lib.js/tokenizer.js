var events = require('events');
var Buffer = require('./buffer').Buffer;
var XML5 = require('./index.js');

require('./core-upgrade');

function keys(h) {
	var r = [];
	for(var k in h) {
		r.push(k);
	}
	return r;
}

XML5.Tokenizer = t = function XML5Tokenizer(input, document) {
	if(!input) throw(new Error("No input given"));
	var state;
	var buffer = this.buffer = new Buffer();
	this.__defineSetter__('state', function(newstate) {
		XML5.debug('tokenizer.state=', newstate)
		state = newstate;
		buffer.commit();
	});
	this.state = 'data_state';
	this.current_token = null;

	if(input instanceof events.EventEmitter) {
		source = input;
		this.pump = null;
	} else {
		var source = new events.EventEmitter();
		this.pump = function() {
			source.emit('data', input);
			source.emit('end');
		}
	}

	this.commit = function() {
		buffer.commit();
	};

	var tokenizer = this;
	source.addListener('data', function(data) {
		if(typeof data !== 'string') data = data.toString();
		buffer.append(data);
		try {
			while(tokenizer[state](buffer));
		} catch(e) {
			if(e != 'drain') {
				throw(e);
			} else {
				buffer.undo();
			}
		}
	});
	source.addListener('end', function(t) { return function() {
		buffer.eof = true;
		while(tokenizer[state](buffer));
		t.emit('end');
	}}(this));
}

t.prototype = new events.EventEmitter;

t.prototype.tokenize = function() {
	if(this.pump) this.pump();
}

t.prototype.emitToken = function(tok) {
	XML5.debug('tokenizer.token', tok)
	this.emit('token', tok);
}

t.prototype.consume_entity = function(buffer, from_attr) {
	var char = null;
	var chars = buffer.char();
	if(chars == XML5.EOF) return false;
	if(chars.match(XML5.SPACE_CHARACTERS) || chars == '<' || chars == '&') {
		buffer.unget(chars);
	} else if(chars[0] == '#') { // Maybe a numeric entity
		var c = buffer.shift(2);
		chars += c;
		if(chars[1] && chars[1].toLowerCase() == 'x' && XML5.HEX_DIGITS_R.test(chars[2])) {
			// Hex entity
			buffer.unget(chars[2]);
			char = this.consume_numeric_entity(buffer, true);
		} else if(chars[1] && XML5.DIGITS_R.test(chars[1])) {
			// Decimal entity
			buffer.unget(chars.slice(1));
			char = this.consume_numeric_entity(buffer, false);
		} else {
			// Not numeric
			buffer.unget(chars);
			this.parse_error("expected-numeric-entity");
		}
	} else {
		var filteredEntityList = keys(XML5.ENTITIES).filter(function(e) {
			return e[0] == chars[0];
		});
		var entityName = null;
		while(true) {
			if(filteredEntityList.some(function(e) {
				return e.indexOf(chars) == 0;
			})) {
				filteredEntityList = filteredEntityList.filter(function(e) {
					return e.indexOf(chars) == 0;
				});
				chars += buffer.char()
			} else {
				break;
			}

			if(XML5.ENTITIES[chars]) {
				entityName = chars;
				if(entityName[entityName.length - 1] == ';') break;
			}
		}

		if(entityName) {
			char = XML5.ENTITIES[entityName];

			if(entityName[entityName.length - 1] != ';' && this.from_attribute && (XML5.ASCII_LETTERS_R.test(chars.substr(entityName.length, 1) || XML5.DIGITS.test(chars.substr(entityName.length, 1))))) {
				buffer.unget(chars);
				char = '&';
			} else {
				buffer.unget(chars.slice(entityName.length));
			}
		} else {
			this.parse_error("expected-named-entity");
			buffer.unget(chars);
		}
	}

	return char;
}

t.prototype.consume_numeric_entity = function(buffer, hex) {
	if(hex) {
		var allowed = XML5.HEX_DIGITS_R;
		var radix = 16;
	} else {
		var allowed = XML5.DIGITS_R;
		var radix = 10;
	}

	chars = '';

	var c = buffer.char();
	while(allowed.test(c)) {
		chars = chars + c;
		c = buffer.char();
	}

	var charAsInt = parseInt(chars, radix);

	if(charAsInt == 13) {
		this.parse_error("incorrect-cr-newline-entity");
		charAsInt = 10;
	} else if(charAsInt >= 128 && charAsInt <= 159) {
		this.parse_error("illegal-windows-1252-entity");
		charAsInt = XML5.WINDOWS1252[charAsInt - 128];
	}

	if(0 < charAsInt && charAsInt <= 1114111 && !(55296 <= charAsInt && charAsInt <= 57343)) {
		char = String.fromCharCode(charAsInt);
	} else {
		char = String.fromCharCode(0xFFFD);
		this.parse_error("cant-convert-numeric-entity");
	}

	if(c != ';') {
		this.parse_error("numeric-entity-without-semicolon");
		buffer.unget(c);
	}

	return char;
}

t.prototype.process_entity_in_attribute = function(buffer) {
	var entity = this.consume_entity(buffer);
	if(entity) {
		this.current_token.data.last().nodeValue += entity;
	} else {
		this.current_token.data.last().nodeValue += '&';
	}
}

t.prototype.process_solidus_in_tag = function(buffer) {
	var data = buffer.peek(1);
	if(this.current_token.type == 'StartTag' && data == '>') {
		this.current_token.type = 'EmptyTag';
		return true;
	} else {
		this.parse_error("incorrectly-placed-solidus");
		return false;
	}
}
// Below are the various tokenizer states worked out.
t.prototype.data_state = function(buffer) {
	var c = buffer.char();
	if(c == "&") {
		var entity = this.consume_entity(buffer);
		if(entity) {
			this.emitToken({type: "Characters", data: entity});
		} else {
			buffer.unget(entity);
		}
	} else if(c == "<") {
		this.state = "tag_state";
	} else if(c == XML5.EOF) {
		// Tokenization ends.
		return false;
	} else {
		var chars = buffer.matchUntil("[&<\\u0000]");
		this.emitToken({type: "Characters", data: c + chars});
	}
	return true;
}

t.prototype.tag_state = function(buffer) {
	var c = buffer.char();
	if(c == "/") {
		this.state = "end_tag_state";
	} else if(c == "?") {
		this.state = "pi_state";
	} else if(c == "!") {
		this.state = "markup_declaration_state";
	} else if(XML5.SPACE_CHARACTERS_R.test(c)
	  || c == "<"
	  || c == ">"
	  || c == ":"
	  || c == XML5.EOF) {
		// XXX parse error
		this.emitToken({type: "Characters", data: "<"});
		buffer.queue.insert(0, c);
		this.state = "data_state";
	} else {
		this.current_token = {type: "StartTag", name: c, attributes: []};
		this.state = "tag_name_state";
	}
	return true;
}

t.prototype.end_tag_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.emitToken({type: "EndTagShort"});
		this.state = "data_state";
	} else if(XML5.SPACE_CHARACTERS_R.test(c)
	  || c == "<"
	  || c == ":"
	  || c == XML5.EOF) {
		// XXX parse error
		// XXX catch more "incorrect" characters here?
		this.emitToken({type: "Characters", data: "</"});
		buffer.queue.insert(0, c);
		this.state = "data_state";
	} else {
		this.current_token = {type: "EndTag", name: c};
		this.state = "end_tag_name_state";
	}
	return true;
}

t.prototype.end_tag_name_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "end_tag_name_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else if(c == ">") {
		this.emit_current_token();
	} else {
		this.current_token["name"] += c;
	}
	return true;
}

t.prototype.end_tag_name_after_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.emit_current_token();
	} else if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else {
		// XXX parse error
		pass;
	}
	return true;
}

t.prototype.pi_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)
	  || c == XML5.EOF) {
		// XXX parse error
		// XXX catch more "incorrect" characters here?
		buffer.unget("?");
		buffer.unget(c);
		this.state = "bogus_comment_state";
	} else {
		this.current_token = {type: "Pi", name: c, data: ""};
		this.state = "pi_target_state";
	}
	return true;
}

t.prototype.pi_target_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "pi_target_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		// XXX catch more "incorrect" characters here?
		this.emit_current_token();
	} else if(c == "?") {
		this.state = "pi_after_state";
	} else {
		this.current_token["name"] += c;
	}
	return true;
}

t.prototype.pi_target_after_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else {
		buffer.unget(c);
		this.state = "pi_content_state";
	}
	return true;
}

t.prototype.pi_content_state = function(buffer) {
	var c = buffer.char();
	if(c == "?") {
		this.state = "pi_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else {
		this.current_token.data += c;
	}
	return true;
}

t.prototype.pi_after_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.emit_current_token();
	} else if(c == "?") {
		this.current_token.data += "?";
	} else {
		buffer.unget(c);
		this.state = "pi_content_state";
	}
	return true;
}

// Markup declarations.
t.prototype.markup_declaration_state = function(buffer) {
	var charStack = [buffer.char(), buffer.char()];
	if(charStack.join("") == "--") {
		this.current_token = {type: "Comment", data: ""};
		this.state = "comment_state";
	} else {
		for(var x=0; x<5; x++) {
			charStack.push(buffer.char());
		}
		if(charStack[charStack.length-1] != XML5.EOF) {
			var n = charStack.join("");
			if(n == "[CDATA[") {
				this.state = "cdata_state";
				return true;
			}
			if(n == "DOCTYPE") {
				// XXX parse error
				this.state = "doctype_state";
				return true;
			}
		}
		// XXX parse error
		buffer.queue.concat(charStack);
		this.state = "bogus_comment_state";
	}
	return true;
}

// Handling of comments. They end after a literal '-->' sequence.
t.prototype.comment_state = function(buffer) {
	var c = buffer.char();
	if(c == "-") {
		this.state = "comment_dash_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emitToken(this.current_token);
		this.state = "data_state";
	} else {
		this.current_token.data += c + buffer.matchUntil("-");
	}
	return true;
}

t.prototype.comment_dash_state = function(buffer) {
	var c = buffer.char();
	if(c == "-") {
		this.state = "comment_end_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emitToken(this.current_token);
		this.state = "data_state";
	} else {
		this.current_token.data += "-" + c +
		  buffer.matchUntil("-");
		// Consume the next character which is either a "-" or an EOF as
		// well so if there's a "-" directly after the "-" we go nicely to
		// the "comment end state" without emitting a ParseError() there.
		buffer.char();
	}
	return true;
}

t.prototype.comment_end_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.emitToken(this.current_token);
		this.state = "data_state";
	} else if(c == "-") {
		this.current_token.data += "-";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emitToken(this.current_token);
		this.state = "data_state";
	} else {
		this.current_token.data += "--" + c;
		this.state = "comment_state";
	}
	return true;
}

// These states handle the last bit of <![CDATA[ foo ]]> blocks.
t.prototype.cdata_state = function(buffer) {
	var c = buffer.char();
	if(c == "]") {
		this.state = "cdata_bracket_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.emitToken({type: "Characters", data:
		  c + buffer.matchUntil("]")});
	}
	return true;
}

t.prototype.cdata_bracket_state = function(buffer) {
	var c = buffer.char();
	if(c == "]") {
		this.state = "cdata_end_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.emitToken({type: "Characters", data:
		  "]" + c + buffer.matchUntil("]")});
		// Consume the next character which is either a "]" or an EOF as
		// well so if there's a "]" directly after the "]" we go nicely to
		// the "cdata end state" without emitting a ParseError() there.
		buffer.char();
	}
	return true;
}

t.prototype.cdata_end_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.state = "data_state";
	} else if(c == "]") {
		this.emitToken({type: "Characters", data: c});
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.emitToken({type: "Characters", data: "]]" + c});
		this.state = "cdata_state";
	}
	return true;
}

// XXX should we emit doctype tokens and such?
t.prototype.doctype_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_root_name_before_state";
	} else if(c == XML5.EOF) {
		// XXX parse error?
		this.state = "data_state";
	} else {
		buffer.unget(c);
		this.state = "bogus_comment_state";
	}
	return true;
}

t.prototype.doctype_root_name_before_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == ">") {
		this.state = "data_state";
	} else if(c == XML5.EOF) {
		// XXX parse error?
		this.state = "data_state";
	} else {
		this.state= "doctype_root_name_state";
	}
	return true;
}

t.prototype.doctype_root_name_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_root_name_after_state";
	} else if(c == ">") {
		this.state = "data_state";
	} else if(c == "[") {
		this.state = "doctype_internal_subset_state";
	} else if(c == XML5.EOF) {
		// XXX parse error?
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_root_name_after_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.state = "data_state";
	} else if(c == "\"") {
		this.state = "doctype_identifier_double_quoted_state";
	} else if(c == "'") {
		this.state = "doctype_identifier_single_quoted_state";
	} else if(c == "[") {
		this.state = "doctype_internal_subset_state";
	} else if(c == XML5.EOF) {
		// XXX parse error?
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_identifier_double_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "\"") {
		this.state = "doctype_root_name_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error?
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_identifier_single_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "'") {
		this.state = "doctype_root_name_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error?
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_internal_subset_state = function(buffer) {
	var c = buffer.char();
	if(c == "<") {
		this.state = "doctype_tag_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else if(c == "%") {
		buffer.queue.concat(this.consumeParameterEntity());
	} else if(c == "]") {
		this.state = "doctype_internal_subset_after_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_internal_subset_after_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.state = "data_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_tag_state = function(buffer) {
	var c = buffer.char();
	if(c == "!") {
		this.state = "doctype_markup_declaration_state";
	} else if(c == "?") {
		this.state = "doctype_pi_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_bogus_comment_state";
	}
	return true;
}

t.prototype.doctype_markup_declaration_state = function(buffer) {
	var charStack = [buffer.char(), buffer.char()];
	if(charStack.join("") == "--") {
		this.state = "doctype_comment_state";
	} else {
		for(var x=0; x<4; x++) {
			charStack.push(buffer.char());
		}
		if(charStack[charStack.length-1] != XML5.EOF) {
			if(charStack.join("") == "ENTITY") {
				this.state = "doctype_entity_state";
				return true;
			}
			var c = buffer.char();
			charStack.push(c);
			if(c != XML5.EOF) {
				if(charStack.join("") == "ATTLIST") {
					this.state = "doctype_attlist_state";
					return true;
				}
				c = buffer.char();
				charStack.push(c);
				if(c != XML5.EOF) {
					if(charStack.join("") == "NOTATION") {
						this.state = "doctype_notation_state";
						return true;
					}
				}
			}
		}
		// XXX parse error
		buffer.queue.concat(charStack);
		this.state = "doctype_bogus_comment_state";
	}
	return true;
}

// <!-- ....
t.prototype.doctype_comment_state = function(buffer) {
	var c = buffer.char();
	if(c == "-") {
		this.state = "doctype_comment_dash_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_comment_dash_state = function(buffer) {
	var c = buffer.char();
	if(c == "-") {
		this.state = "doctype_comment_end_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_comment_state";
	}
	return true;
}

t.prototype.doctype_comment_end_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.state = "doctype_internal_subset_state";
	} else if(c == "-") {
		this.state = "doctype_comment_dash_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_comment_state";
	}
	return true;
}

// <!ENTITY
t.prototype.doctype_entity_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_entity_type_before_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_bogus_comment_state";
	}
	return true;
}

t.prototype.doctype_entity_type_before_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == "%") {
		this.state = "doctype_entity_parameter_before_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.current_token = {type: "entity", name: c, value: ""};
		this.state = "doctype_entity_name_state";
	}
	return true;
}

t.prototype.doctype_entity_parameter_before_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_entity_parameter_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_bogus_comment_state";
	}
	return true;
}

t.prototype.doctype_entity_parameter_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.current_token = {type: "parameterEntity", name: c,
		  value: ""};
		this.state = "doctype_entity_name_state";
	}
	return true;
}

t.prototype.doctype_entity_name_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_entity_name_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.current_token = None;
		this.state = "data_state";
	} else {
		this.current_token["name"] += c;
	}
	return true;
}

t.prototype.doctype_entity_name_after_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == "\"") {
		this.state = "doctype_entity_val_double_quoted_state";
	} else if(c == "'") {
		this.state = "doctype_entity_val_single_quoted_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.current_token == None;
		this.state = "data_state";
	} else {
		this.state = "doctype_entity_identifier_state";
	}
	return true;
}

t.prototype.doctype_entity_val_double_quoted_state = function(buffer) {
	var c = buffer.char();
	// XXX "&" and "%"
	if(c == "\"") {
		this.state = "doctype_entity_val_after_state";
	} else if(c == "&") {
		this.current_token["value"] += this.consumeNumberEntityOnly();
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.current_token == None;
		this.state = "data_state";
	} else {
		this.current_token["value"] += c;
	}
	return true;
}

t.prototype.doctype_entity_val_single_quoted_state = function(buffer) {
	var c = buffer.char();
	// XXX "&" and "%"
	if(c == "'") {
		this.state = "doctype_entity_val_after_state";
	} else if(c == "&") {
		this.current_token["value"] += this.consumeNumberEntityOnly();
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.current_token == None;
		this.state = "data_state";
	} else {
		this.current_token["value"] += c;
	}
	return true;
}

t.prototype.doctype_entity_val_after_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == ">") {
		this.appendEntity();
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.current_token == None;
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_entity_identifier_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.appendEntity();
	} else if(c == "\"") {
		this.state = "doctype_entity_identifier_double_quoted_state";
	} else if(c == "'") {
		this.state = "doctype_entity_identifier_single_quoted_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.current_token = None;
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_entity_identifier_double_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "\"") {
		this.state = "doctype_entity_identifier_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.current_token = None;
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_entity_identifier_single_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "'") {
		this.state = "doctype_entity_identifier_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.current_token = None;
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_attlist_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_attlist_name_before_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_bogus_comment_state";
	}
	return true;
}

t.prototype.doctype_attlist_name_before_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.attributeNormalization.push({name: c, attrs: []});
		this.state = "doctype_attlist_name_state";
	}
	return true;
}

t.prototype.doctype_attlist_name_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_attlist_name_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.attributeNormalization.last()["name"] += c;
	}
	return true;
}

t.prototype.doctype_attlist_name_after_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == ">") {
		this.state = "doctype_internal_subset_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.attributeNormalization.last()["attrs"].push({name: c, type: "", dv: ""});
		this.state = "doctype_attlist_attrname_state";
	}
	return true;
}

t.prototype.doctype_attlist_attrname_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_attlist_attrname_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.attributeNormalization.last()["attrs"].last()["name"] += c;
	}
	return true;
}

t.prototype.doctype_attlist_attrname_after_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.attributeNormalization.last()["attrs"].last()["type"] += c;
		this.state = "doctype_attlist_attrtype_state";
	}
	return true;
}

t.prototype.doctype_attlist_attrtype_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_attlist_attrtype_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.attributeNormalization.last()["attrs"].last()["type"] += c;
	}
	return true;
}

t.prototype.doctype_attlist_attrtype_after_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == "#") {
		this.state = "doctype_attlist_attrdecl_before_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_bogus_comment_state";
	}
	return true;
}

t.prototype.doctype_attlist_attrdecl_before_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_bogus_comment_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_attlist_attrdecl_state";
	}
	return true;
}

t.prototype.doctype_attlist_attrdecl_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_attlist_attrdecl_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_attlist_attrdecl_after_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		pass;
	} else if(c == ">") {
		this.state = "doctype_internal_subset_state";
	} else if(c == "\"") {
		this.state = "doctype_attlist_attrval_double_quoted_state";
	} else if(c == "'") {
		this.state = "doctype_attlist_attrval_single_quoted_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.attributeNormalization.last()["attrs"].push({name: c, type: "", dv: ""});
		this.state = "doctype_attlist_attrname_state";
	}
	return true;
}

t.prototype.doctype_attlist_attrval_double_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "\"") {
		this.state = "doctype_attlist_name_after_state";
	} else if(c == "%") {
		throw(new Error("NotSupported"));
	} else if(c == "&") {
		throw(new Error("NotSupported"));
	} else {
		this.attributeNormalization.last()["attrs"].last()["dv"] += c;
	}
	return true;
}

t.prototype.doctype_attlist_attrval_single_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "'") {
		this.state = "doctype_attlist_name_after_state";
	} else if(c == "%") {
		throw(new Error("NotSupported"));
	} else if(c == "&") {
		throw(new Error("NotSupported"));
	} else {
		this.attributeNormalization.last()["attrs"].last()["dv"] += c;
	}
	return true;
}

// <!NOTATION
t.prototype.doctype_notation_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "doctype_notation_identifier_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_bogus_comment_state";
	}
	return true;
}

t.prototype.doctype_notation_identifier_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.state = "doctype_internal_subset_state";
	} else if(c == "\"") {
		this.state = "doctype_notation_identifier_double_quoted_state";
	} else if(c == "'") {
		this.state = "doctype_notation_identifier_single_quoted_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_notation_identifier_double_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "\"") {
		this.state = "doctype_notation_identifier_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_notation_identifier_single_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "'") {
		this.state = "doctype_notation_identifier_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_pi_state = function(buffer) {
	var c = buffer.char();
	if(c == "?") {
		this.state = "doctype_pi_after_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		pass;
	}
	return true;
}

t.prototype.doctype_pi_after_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.state = "doctype_internal_subset_state";
	} else if(c == "?") {
		pass;
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.state = "data_state";
	} else {
		this.state = "doctype_pi_state_state";
	}
	return true;
}

// Bogus "comments" inside a doctype
t.prototype.doctype_bogus_comment_state = function(buffer) {
	buffer.matchUntil(">");
	buffer.char();
	this.state = "doctype_internal_subset_state";
	return true;
}

// Tag name of a start or empty tag.
t.prototype.tag_name_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "tag_attribute_name_before_state";
	} else if(c == ">") {
		this.emit_current_token();
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else if(c == "/") {
		this.state = "empty_tag_state";
	} else {
		this.current_token["name"] += c;
	}
	return true;
}

t.prototype.empty_tag_state = function(buffer) {
	var c = buffer.char();
	if(c == ">") {
		this.current_token["type"] = "EmptyTag";
		this.emit_current_token();
	} else {
		// XXX parse error
		buffer.queue.insert(0, c);
		this.state = "tag_attribute_name_before_state";
	}
	return true;
}

t.prototype.tag_attribute_name_before_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		buffer.matchUntil(XML5.SPACE_CHARACTERS_IN /*, true */);
	} else if(c == ">") {
		this.emit_current_token();
	} else if(c == "/") {
		this.state = "empty_tag_state";
	} else if(c == ":") {
		// XXX parse error
		pass;
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else {
		this.current_token["attributes"].push([c, ""]);
		this.state = "tag_attribute_name_state";
	}
	return true;
}

t.prototype.tag_attribute_name_state = function(buffer) {
	var c = buffer.char();
	var leavingThisState = true;
	if(c == "=") {
		this.state = "tag_attribute_value_before_state";
	} else if(c == ">") {
		// Token is emitted after attributes are checked.
		pass;
	} else if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "tag_attribute_name_after_state";
	} else if(c == "/") {
		this.state = "empty_tag_state";
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
		leavingThisState = false;
	} else {
		this.current_token["attributes"].last()[0] += c;
		leavingThisState = false;
	}
	if(leavingThisState) {
		// Attributes are not dropped at this stage. That happens when the
		// start tag token is emitted so values can still be safely appended
		// to attributes, but we do want to report the parse error in time.
		for(name, value in this.current_token["attributes"].slice(0,-1)) {
			if(this.current_token["attributes"].last()[0] == name) {
				// XXX parse error
				pass;
			}
		}
		if(c == ">") {
			this.emit_current_token();
		}
	}
	return true;
}

t.prototype.tag_attribute_name_after_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		buffer.matchUntil(XML5.SPACE_CHARACTERS_IN /*, true */);
	} else if(c == "=") {
		this.state = "tag_attribute_value_before_state";
	} else if(c == ">") {
		this.emit_current_token();
	} else if(c == "/") {
		this.state = "empty_tag_state";
	} else if(c == ":") {
		// XXX parse error
		pass;
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else {
		this.current_token["attributes"].push([c, ""]);
		this.state = "tag_attribute_name_state";
	}
	return true;
}

t.prototype.tag_attribute_value_before_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		buffer.matchUntil(XML5.SPACE_CHARACTERS_IN /*, true */);
	} else if(c == "\"") {
		this.state = "tag_attribute_value_double_quoted_state";
	} else if(c == "'") {
		this.state = "tag_attribute_value_single_quoted_state";
	} else if(c == "&") {
		buffer.unget(c);;
		this.state = "tag_attribute_value_unquoted_state";
	} else if(c == ">") {
		this.emit_current_token();
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else {
		this.current_token["attributes"].last()[1] += c;
		this.state = "tag_attribute_value_unquoted_state";
	}
	return true;
}

t.prototype.tag_attribute_value_double_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "\"") {
		this.state = "tag_attribute_name_before_state";
	} else if(c == "&") {
		var entity = this.consume_entity(buffer);
		if(entity) {
			this.current_token["attributes"].last()[1] += entity;
		} else {
			buffer.unget(entity);
		}
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else {
		this.current_token["attributes"].last()[1] += c +
		  buffer.matchUntil("[\\, ]");
	}
	return true;
}

t.prototype.tag_attribute_value_single_quoted_state = function(buffer) {
	var c = buffer.char();
	if(c == "'") {
		this.state = "tag_attribute_name_before_state";
	} else if(c == "&") {
		var entity = this.consume_entity(buffer);
		if(entity) {
			this.current_token["attributes"].last()[1] += entity;
		} else {
			buffer.unget(entity);
		}
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else {
		this.current_token["attributes"].last()[1] += c +
		  buffer.matchUntil("['&]");
	}
	return true;
}

t.prototype.tag_attribute_value_unquoted_state = function(buffer) {
	var c = buffer.char();
	if(XML5.SPACE_CHARACTERS_R.test(c)) {
		this.state = "tag_attribute_name_before_state";
	} else if(c == "&") {
		var entity = this.consume_entity(buffer);
		if(entity) {
			this.current_token["attributes"].last()[1] += entity;
		} else {
			buffer.unget(entity);
		}
	} else if(c == ">") {
		this.emit_current_token();
	} else if(c == XML5.EOF) {
		// XXX parse error
		this.emit_current_token();
	} else {
		this.current_token["attributes"].last()[1] += c +
		  buffer.matchUntil("[" + "&><" + XML5.SPACE_CHARACTERS_IN + "]");
	}
	return true;
}

// Consume everything up and including > and make it a comment.
t.prototype.bogus_comment_state = function(buffer) {
	this.emitToken({type: "Comment", data: buffer.matchUntil(">")});
	buffer.char();
	this.state = "data_state";
	return true;
}

t.prototype.parse_error = function(message) {
	this.emitToken({type: 'ParseError', data: message});
}

t.prototype.emit_current_token = function() {
	var tok = this.current_token;
	switch(tok.type) {
	case 'StartTag':
	case 'EndTag':
	case 'EmptyTag':
		if(tok.type == 'EndTag' && tok.self_closing) {
			this.parse_error('self-closing-end-tag');
		}
		break;
	}
	this.emitToken(tok);
	this.state = 'data_state';
}
