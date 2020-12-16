local event_type = {
    declaration = 'Declaration',
    open_tag = 'OpenTag',
    close_tag = 'CloseTag',
    tag_end = 'TagEnd',
    attribute = 'Attribute',
    c_data = 'CData',
    comment = 'Comment',
    processing_instruction = 'ProcessingInstruction',
    doctype_start = 'DocTypeStart',
    doctype = 'DocType',
    entity_declaration = 'EntityDeclaration',
    doctype_end = 'DocTypeEnd',
    cdata = "CData",
}

local Event = {}

Event.__index = Event

local function _create(e)
    setmetatable(e, Event)
    return e
end

function Event.decl(version, encoding, standalone)
    return _create{
        ty = event_type.declaration,
        version = version,
        encoding = encoding,
        standalone = standalone,
    }
end

function Event.pi(target, content)
    return _create{
        ty = event_type.processing_instruction,
        target = target,
        content = content,
    }
end

function Event.comment(text)
    return _create{
        ty = event_type.comment,
        text = text,
    }
end

function Event.doctype_start(name, external_id, external_value)
    return _create{
        ty = event_type.doctype_start,
        name = name,
        external_id = external_id,
        external_value = external_value,
    }
end

function Event.empty_doctype(name, external_id, external_value)
    return _create{
        ty = event_type.doctype,
        name = name,
        external_id = external_id,
        external_value = external_value,
    }
end

function Event.entity_declaration(name, external_id, external_value, ndata)
    return _create{
        ty = event_type.entity_declaration,
        name = name,
        external_id = external_id,
        external_value = external_value,
        ndata = ndata,
    }
end

function Event.doctype_end()
    return _create{
        ty = event_type.doctype_end
    }
end

function Event.open_tag(prefix, name)
    return _create{
        ty = event_type.open_tag,
        prefix = prefix,
        name = name,
    }
end

function Event.attr(prefix, name, value)
    return  _create{
        ty = event_type.attribute,
        prefix = prefix,
        name = name,
        value = value
    }
end

function Event.close_tag(prefix, name)
    return _create{
        ty = event_type.close_tag,
        prefix = prefix,
        name = name,
    }
end

function Event.tag_end(is_empty)
    return _create{
        ty = event_type.tag_end,
        is_empty = is_empty,
    }
end

function Event.cdata(text)
    return _create{
        ty = event_type.cdata,
        text = text,
    }
end

return {
    Event = Event,
    event_type = event_type,
}
