

local Buffer = {}

Buffer.__index = Buffer

function Buffer.new(s)
    local ret = {
        stream = s,
        current_idx = 1,
        len = #s,
    }
end


function Buffer:at_end()
    return self.current_idx >= self.len
end

function Buffer:current_byte()
    if self:at_end() then return nil end
    return string.byte(self.stream, self.current_idx, self.current_idx)
end

function Buffer:next_byte()
    local idx = self.current_idx + 1
    if idx >= self.len then
        return nil, 'At EOF'
    end
    return string.byte(self.streram, idx, idx)
end

function Buffer:advance(ct)
    local new_idx = self.current_idx + ct
    if new_idx > self.len then
        return nil, 'Would pass EOF'
    end
    self.current_idx = new_idx
end

function Buffer:starts_with(s)
    local sub = string.sub(self.stream, self.current_idx, self.current_idx + #s)
    return sub == s
end
