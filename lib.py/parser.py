from tokenizer import XMLTokenizer

import treebuilders
from constants import spaceCharacters
from treebuilders import simpletree

class XMLParser(object):
    def __init__(self, tree=simpletree.TreeBuilder):
        self.tree = tree()
        self.errors = []

        self.phases = {
            "start":self.startPhase,
            "main":self.mainPhase,
            "end":self.endPhase
        }
        self.phase = self.phases["start"]

    def _parse(self, stream, encoding=None):
        self.tree.reset()
        self.errors = []
        self.tokenizer = XMLTokenizer(stream, encoding)

        for token in self.tokenizer:
            self.phase(token)
        # When the loop finishes it's EOF
        # XXX

    def parse(self, stream, encoding=None):
        self._parse(stream, encoding=encoding)
        return self.tree.getDocument()

    def containsWhiteSpace(self, string):
        for c in string:
            if c not in spaceCharacters:
                return False
        return True

    def startPhase(self, token):
        if token["type"] == "StartTag":
            element = self.tree.createElement(token["name"], token["attributes"])
            self.tree.document.appendChild(element)
            self.tree.openElements.append(element)
            self.phase = self.phases["main"]
        elif token["type"] == "EmptyTag":
            element = self.tree.createElement(token["name"], token["attributes"])
            self.tree.document.appendChild(element)
            self.phase = self.phases["end"]
        elif token["type"] == "Comment":
            self.tree.document.appendChild(self.tree.commentClass(token["data"]))
        elif token["type"] == "Pi":
            self.tree.document.appendChild(self.tree.piClass(token["name"], token["data"]))
        elif token["type"] == "Characters" and self.containsWhiteSpace(token["data"]):
            pass
        else:
            # XXX parse error
            pass

    def mainPhase(self, token):
        if token["type"] == "Characters":
            self.tree.insertText(token["data"])
        elif token["type"] == "StartTag":
            element = self.tree.createElement(token["name"], token["attributes"])
            self.tree.openElements[-1].appendChild(element)
            self.tree.openElements.append(element)
        elif token["type"] == "EmptyTag":
            element = self.tree.createElement(token["name"], token["attributes"])
            self.tree.openElements[-1].appendChild(element)
        elif token["type"] == "EndTag":
            if self.tree.openElements[-1].name != token["name"]:
                # XXX parse error
                pass
            if self.tree.elementInScope(token["name"]):
                while self.tree.openElements[-1].name != token["name"]:
                    self.tree.openElements.pop()
                self.tree.openElements.pop()
                if len(self.tree.openElements) == 0:
                    self.phase = self.phases["end"]
        elif token["type"] == "EndTagShort":
            self.tree.openElements.pop()
            if len(self.tree.openElements) == 0:
                self.phase = self.phases["end"]
        elif token["type"] == "Comment":
            self.tree.openElements[-1].appendChild(self.tree.commentClass(token["data"]))
        elif token["type"] == "Pi":
            self.tree.openElements[-1].appendChild(self.tree.piClass(token["name"], token["data"]))

    def endPhase(self, token):
        if token["type"] == "Comment":
            self.tree.document.appendChild(self.tree.commentClass(token["data"]))
        elif token["type"] == "Pi":
            self.tree.document.appendChild(self.tree.piClass(token["name"], token["data"]))
        elif token["type"] == "Characters" and self.containsWhiteSpace(token["data"]):
            pass
        else:
            # XXX parse error
            pass
