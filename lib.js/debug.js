var XML5 = require('./index.js');

var sys = require('sys');

var debugFlags = {any: true}

XML5.debug = function() {
	section = arguments[0];
	if(debugFlags[section] || debugFlags[section.split('.')[0]]) {
		var str = [];
		for(var i in arguments) {
			str.push(sys.inspect(arguments[i]))
		}
		sys.debug(str.join(' '))
	}
}

XML5.enableDebug = function(section) {
	debugFlags[section] = true;
}

XML5.disableDebug = function(section) {
	debugFlags[section] = false;
}

XML5.dumpTagStack = function(tags) {
	var r = [];
	for(i in tags) {
		r.push(tags[i].tagName);
	}
	return r.join(', ');
}
