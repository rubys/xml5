require 'constants'
require 'inputstream'

class XMLTokenizer
  attr_accessor :charCount
  attr_accessor :entityCount
  attr_accessor :entityValueLen

  def initialize(stream, encoding=nil)
    # The stream holds all the characters.
    @stream = XMLInputStream.new(stream, self, encoding)

    # Set of states and the initial state
    @states = {
      "data" => :dataState,
      "tag" => :tagState,
      "endTag" => :endTagState,
      "endTagName" => :endTagNameState,
      "endTagNameAfter" => :endTagNameAfterState,
      "pi" => :piState,
      "piTarget" => :piTargetState,
      "piTargetAfter" => :piTargetAfterState,
      "piContent" => :piContentState,
      "piAfter" => :piAfterState,
      "markupDeclaration" => :markupDeclarationState,
      "comment" => :commentState,
      "commentDash" => :commentDashState,
      "commentEnd" => :commentEndState,
      "cdata" => :cdataState,
      "cdataBracket" => :cdataBracketState,
      "cdataEnd" => :cdataEndState,
      "doctype" => :doctypeState,
      "doctypeRootNameBefore" => :doctypeRootNameBeforeState,
      "doctypeRootName" => :doctypeRootNameState,
      "doctypeRootNameAfter" => :doctypeRootNameAfterState,
      "doctypeIdentifierDoubleQuoted" => :doctypeIdentifierDoubleQuotedState,
      "doctypeIdentifierSingleQuoted" => :doctypeIdentifierSingleQuotedState,
      "doctypeInternalSubset" => :doctypeInternalSubsetState,
      "doctypeInternalSubsetAfter" => :doctypeInternalSubsetAfterState,
      "doctypeTag" => :doctypeTagState,
      "doctypeMarkupDeclaration" => :doctypeMarkupDeclarationState,
      "doctypeComment" => :doctypeCommentState,
      "doctypeCommentDash" => :doctypeCommentDashState,
      "doctypeCommentEnd" => :doctypeCommentEndState,
      "doctypeEntity" => :doctypeEntityState,
      "doctypeEntityTypeBefore" => :doctypeEntityTypeBeforeState,
      "doctypeEntityParameterBefore" => :doctypeEntityParameterBeforeState,
      "doctypeEntityParameter" => :doctypeEntityParameterState,
      "doctypeEntityName" => :doctypeEntityNameState,
      "doctypeEntityNameAfter" => :doctypeEntityNameAfterState,
      "doctypeEntityValDoubleQuoted" => :doctypeEntityValDoubleQuotedState,
      "doctypeEntityValSingleQuoted" => :doctypeEntityValSingleQuotedState,
      "doctypeEntityValAfter" => :doctypeEntityValAfterState,
      "doctypeEntityIdentifier" => :doctypeEntityIdentifierState,
      "doctypeEntityIdentifierDoubleQuoted" => :doctypeEntityIdentifierDoubleQuotedState,
      "doctypeEntityIdentifierSingleQuoted" => :doctypeEntityIdentifierSingleQuotedState,
      "doctypeAttlist" => :doctypeAttlistState,
      "doctypeAttlistNameBefore" => :doctypeAttlistNameBeforeState,
      "doctypeAttlistName" => :doctypeAttlistNameState,
      "doctypeAttlistNameAfter" => :doctypeAttlistNameAfterState,
      "doctypeAttlistAttrname" => :doctypeAttlistAttrnameState,
      "doctypeAttlistAttrnameAfter" => :doctypeAttlistAttrnameAfterState,
      "doctypeAttlistAttrtype" => :doctypeAttlistAttrtypeState,
      "doctypeAttlistAttrtypeAfter" => :doctypeAttlistAttrtypeAfterState,
      "doctypeAttlistAttrdeclBefore" => :doctypeAttlistAttrdeclBeforeState,
      "doctypeAttlistAttrdecl" => :doctypeAttlistAttrdeclState,
      "doctypeAttlistAttrdeclAfter" => :doctypeAttlistAttrdeclAfterState,
      "doctypeAttlistAttrvalDoubleQuoted" => :doctypeAttlistAttrvalDoubleQuotedState,
      "doctypeAttlistAttrvalSingleQuoted" => :doctypeAttlistAttrvalSingleQuotedState,
      "doctypeNotation" => :doctypeNotationState,
      "doctypeNotationIdentifier" => :doctypeNotationIdentifierState,
      "doctypeNotationIdentifierDoubleQuoted" => :doctypeNotationIdentifierDoubleQuotedState,
      "doctypeNotationIdentifierSingleQuoted" => :doctypeNotationIdentifierSingleQuotedState,
      "doctypePi" => :doctypePiState,
      "doctypePiAfter" => :doctypePiAfterState,
      "doctypeBogusComment" => :doctypeBogusCommentState,
      "tagName" => :tagNameState,
      "emptyTag" => :emptyTagState,
      "tagAttributeNameBefore" => :tagAttributeNameBeforeState,
      "tagAttributeName" => :tagAttributeNameState,
      "tagAttributeNameAfter" => :tagAttributeNameAfterState,
      "tagAttributeValueBefore" => :tagAttributeValueBeforeState,
      "tagAttributeValueDoubleQuoted" => :tagAttributeValueDoubleQuotedState,
      "tagAttributeValueSingleQuoted" => :tagAttributeValueSingleQuotedState,
      "tagAttributeValueUnquoted" => :tagAttributeValueUnquotedState,
      "bogusComment" => :bogusCommentState
    }
    @state = @states["data"]

    # The current token being created
    @currentToken = nil

    # Entities
    @entities = {
      "lt" => "&#60;",
      "gt" => ">",
      "amp" => "&#38;",
      "apos" => "'",
      "quot" => "\""
    }
    @parameterEntities = {}
    @attributeNormalization = []

    # Dealing with entities
    @entityValueLen = 0
    @charCount = 0
    @entityCount = 0

    # Tokens yet to be processed.
    @tokenQueue = []
  end

  def each
    @stream.reset()
    @tokenQueue = []

    # Start processing. When EOF is reached state will return false
    # instead of true and the loop will terminate.
    while send @state
      until @tokenQueue.empty?
        yield @tokenQueue.shift
      end
    end
  end

  def consumeNumberEntity(isHex)
    allowed = Digits
    radix = 10
    if isHex
      allowed = HexDigits
      radix = 16
    end

    char = "\xef\xbf\xbd" # U+FFFD

    # Consume all the characters that are in range while making sure we
    # don't hit an EOF.
    value = @stream.charsUntil(allowed, true)

    # Convert the set of characters consumed to an int.
    charAsInt = value.to_i(radix)

    # No NULL characters.
    # XXX any other characters?
    if charAsInt == 0
      charAsInt = 65533
    end

    # Convert the int value to an actual char
    begin
      char = [charAsInt].pack('U')
    rescue
      # XXX parse error
      # pass
    end

    # Discard the ; if present. Otherwise, put it back on the queue and
    # invoke parseError on parser.
    c = @stream.char()
    if c != ";"
      # XXX parse error
      @stream.queue << c
    end
    return char
  end

  def consumeEntity(fromAttribute=false)
    # The result of this function is a tuple consisting of the entity
    # value and whether it needs to be inserted into the stream or
    # simply appended as character data.
    c = @stream.char()
    if c == "#"
      # Character reference (numeric entity).
      value = "&#"
      c = @stream.char()
      if c == "x"
        c = @stream.char()
        if HexDigits.include? c
          # Hexadecimal entity detected.
          @stream.queue.insert(0, c)
          value = consumeNumberEntity(true)
        else
          value += "x"
        end
      elsif Digits.include? c
        # Decimal entity detected.
        @stream.queue.insert(0, c)
        value = consumeNumberEntity(false)
      elsif c == EOF
        # XXX parse error
        # pass
      else
        # XXX parse error
        value += c
      end
      return "Characters", value
    # Break out if we reach the end of the file
    elsif c == EOF
      # XXX parse error
      return "Characters", "&"
    else
      # Named entity.
      _end = ";"
      name = c + @stream.charsUntil(";")

      # Check whether or not the last character returned can be
      # discarded or needs to be put back.
      c = @stream.char()
      if c != ";"
        # XXX parse error
        _end = ""
      end

      if @entities.include? name
        if @entityCount < 16
          @entityCount += 1
          value = @entities[name]
          if fromAttribute
            # This is a hack to make things "work". Or is it
            # really the only good solution?
            value.gsub!("\n", "&#10;")
            value.gsub!("\r", "&#10;")
            value.gsub!("\t", "&#9;")
            value.gsub!(" ", "&#32;")
            value.gsub!("\"", "&#34;")
            value.gsub!("'", "&#39;")
          end
          @entityValueLen += value.length
          return "Stream", value
        else
          # XXX parse error
          return "Characters", ""
        end
      else
        # XXX parse error
        return "Characters", "&" + name + _end
      end
    end
    assert 0
  end

  def consumeNumberEntityOnly
    c = @stream.char()
    value = "&"
    if c == EOF
      @stream.queue.insert(0, c)
    elsif c != "#"
      value += c
    else
      value += "#"
      c = @stream.char()
      if c == "x"
        c = @stream.char()
        if HexDigits.include? c
          # Hexadecimal entity detected.
          @stream.queue.unshift c
          value = consumeNumberEntity(true)
        else
          value += "x"
        end
      elsif Digits.include? c
        # Decimal entity detected.
        @stream.queue.insert(0, c)
        value = consumeNumberEntity(false)
      elsif c == EOF
        # XXX parse error
        # pass
      else
        # XXX parse error
        value += c
      end
    end
    return value
  end

  def consumeParameterEntity
    name = @stream.charsUntil(";")
    c = @stream.char()
    if c != ";"
      # XXX parse error
      # pass
    end

    if @parameterEntities.include?(name) and @entityCount < 16
      @entityCount += 1
      value = @parameterEntities[name]
      @entityValueLen += value.length
      return value
    else
      # XXX parse error
      return ""
    end
  end

  def attributeNameExists(name)
    for x,y in @currentToken["attributes"]
      if x == name
        return true
      end
    end
    return false
  end

  def emitCurrentToken
    if (@currentToken["type"] == "StartTag" or
      @currentToken["type"] == "EmptyTag") and\
      @attributeNormalization
      for token in @attributeNormalization
        if token["name"] == @currentToken["name"]
          for attr in token["attrs"]
            if attr["dv"] != "" and not attributeNameExists(attr["name"])
              @currentToken["attributes"] << [attr["name"], attr["dv"]]
            end
          end
        end
      end
    end
    @tokenQueue << @currentToken
    @state = @states["data"]
  end

  def appendEntity
    assert @currentToken
    name = @currentToken["name"]
    value = @currentToken["value"]
    type = @currentToken["type"]
    if type == "entity"
      if not @entities.include? name
        @entities[name] = value
      end
    elsif type == "parameterEntity"
      if not @parameterEntities.include? name
        @parameterEntities[name] = value
      end
    else
      assert 0
    end
    @state = @states["doctypeInternalSubset"]
  end

  # Below are the various tokenizer states worked out.

  def dataState
    data = @stream.char()
    if data == "&"
      entity = consumeEntity()
      if entity[0] == "Characters"
        @tokenQueue << {"type" => "Characters", "data" => entity[1]}
      else
        entity[1].each_char.each_with_index do |x, i|
          @stream.queue.insert(i, x)
        end
      end
    elsif data == "<"
      @state = @states["tag"]
    elsif data == EOF
      # Tokenization ends.
      return false
    else
      @tokenQueue << {"type" => "Characters", "data" => data}
    end
    return true
  end

  def tagState
    data = @stream.char()
    if data == "/"
      @state = @states["endTag"]
    elsif data == "?"
      @state = @states["pi"]
    elsif data == "!"
      @state = @states["markupDeclaration"]
    elsif SpaceCharacters.include?(data)\
      or data == "<"\
      or data == ">"\
      or data == ":"\
      or data == EOF
      # XXX parse error
      @tokenQueue.append({"type" => "Characters", "data" => "<"})
      @stream.queue.insert(0, data)
      @state = @states["data"]
    else
      @currentToken = {"type" => "StartTag", "name" => data,
        "attributes" => []}
      @state = @states["tagName"]
    end
    return true
  end

  def endTagState
    data = @stream.char()
    if data == ">"
      @tokenQueue << {"type" => "EndTagShort"}
      @state = @states["data"]
    elsif SpaceCharacters.include? data\
      or data == "<"\
      or data == ":"\
      or data == EOF
      # XXX parse error
      # XXX catch more "incorrect" characters here?
      @tokenQueue << {"type" => "Characters", "data" => "</"}
      @stream.queue.insert(0, data)
      @state = @states["data"]
    else
      @currentToken = {"type" => "EndTag", "name" => data}
      @state = @states["endTagName"]
    end
    return true
  end

  def endTagNameState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["endTagNameAfter"]
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    elsif data == ">"
      emitCurrentToken()
    else
      @currentToken["name"] += data
    end
    return true
  end

  def endTagNameAfterState
    data = @stream.char()
    if data == ">"
      emitCurrentToken()
    elsif SpaceCharacters.include? data
      # pass
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    else
      # XXX parse error
      # pass
    end
    return true
  end

  def piState
    data = @stream.char()
    if SpaceCharacters.include?(data) or data == EOF
      # XXX parse error
      # XXX catch more "incorrect" characters here?
      @stream.queue.append("?")
      @stream.queue.append(data)
      @state = @states["bogusComment"]
    else
      @currentToken = {"type" => "Pi", "name" => data, "data" => ""}
      @state = @states["piTarget"]
    end
    return true
  end

  def piTargetState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["piTargetAfter"]
    elsif data == EOF
      # XXX parse error
      # XXX catch more "incorrect" characters here?
      emitCurrentToken()
    elsif data == "?"
      @state = @states["piAfter"]
    else
      @currentToken["name"] += data
    end
    return true
  end

  def piTargetAfterState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    else
      @stream.queue.append(data)
      @state = @states["piContent"]
    end
    return true
  end

  def piContentState
    data = @stream.char()
    if data == "?"
      @state = @states["piAfter"]
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    else
      @currentToken["data"] += data
    end
    return true
  end

  def piAfterState
    data = @stream.char()
    if data == ">"
      emitCurrentToken()
    elsif data == "?"
      @currentToken["data"] += "?"
    else
      @stream.queue.append(data)
      @state = @states["piContent"]
    end
    return true
  end

  # Markup declarations.
  def markupDeclarationState
    charStack = [@stream.char(), @stream.char()]
    if charStack == ["-", "-"]
      @currentToken = {"type" => "Comment", "data" => ""}
      @state = @states["comment"]
    else
      5.times do
        charStack << @stream.char()
      end
      if not charStack.include? EOF
        n = charStack.join('')
        if n == "[CDATA["
          @state = @states["cdata"]
          return true
        end
        if n == "DOCTYPE"
          # XXX parse error
          @state = @states["doctype"]
          return true
        end
      end
      # XXX parse error
      @stream.queue.concat(charStack)
      @state = @states["bogusComment"]
    end
    return true
  end

  # Handling of comments. They end after a literal '-->' sequence.
  def commentState
    data = @stream.char()
    if data == "-"
      @state = @states["commentDash"]
    elsif data == EOF
      # XXX parse error
      @tokenQueue.append(@currentToken)
      @state = @states["data"]
    else
      @currentToken["data"] += data + @stream.charsUntil("-")
    end
    return true
  end

  def commentDashState
    data = @stream.char()
    if data == "-"
      @state = @states["commentEnd"]
    elsif data == EOF
      # XXX parse error
      @tokenQueue.append(@currentToken)
      @state = @states["data"]
    else
      @currentToken["data"] += "-" + data +\
        @stream.charsUntil("-")
      # Consume the next character which is either a "-" or an EOF as
      # well so if there's a "-" directly after the "-" we go nicely to
      # the "comment end state" without emitting a ParseError() there.
      @stream.char()
    end
    return true
  end

  def commentEndState
    data = @stream.char()
    if data == ">"
      @tokenQueue.append(@currentToken)
      @state = @states["data"]
    elsif data == "-"
      @currentToken["data"] += "-"
    elsif data == EOF
      # XXX parse error
      @tokenQueue.append(@currentToken)
      @state = @states["data"]
    else
      @currentToken["data"] += "--" + data
      @state = @states["comment"]
    end
    return true
  end

  # These states handle the last bit of <![CDATA[ foo ]]> blocks.
  def cdataState
    data = @stream.char()
    if data == "]"
      @state = @states["cdataBracket"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @tokenQueue.append({"type" => "Characters", "data" =>
        data + @stream.charsUntil("]")})
    end
    return true
  end

  def cdataBracketState
    data = @stream.char()
    if data == "]"
      @state = @states["cdataEnd"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @tokenQueue.append({"type" => "Characters", "data" =>
        "]" + data + @stream.charsUntil("]")})
      # Consume the next character which is either a "]" or an EOF as
      # well so if there's a "]" directly after the "]" we go nicely to
      # the "cdata end state" without emitting a ParseError() there.
      @stream.char()
    end
    return true
  end

  def cdataEndState
    data = @stream.char()
    if data == ">"
      @state = @states["data"]
    elsif data == "]"
      @tokenQueue.append({"type" => "Characters", "data" => data})
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @tokenQueue.append({"type" => "Characters", "data" => "]]" + data})
      @state = @states["cdata"]
    end
    return true
  end

  # XXX should we emit doctype tokens and such?
  def doctypeState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeRootNameBefore"]
    elsif data == EOF
      # XXX parse error?
      @state = @states["data"]
    else
      @stream.queue.append(data)
      @state = @states["bogusComment"]
    end
    return true
  end

  def doctypeRootNameBeforeState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == ">"
      @state = @states["data"]
    elsif data == EOF
      # XXX parse error?
      @state = @states["data"]
    else
      @state= @states["doctypeRootName"]
    end
    return true
  end

  def doctypeRootNameState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeRootNameAfter"]
    elsif data == ">"
      @state = @states["data"]
    elsif data == "["
      @state = @states["doctypeInternalSubset"]
    elsif data == EOF
      # XXX parse error?
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeRootNameAfterState
    data = @stream.char()
    if data == ">"
      @state = @states["data"]
    elsif data == "\""
      @state = @states["doctypeIdentifierDoubleQuoted"]
    elsif data == "'"
      @state = @states["doctypeIdentifierSingleQuoted"]
    elsif data == "["
      @state = @states["doctypeInternalSubset"]
    elsif data == EOF
      # XXX parse error?
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeIdentifierDoubleQuotedState
    data = @stream.char()
    if data == "\""
      @state = @states["doctypeRootNameAfter"]
    elsif data == EOF
      # XXX parse error?
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeIdentifierSingleQuotedState
    data = @stream.char()
    if data == "'"
      @state = @states["doctypeRootNameAfter"]
    elsif data == EOF
      # XXX parse error?
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeInternalSubsetState
    data = @stream.char()
    if data == "<"
      @state = @states["doctypeTag"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    elsif data == "%"
      consumeParameterEntity().each_char do |c|
        @stream.queue << c
      end
    elsif data == "]"
      @state = @states["doctypeInternalSubsetAfter"]
    else
      # pass
    end
    return true
  end

  def doctypeInternalSubsetAfterState
    data = @stream.char()
    if data == ">"
      @state = @states["data"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeTagState
    data = @stream.char()
    if data == "!"
      @state = @states["doctypeMarkupDeclaration"]
    elsif data == "?"
      @state = @states["doctypePi"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeBogusComment"]
    end
    return true
  end

  def doctypeMarkupDeclarationState
    charStack = [@stream.char(), @stream.char()]
    if charStack == ["-", "-"]
      @state = @states["doctypeComment"]
    else
      4.times do
        charStack << @stream.char()
      end
      if not charStack.include? EOF
        if charStack.join('') == "ENTITY"
          @state = @states["doctypeEntity"]
          return true
        end
        data = @stream.char()
        charStack << data
        if data != EOF
          if charStack.join('') == "ATTLIST"
            @state = @states["doctypeAttlist"]
            return true
          end
          data = @stream.char()
          charStack.append(data)
          if data != EOF
            if charStack.join('') == "NOTATION"
              @state = @states["doctypeNotation"]
              return true
            end
          end
        end
      end
      # XXX parse error
      @stream.queue += charStack
      @state = @states["doctypeBogusComment"]
    end
    return true
  end

  # <!-- ....
  def doctypeCommentState
    data = @stream.char()
    if data == "-"
      @state = @states["doctypeCommentDash"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeCommentDashState
    data = @stream.char()
    if data == "-"
      @state = @states["doctypeCommentEnd"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeComment"]
    end
    return true
  end

  def doctypeCommentEndState
    data = @stream.char()
    if data == ">"
      @state = @states["doctypeInternalSubset"]
    elsif data == "-"
      @state = @states["doctypeCommentDash"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeComment"]
    end
    return true
  end

  # <!ENTITY
  def doctypeEntityState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeEntityTypeBefore"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeBogusComment"]
    end
    return true
  end

  def doctypeEntityTypeBeforeState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == "%"
      @state = @states["doctypeEntityParameterBefore"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @currentToken = {"type" => "entity", "name" => data, "value" => ""}
      @state = @states["doctypeEntityName"]
    end
    return true
  end

  def doctypeEntityParameterBeforeState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeEntityParameter"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeBogusComment"]
    end
    return true
  end

  def doctypeEntityParameterState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @currentToken = {"type" => "parameterEntity", "name" => data,
        "value" => ""}
      @state = @states["doctypeEntityName"]
    end
    return true
  end

  def doctypeEntityNameState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeEntityNameAfter"]
    elsif data == EOF
      # XXX parse error
      @currentToken = nil
      @state = @states["data"]
    else
      @currentToken["name"] += data
    end
    return true
  end

  def doctypeEntityNameAfterState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == "\""
      @state = @states["doctypeEntityValDoubleQuoted"]
    elsif data == "'"
      @state = @states["doctypeEntityValSingleQuoted"]
    elsif data == EOF
      # XXX parse error
      @currentToken == nil
      @state = @states["data"]
    else
      @state = @states["doctypeEntityIdentifier"]
    end
    return true
  end

  def doctypeEntityValDoubleQuotedState
    data = @stream.char()
    # XXX "&" and "%"
    if data == "\""
      @state = @states["doctypeEntityValAfter"]
    elsif data == "&"
      @currentToken["value"] += consumeNumberEntityOnly()
    elsif data == EOF
      # XXX parse error
      @currentToken == nil
      @state = @states["data"]
    else
      @currentToken["value"] += data
    end
    return true
  end

  def doctypeEntityValSingleQuotedState
    data = @stream.char()
    # XXX "&" and "%"
    if data == "'"
      @state = @states["doctypeEntityValAfter"]
    elsif data == "&"
      @currentToken["value"] += consumeNumberEntityOnly()
    elsif data == EOF
      # XXX parse error
      @currentToken == nil
      @state = @states["data"]
    else
      @currentToken["value"] += data
    end
    return true
  end

  def doctypeEntityValAfterState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == ">"
      appendEntity()
    elsif data == EOF
      # XXX parse error
      @currentToken == nil
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeEntityIdentifierState
    data = @stream.char()
    if data == ">"
      appendEntity()
    elsif data == "\""
      @state = @states["doctypeEntityIdentifierDoubleQuoted"]
    elsif data == "'"
      @state = @states["doctypeEntityIdentifierSingleQuoted"]
    elsif data == EOF
      # XXX parse error
      @currentToken = nil
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeEntityIdentifierDoubleQuotedState
    data = @stream.char()
    if data == "\""
      @state = @states["doctypeEntityIdentifier"]
    elsif data == EOF
      # XXX parse error
      @currentToken = nil
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeEntityIdentifierSingleQuotedState
    data = @stream.char()
    if data == "'"
      @state = @states["doctypeEntityIdentifier"]
    elsif data == EOF
      # XXX parse error
      @currentToken = nil
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeAttlistState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeAttlistNameBefore"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeBogusComment"]
    end
    return true
  end

  def doctypeAttlistNameBeforeState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @attributeNormalization << {"name" => data, "attrs" => []}
      @state = @states["doctypeAttlistName"]
    end
    return true
  end

  def doctypeAttlistNameState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeAttlistNameAfter"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @attributeNormalization[-1]["name"] += data
    end
    return true
  end

  def doctypeAttlistNameAfterState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == ">"
      @state = @states["doctypeInternalSubset"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @attributeNormalization[-1]["attrs"]<< {"name" => data,
        "type" => "", "dv" => ""}
      @state = @states["doctypeAttlistAttrname"]
    end
    return true
  end

  def doctypeAttlistAttrnameState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeAttlistAttrnameAfter"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @attributeNormalization[-1]["attrs"][-1]["name"] += data
    end
    return true
  end

  def doctypeAttlistAttrnameAfterState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @attributeNormalization[-1]["attrs"][-1]["type"] += data
      @state = @states["doctypeAttlistAttrtype"]
    end
    return true
  end

  def doctypeAttlistAttrtypeState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeAttlistAttrtypeAfter"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @attributeNormalization[-1]["attrs"][-1]["type"] += data
    end
    return true
  end

  def doctypeAttlistAttrtypeAfterState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == "#"
      @state = @states["doctypeAttlistAttrdeclBefore"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeBogusComment"]
    end
    return true
  end

  def doctypeAttlistAttrdeclBeforeState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeBogusComment"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeAttlistAttrdecl"]
    end
    return true
  end

  def doctypeAttlistAttrdeclState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeAttlistAttrdeclAfter"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeAttlistAttrdeclAfterState
    data = @stream.char()
    if SpaceCharacters.include? data
      # pass
    elsif data == ">"
      @state = @states["doctypeInternalSubset"]
    elsif data == "\""
      @state = @states["doctypeAttlistAttrvalDoubleQuoted"]
    elsif data == "'"
      @state = @states["doctypeAttlistAttrvalSingleQuoted"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @attributeNormalization[-1]["attrs"].append({"name" => data,
        "type" => "", "dv" => ""})
      @state = @states["doctypeAttlistAttrname"]
    end
    return true
  end

  def doctypeAttlistAttrvalDoubleQuotedState
    data = @stream.char()
    if data == "\""
      @state = @states["doctypeAttlistNameAfter"]
    elsif data == "%"
      raise NotSupportedError
    elsif data == "&"
      raise NotSupportedError
    else
      @attributeNormalization[-1]["attrs"][-1]["dv"] += data
    end
    return true
  end

  def doctypeAttlistAttrvalSingleQuotedState
    data = @stream.char()
    if data == "'"
      @state = @states["doctypeAttlistNameAfter"]
    elsif data == "%"
      raise NotSupportedError
    elsif data == "&"
      raise NotSupportedError
    else
      @attributeNormalization[-1]["attrs"][-1]["dv"] += data
    end
    return true
  end

  # <!NOTATION
  def doctypeNotationState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["doctypeNotationIdentifier"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypeBogusComment"]
    end
    return true
  end

  def doctypeNotationIdentifierState
    data = @stream.char()
    if data == ">"
      @state = @states["doctypeInternalSubset"]
    elsif data == "\""
      @state = @states["doctypeNotationIdentifierDoubleQuoted"]
    elsif data == "'"
      @state = @states["doctypeNotationIdentifierSingleQuoted"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeNotationIdentifierDoubleQuotedState
    data = @stream.char()
    if data == "\""
      @state = @states["doctypeNotationIdentifier"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypeNotationIdentifierSingleQuotedState
    data = @stream.char()
    if data == "'"
      @state = @states["doctypeNotationIdentifier"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypePiState
    data = @stream.char()
    if data == "?"
      @state = @states["doctypePiAfter"]
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      # pass
    end
    return true
  end

  def doctypePiAfterState
    data = @stream.char()
    if data == ">"
      @state = @states["doctypeInternalSubset"]
    elsif data == "?"
      # pass
    elsif data == EOF
      # XXX parse error
      @state = @states["data"]
    else
      @state = @states["doctypePiState"]
    end
    return true
  end

  # Bogus "comments" inside a doctype
  def doctypeBogusCommentState
    @stream.charsUntil(">")
    @stream.char()
    @state = @states["doctypeInternalSubset"]
    return true
  end

  # Tag name of a start or empty tag.
  def tagNameState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["tagAttributeNameBefore"]
    elsif data == ">"
      emitCurrentToken()
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    elsif data == "/"
      @state = @states["emptyTag"]
    else
      @currentToken["name"] += data
    end
    return true
  end

  def emptyTagState
    data = @stream.char()
    if data == ">"
      @currentToken["type"] = "EmptyTag"
      emitCurrentToken()
    else
      # XXX parse error
      @stream.queue.insert(0, data)
      @state = @states["tagAttributeNameBefore"]
    end
    return true
  end

  def tagAttributeNameBeforeState
    data = @stream.char()
    if SpaceCharacters.include? data
      @stream.charsUntil(SpaceCharacters, true)
    elsif data == ">"
      emitCurrentToken()
    elsif data == "/"
      @state = @states["emptyTag"]
    elsif data == ":"
      # XXX parse error
      # pass
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    else
      @currentToken["attributes"] << [data, ""]
      @state = @states["tagAttributeName"]
    end
    return true
  end

  def tagAttributeNameState
    data = @stream.char()
    leavingThisState = true
    if data == "="
      @state = @states["tagAttributeValueBefore"]
    elsif data == ">"
      # Token is emitted after attributes are checked.
      # pass
    elsif SpaceCharacters.include? data
      @state = @states["tagAttributeNameAfter"]
    elsif data == "/"
      @state = @states["emptyTag"]
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
      leavingThisState = false
    else
      @currentToken["attributes"][-1][0] += data
      leavingThisState = false
    end

    if leavingThisState
      # Attributes are not dropped at this stage. That happens when the
      # start tag token is emitted so values can still be safely appended
      # to attributes, but we do want to report the parse error in time.
      for name, value in @currentToken["attributes"][0..-2]
        if @currentToken["attributes"][-1][0] == name
          # XXX parse error
          # pass
        end
      end
      if data == ">"
        emitCurrentToken()
      end
    end
    return true
  end

  def tagAttributeNameAfterState
    data = @stream.char()
    if SpaceCharacters.include? data
      @stream.charsUntil(spaceCharacters, true)
    elsif data == "="
      @state = @states["tagAttributeValueBefore"]
    elsif data == ">"
      emitCurrentToken()
    elsif data == "/"
      @state = @states["emptyTag"]
    elsif data == ":"
      # XXX parse error
      # pass
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    else
      @currentToken["attributes"].append([data, ""])
      @state = @states["tagAttributeName"]
    end
    return true
  end

  def tagAttributeValueBeforeState
    data = @stream.char()
    if SpaceCharacters.include? data
      @stream.charsUntil(spaceCharacters, true)
    elsif data == "\""
      @state = @states["tagAttributeValueDoubleQuoted"]
    elsif data == "'"
      @state = @states["tagAttributeValueSingleQuoted"]
    elsif data == "&"
      @stream.queue << data
      @state = @states["tagAttributeValueUnquoted"]
    elsif data == ">"
      emitCurrentToken()
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    else
      @currentToken["attributes"][-1][1] += data
      @state = @states["tagAttributeValueUnquoted"]
    end
    return true
  end

  def tagAttributeValueDoubleQuotedState
    data = @stream.char()
    if data == "\""
      @state = @states["tagAttributeNameBefore"]
    elsif data == "&"
      entity = consumeEntity(true)
      if entity[0] == "Characters"
        @currentToken["attributes"][-1][1] += entity[1]
      else
        entity[1].each_char.each_with_index do |x, i|
          @stream.queue.insert(i, x)
        end
      end
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    else
      @currentToken["attributes"][-1][1] += data +\
        @stream.charsUntil(["\"", "&"])
    end
    return true
  end

  def tagAttributeValueSingleQuotedState
    data = @stream.char()
    if data == "'"
      @state = @states["tagAttributeNameBefore"]
    elsif data == "&"
      entity = consumeEntity(true)
      if entity[0] == "Characters"
        @currentToken["attributes"][-1][1] += entity[1]
      else
        entity[1].each_char.each_with_index do |x, i|
          @stream.queue.insert(i, x)
        end
      end
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    else
      @currentToken["attributes"][-1][1] += data +\
        @stream.charsUntil(["'", "&"])
    end
    return true
  end

  def tagAttributeValueUnquotedState
    data = @stream.char()
    if SpaceCharacters.include? data
      @state = @states["tagAttributeNameBefore"]
    elsif data == "&"
      entity = consumeEntity(true)
      if entity[0] == "Characters"
        @currentToken["attributes"][-1][1] += entity[1]
      else
        entity[1].each_char.each_with_index do |x, i|
          @stream.queue.insert(i, x)
        end
      end
    elsif data == ">"
      emitCurrentToken()
    elsif data == EOF
      # XXX parse error
      emitCurrentToken()
    else
      @currentToken["attributes"][-1][1] += data +\
        @stream.charsUntil(["&", ">","<"] | SpaceCharacters)
    end
    return true
  end

  # Consume everything up and including > and make it a comment.
  def bogusCommentState
    @tokenQueue << {"type"=> "Comment", "data"=> @stream.charsUntil(">")}
    @stream.char()
    @state = @states["data"]
    return true
  end

  def assert expression
    raise Exception.new('AssertionError') unless expression
  end
end
