local event = require 'event'
local Buffer = require 'buffer'


local Puller = {}


Puller.__index = Puller

local state = {
    declaration = 'Declaration',
    after_declaration = 'AfterDeclaration',
    doctype = 'Doctype',
    after_doctype = 'AfterDoctype',
    elements = 'Elements',
    attributes = 'Attributes',
    after_elements = 'AfterElements',
    done = 'End',
}

--- parse any number of letters, numbers, periods
--- underscores followed by a single `-` recursivly
function Puller:_parse_encoding_trailer()
    local s = self:eat('[a-zA-Z0-9._]*')
    local s2 = self:eat('-') or ''
    if not s or s == '' and not s2 then return '' end
    if not s2 then return s end
    if not s or s == '' then return s2 end
    return s .. s2 .. self:_parse_encoding_trailer()
end

function Puller:_parse_decl()
    self:_advancebuffer(6)
    self:_skip_whitespace()
    if not self:eat('version') then
        return nil, 'expected `version`'
    end
    if not self:eat('=') then
        return nil, 'expected = found ' .. string.char(self.buffer:current_byte())
    end
    local q = self:eat('\'') or self:eat('"')
    if not q then
        return nil, 'version must be quoted ' .. string.char(self.buffer:current_byte())
    end
    local v = self.buffer:consume_str('1%.%d+')
    if not v then
        return nil, 'expected version number'
    end
    self:eat(q)
    self:_skip_whitespace()
    local encoding
    if self:eat('encoding') then
        self:_parse_eq()
        local q2 = self:_parse_quote()
        local e
        encoding, e = self:eat('[a-zA-Z]')
        if not encoding then
            return nil, e
        end
        encoding = encoding .. self:_parse_encoding_trailer()
        self:_parse_quote(q2)
        self:_skip_whitespace()
    end
    local standalone
    if self:eat('standalone') then
        self:_parse_eq()
        local q3 = self:_parse_quote()
        if self:eat('yes') then
            standalone = true
        elseif self:eat('no') then
            standalone = false
        end
        if standalone == nil then
            return nil, 'Invalid value for standalone'
        end
        self:eat(q3)
    end
    self:_skip_whitespace()
    self:eat('%?>')
    return event.Event.decl(v, encoding, standalone)
end

function Puller:parse_doctype()
    self.buffer:advance(9)
    self:_skip_whitespace()
    local name = self:_eat_name()
    self:_skip_whitespace()
    local external_id, lit1, lit2
    if self.buffer:starts_with('SYSTEM') or self.buffer:starts_with('PUBLIC') then
        external_id, lit1, lit2 = self:parse_external_id()
    end
    self:_skip_whitespace()
    local current_char = self.buffer:current_char()
    if current_char ~= '>' and current_char ~= '[' then
        return nil, 'Expected > or [ in doctype found ' .. current_char
    end
    self.buffer:advance(1)
    local external_value = {}
    if not lit1 and not lit2 then
        external_value = nil
        external_value = {lit1, lit2}
    end
    if lit1 then table.insert(external_value, lit1) end
    if lit2 then table.insert(external_value, lit2) end
    if current_char == '[' then
        return event.Event.doctype_start(name, external_id, external_value)
    end
    return event.Event.empty_doctype(name, external_id, external_value)
end

function Puller:parse_comment()
    self.buffer:advance(4)
    local content = self.buffer:consume_until('-->')
    self.buffer:advance(3)
    return event.Event.comment(content)
end

function Puller:parse_pi()
    self.buffer:advance(2)
    local target = self:_eat_name()
    self:_skip_whitespace()
    local content = self.buffer:consume_until('?>')
    if content == '' then
        content = nil
    end
    return event.Event.pi(target, content)
end

function Puller:parse_external_id()
    local id = self.buffer:advance(6)
    self:_skip_whitespace()
    local q = self:_parse_quote()
    local lit1 = self.buffer:consume_while(function(s) return s ~= q end)
    self:_parse_quote(q)
    if id == 'SYSTEM' then
        return id, lit1
    else
        self:_skip_whitespace()
        local q2 = self:_parse_quote()
        local lit2 = self.buffer:consume_while(function(s) return s ~= q end)
        self:_parse_quote(q2)
        return id, lit1, lit2
    end
end

function Puller:_parse_quote(q)
    return assert(self:eat(q or '["\']'), string.format('expected %s found: %s', q or '" or \'', self.buffer:current_char()))
end

function Puller:_parse_eq()
    return assert(self:eat('='), 'expected equal sign')
end


function Puller:_eat_name()
    local at_start, len = self:_at_name_start()
    assert(at_start, 'Invalid name start')
    local ret = self.buffer:advance(len)
    local at_continue, len = self:_at_name_cont()
    while at_continue do
        ret = ret .. self.buffer:advance(len)
        at_continue, len = self:_at_name_cont()
    end
    return ret
end

function Puller:_at_name_start()
    if self.buffer:starts_with('[a-zA-Z:_]') then
        return true, 1
    end

    local ch, len = self.buffer:next_utf8_int()

    return ((ch >= 0x0000C0 and ch <= 0x0000D6)
        or (ch >= 0x0000D8 and ch <= 0x0000F6)
        or (ch >= 0x0000F8 and ch <= 0x0002FF)
        or (ch >= 0x000370 and ch <= 0x00037D)
        or (ch >= 0x00037F and ch <= 0x001FFF)
        or (ch >= 0x00200C and ch <= 0x00200D)
        or (ch >= 0x002070 and ch <= 0x00218F)
        or (ch >= 0x002C00 and ch <= 0x002FEF)
        or (ch >= 0x003001 and ch <= 0x00D7FF)
        or (ch >= 0x00F900 and ch <= 0x00FDCF)
        or (ch >= 0x00FDF0 and ch <= 0x00FFFD)
        or (ch >= 0x010000 and ch <= 0x0EFFFF)), len
end

function Puller:_at_name_cont()
    if self.buffer:starts_with('[a-zA-Z0-9:_%-%.]') then
        return true, 1
    end
    local ch, len = self.buffer:next_utf8_int()
    return (ch == 0x0000B7
        or (ch >= 0x0000C0 and ch <= 0x0000D6)
        or (ch >= 0x0000D8 and ch <= 0x0000F6)
        or (ch >= 0x0000F8 and ch <= 0x0002FF)
        or (ch >= 0x000300 and ch <= 0x00036F)
        or (ch >= 0x000370 and ch <= 0x00037D)
        or (ch >= 0x00037F and ch <= 0x001FFF)
        or (ch >= 0x00200C and ch <= 0x00200D)
        or (ch >= 0x00203F and ch <= 0x002040)
        or (ch >= 0x002070 and ch <= 0x00218F)
        or (ch >= 0x002C00 and ch <= 0x002FEF)
        or (ch >= 0x003001 and ch <= 0x00D7FF)
        or (ch >= 0x00F900 and ch <= 0x00FDCF)
        or (ch >= 0x00FDF0 and ch <= 0x00FFFD)
        or (ch >= 0x010000 and ch <= 0x0EFFFF)), len
end

function Puller:_parse_name_cont()
    return assert(self:eat('[]+'))
end

function Puller.new(buffer, buffer_is_fragment)
    local st = state.declaration
    if buffer_is_fragment then
        st = state.elements
    end
    local ret = {
        ---@type string
        buffer = Buffer.new(buffer),
        depth = 0,
        state = st,
    }
    setmetatable(ret, Puller)
    return ret
end

function Puller:eat(s)
    return self.buffer:consume_str(s)
end

function Puller:_advancebuffer(ct)
    return self.buffer:advance(ct)
end

function Puller:_skip_whitespace()
    self.buffer:skip_whitespace()
end

function Puller:_complete_string(quote)
    local after = string.sub(self.buffer, 2)
    local _, end_idx = string.find(after, quote)
    return string.sub(self.buffer, 1, end_idx)
end

---Fetch the next full block of non-whitespace
function Puller:_next_block(target_end)
    target_end = target_end or "^[^%s]+"
    -- Look ahead 1 char to see if we are starting
    -- a string because that would mean we need to look
    -- for the companion quote symbol and not whitespace
    -- as the terminator of the block
    local next_char = string.sub(self.buffer, 1, 2);
    if next_char == '"' or next_char == '\'' then
        local s = self._complete_string(next_char)
        self:_advancebuffer(#s)
        return s
    else
        local s = string.match(self.buffer, "^[^%s]+")
        self:_advancebuffer(#s)
        return s
    end
end

function Puller:next()
    self:_skip_whitespace()
    if self.state == state.declaration then
        self.state = state.after_declaration
        if self.buffer:starts_with('<%?xml') then
            return self:_parse_decl(self)
        else
            return self:next()
        end
    elseif self.state == state.after_declaration then
        if self.buffer:starts_with('<!DOCTYPE') then
            local tok, err = self:parse_doctype()
            if not tok then
                return tok, err
            end
            if tok.ty == event.event_type.doctype then
                self.state = state.doctype
            elseif tok.ty == event.event_type.doctype_start then
                self.state = state.after_doctype
            else
                return nil, 'Invalid doctype'
            end
            return tok, err
        elseif self.buffer:starts_with('<!--') then
            return self:parse_comment()
        elseif self.buffer:starts_with('<?') then
            if self.buffer:starts_with('<?xml') then
                return nil, string.format('Invalid decl @ %s', self.current_idx) 
            end
            return self:parse_pi()
        else
            self.state = state.after_declaration
            return self:next()
        end
    end
end



return Puller