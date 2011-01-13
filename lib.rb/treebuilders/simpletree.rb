require 'treebuilders/base'

# DOM-core like implementation with extensions.
module SimpleTree
  class Node < Base::Node
    def initialize
      @childNodes = []
    end

    def each
      for node in @childNodes
        yield node
        for item in node
          yield item
        end
      end
    end

    def to_s
      return @name
    end

    def to_xml
      raise NotImplementedError
    end

    def printTree(indent=0)
      tree = "\n|#{' ' * indent}#{to_s}"
      for child in @childNodes
        tree += child.printTree(indent + 2)
      end
      return tree
    end

    def appendChild(node, index=nil)
      if (node.instance_of?(Text) and not @childNodes.empty? and
        @childNodes.last.instance_of?(Text))
        @childNodes.last.value += node.value
      else
        @childNodes << node
      end
      node.parent = self
    end

    def insertText(data)
      appendChild(Text.new(data))
    end

    def hasContent
      """Return true if the node has children or text"""
      return bool(@childNodes)
    end
  end

  class Document < Node
    def initialize
      super
    end

    def to_s
      return "#document"
    end

    def to_xml(encoding="utf=8")
      result = ""
      for child in @childNodes
        result += child.to_xml()
      end
      return result.encode(encoding)
    end

    def hilite(encoding="utf-8")
      result = "<pre>"
      for child in @childNodes
        result += child.hilite()
      end
      return result.encode(encoding) + "</pre>"
    end

    def printTree
      tree = self.to_s
      for child in @childNodes
        tree += child.printTree(1)
      end
      return tree
    end
  end

  class Text < Node
    attr_accessor :value

    def initialize(value)
      super()
      @value = value
    end

    def to_s
      return "\"%s\"" % @value
    end

    def to_xml
      return escape(@value)
    end

    alias :hilite :to_xml
  end

  class Element < Node
    attr_reader :name
    attr_reader :attributes

    def initialize(name, prefix, localname, namespace, attributes)
      super()
      @name = name
      @prefix = prefix
      @localname = localname
      @namespace = namespace
      @attributes = attributes
    end

    def to_s
      return "<%s>" % @name
    end

    def printTree(indent)
      tree = "\n|#{' ' * indent}<#{@name}> " +
        "(#{@prefix}, #{@localname}, #{@namespace})"
      indent += 2
      if @attributes
        for token in @attributes
          tree += "\n|#{' ' * indent}#{token["name"]}=\"#{token["value"]}\" " +
            "(#{token["prefix"]}, #{token["localname"]}, #{token["namespace"]})"
        end
      end
      for child in @childNodes
        tree += child.printTree(indent)
      end
      return tree
    end
  end

  class Pi < Node
    def initialize(name, data)
      super()
      @name = name
      @data = data
    end

    def to_s
      return "<?#{@name} #{@data}?>"
    end

    def to_xml
      return "<?#{@name} #{@data}?>"
    end

    def hilite
      return '<code class="markup pi">&lt;?%s %s?></code>' % [escape(@name),
      escape(@data)]
    end
  end

  class Comment < Node
    def initialize(data)
      super()
      @data = data
    end

    def to_s
      return "<!-- %s -->" % @data
    end

    def to_xml
      return "<!--%s-->" % @data
    end

    def hilite
      return '<code class="markup comment">&lt;!--%s--></code>' % escape(@data)
    end
  end

  class TreeBuilder < Base::TreeBuilder
    @@documentClass = Document
    @@elementClass = Element
    @@piClass = Pi
    @@commentClass = Comment

    def testSerializer(node)
      return node.printTree()
    end
  end
end
