#! /usr/bin/lua
require 'DataDumper'   -- http://lua-users.org/wiki/DataDumper
------------------------ test infrastructure --------------------
local function warn(str)
    io.stderr:write(str,'\n')
end
local function die(str)
    io.stderr:write(str,'\n')
    os.exit(1)
end
local function equals(t1,t2)
    if DataDumper(t1) == DataDumper(t2) then return true else return false end
end
local function readOnly(t)  -- Programming in Lua, page 127
    local proxy = {}
    local mt = {
        __index = t,
        __newindex = function (t, k, v)
            die("attempt to update a read-only table")
        end
    }
    setmetatable(proxy, mt)
    return proxy
end
local function deepcopy(object)  -- http://lua-users.org/wiki/CopyTable
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end

local Test = 20 ; local i_test = 0; local Failed = 0;
function ok(b,s)
    i_test = i_test + 1
    if b then
        io.write('ok '..i_test..' - '..s.."\n")
    else
        io.write('not ok '..i_test..' - '..s.."\n")
        Failed = Failed + 1
    end
end
-------------------------------------------------------------
ALSA = require 'midialsa'

function fwrite (fmt, ...)
	return io.write(string.format(fmt, ...))
end

warn('# This test script is not very portable: it depends')
warn('# on virmidi ports on 24:0 and 25:0, for example...')

rc = ALSA.inputpending()
ok(rc==0, "inputpending() with no client returned "..tostring(rc))

rc = ALSA.client('test_a.lua',2,2,1)
ok(rc, "client('test_a.lua',2,2,1)")

rc = ALSA.connectfrom(1,24,0)
ok(rc, 'connectfrom(1,24,0)')

rc = ALSA.connectfrom(1,133,0)
ok(not rc, 'connectfrom(1,133,0) correctly reported failure')

rc = ALSA.connectto(2,25,0)
ok(rc, 'connectto(2,25,0)')

rc = ALSA.connectto(1,133,0)
ok(not rc, 'connectto(1,133,0) correctly reported failure')

rc = ALSA.start()
ok(rc, 'start()')

fd = ALSA.fd()
ok(fd > 0, 'fd()')

id = ALSA.id()
ok(id > 0, 'id() returns '..id)

local inp = assert(io.open('/dev/snd/midiC2D0','wb'))  -- client 24
local oup = assert(io.open('/dev/snd/midiC2D1','rb'))  -- client 25

warn('# feeding ourselves a patch_change event...')
assert(inp:write(string.char(12*16, 99))) -- {'patch_change',0,0,99}
assert(inp:flush())
rc =  ALSA.inputpending()
ok(rc > 0, 'inputpending() returns '..rc)
local alsaevent  = ALSA.input()
correct = {11, 1, 0, 1, 300, {24,0}, {id,1}, {0, 0, 0, 0, 0, 99} }
alsaevent[5] = 300
ok(equals(alsaevent, correct), 'input() returns {11,1,0,1,300,{24,0},{id,1},{0,0,0,0,0,99}}')
local e = ALSA.alsa2scoreevent(alsaevent)
correct = {'patch_change',300000,0,99}
ok(equals(e, correct), 'alsa2scoreevent() returns {"patch_change",300000,0,99}')

warn('# feeding ourselves a control_change event...')
assert(inp:write(string.char(11*16+2,10,103))) -- {'control_change',3,2,10,103}
assert(inp:flush())
rc =  ALSA.inputpending()
local alsaevent  = ALSA.input()
correct = {10, 1, 0, 1, 300, {24,0}, {id,1}, {2, 0, 0, 0,10,103} }
alsaevent[5] = 300
ok(equals(alsaevent, correct), 'input() returns {10,1,0,1,300,{24,0},{id,1},{2,0,0,0,10,103}}')
local e = ALSA.alsa2scoreevent(alsaevent)
correct = {'control_change',300000,2,10,103}
ok(equals(e, correct), 'alsa2scoreevent() returns {"control_change",300000,2,10,103}')

warn('# feeding ourselves a note_on event...')
assert(inp:write(string.char(9*16, 60,101))) -- {'note_on',0,60,101}
assert(inp:flush())
rc =  ALSA.inputpending()
local alsaevent  = ALSA.input()
local save_time = alsaevent[5]
correct = { 6, 1, 0, 1, 300, { 24, 0 }, { 129, 1 }, { 0, 60, 101, 0, 0 } }
alsaevent[5] = 300
alsaevent[8][5] = 0
ok(equals(alsaevent, correct), 'input() returns {6,1,0,1,300,{24,0},{id,1},{0,60,101,0,0}}')
local opusevent = ALSA.alsa2opusevent(alsaevent)
opusevent[2] = 300000
correct = {'note_on',300000,0,60,101}
ok(equals(opusevent, correct), 'alsa2opusevent() returns {"note_on",300000,0,60,101}')

warn('# feeding ourselves a note_off event...')
assert(inp:write(string.char(8*16, 60,101))) -- {'note_off',0,60,101}
assert(inp:flush())
rc =  ALSA.inputpending()
local alsaevent  = ALSA.input()
local save_time = alsaevent[5]
correct = { 7, 1, 0, 1, 300, { 24, 0 }, { 129, 1 }, { 0, 60, 101, 0, 0 } }
alsaevent[5] = 300
alsaevent[8][5] = 0
ok(equals(alsaevent, correct), 'input() returns {7,1,0,1,300,{24,0},{id,1},{0,60,101,0,0}}')
--print('alsaevent='..DataDumper(alsaevent))
local opusevent = ALSA.alsa2opusevent(alsaevent)
--print('opusevent='..DataDumper(opusevent))
opusevent[2] = 300000
correct = {'note_off',300000,0,60,101}
ok(equals(opusevent, correct), 'alsa2opusevent() returns {"note_off",300000,0,60,101}')

warn('# outputting a patch_change event...')
correct = {11, 1, 0, 1, 0.5, {24,0}, {id,1}, {0, 0, 0, 0, 0, 99} }
rc =  ALSA.output(correct)
bytes = assert(oup:read(2))
-- warn('# bytes = '..string.format('%d %d',string.byte(bytes),string.byte(bytes,2)))
ok(equals(bytes, string.char(12*16, 99)), 'patch_change event detected')

warn('# outputting a control_change event...')
correct = {10, 1, 0, 1, 1.5, {24,0}, {id,1}, {2, 0, 0, 0,10,103} }
rc =  ALSA.output(correct)
bytes = assert(oup:read(3))
-- warn('# bytes = '..string.format('%d %d',string.byte(bytes),string.byte(bytes,2)))
ok(equals(bytes, string.char(11*16+2,10,103)), 'control_change event detected')

warn('# outputting a note_on event...')
correct = { 6, 1, 0, 1, 2.0, { 24, 0 }, { id, 1 }, { 0, 60, 101, 0, 0 } }
rc =  ALSA.output(correct)
bytes = assert(oup:read(3))
--warn('# bytes = '..string.format('%d %d %d',string.byte(bytes),string.byte(bytes,2),string.byte(bytes,3)))
ok(equals(bytes, string.char(9*16, 60,101)), 'note_on event detected')

warn('# outputting a note_off event...')
correct = { 7, 1, 0, 1, 2.5, { 24, 0 }, { id, 1 }, { 0, 60, 101, 0, 0 } }
rc =  ALSA.output(correct)
bytes = assert(oup:read(3))
--warn('# bytes = '..string.format('%d %d %d',string.byte(bytes),string.byte(bytes,2),string.byte(bytes,3)))
ok(equals(bytes, string.char(8*16, 60,101)), 'note_off event detected')

warn('# running  aconnect -d 24 '..id..':1 ...')
os.execute('aconnect -d 24 '..id..':1')
rc =  ALSA.inputpending()
local alsaevent  = ALSA.input()
ok(alsaevent[1] == ALSA.SND_SEQ_EVENT_PORT_UNSUBSCRIBED, 'SND_SEQ_EVENT_PORT_UNSUBSCRIBED event received')

rc = ALSA.stop()
ok(rc,'stop() returns success')
