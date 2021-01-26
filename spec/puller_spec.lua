local puller = require 'xml-puller'
local event = require 'event'


function _assert(test, ...)
    if not test then
        error(string.format(...), 2)
    end
end

describe('Puller', function ()
    describe('should parse decl', function ()
        it('with all values', function ()
            local p = puller.new('<?xml version="1.2" encoding="utf-8" standalone="no" ?>')
            local e = assert(p:next())
            _assert(e.ty == event.event_type.declaration, 'expected decl found %s', e.ty)
            _assert(e.version == '1.2', 'expected version 1.2 found %s', e.version)
            _assert(e.encoding == 'utf-8', 'expected utf-8 found %s', e.encoding)
            _assert(e.standalone == false, 'expected standalone to be false found %s', e.standalone)
        end)
    end)
    describe('should parse doctype', function()
        it('empty with all values', function ()
            local p = puller.new('<!DOCTYPE name PUBLIC "first_value" "second_value">')
            local e = assert(p:next())
            _assert(e.ty == event.event_type.doctype, 'expected empty doctype, found %s', e.ty)
            _assert(e.name == 'name', 'expected name of name found "%s"', e.name)
            _assert(e.external_id == 'PUBLIC', 'expected external_id of PUBLIC found "%s"', e.external_id)
            _assert(e.external_value[1] == 'first_value', 'expected external value first_value found "%s"', e.external_value[2])
            _assert(e.external_value[2] == 'second_value', 'expected external value second_value found "%s"', e.external_value[2])
        end)
        it('empty with SYSTEM', function ()
            local p = puller.new('<!DOCTYPE name SYSTEM "first_value">')
            local e = assert(p:next())
            _assert(e.ty == event.event_type.doctype, 'expected empty doctype, found %s', e.ty)
            _assert(e.name == 'name', 'expected name of name found "%s"', e.name)
            _assert(e.external_id == 'SYSTEM', 'expected external_id of SYSTEM found "%s"', e.external_id)
            _assert(e.external_value[1] == 'first_value', 'expected external value first_value found "%s"', e.external_value[2])
        end)
        it('not empty, one entity, not system or public', function ()
            local p = puller.new([[<!DOCTYPE svg [
                <!ENTITY name "value">
            ]>]])
            local e1 = assert(p:next())
            _assert(e1.ty == event.event_type.doctype_start, 'expected %s found %s', event.event_type.doctype_start, e1.ty)
            _assert(e1.name == 'svg', 'expecte svg found %s', e1.name)
            _assert(e1.external_id == nil, 'expecte nil found %s', e1.external_id)
            _assert(#e1.external_value == 0, 'expecte 0 found %s', #e1.external_value)
            local e2 = assert(p:next())
            _assert(e2.ty == event.event_type.entity_declaration, 'expected %s found %s', event.event_type.entity_declaration, e2.ty)
            _assert(e2.name == 'name', 'Expected name found `%s`', e2.name)
            _assert(e2.external_value == 'value', 'expected value found `%s`', e2.external_value)

        end)
        it('not empty, entity, system and public', function ()
            local p = puller.new([[<!DOCTYPE svg [
                <!ENTITY system SYSTEM "system_value">
                <!ENTITY public PUBLIC "public_value1" "public_value2">
            ]>]])
            local e1 = assert(p:next())
            _assert(e1.ty == event.event_type.doctype_start, 'expected %s found %s', event.event_type.doctype_start, e1.ty)
            _assert(e1.name == 'svg', 'expecte svg found %s', e1.name)
            _assert(e1.external_id == nil, 'expecte nil found %s', e1.external_id)
            _assert(#e1.external_value == 0, 'expecte 0 found %s', #e1.external_value)
            local e2 = assert(p:next())
            _assert(e2.ty == event.event_type.entity_declaration, 'expected %s found %s', event.event_type.entity_declaration, e2.ty)
            _assert(e2.external_id == 'SYSTEM', 'Expected SYSTEM found `%s`', e2.external_id)
            _assert(e2.name == 'system', 'Expected system found `%s`', e2.name)
            _assert(e2.external_value[1] == 'system_value', 'expected system_value found `%s`', e2.external_value[1])
            local e3 = assert(p:next())
            _assert(e3.ty == event.event_type.entity_declaration, 'expected %s found %s', event.event_type.entity_declaration, e2.ty)
            _assert(e3.name == 'public', 'Expected system found `%s`', e3.name)
            _assert(e3.external_id == 'PUBLIC', 'Expected PUBLIC found `%s`', e3.external_id)
            _assert(e3.external_value[1] == 'public_value1', 'expected public_value1 found `%s`', e3.external_value[1])
            _assert(e3.external_value[2] == 'public_value2', 'expected public_value2 found `%s`', e3.external_value[2])
            local e4 = assert(p:next())
            _assert(e4.ty == event.event_type.doctype_end, 'expected %s found %s', event.event_type.doctype_end, e4.ty)
        end)
    end)
    describe('should parse comments', function()
        it('single line comment', function()
            local p = puller.new('<!-- This is a comment! -->')
            local e = assert(p:next())
            _assert(e.ty == event.event_type.comment, 'expected comment found %s', e.ty)
            _assert(e.text == ' This is a comment! ', 'bad comment text found "%s"', e.text)
        end)
    end)
    describe('should parse processing instruction', function()
        it('with content', function()
            local p = puller.new('<?target content?>')
            local e = assert(p:next())
            _assert(e.ty == event.event_type.processing_instruction, 'expected pi found %s', e.ty)
            _assert(e.target == 'target', 'bad target found "%s"', e.target)
            _assert(e.content == 'content', 'bad content found "%s"', e.content)
        end)
        it('without content', function()
            local p = puller.new('<?target?>')
            local e = assert(p:next())
            _assert(e.ty == event.event_type.processing_instruction, 'expected pi found %s', e.ty)
            _assert(e.target == 'target', 'bad target found "%s"', e.target)
            _assert(e.content == nil, 'bad content found "%s"', e.content)
        end)
    end)
    describe('should parse cdata', function ()
        local p = puller.new('<p><![CDATA[cdata]]></p>')
        local e1 = assert(p:next())
        _assert(e1.ty == event.event_type.open_tag, '')
        _assert(e1.name == 'p', 'expected `p` found `%s`', e1.name)
        local e2 = assert(p:next())
        _assert(e2.ty == event.event_type.tag_end, 'expected %s found %s', event.event_type.tag_end, e2.ty)
        local e3 = assert(p:next())
        _assert(e3.ty == event.event_type.cdata, 'expecting %s found %s', event.event_type.tag_end, e3.ty)
        _assert(e3.text == 'cdata', 'expected cdata found %s', e3.text)
        local e4 = assert(p:next())
        _assert(e4.ty == event.event_type.close_tag, 'Expected %s, found `%s`', event.event_type.close_tag, e4.ty)
        _assert(e4.name == 'p', 'exepected p found `%s`', e4.name)
    end)
end)