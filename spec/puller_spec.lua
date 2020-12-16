local puller = require 'xml-puller'
local event = require 'event'


function _assert(test, ...)
    assert(test, string.format(...))
end

describe('Puller', function ()
    describe('should parse decl', function ()
        it('with all values', function ()
            local p = puller.new('<?xml version="1.2" encoding="utf-8" standalone="no" ?>')
            local e = p:next()
            _assert(e.ty == event.event_type.declaration, 'expected decl found %s', event.ty)
            _assert(e.version == '1.2', 'expected version 1.2 found %s', event.version)
            _assert(e.encoding == 'utf-8', 'expected utf-8 found %s', event.encoding)
            _assert(e.standalone == false, 'expected standalone to be false found %s', event.standalone)
        end)
    end)
end)