from constants import spaceCharacters, digits, hexDigits, EOF
from inputstream import XMLInputStream
import re

class XMLTokenizer(object):
    def __init__(self, stream, encoding=None):
        # The stream holds all the characters.
        self.stream = XMLInputStream(stream, self, encoding)

        # Set of states and the initial state
        self.states = {
          "data":self.dataState,
          "tag":self.tagState,
          "endTag":self.endTagState,
          "endTagName":self.endTagNameState,
          "endTagNameAfter":self.endTagNameAfterState,
          "pi":self.piState,
          "piTarget":self.piTargetState,
          "piTargetAfter":self.piTargetAfterState,
          "piContent":self.piContentState,
          "piAfter":self.piAfterState,
          "markupDeclaration":self.markupDeclarationState,
          "comment":self.commentState,
          "commentDash":self.commentDashState,
          "commentEnd":self.commentEndState,
          "cdata":self.cdataState,
          "cdataBracket":self.cdataBracketState,
          "cdataEnd":self.cdataEndState,
          "doctype":self.doctypeState,
          "doctypeRootNameBefore":self.doctypeRootNameBeforeState,
          "doctypeRootName":self.doctypeRootNameState,
          "doctypeRootNameAfter":self.doctypeRootNameAfterState,
          "doctypeIdentifierDoubleQuoted":self.doctypeIdentifierDoubleQuotedState,
          "doctypeIdentifierSingleQuoted":self.doctypeIdentifierSingleQuotedState,
          "doctypeInternalSubset":self.doctypeInternalSubsetState,
          "doctypeInternalSubsetAfter":self.doctypeInternalSubsetAfterState,
          "doctypeTag":self.doctypeTagState,
          "doctypeMarkupDeclaration":self.doctypeMarkupDeclarationState,
          "doctypeComment":self.doctypeCommentState,
          "doctypeCommentDash":self.doctypeCommentDashState,
          "doctypeCommentEnd":self.doctypeCommentEndState,
          "doctypeEntity":self.doctypeEntityState,
          "doctypeEntityTypeBefore":self.doctypeEntityTypeBeforeState,
          "doctypeEntityParameterBefore":self.doctypeEntityParameterBeforeState,
          "doctypeEntityParameter":self.doctypeEntityParameterState,
          "doctypeEntityName":self.doctypeEntityNameState,
          "doctypeEntityNameAfter":self.doctypeEntityNameAfterState,
          "doctypeEntityValDoubleQuoted":self.doctypeEntityValDoubleQuotedState,
          "doctypeEntityValSingleQuoted":self.doctypeEntityValSingleQuotedState,
          "doctypeEntityValAfter":self.doctypeEntityValAfterState,
          "doctypeEntityIdentifier":self.doctypeEntityIdentifierState,
          "doctypeEntityIdentifierDoubleQuoted":self.doctypeEntityIdentifierDoubleQuotedState,
          "doctypeEntityIdentifierSingleQuoted":self.doctypeEntityIdentifierSingleQuotedState,
          "doctypeAttlist":self.doctypeAttlistState,
          "doctypeAttlistNameBefore":self.doctypeAttlistNameBeforeState,
          "doctypeAttlistName":self.doctypeAttlistNameState,
          "doctypeAttlistNameAfter":self.doctypeAttlistNameAfterState,
          "doctypeAttlistAttrname":self.doctypeAttlistAttrnameState,
          "doctypeAttlistAttrnameAfter":self.doctypeAttlistAttrnameAfterState,
          "doctypeAttlistAttrtype":self.doctypeAttlistAttrtypeState,
          "doctypeAttlistAttrtypeAfter":self.doctypeAttlistAttrtypeAfterState,
          "doctypeAttlistAttrdeclBefore":self.doctypeAttlistAttrdeclBeforeState,
          "doctypeAttlistAttrdecl":self.doctypeAttlistAttrdeclState,
          "doctypeAttlistAttrdeclAfter":self.doctypeAttlistAttrdeclAfterState,
          "doctypeAttlistAttrvalDoubleQuoted":self.doctypeAttlistAttrvalDoubleQuotedState,
          "doctypeAttlistAttrvalSingleQuoted":self.doctypeAttlistAttrvalSingleQuotedState,
          "doctypeNotation":self.doctypeNotationState,
          "doctypeNotationIdentifier":self.doctypeNotationIdentifierState,
          "doctypeNotationIdentifierDoubleQuoted":self.doctypeNotationIdentifierDoubleQuotedState,
          "doctypeNotationIdentifierSingleQuoted":self.doctypeNotationIdentifierSingleQuotedState,
          "doctypePi":self.doctypePiState,
          "doctypePiAfter":self.doctypePiAfterState,
          "doctypeBogusComment":self.doctypeBogusCommentState,
          "tagName":self.tagNameState,
          "emptyTag":self.emptyTagState,
          "tagAttributeNameBefore":self.tagAttributeNameBeforeState,
          "tagAttributeName":self.tagAttributeNameState,
          "tagAttributeNameAfter":self.tagAttributeNameAfterState,
          "tagAttributeValueBefore":self.tagAttributeValueBeforeState,
          "tagAttributeValueDoubleQuoted":self.tagAttributeValueDoubleQuotedState,
          "tagAttributeValueSingleQuoted":self.tagAttributeValueSingleQuotedState,
          "tagAttributeValueUnquoted":self.tagAttributeValueUnquotedState,
          "bogusComment":self.bogusCommentState
        }
        self.state = self.states["data"]

        # The current token being created
        self.currentToken = None

        # Entities
        self.entities = {
          "lt":"&#60;",
          "gt":">",
          "amp":"&#38;",
          "apos":"'",
          "quot":"\""
        }
        self.parameterEntities = {}
        self.attributeNormalization = []

        # Dealing with entities
        self.entityValueLen = 0
        self.charCount = 0
        self.entityCount = 0

        # Tokens yet to be processed.
        self.tokenQueue = []

    def __iter__(self):
        self.stream.reset()
        self.tokenQueue = []

        # Start processing. When EOF is reached self.state will return False
        # instead of True and the loop will terminate.
        while self.state():
            while self.tokenQueue:
                yield self.tokenQueue.pop(0)

    def consumeNumberEntity(self, isHex):
        allowed = digits
        radix = 10
        if isHex:
            allowed = hexDigits
            radix = 16

        char = u"\uFFFD"

        # Consume all the characters that are in range while making sure we
        # don't hit an EOF.
        value = self.stream.charsUntil(allowed, True)

        # Convert the set of characters consumed to an int.
        charAsInt = int(value, radix)

        # No NULL characters.
        # XXX any other characters?
        if charAsInt == 0:
            charAsInt = 65533

        # Convert the int value to an actual char
        try:
            # XXX We should have a separate function that does "int" to
            # "unicodestring" conversion since this doesn't always work
            # according to hsivonen. Also, unichr has a limitation of 65535
            char = unichr(charAsInt)
        except:
            # XXX parse error
            pass

        # Discard the ; if present. Otherwise, put it back on the queue and
        # invoke parseError on parser.
        c = self.stream.char()
        if c != ";":
            # XXX parse error
            self.stream.queue.append(c)
        return char

    def consumeEntity(self, fromAttribute=False):
        # The result of this function is a tuple consisting of the entity
        # value and whether it needs to be inserted into the stream or
        # simply appended as character data.
        c = self.stream.char()
        if c == "#":
            # Character reference (numeric entity).
            value = "&#"
            c = self.stream.char()
            if c == "x":
                c = self.stream.char()
                if c in hexdigits:
                    # Hexadecimal entity detected.
                    self.stream.queue.insert(0, c)
                    value = self.consumeNumberEntity(True)
                else:
                    value += "x"
            elif c in digits:
                # Decimal entity detected.
                self.stream.queue.insert(0, c)
                value = self.consumeNumberEntity(False)
            elif c == EOF:
                # XXX parse error
                pass
            else:
                # XXX parse error
                value += c
            return "Characters", value
        # Break out if we reach the end of the file
        elif c == EOF:
            # XXX parse error
            return "Characters", "&"
        else:
            # Named entity.
            end = ";"
            name = c + self.stream.charsUntil(";")

            # Check whether or not the last character returned can be
            # discarded or needs to be put back.
            c = self.stream.char()
            if c != ";":
                # XXX parse error
                end = ""

            if name in self.entities:
                if self.entityCount < 16:
                    self.entityCount += 1
                    value = self.entities[name]
                    if fromAttribute:
                        # This is a hack to make things "work". Or is it
                        # really the only good solution?
                        value = re.sub("\n", "&#10;", value)
                        value = re.sub("\r", "&#10;", value)
                        value = re.sub("\t", "&#9;", value)
                        value = re.sub(" ", "&#32;", value)
                        value = re.sub("\"", "&#34;", value)
                        value = re.sub("'", "&#39;", value)
                    self.entityValueLen += len(value)
                    return "Stream", value
                else:
                    # XXX parse error
                    return "Characters", ""
            else:
                # XXX parse error
                return "Characters", "&" + name + end
        assert 0

    def consumeNumberEntityOnly(self):
        c = self.stream.char()
        value = "&"
        if c == EOF:
            self.stream.queue.insert(0, c)
        elif c != "#":
            value += c
        else:
            value += "#"
            c = self.stream.char()
            if c == "x":
                c = self.stream.char()
                if c in hexdigits:
                    # Hexadecimal entity detected.
                    self.stream.queue.insert(0, c)
                    value = self.consumeNumberEntity(True)
                else:
                    value += "x"
            elif c in digits:
                # Decimal entity detected.
                self.stream.queue.insert(0, c)
                value = self.consumeNumberEntity(False)
            elif c == EOF:
                # XXX parse error
                pass
            else:
                # XXX parse error
                value += c
        return value

    def consumeParameterEntity(self):
        name = self.stream.charsUntil(";")
        c = self.stream.char()
        if c != ";":
            # XXX parse error
            pass

        if name in self.parameterEntities and self.entityCount < 16:
            self.entityCount += 1
            value = self.parameterEntities[name]
            self.entityValueLen += len(value)
            return value
        else:
            # XXX parse error
            return ""

    def attributeNameExists(self, name):
        for x,y in self.currentToken["attributes"]:
            if x == name:
                return True
        return False

    def emitCurrentToken(self):
        if (self.currentToken["type"] == "StartTag" or
          self.currentToken["type"] == "EmptyTag") and\
          self.attributeNormalization:
            for token in self.attributeNormalization:
                if token["name"] == self.currentToken["name"]:
                    for attr in token["attrs"]:
                        if attr["dv"] != "" and not self.attributeNameExists(attr["name"]):
                            self.currentToken["attributes"].append([attr["name"], attr["dv"]])
        self.tokenQueue.append(self.currentToken)
        self.state = self.states["data"]

    def appendEntity(self):
        assert self.currentToken
        name = self.currentToken["name"]
        value = self.currentToken["value"]
        type = self.currentToken["type"]
        if type == "entity":
            if name not in self.entities:
                self.entities[name] = value
        elif type == "parameterEntity":
            if name not in self.parameterEntities:
                self.parameterEntities[name] = value
        else:
            assert 0
        self.state = self.states["doctypeInternalSubset"]


    # Below are the various tokenizer states worked out.

    def dataState(self):
        data = self.stream.char()
        if data == "&":
            entity = self.consumeEntity()
            if entity[0] == "Characters":
                self.tokenQueue.append({"type":"Characters","data":entity[1]})
            else:
                i = 0
                for x in entity[1]:
                    self.stream.queue.insert(i, x)
                    i += 1
        elif data == "<":
            self.state = self.states["tag"]
        elif data == EOF:
            # Tokenization ends.
            return False
        else:
            chars = self.stream.charsUntil((u"&", u"<", u"\u0000"))
            self.tokenQueue.append({"type":"Characters","data":data + chars})
        return True

    def tagState(self):
        data = self.stream.char()
        if data == "/":
            self.state = self.states["endTag"]
        elif data == "?":
            self.state = self.states["pi"]
        elif data == "!":
            self.state = self.states["markupDeclaration"]
        elif data in spaceCharacters\
          or data == "<"\
          or data == ">"\
          or data == ":"\
          or data == EOF:
            # XXX parse error
            self.tokenQueue.append({"type":"Characters", "data":"<"})
            self.stream.queue.insert(0, data)
            self.state = self.states["data"]
        else:
            self.currentToken = {"type":"StartTag", "name":data, "attributes":[]}
            self.state = self.states["tagName"]
        return True

    def endTagState(self):
        data = self.stream.char()
        if data == ">":
            self.tokenQueue.append({"type":"EndTagShort"})
            self.state = self.states["data"]
        elif data in spaceCharacters\
          or data == "<"\
          or data == ":"\
          or data == EOF:
            # XXX parse error
            # XXX catch more "incorrect" characters here?
            self.tokenQueue.append({"type":"Characters", "data":"</"})
            self.stream.queue.insert(0, data)
            self.state = self.states["data"]
        else:
            self.currentToken = {"type":"EndTag", "name":data}
            self.state = self.states["endTagName"]
        return True

    def endTagNameState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["endTagNameAfter"]
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        elif data == ">":
            self.emitCurrentToken()
        else:
            self.currentToken["name"] += data
        return True

    def endTagNameAfterState(self):
        data = self.stream.char()
        if data == ">":
            self.emitCurrentToken()
        elif data in spaceCharacters:
            pass
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        else:
            # XXX parse error
            pass
        return True

    def piState(self):
        data = self.stream.char()
        if data in spaceCharacters\
          or data == EOF:
            # XXX parse error
            # XXX catch more "incorrect" characters here?
            self.stream.queue.append("?")
            self.stream.queue.append(data)
            self.state = self.states["bogusComment"]
        else:
            self.currentToken = {"type":"Pi", "name":data, "data":""}
            self.state = self.states["piTarget"]
        return True

    def piTargetState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["piTargetAfter"]
        elif data == EOF:
            # XXX parse error
            # XXX catch more "incorrect" characters here?
            self.emitCurrentToken()
        elif data == "?":
            self.state = self.states["piAfter"]
        else:
            self.currentToken["name"] += data
        return True

    def piTargetAfterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        else:
            self.stream.queue.append(data)
            self.state = self.states["piContent"]
        return True

    def piContentState(self):
        data = self.stream.char()
        if data == "?":
            self.state = self.states["piAfter"]
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        else:
            self.currentToken["data"] += data
        return True

    def piAfterState(self):
        data = self.stream.char()
        if data == ">":
            self.emitCurrentToken()
        elif data == "?":
            self.currentToken["data"] += "?"
        else:
            self.stream.queue.append(data)
            self.state = self.states["piContent"]
        return True

    # Markup declarations.
    def markupDeclarationState(self):
        charStack = [self.stream.char(), self.stream.char()]
        if charStack == ["-", "-"]:
            self.currentToken = {"type":"Comment", "data":""}
            self.state = self.states["comment"]
        else:
            for x in xrange(5):
                charStack.append(self.stream.char())
            if not EOF in charStack:
                n = "".join(charStack)
                if n == "[CDATA[":
                    self.state = self.states["cdata"]
                    return True
                if n == "DOCTYPE":
                    # XXX parse error
                    self.state = self.states["doctype"]
                    return True
            # XXX parse error
            self.stream.queue.extend(charStack)
            self.state = self.states["bogusComment"]
        return True

    # Handling of comments. They end after a literal '-->' sequence.
    def commentState(self):
        data = self.stream.char()
        if data == "-":
            self.state = self.states["commentDash"]
        elif data == EOF:
            # XXX parse error
            self.tokenQueue.append(self.currentToken)
            self.state = self.states["data"]
        else:
            self.currentToken["data"] += data + self.stream.charsUntil("-")
        return True

    def commentDashState(self):
        data = self.stream.char()
        if data == "-":
            self.state = self.states["commentEnd"]
        elif data == EOF:
            # XXX parse error
            self.tokenQueue.append(self.currentToken)
            self.state = self.states["data"]
        else:
            self.currentToken["data"] += "-" + data +\
              self.stream.charsUntil("-")
            # Consume the next character which is either a "-" or an EOF as
            # well so if there's a "-" directly after the "-" we go nicely to
            # the "comment end state" without emitting a ParseError() there.
            self.stream.char()
        return True

    def commentEndState(self):
        data = self.stream.char()
        if data == ">":
            self.tokenQueue.append(self.currentToken)
            self.state = self.states["data"]
        elif data == "-":
            self.currentToken["data"] += "-"
        elif data == EOF:
            # XXX parse error
            self.tokenQueue.append(self.currentToken)
            self.state = self.states["data"]
        else:
            self.currentToken["data"] += "--" + data
            self.state = self.states["comment"]
        return True

    # These states handle the last bit of <![CDATA[ foo ]]> blocks.
    def cdataState(self):
        data = self.stream.char()
        if data == "]":
            self.state = self.states["cdataBracket"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.tokenQueue.append({"type":"Characters", "data":\
              data + self.stream.charsUntil("]")})
        return True

    def cdataBracketState(self):
        data = self.stream.char()
        if data == "]":
            self.state = self.states["cdataEnd"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.tokenQueue.append({"type":"Characters", "data":\
              "]" + data + self.stream.charsUntil("]")})
            # Consume the next character which is either a "]" or an EOF as
            # well so if there's a "]" directly after the "]" we go nicely to
            # the "cdata end state" without emitting a ParseError() there.
            self.stream.char()
        return True

    def cdataEndState(self):
        data = self.stream.char()
        if data == ">":
            self.state = self.states["data"]
        elif data == "]":
            self.tokenQueue.append({"type":"Characters", "data":data})
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.tokenQueue.append({"type":"Characters", "data":"]]" + data})
            self.state = self.states["cdata"]
        return True

    # XXX should we emit doctype tokens and such?
    def doctypeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeRootNameBefore"]
        elif data == EOF:
            # XXX parse error?
            self.state = self.states["data"]
        else:
            self.stream.queue.append(data)
            self.state = self.states["bogusComment"]
        return True

    def doctypeRootNameBeforeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == ">":
            self.state = self.states["data"]
        elif data == EOF:
            # XXX parse error?
            self.state = self.states["data"]
        else:
            self.state= self.states["doctypeRootName"]
        return True

    def doctypeRootNameState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeRootNameAfter"]
        elif data == ">":
            self.state = self.states["data"]
        elif data == "[":
            self.state = self.states["doctypeInternalSubset"]
        elif data == EOF:
            # XXX parse error?
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeRootNameAfterState(self):
        data = self.stream.char()
        if data == ">":
            self.state = self.states["data"]
        elif data == "\"":
            self.state = self.states["doctypeIdentifierDoubleQuoted"]
        elif data == "'":
            self.state = self.states["doctypeIdentifierSingleQuoted"]
        elif data == "[":
            self.state = self.states["doctypeInternalSubset"]
        elif data == EOF:
            # XXX parse error?
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeIdentifierDoubleQuotedState(self):
        data = self.stream.char()
        if data == "\"":
            self.state = self.states["doctypeRootNameAfter"]
        elif data == EOF:
            # XXX parse error?
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeIdentifierSingleQuotedState(self):
        data = self.stream.char()
        if data == "'":
            self.state = self.states["doctypeRootNameAfter"]
        elif data == EOF:
            # XXX parse error?
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeInternalSubsetState(self):
        data = self.stream.char()
        if data == "<":
            self.state = self.states["doctypeTag"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        elif data == "%":
            self.stream.queue.extend(self.consumeParameterEntity())
        elif data == "]":
            self.state = self.states["doctypeInternalSubsetAfter"]
        else:
            pass
        return True

    def doctypeInternalSubsetAfterState(self):
        data = self.stream.char()
        if data == ">":
            self.state = self.states["data"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeTagState(self):
        data = self.stream.char()
        if data == "!":
            self.state = self.states["doctypeMarkupDeclaration"]
        elif data == "?":
            self.state = self.states["doctypePi"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeBogusComment"]
        return True

    def doctypeMarkupDeclarationState(self):
        charStack = [self.stream.char(), self.stream.char()]
        if charStack == ["-", "-"]:
            self.state = self.states["doctypeComment"]
        else:
            for x in xrange(4):
                charStack.append(self.stream.char())
            if not EOF in charStack:
                if "".join(charStack) == "ENTITY":
                    self.state = self.states["doctypeEntity"]
                    return True
                data = self.stream.char()
                charStack.append(data)
                if data != EOF:
                    if "".join(charStack) == "ATTLIST":
                        self.state = self.states["doctypeAttlist"]
                        return True
                    data = self.stream.char()
                    charStack.append(data)
                    if data != EOF:
                        if "".join(charStack) == "NOTATION":
                            self.state = self.states["doctypeNotation"]
                            return True
            # XXX parse error
            self.stream.queue.extend(charStack)
            self.state = self.states["doctypeBogusComment"]
        return True

    # <!-- ....
    def doctypeCommentState(self):
        data = self.stream.char()
        if data == "-":
            self.state = self.states["doctypeCommentDash"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeCommentDashState(self):
        data = self.stream.char()
        if data == "-":
            self.state = self.states["doctypeCommentEnd"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeComment"]
        return True

    def doctypeCommentEndState(self):
        data = self.stream.char()
        if data == ">":
            self.state = self.states["doctypeInternalSubset"]
        elif data == "-":
            self.state = self.states["doctypeCommentDash"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeComment"]
        return True

    # <!ENTITY
    def doctypeEntityState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeEntityTypeBefore"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeBogusComment"]
        return True

    def doctypeEntityTypeBeforeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == "%":
            self.state = self.states["doctypeEntityParameterBefore"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.currentToken = {"type":"entity", "name":data, "value":""}
            self.state = self.states["doctypeEntityName"]
        return True

    def doctypeEntityParameterBeforeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeEntityParameter"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeBogusComment"]
        return True

    def doctypeEntityParameterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.currentToken = {"type":"parameterEntity", "name":data,\
              "value":""}
            self.state = self.states["doctypeEntityName"]
        return True

    def doctypeEntityNameState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeEntityNameAfter"]
        elif data == EOF:
            # XXX parse error
            self.currentToken = None
            self.state = self.states["data"]
        else:
            self.currentToken["name"] += data
        return True

    def doctypeEntityNameAfterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == "\"":
            self.state = self.states["doctypeEntityValDoubleQuoted"]
        elif data == "'":
            self.state = self.states["doctypeEntityValSingleQuoted"]
        elif data == EOF:
            # XXX parse error
            self.currentToken == None
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeEntityIdentifier"]
        return True

    def doctypeEntityValDoubleQuotedState(self):
        data = self.stream.char()
        # XXX "&" and "%"
        if data == "\"":
            self.state = self.states["doctypeEntityValAfter"]
        elif data == "&":
            self.currentToken["value"] += self.consumeNumberEntityOnly()
        elif data == EOF:
            # XXX parse error
            self.currentToken == None
            self.state = self.states["data"]
        else:
            self.currentToken["value"] += data
        return True

    def doctypeEntityValSingleQuotedState(self):
        data = self.stream.char()
        # XXX "&" and "%"
        if data == "'":
            self.state = self.states["doctypeEntityValAfter"]
        elif data == "&":
            self.currentToken["value"] += self.consumeNumberEntityOnly()
        elif data == EOF:
            # XXX parse error
            self.currentToken == None
            self.state = self.states["data"]
        else:
            self.currentToken["value"] += data
        return True

    def doctypeEntityValAfterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == ">":
            self.appendEntity()
        elif data == EOF:
            # XXX parse error
            self.currentToken == None
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeEntityIdentifierState(self):
        data = self.stream.char()
        if data == ">":
            self.appendEntity()
        elif data == "\"":
            self.state = self.states["doctypeEntityIdentifierDoubleQuoted"]
        elif data == "'":
            self.state = self.states["doctypeEntityIdentifierSingleQuoted"]
        elif data == EOF:
            # XXX parse error
            self.currentToken = None
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeEntityIdentifierDoubleQuotedState(self):
        data = self.stream.char()
        if data == "\"":
            self.state = self.states["doctypeEntityIdentifier"]
        elif data == EOF:
            # XXX parse error
            self.currentToken = None
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeEntityIdentifierSingleQuotedState(self):
        data = self.stream.char()
        if data == "'":
            self.state = self.states["doctypeEntityIdentifier"]
        elif data == EOF:
            # XXX parse error
            self.currentToken = None
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeAttlistState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeAttlistNameBefore"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeBogusComment"]
        return True

    def doctypeAttlistNameBeforeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.attributeNormalization.append({"name":data, "attrs":[]})
            self.state = self.states["doctypeAttlistName"]
        return True

    def doctypeAttlistNameState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeAttlistNameAfter"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.attributeNormalization[-1]["name"] += data
        return True

    def doctypeAttlistNameAfterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == ">":
            self.state = self.states["doctypeInternalSubset"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.attributeNormalization[-1]["attrs"].append({"name":data, "type":"", "dv":""})
            self.state = self.states["doctypeAttlistAttrname"]
        return True

    def doctypeAttlistAttrnameState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeAttlistAttrnameAfter"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.attributeNormalization[-1]["attrs"][-1]["name"] += data
        return True

    def doctypeAttlistAttrnameAfterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.attributeNormalization[-1]["attrs"][-1]["type"] += data
            self.state = self.states["doctypeAttlistAttrtype"]
        return True

    def doctypeAttlistAttrtypeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeAttlistAttrtypeAfter"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.attributeNormalization[-1]["attrs"][-1]["type"] += data
        return True

    def doctypeAttlistAttrtypeAfterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == "#":
            self.state = self.states["doctypeAttlistAttrdeclBefore"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeBogusComment"]
        return True

    def doctypeAttlistAttrdeclBeforeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeBogusComment"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeAttlistAttrdecl"]
        return True

    def doctypeAttlistAttrdeclState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeAttlistAttrdeclAfter"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeAttlistAttrdeclAfterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            pass
        elif data == ">":
            self.state = self.states["doctypeInternalSubset"]
        elif data == "\"":
            self.state = self.states["doctypeAttlistAttrvalDoubleQuoted"]
        elif data == "'":
            self.state = self.states["doctypeAttlistAttrvalSingleQuoted"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.attributeNormalization[-1]["attrs"].append({"name":data, "type":"", "dv":""})
            self.state = self.states["doctypeAttlistAttrname"]
        return True

    def doctypeAttlistAttrvalDoubleQuotedState(self):
        data = self.stream.char()
        if data == "\"":
            self.state = self.states["doctypeAttlistNameAfter"]
        elif data == "%":
            raise NotSupportedError
        elif data == "&":
            raise NotSupportedError
        else:
            self.attributeNormalization[-1]["attrs"][-1]["dv"] += data
        return True

    def doctypeAttlistAttrvalSingleQuotedState(self):
        data = self.stream.char()
        if data == "'":
            self.state = self.states["doctypeAttlistNameAfter"]
        elif data == "%":
            raise NotSupportedError
        elif data == "&":
            raise NotSupportedError
        else:
            self.attributeNormalization[-1]["attrs"][-1]["dv"] += data
        return True

    # <!NOTATION
    def doctypeNotationState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["doctypeNotationIdentifier"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypeBogusComment"]
        return True

    def doctypeNotationIdentifierState(self):
        data = self.stream.char()
        if data == ">":
            self.state = self.states["doctypeInternalSubset"]
        elif data == "\"":
            self.state = self.states["doctypeNotationIdentifierDoubleQuoted"]
        elif data == "'":
            self.state = self.states["doctypeNotationIdentifierSingleQuoted"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeNotationIdentifierDoubleQuotedState(self):
        data = self.stream.char()
        if data == "\"":
            self.state = self.states["doctypeNotationIdentifier"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypeNotationIdentifierSingleQuotedState(self):
        data = self.stream.char()
        if data == "'":
            self.state = self.states["doctypeNotationIdentifier"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypePiState(self):
        data = self.stream.char()
        if data == "?":
            self.state = self.states["doctypePiAfter"]
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            pass
        return True

    def doctypePiAfterState(self):
        data = self.stream.char()
        if data == ">":
            self.state = self.states["doctypeInternalSubset"]
        elif data == "?":
            pass
        elif data == EOF:
            # XXX parse error
            self.state = self.states["data"]
        else:
            self.state = self.states["doctypePiState"]
        return True

    # Bogus "comments" inside a doctype
    def doctypeBogusCommentState(self):
        self.stream.charsUntil(">")
        self.stream.char()
        self.state = self.states["doctypeInternalSubset"]
        return True

    # Tag name of a start or empty tag.
    def tagNameState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["tagAttributeNameBefore"]
        elif data == ">":
            self.emitCurrentToken()
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        elif data == "/":
            self.state = self.states["emptyTag"]
        else:
            self.currentToken["name"] += data
        return True

    def emptyTagState(self):
        data = self.stream.char()
        if data == ">":
            self.currentToken["type"] = "EmptyTag"
            self.emitCurrentToken()
        else:
            # XXX parse error
            self.stream.queue.insert(0, data)
            self.state = self.states["tagAttributeNameBefore"]
        return True

    def tagAttributeNameBeforeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.stream.charsUntil(spaceCharacters, True)
        elif data == ">":
            self.emitCurrentToken()
        elif data == "/":
            self.state = self.states["emptyTag"]
        elif data == ":":
            # XXX parse error
            pass
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        else:
            self.currentToken["attributes"].append([data, ""])
            self.state = self.states["tagAttributeName"]
        return True

    def tagAttributeNameState(self):
        data = self.stream.char()
        leavingThisState = True
        if data == "=":
            self.state = self.states["tagAttributeValueBefore"]
        elif data == ">":
            # Token is emitted after attributes are checked.
            pass
        elif data in spaceCharacters:
            self.state = self.states["tagAttributeNameAfter"]
        elif data == "/":
            self.state = self.states["emptyTag"]
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
            leavingThisState = False
        else:
            self.currentToken["attributes"][-1][0] += data
            leavingThisState = False

        if leavingThisState:
            # Attributes are not dropped at this stage. That happens when the
            # start tag token is emitted so values can still be safely appended
            # to attributes, but we do want to report the parse error in time.
            for name, value in self.currentToken["attributes"][:-1]:
                if self.currentToken["attributes"][-1][0] == name:
                    # XXX parse error
                    pass
            if data == ">":
                self.emitCurrentToken()
        return True

    def tagAttributeNameAfterState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.stream.charsUntil(spaceCharacters, True)
        elif data == "=":
            self.state = self.states["tagAttributeValueBefore"]
        elif data == ">":
            self.emitCurrentToken()
        elif data == "/":
            self.state = self.states["emptyTag"]
        elif data == ":":
            # XXX parse error
            pass
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        else:
            self.currentToken["attributes"].append([data, ""])
            self.state = self.states["tagAttributeName"]
        return True

    def tagAttributeValueBeforeState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.stream.charsUntil(spaceCharacters, True)
        elif data == "\"":
            self.state = self.states["tagAttributeValueDoubleQuoted"]
        elif data == "'":
            self.state = self.states["tagAttributeValueSingleQuoted"]
        elif data == "&":
            self.stream.queue.append(data);
            self.state = self.states["tagAttributeValueUnquoted"]
        elif data == ">":
            self.emitCurrentToken()
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        else:
            self.currentToken["attributes"][-1][1] += data
            self.state = self.states["tagAttributeValueUnquoted"]
        return True

    def tagAttributeValueDoubleQuotedState(self):
        data = self.stream.char()
        if data == "\"":
            self.state = self.states["tagAttributeNameBefore"]
        elif data == "&":
            entity = self.consumeEntity(True)
            if entity[0] == "Characters":
                self.currentToken["attributes"][-1][1] += entity[1]
            else:
                i = 0
                for x in entity[1]:
                    self.stream.queue.insert(i, x)
                    i += 1
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        else:
            self.currentToken["attributes"][-1][1] += data +\
              self.stream.charsUntil(("\"", "&"))
        return True

    def tagAttributeValueSingleQuotedState(self):
        data = self.stream.char()
        if data == "'":
            self.state = self.states["tagAttributeNameBefore"]
        elif data == "&":
            entity = self.consumeEntity(True)
            if entity[0] == "Characters":
                self.currentToken["attributes"][-1][1] += entity[1]
            else:
                i = 0
                for x in entity[1]:
                    self.stream.queue.insert(i, x)
                    i += 1
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        else:
            self.currentToken["attributes"][-1][1] += data +\
              self.stream.charsUntil(("'", "&"))
        return True

    def tagAttributeValueUnquotedState(self):
        data = self.stream.char()
        if data in spaceCharacters:
            self.state = self.states["tagAttributeNameBefore"]
        elif data == "&":
            entity = self.consumeEntity(True)
            if entity[0] == "Characters":
                self.currentToken["attributes"][-1][1] += entity[1]
            else:
                i = 0
                for x in entity[1]:
                    self.stream.queue.insert(i, x)
                    i += 1
        elif data == ">":
            self.emitCurrentToken()
        elif data == EOF:
            # XXX parse error
            self.emitCurrentToken()
        else:
            self.currentToken["attributes"][-1][1] += data +\
              self.stream.charsUntil(frozenset(("&", ">","<")) | spaceCharacters)
        return True

    # Consume everything up and including > and make it a comment.
    def bogusCommentState(self):
        self.tokenQueue.append({"type": "Comment", "data": self.stream.charsUntil(">")})
        self.stream.char()
        self.state = self.states["data"]
        return True
