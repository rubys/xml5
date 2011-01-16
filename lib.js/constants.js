var XML5 = require('./index.js');

XML5.SPACE_CHARACTERS_R = /^[\t\n\x0B\x0C \r]/;
XML5.EOF = '\u0000';
XML5.DIGITS = '0123456789';
XML5.DIGITS_R = new RegExp('^[0123456789]');
XML5.HEX_DIGITS = XML5.DIGITS + 'abcdefABCDEF';
XML5.HEX_DIGITS_R = new RegExp('^[' + XML5.DIGITS + 'abcdefABCDEF' +']' );
XML5.SPACE_CHARACTERS_IN = "\t\n\x0B\x0C\x20\u0012\r";

