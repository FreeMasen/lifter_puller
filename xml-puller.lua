local event = require 'event'

local CONT_MASK = 63

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


function Puller:_parse_quote(q)
    return assert(self:eat(q or '["\']'), string.format('expected %s', q or '" or \''))
end

function Puller:_parse_eq()
    return assert(self:eat('='), 'expected equal sign')
end

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
    self:_advance_buffer(6)
    self:_skip_whitespace()
    assert(self:eat('version'), string.format('expected version found "%s"', string.sub(self._buffer, 1, 7)))
    self:_parse_eq()
    local q = self:_parse_quote()
    local v = assert(self:eat('1%.%d+'), 'expected version number')
    self:_parse_quote(q)
    self:_skip_whitespace()
    local encoding
    if self:eat('encoding') then
        self:_parse_eq()
        local q2 = self:_parse_quote()
        encoding = assert(self:eat('[a-zA-Z]'))
        encoding = encoding .. self:_parse_encoding_trailer()
        self:_parse_quote(q2)
        self:_skip_whitespace()
    end
    local standalone
    if self:eat('standalone') then
        self:_parse_eq()
        local q3 = self:_parse_quote()
        local name = self:_eat_name()
        if name == 'yes' then
            standalone = true
        elseif name == 'no' then
            standalone = false
        end
        assert(standalone ~= nil, 'Invalid value for standalone ' .. name)
        self:_parse_quote(q3)
    end
    self:_skip_whitespace()
    self:eat('%?>')
    return event.Event.decl(v, encoding, standalone)
end

function Puller:_eat_name()
    local at_start, len = self:_at_name_start()
    assert(at_start, 'Invalid name start')
    local ret = self:_advance_buffer(len)
    local at_continue, len = self:_at_name_cont()
    while at_continue do
        ret = ret .. self:_advance_buffer(len)
        at_continue, len = self:_at_name_cont()
    end
    return ret
end

function Puller:_at_name_start()
    local ascii = string.match(self._buffer, '^[a-zA-Z:_]')
    if ascii then
        return true, 1
    end

    local ch, len = self:_next_utf8_int()

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
    local ascii = string.match(self._buffer, '^[a-zA-Z0-9:_%-%.]')
    if ascii then
        return true, 1
    end
    local ch, len = self:_next_utf8_int()
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

function Puller:_next_utf8_int()
    local function acc_cont_byte(acc, b)
        return (acc << 6) | (b & CONT_MASK)
    end
    local byte = string.byte(self._buffer, 1, 1) or 0
    if byte < 128 then
        return byte, 1
    end
    local init = byte & (0x7F >> 2)
    local y = string.byte(self._buffer, 2, 2) or 0
    local ch = acc_cont_byte(init, y)
    if byte < 0xE0 then
        return ch, 2
    end
    local z = string.byte(self._buffer, 3, 3) or 0
    local y_z = acc_cont_byte(y & CONT_MASK, z)
    ch = init << 12 | y_z
    if byte < 0xF0 then
        return ch, 3
    end
    local w = string.byte(self._buffer, 4, 4) or 0
    ch = (init & 7) << 18 | acc_cont_byte(y_z, w)
    return ch, 4
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
        _buffer = buffer,
        depth = 0,
        state = st,
    }
    setmetatable(ret, Puller)
    return ret
end

function Puller:eat(s)
    local s2 = string.match(self._buffer, string.format('^%s', s))

    if s2 then
        self:_advance_buffer(#s2)
        return s2
    end
end

function Puller:_advance_buffer(ct)
    local ret = string.sub(self._buffer, 1, ct)
    self._buffer = string.sub(self._buffer, ct+1)
    return ret
end

function Puller:_skip_whitespace()
    local ws = string.match(self._buffer, "^%s*")
    self:_advance_buffer(#ws)
    return #ws
end

function Puller:_complete_string(quote)
    local after = string.sub(self._buffer, 2)
    local _, end_idx = string.find(after, quote)
    return string.sub(self._buffer, 1, end_idx)
end

---Fetch the next full block of non-whitespace
function Puller:_next_block(target_end)
    target_end = target_end or "^[^%s]+"
    -- Look ahead 1 char to see if we are starting
    -- a string because that would mean we need to look
    -- for the companion quote symbol and not whitespace
    -- as the terminator of the block
    local next_char = string.sub(self._buffer, 1, 2);
    if next_char == '"' or next_char == '\'' then
        local s = self._complete_string(next_char)
        self:_advance_buffer(#s)
        return s
    else
        local s = string.match(self._buffer, "^[^%s]+")
        self:_advance_buffer(#s)
        return s
    end
end

function Puller:next()
    self:_skip_whitespace()
    if self.state == state.declaration then
        self.state = state.after_declaration
        if string.find(self._buffer, '<%?xml') then
            return self:_parse_decl(self)
        else
            return self:next()
        end
    end
end



return Puller