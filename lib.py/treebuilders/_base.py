class Node(object):
    def __init__(self, name):
        """Node representing an item in the tree.
        parent - The parent of the current node (or None for the document node)
        childNodes - a list of child nodes of the current node. This must 
        """
        self.parent = None
        self.childNodes = []

    def __unicode__(self):
        raise NotImplementedError

    def appendChild(self, node):
        """Insert node as a child of the current node
        """
        raise NotImplementedError

    def insertText(self, data, insertBefore=None):
        """Insert data as text in the current node, positioned before the 
        start of node insertBefore or to the end of the node's text.
        """
        raise NotImplementedError

class TreeBuilder(object):
    """Base treebuilder implementation
    """

    documentClass = None
    elementClass = None
    piClass = None
    commentClass = None

    def __init__(self):
        self.reset()

    def reset(self):
        self.openElements = []
        self.document = self.documentClass()

    def findDefaultNamespaceInAttributes(self, attributes):
        for name,value in attributes:
            if name == "xmlns":
                return value
        return None

    def findDefaultNamespaceInAttributeTokens(self, attributes):
        for token in attributes:
            if token["name"] == "xmlns":
                return token["value"]
        return None

    def findNamespaceInAttributes(self, attributes, prefix):
        for name,value in attributes:
            if name == "".join(["xmlns:",prefix]):
                return value
        return None

    def findNamespaceInAttributeTokens(self, attributes, prefix):
        if attributes:
            for token in attributes:
                if token["name"] == "".join(["xmlns:",prefix]):
                    return token["value"]
        return None

    def findDefaultNamespace(self):
        tempNamespace = None
        for node in self.openElements[::-1]:
            if node.attributes:
                tempNamespace = self.findDefaultNamespaceInAttributeTokens(node.attributes)
                if tempNamespace:
                    return tempNamespace
        return ""

    def findNamespace(self, prefix):
        tempNamespace = None
        for node in self.openElements[::-1]:
            if node.attributes:
                tempNamespace = self.findNamespaceInAttributeTokens(node.attributes, prefix)
                if tempNamespace:
                    return tempNamespace
        return ""
    
    def findElementNamespace(self, prefix, attributes):
        namespace = None
        if prefix == "":
            if attributes:
                namespace = self.findDefaultNamespaceInAttributes(attributes)
            if not namespace:
                namespace = self.findDefaultNamespace()
        else:
            if attributes:
                namespace = self.findNamespaceInAttributes(attributes, prefix)
            if not namespace:
                namespace = self.findNamespace(prefix)
        return namespace

    def createAttributeList(self, attributes):
        newAttributeList = []
        for name,value in attributes:
            prefix, localname, tempNamespace = ("", name, None)
            if name.find(":") != -1:
                prefix, localname = name.split(":", 1)
            token = {"name":name, "localname":localname, "prefix":prefix, "namespace":"", "value":value}
            if name == "xmlns" or prefix == "xmlns":
                token["namespace"] = "http://www.w3.org/2000/xmlns/"
            elif prefix == "xml":
                token["namespace"] = "http://www.w3.org/XML/1998/namespace"
            elif prefix != "":
                if attributes:
                    tempNamespace = self.findNamespaceInAttributes(attributes, prefix)
                if not tempNamespace:
                    tempNamespace = self.findNamespace(prefix)
                token["namespace"] = tempNamespace

            # Remove duplicate attributes
            duplicate = False
            for item in newAttributeList:
                if item["localname"] == token["localname"] and\
                  item["namespace"] == token["namespace"]:
                    # XXX parse error
                    duplicate = True
                    break
            if not duplicate:
                newAttributeList.append(token)
        return newAttributeList

    def createElement(self, name, attributes):
        prefix = ""
        localname = name
        if name.find(":") != -1:
            prefix, localname = name.split(":", 1)
        if prefix == "xmlns":
            namespace = "http://www.w3.org/2000/xmlns/"
        elif prefix == "xml":
            namespace = "http://www.w3.org/XML/1998/namespace"
        else:
            namespace = self.findElementNamespace(prefix, attributes)
        if attributes:
            attributes = self.createAttributeList(attributes)
        return self.elementClass(name, prefix, localname, namespace, attributes)

    def elementInScope(self, target):
        if self.openElements[-1].name == target:
            return True

        # AT Use reverse instead of [::-1] when we can rely on Python 2.4
        for node in self.openElements[::-1][1:]:
            if node.name == target:
                return True
        return False

    def insertText(self, data, parent=None):
        """Insert text data."""
        if parent is None:
            parent = self.openElements[-1]
        parent.insertText(data)

    def getDocument(self):
        "Return the final tree"
        return self.document

    def testSerializer(self, node):
        """Serialize the subtree of node in the format required by unit tests
        node - the node from which to start serializing"""
        raise NotImplementedError
