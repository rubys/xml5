#!/usr/bin/env python
import codecs
import re
EOF = None

class XMLInputStream(object):
    def __init__(self, source, tokenizer, encoding=None):
        """XMLInputStream(source, tokenizer, [encoding])

        source can be either a file-object, local filename or a string.
        """

        # List of where new lines occur
        self.newLines = []
        
        # Need a reference to the tokenizer object to deal with the madness
        # that is XML entities
        self.tokenizer = tokenizer

        # The octet stream
        self.rawStream = self.openStream(source)

        self.defaultEncoding = "UTF-8"

        # Detect encoding if no explicit "transport level" encoding is
        # supplied
        if not encoding:
            encoding = self.detectEncoding()
        self.charEncoding = encoding

        # The Unicode string
        uString = self.rawStream.read().decode(self.charEncoding, 'replace')

        # Normalize newlines and null characters
        uString = re.sub('\r\n?', '\n', uString)
        uString = re.sub('\x00', u'\uFFFD', uString)

        # Convert the unicode string into a list to be used as the data stream
        self.dataStream = uString

        self.queue = []

        # Reset position in the list to read from
        self.reset()

    def openStream(self, source):
        """Produces a file object from source. source can be either a file
        object, local filename or a string.
        """

        # Already a file object
        if hasattr(source, 'read'):
            stream = source
        else:
            # Otherwise treat source as a string and convert to a file object
            import cStringIO
            stream = cStringIO.StringIO(str(source))
        return stream

    def detectEncoding(self):
        # XXX This doesn't cover <?xml encoding=""?>
        encoding = self.detectBOM()
        if encoding is None:
            encoding = self.defaultEncoding
        return encoding

    def detectBOM(self):
        """Attempts to detect at BOM at the start of the stream. If
        an encoding can be determined from the BOM return the name of the
        encoding otherwise return None"""

        bomDict = {
            codecs.BOM_UTF8: 'utf-8',
            codecs.BOM_UTF16_LE: 'utf-16-le', codecs.BOM_UTF16_BE: 'utf-16-be',
            codecs.BOM_UTF32_LE: 'utf-32-le', codecs.BOM_UTF32_BE: 'utf-32-be'
        }

        # Go to beginning of file and read in 4 bytes
        self.rawStream.seek(0)
        string = self.rawStream.read(4)

        # Try detecting the BOM using bytes from the string
        encoding = bomDict.get(string[:3])       # UTF-8
        seek = 3
        if not encoding:
            encoding = bomDict.get(string[:2])   # UTF-16
            seek = 2
            if not encoding:
                encoding = bomDict.get(string)   # UTF-32
                seek = 4

        # Set the read position past the BOM if one was found, otherwise
        # set it to the start of the stream
        self.rawStream.seek(encoding and seek or 0)

        return encoding

    def determineNewLines(self):
        # Looks through the stream to find where new lines occur so
        # the position method can tell where it is.
        self.newLines.append(0)
        for i in xrange(len(self.dataStream)):
            if self.dataStream[i] == u"\n":
                self.newLines.append(i)

    def position(self):
        """Returns (line, col) of the current position in the stream."""
        # Generate list of new lines first time around
        if not self.newLines:
            self.determineNewLines()

        line = 0
        tell = self.tell
        for pos in self.newLines:
            if pos < tell:
                line += 1
            else:
                break
        col = tell - self.newLines[line-1] - 1
        return (line, col)

    def reset(self):
        """Resets the position in the stream back to the start."""
        self.tell = 0

    def char(self):
        """Read one character from the stream or queue if available. Return
        EOF when EOF is reached.
        """
        if self.tokenizer.entityCount > 0:
            self.tokenizer.charCount += 1
            if self.tokenizer.charCount > self.tokenizer.entityValueLen:
                self.tokenizer.entityValueLen = 0
                self.tokenizer.charCount = 0
                self.tokenizer.entityCount = 0
        
        if self.queue:
            return self.queue.pop(0)
        else:
            try:
                self.tell += 1
                return self.dataStream[self.tell - 1]
            except:
                return EOF

    def charsUntil(self, characters, opposite=False):
        """Returns a string of characters from the stream up to but not
        including any character in characters or EOF. characters can be any
        container that supports the in method being called on it.
        """
        charStack = [self.char()]

        # First from the queue
        while charStack[-1] and (charStack[-1] in characters) == opposite \
          and self.queue:
            charStack.append(self.queue.pop(0))

        # Then the rest
        while charStack[-1] and (charStack[-1] in characters) == opposite:
            try:
                self.tell += 1
                charStack.append(self.dataStream[self.tell - 1])
            except:
                charStack.append(EOF)

        # Put the character stopped on back to the front of the queue
        # from where it came.
        self.queue.insert(0, charStack.pop())
        return "".join(charStack)
