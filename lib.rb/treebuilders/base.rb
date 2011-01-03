module SimpleTree
  module Base
    class Node
      attr_accessor :parent
      def initialize(name)
        """Node representing an item in the tree.
        parent - The parent of the current node (or nil for the document node)
        childNodes - a list of child nodes of the current node. This must
        """
        @parent = nil
        @childNodes = []
      end

      def to_s
        raise NotImplementedError
      end

      def appendChild(node)
        """Insert node as a child of the current node
        """
        raise NotImplementedError
      end

      def insertText(data, insertBefore=nil)
        """Insert data as text in the current node, positioned before the
        start of node insertBefore or to the end of the node's text.
        """
        raise NotImplementedError
      end
    end

    class TreeBuilder
      """Base treebuilder implementation
      """
      attr_reader :document
      attr_reader :openElements

      @@documentClass = nil
      @@elementClass = nil
      @@piClass = nil
      @@commentClass = nil

      def elementClass
        @@elementClass
      end

      def commentClass
        @@commentClass
      end

      def initialize
        reset()
      end

      def reset
        @openElements = []
        @document = @@documentClass.new
      end

      def findDefaultNamespaceInAttributes(attributes)
        for name,value in attributes
          if name == "xmlns"
            return value
          end
        end
        return nil
      end

      def findDefaultNamespaceInAttributeTokens(attributes)
        for token in attributes
          if token["name"] == "xmlns"
            return token["value"]
          end
        end
        return nil
      end

      def findNamespaceInAttributes(attributes, prefix)
        for name,value in attributes
          if name == "xmlns:#{prefix}"
            return value
          end
        end
        return nil
      end

      def findNamespaceInAttributeTokens(attributes, prefix)
        if attributes
          for token in attributes
            if token["name"] == "xmlns:#{prefix}"
              return token["value"]
            end
          end
        end
        return nil
      end

      def findDefaultNamespace
        tempNamespace = nil
        for node in @openElements.reverse
          if node.attributes
            tempNamespace = findDefaultNamespaceInAttributeTokens(node.attributes)
            if tempNamespace
              return tempNamespace
            end
           end
        end
        return ""
      end

      def findNamespace(prefix)
        tempNamespace = nil
        for node in @openElements.reverse
          if node.attributes
            tempNamespace = findNamespaceInAttributeTokens(node.attributes, prefix)
            if tempNamespace
              return tempNamespace
            end
          end
        end
        return ""
      end

      def findElementNamespace(prefix, attributes)
        namespace = nil
        if prefix == ""
          if attributes
            namespace = findDefaultNamespaceInAttributes(attributes)
           end
          if not namespace
            namespace = findDefaultNamespace()
          end
        else
          if attributes
            namespace = findNamespaceInAttributes(attributes, prefix)
          end
          if not namespace
            namespace = findNamespace(prefix)
          end
        end
        return namespace
      end

      def createAttributeList(attributes)
        newAttributeList = []
        for name,value in attributes
          prefix, localname, tempNamespace = "", name, nil
          if name.index(":")
            prefix, localname = name.split(":", 2)
          end
          token = {"name" => name, "localname" => localname,
            "prefix" => prefix, "namespace" => "", "value" => value}
          if name == "xmlns" or prefix == "xmlns"
            token["namespace"] = "http://www.w3.org/2000/xmlns/"
          elsif prefix == "xml"
            token["namespace"] = "http://www.w3.org/XML/1998/namespace"
          elsif prefix != ""
            if attributes
              tempNamespace = findNamespaceInAttributes(attributes, prefix)
            end
            if not tempNamespace
              tempNamespace = findNamespace(prefix)
            end
            token["namespace"] = tempNamespace
          end

          # Remove duplicate attributes
          duplicate = false
          for item in newAttributeList
            if item["localname"] == token["localname"] and\
              item["namespace"] == token["namespace"]
              # XXX parse error
              duplicate = true
              break
            end
          end
          if not duplicate
            newAttributeList << token
          end
        end
        return newAttributeList
      end

      def createElement(name, attributes)
        prefix = ""
        localname = name
        if name.index(":")
          prefix, localname = name.split(":", 2)
        end
        if prefix == "xmlns"
          namespace = "http://www.w3.org/2000/xmlns/"
        elsif prefix == "xml"
          namespace = "http://www.w3.org/XML/1998/namespace"
        else
          namespace = findElementNamespace(prefix, attributes)
        end
        if attributes
          attributes = createAttributeList(attributes)
        end
        return @@elementClass.new(name, prefix, localname, namespace, attributes)
      end

      def elementInScope(target)
        if @openElements[-1].name == target
          return true
        end

        for node in @openElements.reverse[1..-1]
          if node.name == target
            return true
          end
        end
        return false
      end

      def insertText(data, parent=nil)
        """Insert text data."""
        if parent == nil
          parent = @openElements[-1]
        end
        parent.insertText(data)
      end

      def getDocument
        "Return the final tree"
        return @document
      end

      def testSerializer(node)
        """Serialize the subtree of node in the format required by unit tests
        node - the node from which to start serializing"""
        raise NotImplementedError
      end
    end
  end
end
