require 'tokenizer'
require 'treebuilders'
require 'constants'

class XMLParser
  def initialize(tree=SimpleTree::TreeBuilder)
    @tree = tree.new()
    @errors = []

    @phases = {
      "start" => :startPhase,
      "main" => :mainPhase,
      "end" => :endPhase
    }
    @phase = @phases["start"]
  end

  def _parse(stream, encoding=nil)
    @tree.reset()
    @errors = []
    @tokenizer = XMLTokenizer.new(stream, encoding)

    @tokenizer.each do |token|
      send @phase, token
    end
    # When the loop finishes it's EOF
    # XXX
  end

  def parse(stream, encoding=nil)
    _parse(stream, encoding=encoding)
    return @tree.getDocument()
  end

  def containsWhiteSpace(string)
    string.each_char do |c|
      if SpaceCharacters.include? c
        return false
      end
    end
    return true
  end

  def startPhase(token)
    if token["type"] == "StartTag"
      element = @tree.createElement(token["name"], token["attributes"])
      @tree.document.appendChild(element)
      @tree.openElements << element
      @phase = @phases["main"]
    elsif token["type"] == "EmptyTag"
      element = @tree.createElement(token["name"], token["attributes"])
      @tree.document.appendChild(element)
      @phase = @phases["end"]
    elsif token["type"] == "Comment"
      @tree.document.appendChild(@tree.commentClass.new(token["data"]))
    elsif token["type"] == "Pi"
      @tree.document.appendChild(@tree.piClass(token["name"], token["data"]))
    elsif token["type"] == "Characters" and containsWhiteSpace(token["data"])
      # pass
    else
      # XXX parse error
      # pass
    end
  end

  def mainPhase(token)
    if token["type"] == "Characters"
      @tree.insertText(token["data"])
    elsif token["type"] == "StartTag"
      element = @tree.createElement(token["name"], token["attributes"])
      @tree.openElements[-1].appendChild(element)
      @tree.openElements << element
    elsif token["type"] == "EmptyTag"
      element = @tree.createElement(token["name"], token["attributes"])
      @tree.openElements[-1].appendChild(element)
    elsif token["type"] == "EndTag"
      if @tree.openElements[-1].name != token["name"]
        # XXX parse error
        # pass
      end
      if @tree.elementInScope(token["name"])
        while @tree.openElements[-1].name != token["name"]
          @tree.openElements.pop()
        end
        @tree.openElements.pop()
        if @tree.openElements.empty?
          @phase = @phases["end"]
        end
      end
    elsif token["type"] == "EndTagShort"
      @tree.openElements.pop()
      if @tree.openElements.empty?
        @phase = @phases["end"]
      end
    elsif token["type"] == "Comment"
      @tree.openElements[-1].appendChild(@tree.commentClass(token["data"]))
    elsif token["type"] == "Pi"
      @tree.openElements[-1].appendChild(@tree.piClass(token["name"], token["data"]))
    end
  end

  def endPhase(token)
    if token["type"] == "Comment"
      @tree.document.appendChild(@tree.commentClass(token["data"]))
    elsif token["type"] == "Pi"
      @tree.document.appendChild(@tree.piClass(token["name"], token["data"]))
    elsif token["type"] == "Characters" and containsWhiteSpace(token["data"])
      # pass
    else
      # XXX parse error
      # pass
    end
  end
end
