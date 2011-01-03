require 'iconv'
require 'constants'

class XMLInputStream
  attr_reader :queue

  def initialize(source, tokenizer, encoding=nil)
    """XMLInputStream(source, tokenizer, [encoding])

    source can be either a file-object, local filename or a string.
    """

    # List of where new lines occur
    @newLines = []

    # Need a reference to the tokenizer object to deal with the madness
    # that is XML entities
    @tokenizer = tokenizer

    # The octet stream
    @rawStream = openStream(source)

    @defaultEncoding = "UTF-8"

    # Detect encoding if no explicit "transport level" encoding is
    # supplied
    if not encoding
      encoding = detectEncoding()
    end
    @charEncoding = encoding

    # The Unicode string
    uString = @rawStream.read()
    if uString.respond_to? :force_encoding
      uString.force_encoding(@charEncoding)
    elsif @charEncoding.downcase != 'utf-8'
      uString = Iconv.conv('utf-8', @charEncoding, uString)
    end

    # Normalize newlines and null characters
    uString.gsub! /\r\n?/, "\n"
    uString.gsub! /\x00/, "\xef\xbf\xbd" # U+FFFD

    # Convert the unicode string into a list to be used as the data stream
    require 'generator'
    @dataStream = Generator.new(uString.chars)
    def @dataStream.reset; end

    @queue = []

    # Reset position in the list to read from
    reset()
  end

  def openStream(source)
    """Produces a file object from source. source can be either a file
    object, local filename or a string.
    """

    # Already a file object
    if source.respond_to? :read
      stream = source
    else
      # Otherwise treat source as a string and convert to a file object
      require 'stringio'
      stream = StringIO.new(source.to_s)
    end
    return stream
  end

  def detectEncoding
    # XXX This doesn't cover <?xml encoding=""?>
    encoding = detectBOM()
    if encoding == nil
      encoding = @defaultEncoding
    end
    return encoding
  end

  def detectBOM
    """Attempts to detect at BOM at the start of the stream. If
    an encoding can be determined from the BOM return the name of the
    encoding otherwise return nil"""

    bomDict = {
      "\xef\xbb\xbf" => 'utf-8',
      "\xff\xfe" => 'utf-16-le',
      "\xfe\xff" => 'utf-16-be',
      "\xff\xfe\x00\x00" => 'utf-32-le',
      "\x00\x00\xfe\xff" => 'utf-32-be'
    }

    # Go to beginning of file and read in 4 bytes
    @rawStream.seek(0)
    string = @rawStream.read(4)

    # Try detecting the BOM using bytes from the string
    encoding = bomDict[string[0..2]]       # UTF-8
    seek = 3
    if not encoding
      encoding = bomDict[string[0..1]]   # UTF-16
      seek = 2
      if not encoding
        encoding = bomDict[string]   # UTF-32
        seek = 4
      end
    end

    # Set the read position past the BOM if one was found, otherwise
    # set it to the start of the stream
    @rawStream.seek(encoding ? seek : 0)

    return encoding
  end

  def determineNewLines
    # Looks through the stream to find where new lines occur so
    # the position method can tell where it is.
    @newLines.append(0)
    for i in xrange(len(@dataStream))
      if @dataStream[i] == "\n"
        @newLines.append(i)
      end
    end
  end

  def position
    """Returns (line, col) of the current position in the stream."""
    # Generate list of new lines first time around
    if not @newLines
      determineNewLines()
    end

    line = 0
    tell = @tell
    for pos in @newLines
      if pos < tell
        line += 1
      else
        break
      end
    end
    col = tell - @newLines[line-1] - 1
    return [line, col]
  end

  def reset
    """Resets the position in the stream back to the start."""
    @tell = 0
  end

  def char
    """Read one character from the stream or queue if available. Return
    EOF when EOF is reached.
    """
    if @tokenizer.entityCount > 0
      @tokenizer.charCount += 1
      if @tokenizer.charCount > @tokenizer.entityValueLen
        @tokenizer.entityValueLen = 0
        @tokenizer.charCount = 0
        @tokenizer.entityCount = 0
      end
    end

    unless @queue.empty?
      return @queue.shift
    else
      begin
        @tell += 1
        return @dataStream.next
      rescue
        return EOF
      end
    end
  end

  def charsUntil(characters, opposite=false)
    """Returns a string of characters from the stream up to but not
    including any character in characters or EOF. characters can be any
    container that supports the in method being called on it.
    """
    charStack = [char()]

    # First from the queue
    while charStack[-1] and (characters.include? charStack[-1]) == opposite \
      and not @queue.empty?
      charStack << @queue.shift
    end

    # Then the rest
    while charStack[-1] and (characters.include? charStack[-1]) == opposite
      begin
        @tell += 1
        charStack << @dataStream.next
      rescue
        charStack << EOF
      end
    end

    # Put the character stopped on back to the front of the queue
    # from where it came.
    @queue.insert(0, charStack.pop())
    return charStack.join('')
  end
end
