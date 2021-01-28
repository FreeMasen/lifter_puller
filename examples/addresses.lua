local xml = [[<?xml version="1.1" encoding="UTF-8"?>
<!-- List of addresses -->
<addresses>
    <address>
        <name>Sherlock Holmes</name>
        <street-address>
            187 North Gower Street
        </street-address>
        <street-address2>
            Kings Cross
        </street-address2>
        <city>London</city>
        <postal-code components="outcode,incode" sep=" ">
            NW1 2NJ
        </postal-code>
        <country>England</country>
    </address>
    <address>
        <name>Balki Bartokomous</name>
        <street-address>
            711 Coldwell St.
        </street-address>
        <street-address2>
            Apt 209
        </street-address2>
        <city>Chicago</city>
        <state>IL</state>
        <postal-code components="zip,plus-four" sep="-">60714-4471</postal-code>
        <country>USA</country>
    </address>
    <address>
        <name>David Rose</name>
        <street-address>
            308399 Hockley Rd
        </street-address>
        <city>Orangeville</city>
        <province>ON</province>
        <postal-code components="fsa,ldu" sep=" ">L9W 2Z2</postal-code>
        <country>CANADA</country>
    </address>
</addresses>
]]

local lftr_pllr = require 'lifter_puller'

local puller = lftr_pllr.Puller.new(xml)

local decl = puller:next()
print(string.format('XML Declaration: version = %s, encoding = %s', decl.version, decl.encoding))


local function assert_eq(lhs, rhs)
    if lhs == rhs then
        return true
    end
    error(string.format('%s ~= %s', lhs, rhs), 2)
end

local comment = puller:next()
assert_eq(comment.ty, lftr_pllr.event_type.comment)

local function extract_node_info(p)
    local node_start = assert(p:next())
    assert_eq(node_start.ty, lftr_pllr.event_type.open_tag)
    local name = node_start.name
    local attrs = {}
    while true do
        local attr_or_end = assert(p:next())
        if attr_or_end.ty == lftr_pllr.event_type.tag_end then
            break
        end
        assert_eq(attr_or_end.ty, lftr_pllr.event_type.attribute)
        attrs[attr_or_end.name] = attr_or_end.value
    end
    local text_node = assert(p:next())
    assert_eq(text_node.ty, lftr_pllr.event_type.text)
    local text = string.match(text_node.text, "^%s*(.-)%s*$")
    local node_end = assert(p:next())
    assert_eq(node_end.ty, lftr_pllr.event_type.close_tag)
    assert_eq(node_end.name, name)
    return {
        name = name,
        attrs = attrs,
        text = text,
    }
end

local function split_string(s, sep)
    sep = sep or '%s'
    local ret = {}
    for part in string.gmatch(s, '([^'..sep .. ']+)') do
        table.insert(ret, part)
    end
    return ret
end

local function extract_postal_code_names(text, parts_attr, sep_attr)
    local ret = {}
    local part_names = split_string(parts_attr, ',')
    local parts = split_string(text, sep_attr)
    for i = 1, #parts do
        ret[part_names[i]] = parts[i]
    end
    return ret
end

local function parse_address(p, open)
    assert_eq(open.ty, lftr_pllr.event_type.open_tag)
    assert_eq(open.name, 'address')
    local address_end = p:next()
    assert_eq(address_end.ty, lftr_pllr.event_type.tag_end)
    local ret = {}
    while true do
        local node = extract_node_info(p)
        local normalized_name = string.gsub(node.name, '-', '_')
        if normalized_name == 'postal_code' then
            ret[normalized_name] = extract_postal_code_names(node.text, node.attrs.components, node.attrs.sep)
        else
            ret[normalized_name] = node.text
            if normalized_name == 'country' then
                break
            end
        end
    end
    local address_end = assert(p:next())
    assert_eq(address_end.ty, lftr_pllr.event_type.close_tag)
    assert_eq(address_end.name, 'address')
    return ret
end

local function parse_addresses(p)
    local addresses_start = assert(p:next())
    assert_eq(addresses_start.ty, lftr_pllr.event_type.open_tag)
    assert_eq(addresses_start.name, 'addresses')
    local addresses_end = assert(p:next())
    assert(addresses_end.ty == lftr_pllr.event_type.tag_end)
    local addresses = {}
    while true do
        local start = p:next()
        if start.ty == lftr_pllr.event_type.close_tag and start.name == 'addresses' then
            break
        end
        table.insert(addresses, parse_address(p, start))
    end
    return addresses
end

local function print_address(address)
    print(address.name)
    print(address.street_address)
    if address.street_address2 ~= nil then
        print(address.street_address2)
    end
    if address.country == 'USA' then
        print(string.format("%s, %s %s", address.city, address.state, address.postal_code.zip))
    elseif address.country == 'UK' then
        print(address.city)
        print(string.format('%s %s', address.postal_code.outcode, address.postal_code.incode))
    elseif address.country == 'CANADA' then
        print(string.format("%s %s %s %s", address.city, address.province, address.postal_code.fsa, address.postal_code.ldu))
    end
    print(address.country)
end

local addresses = parse_addresses(puller)

for _, address in ipairs(addresses) do
    print('-----------')
    print_address(address)
    print('-----------')
end
