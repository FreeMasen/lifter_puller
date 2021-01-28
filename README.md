# Lifter Puller

An xml pull parser in pure lua

## About

An [XML Pull Parser](http://www.extreme.indiana.edu/xgws/xsoap/xpp/) is a method for parsing XML in an ergonomic
and flexible way. Since XML is so flexible, this kind of parser is incredibly useful for building protocol parsers
on top of. The basic structure for any pull parser is driven by the user, each time the user wants to move forward
in the document they will "pull out" the next event. An event has a type and properties dependant on that type. For
example an XML node with attributes like `<a attr="thing" />` would consist of 3 events. 

1. `{ ty = 'OpenTag', name = 'a' }`
1. `{ ty = 'Attribute', name = 'attr', value = 'thing' }`
1. `{ ty = 'TagEnd', is_empty = true }`

This format provides the flexibility to build protocol specific parsing on top
of this Pull Parser. The [Below example](#Puller) should provide an idea of
what protocol specific parsing might look like.

## Installation

```sh$
lua rocks install lifter_puller
```
## Usage

### Puller

The protocol for this example is defined as the following

- The top level node should be a list of addressed named `<addresses>`
- Each child node of `<addresses>` should be an `<address>` node
- An `<address>` node should have the following child nodes in the following order
    - `<name>` required
    - `<street-address>` required
    - `<street-address2>` optional
    - `<city>` required
    - `<state>` optional
    - `<province>` optional
    - `<postal-code>` required
        - `components` attribute should define the parts of the postal code
        - `sep` should provide the separator used to break the parts in `components` up
    - `country` required

```lua
---@lang xml
local xml = [[<?xml version="1.1" encoding="UTF-8"?>
<!-- List of addresses -->
<addresses>
    <address>
        <name>Sherlock Holmes</name>
        <street-address>
            187 North Gower Street
        </street-address>
        <city>London</city>
        <postal-code components="outcode,incode" sep=" ">
            NW1 2NJ
        </postal-code>
        <country>England</country>
    </address>
    <address>
        <name>Balki Bartokomous</name>
        <street-address>
            1100 S Main St.
        </street-address>
        <street-address2>
            Apt 209
        </street-address2>
        <city>Los Angeles</city>
        <state>CA</state>
        <postal-code components="zip,plus-four" sep="-">90015-4858</postal-code>
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


---Check two pieces of data for equality, raising an error if not equal
---similar to assert(lhs == rhs) but with a built in error message
---@param lhs any
---@param rhs any
---@return boolean
local function assert_eq(lhs, rhs)
    if lhs == rhs then
        return true
    end
    error(string.format('%s ~= %s', lhs, rhs), 2)
end

local puller = lftr_pllr.Puller.new(xml)

-- Our first event is going to be the xml declaration
local decl = puller:next()
assert_eq(decl.ty, lftr_pllr.event_type.declaration)
assert_eq(decl.version, '1.1')
assert_eq(decl.encoding, 'UTF-8')

-- Our second event is going to be a comment
local comment = puller:next()
assert_eq(comment.ty, lftr_pllr.event_type.comment)

---Extract the contents of a node into a table
---@param p lftr_pllr.Puller
---@return table
local function extract_node_info(p)
    local node_start = assert(p:next())
    -- first make sure we are at an open tag like <name
    assert_eq(node_start.ty, lftr_pllr.event_type.open_tag)
    local name = node_start.name
    local attrs = {}
    while true do
        local attr_or_end = assert(p:next())
        -- If we are at > then we want to stop looking for attributes
        if attr_or_end.ty == lftr_pllr.event_type.tag_end then
            break
        end
        assert_eq(attr_or_end.ty, lftr_pllr.event_type.attribute)
        -- Put the name="value" into the table of attributes
        attrs[attr_or_end.name] = attr_or_end.value
    end
    local text_node = assert(p:next())
    -- All of our nodes have text inside
    assert_eq(text_node.ty, lftr_pllr.event_type.text)
    -- trim the leading/trailing whitespace
    local text = string.match(text_node.text, "^%s*(.-)%s*$")
    local node_end = assert(p:next())
    -- We should now be at a close tag, and that close tag should
    -- have the same name we started with
    assert_eq(node_end.ty, lftr_pllr.event_type.close_tag)
    assert_eq(node_end.name, name)
    return {
        name = name,
        attrs = attrs,
        text = text,
    }
end

---Split a string on a seperator into a list of strings
---@param s string The string to split
---@param sep string|nil The seperator to use (%s if not provided)
---@return string[]
local function split_string(s, sep)
    sep = sep or '%s'
    local ret = {}
    for part in string.gmatch(s, '([^'..sep .. ']+)') do
        table.insert(ret, part)
    end
    return ret
end

---Extract the postal code components and their values from the attributes
--- on a <postal_code> elements
---@param text string The contents of the node
---@param parts_attr string The value from the `components` attribute
---@param sep_attr string The value from the `sep` attribute
---@return PostalCode
local function extract_postal_code_names(text, parts_attr, sep_attr)
    ---@class PostalCode
    ---@field zip string US Postal Code Start
    ---@field plus_four string|nil US Postal Code End
    ---@field fsa string CA Postal Code Start
    ---@field ldu string CA Postal Code End
    ---@field incode string UK Postal Code End
    ---@field outcode string UK Postal Code End
    local ret = {}
    local part_names = split_string(parts_attr, ',')
    local parts = split_string(text, sep_attr)
    for i = 1, #parts do
        ret[part_names[i]] = parts[i]
    end
    return ret
end

---Parse the xml contents of a single <address> node into an address table
---@param p lftr_pllr.Puller
---@param open lftr_pllr.Event The event that opened this <address> node
---@return Address
local function parse_address(p, open)
    assert_eq(open.ty, lftr_pllr.event_type.open_tag)
    assert_eq(open.name, 'address')
    local address_end = p:next()
    assert_eq(address_end.ty, lftr_pllr.event_type.tag_end)
    ---@class Address
    ---@field name string
    ---@field street_address string
    ---@field street_address2 string|nil
    ---@field city string
    ---@field state string|nil
    ---@field province string|nil
    ---@field postal_code PostalCode
    ---@field country string
    local ret = {}
    while true do
        local node = extract_node_info(p)
        -- update add names to have _ instead of -
        local normalized_name = string.gsub(node.name, '-', '_')
        if normalized_name == 'postal_code' then
            ret[normalized_name] = extract_postal_code_names(node.text, node.attrs.components, node.attrs.sep)
        else
            ret[normalized_name] = node.text
            -- country is the last element in our address nodes
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

---Parse a single html <address> node's contents into a table
---@param p lftr_pllr.Puller
---@return Address[]
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

--- Print an address table in the appropriate format for the country
---@param address Address the address table to be printed
local function print_address(address)
    print(address.name)
    print(address.street_address)
    if address.street_address2 ~= nil then
        print(address.street_address2)
    end
    if address.country == 'USA' then
        print(string.format("%s, %s %s", address.city, address.state, address.postal_code.zip))
    elseif address.country == 'England' then
        print(string.upper(address.city))
        print(string.format('%s %s', address.postal_code.outcode, address.postal_code.incode))
        print('UNITED KINGDOM')
        return
    elseif address.country == 'CANADA' then
        print(string.format("%s %s %s %s", address.city, address.province, address.postal_code.fsa, address.postal_code.ldu))
    end
    print(address.country)
end

-- parse the addresses into a list
local addresses = parse_addresses(puller)

--- print each address to the console
for _, address in ipairs(addresses) do
    print('-----------')
    print_address(address)
    print('-----------')
end

```

when run would output the following

```sh
-----------
Sherlock Holmes
187 North Gower Street
LONDON
NW1 2NJ
UNITED KINGDOM
-----------
-----------
Balki Bartokomous
1100 S Main St.
Apt 209
Los Angeles, CA 90015
USA
-----------
-----------
David Rose
308399 Hockley Rd
Orangeville ON L9W 2Z2
CANADA
-----------
```

### Iterator

This library also provides an iterator interface as a function named `events`.

Here is an example of how this works:

```lua
local events = require 'lifter_puller.init'.events

for ev in events('<?xml version="1.1" encoding="UTF-8"?><p>hi</p>') do
    print(ev.ty)
end
```

When run would print the following:

```sh
Declaration
OpenTag
TagEnd
Text
CloseTag
```