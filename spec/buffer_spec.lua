local Buffer = require 'lifter_puller.buffer'
local char_maps = require "spec.char_maps"

describe('Buffer', function ()
    describe('utf-8', function ()
        it('should parse ascii characters', function ()
            local ascii = 'abcdefghijklmnopqrstuvwxyz'
            ascii = ascii .. string.upper(ascii)
            ascii = ascii .. '0123456789`!@#$%^&*()_+=-[]\\|}{;\'":/.,<>?'
            local b = Buffer.new(ascii)
            for ch in string.gmatch(ascii, '.') do
                local i, len = b:next_utf8_int()
                local target = string.byte(ch, 1, 1)
                assert(i == target, string.format('expected byte for %s, found %s expected %s', ch, i, target))
                b:advance(len)
            end
        end)
        it('should parse 2 byte characters', function ()
            local char_map = char_maps.two_byte
            local s = ''
            for key, _ in pairs(char_map) do
                s = s .. key
            end
            local b = Buffer.new(s)
            for ch in string.gmatch(s, '..') do
                local i, len = b:next_utf8_int()
                local bytes = char_map[ch]
                local expected = ((bytes[1] & 63) << 6) | (bytes[2] & 63)
                assert(i, expected)
                b:advance(len)
            end
        end)
        it('should parse 3 byte characters', function ()
            local char_map = char_maps.three_byte
            local s = ''
            for key, _ in pairs(char_map) do
                s = s .. key
            end
            local b = Buffer.new(s)
            for ch in string.gmatch(s, '...') do
                local i, len = b:next_utf8_int()
                local bytes = char_map[ch]
                local expected = ((bytes[1] & 63) << 12) | ((bytes[2] & 63) << 6) | (bytes[3] & 63)
                assert(i, expected)
                b:advance(len)
            end
        end)
        it('should parse 4 byte characters', function ()
            local char_map = char_maps.four_byte
            local s = ''
            for key, _ in pairs(char_map) do
                s = s .. key
            end
            local b = Buffer.new(s)
            for ch in string.gmatch(s, '....') do
                local i, len = b:next_utf8_int()
                local bytes = char_map[ch]
                local expected = ((bytes[1] & 63) << 18) | ((bytes[2] & 63) << 6) | ((bytes[3] & 63) << 6) | (bytes[4] & 63)
                assert(i, expected)
                b:advance(len)
            end
        end)
    end)
    local text = 'asdfqwerzxcv'
    describe('advancing methods', function ()
        it('advance', function ()
            local b = Buffer.new(text)
            assert(b:current_byte() == string.byte('a'))
            assert(b:advance(4))
            assert(b:current_byte() == string.byte('q'))
            assert(b:advance(4))
            assert(b:current_byte() == string.byte('z'))
            assert(b:advance(3))
            assert(b:current_byte() == string.byte('v'))
            assert(not b:advance(1))
        end)
    end)
    describe('consume_str', function ()
        local b = Buffer.new(text)
        local asdf = assert(b:consume_str('asdf'))
        assert(asdf == 'asdf', string.format('expected asdf found "%s"', asdf))
        assert(b:current_byte() == string.byte('q'), string.char(b:current_byte()))
        assert(b:next_byte() == string.byte('w'), string.char(b:next_byte()))
    end)
    describe('consume_while', function ()
        local b = Buffer.new(text)
        local asdf = b:consume_while(function (ch)
            return ch ~= 'q'
        end)
        assert(asdf == 'asdf', asdf)
        local c = b:current_byte()
        local n = b:next_byte()
        assert(c == string.byte('q'), string.char(c))
        assert(n == string.byte('w'), string.char(n))
    end)
end)