---------------------------------------------------------------------
--     This Lua5 module is Copyright (c) 2011, Peter J Billam      --
--                       www.pjb.com.au                            --
--                                                                 --
--  This module is free software; you can redistribute it and/or   --
--         modify it under the same terms as Lua5 itself.          --
---------------------------------------------------------------------
-- This module is a translation into Lua by Peter Billam
-- of the alsaseq and alsamidi Python modules by Patricio Paez.
-- The calling interface is reasonably identical.

-- see: pydoc3 alsaseq ;    pydoc3 alsamidi
--      http://alsa-project.org/alsa-doc/alsa-lib/seq.html
-- Example usage:
-- local ALSA = require 'midialsa'
-- ALSA.client( 'Lua client', 1, 1, false )
-- ALSA.connectto( 0, 129, 0 )
-- ALSA.connectfrom( 1, 130, 0 )
-- while true then
--     local alsaevent = ALSA.input()
--     if alsaevent[1] == ALSA.SND_SEQ_EVENT_PORT_UNSUBSCRIBED then break end
--     ALSA.output( alsaevent )
-- end

local M = {} -- public interface
M.Version = '1.02'
M.VersionDate = '13feb2011'
-- 20110213 1.02 add disconnectto and disconnectfrom
-- 20110210 1.01 output() no longer floors the time to the nearest second
-- 20110209 1.01 pitchbendevent() and chanpress() return correct data
-- 20110129 1.00 first working version

------------------------------ private ------------------------------
local function warn(str) io.stderr:write(str,'\n') end
local function die(str) io.stderr:write(str,'\n') ;  os.exit(1) end
local function qw(s)  -- t = qw[[ foo  bar  baz ]]
	local t = {} ; for x in s:gmatch("%S+") do t[#t+1] = x end ; return t
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
local  maximum_nports = 4

----------------- from Lua Programming Gems p. 331 ----------------
local require, table = require, table -- save the used globals
local aux, prv = {}, {} -- auxiliary & private C function tables
local initialise = require 'C-midialsa'
initialise(aux, prv, M) -- initialise the C lib with aux,prv & module tables

----------------- public functions from alsaseq.py  -----------------
function M.client(name, ninputports, noutputports, createqueue)
	if ninputports > maximum_nports then
    	warn("midialsa.client: only "..maximum_nports..
		 " input ports are allowed.")
		return false
	elseif noutputports > maximum_nports then
    	warn("midialsa.client: only "..maximum_nports..
		 " output ports are allowed.")
		return false
	end
	return prv.client(name, ninputports, noutputports, createqueue)
end
function M.connectfrom( inputport, src_client, src_port )
	return prv.connectfrom( inputport, src_client, src_port )
end
function M.connectto( outputport, dest_client, dest_port )
	return prv.connectto( outputport, dest_client, dest_port )
end
function M.disconnectfrom( inputport, src_client, src_port )
	return prv.disconnectfrom( inputport, src_client, src_port )
end
function M.disconnectto( outputport, dest_client, dest_port )
	return prv.disconnectto( outputport, dest_client, dest_port )
end
function M.fd()
	return prv.fd()
end
function M.id()
	return prv.id()
end
function M.input()
	local ev = {prv.input()}
	return { ev[1], ev[2], ev[3], ev[4], ev[5],
	 {ev[6],ev[7]}, {ev[8],ev[9]},
	 {ev[10],ev[11],ev[12],ev[13],ev[14],ev[15]} }
end
function M.inputpending()
	return prv.inputpending()
end
function M.output(e)
	if e == nil then return end
	local ev   = deepcopy(e)
	local data = table.remove(ev)
	local src  = ev[6]
	local dest = ev[7]
	return prv.output(ev[1], ev[2], ev[3], ev[4], ev[5],
	 src[1],src[2], dest[1],dest[2],
	 data[1],data[2],data[3],data[4],data[5],data[6])
end
function M.start(queue)
	return prv.start()
end
function M.status(queue)
	return {prv.status()}
end
function M.stop(queue)
	return prv.stop()
end
function M.syncoutput(queue)
	return prv.syncoutput()
end

----------------- public functions from alsamidi.py  -----------------
function M.noteevent( ch, key, vel, start, duration )
    return { M.SND_SEQ_EVENT_NOTE, M.SND_SEQ_TIME_STAMP_REAL,
        0, 0, start, { 0,0 }, { 0,0 },
		{ ch, key, vel, 0, math.floor(0.5 + 1000*duration) } }
end

function M.noteonevent( ch, key, vel )
    return { M.SND_SEQ_EVENT_NOTEON, M.SND_SEQ_TIME_STAMP_REAL,
        0, M.SND_SEQ_QUEUE_DIRECT, 0,
        { 0,0 }, { 0,0 }, { ch, key, vel, 0, 0 } }
end

function M.noteoffevent( ch, key, vel )
    return { M.SND_SEQ_EVENT_NOTEOFF, M.SND_SEQ_TIME_STAMP_REAL,
        0, M.SND_SEQ_QUEUE_DIRECT, 0,
        { 0,0 }, { 0,0 }, { ch, key, vel, 0, 0 } }
end

function M.pgmchangeevent( ch, value, start )
    -- If start is not provided, the event will be sent directly.
    if start == nil then
        return { M.SND_SEQ_EVENT_PGMCHANGE, M.SND_SEQ_TIME_STAMP_REAL,
        0, M.SND_SEQ_QUEUE_DIRECT, 0,
        { 0,0 }, { 0,0 }, { ch, 0, 0, 0, 0, value } }
    else
        return { M.SND_SEQ_EVENT_PGMCHANGE, M.SND_SEQ_TIME_STAMP_REAL,
        0, 0, start,
        { 0,0 }, { 0,0 }, { ch, 0, 0, 0, 0, value } }
	end
end

function M.pitchbendevent( ch, value, start )
    -- If start is not provided, the event will be sent directly.
    if start == nil then
        return { M.SND_SEQ_EVENT_PITCHBEND, M.SND_SEQ_TIME_STAMP_REAL,
        0, M.SND_SEQ_QUEUE_DIRECT, 0,
        { 0,0 }, { 0,0 }, { ch, 0, 0, 0, 0, value } } -- 1.01
    else
        return { M.SND_SEQ_EVENT_PITCHBEND, M.SND_SEQ_TIME_STAMP_REAL,
        0, 0, start,
        { 0,0 }, { 0,0 }, { ch, 0, 0, 0, 0, value } } -- 1.01
	end
end
function M.chanpress( ch, value, start )
    -- If start is not provided, the event will be sent directly.
    if start == nil then
        return { M.SND_SEQ_EVENT_CHANPRESS, M.SND_SEQ_TIME_STAMP_REAL,
        0, M.SND_SEQ_QUEUE_DIRECT, 0,
        { 0,0 }, { 0,0 }, { ch, 0, 0, 0, 0, value } } -- 1.01
    else
        return { M.SND_SEQ_EVENT_CHANPRESS, M.SND_SEQ_TIME_STAMP_REAL,
        0, 0, start,
        { 0,0 }, { 0,0 }, { ch, 0, 0, 0, 0, value } } -- 1.01
	end
end
------------- public functions to handle MIDI.lua events  -------------
-- for MIDI.lua events see http://www.pjb.com.au/comp/lua/MIDI.html#events
-- for data args see http://alsa-project.org/alsa-doc/alsa-lib/seq.html
-- http://alsa-project.org/alsa-doc/alsa-lib/group___seq_events.html

local ticks_so_far = 0;
local chapitch2note_on_events = {}  -- this mechanism courtesy of MIDI.lua
function M.alsa2opusevent(alsaevent, want_score)
	local new_ticks = math.floor(0.5 + 1000*alsaevent[5])
	local ticks
	local function_name
	if want_score then
		function_name = 'midialsa.alsa2scoreevent'
		ticks = new_ticks
	else
		function_name = 'midialsa.alsa2opusevent'
		ticks = new_ticks - ticks_so_far
		if ticks < 0 then ticks = 0 end
		ticks_so_far = new_ticks
	end
	local data = alsaevent[8]  -- deepcopy?
	-- snd_seq_ev_note_t: channel, note, velocity, off_velocity, duration
	if alsaevent[1] == M.SND_SEQ_EVENT_NOTE then
		return { 'note',ticks,data[5],data[1],data[2],data[3] } -- 1.01
	elseif alsaevent[1] == M.SND_SEQ_EVENT_NOTEOFF
	 or (alsaevent[1] == M.SND_SEQ_EVENT_NOTEON and data[3] == 0) then
		if want_score then
			local cha = data[1]
			local pitch = data[2]
			local key = cha*128 + pitch
			local pending_notes = chapitch2note_on_events[key]
			if pending_notes and #pending_notes > 0 then
				local new_e = table.remove(pending_notes, 1)
				new_e[3] = ticks - new_e[2]
				return new_e
			elseif pitch > 127 then
				warn(function_name..': note_off with no note_on, bad pitch='
					 ..tostring(pitch))
				return nil
			else
				warn(function_name..': note_off with no note_on cha='
				 ..tostring(cha)..' pitch='..tostring(pitch))
				return nil
			end
		else
			return { 'note_off',ticks,data[1],data[2],data[3] }
		end
	elseif alsaevent[1] == M.SND_SEQ_EVENT_NOTEON then
		local cha = data[1]
		local pitch = data[2]
		if want_score then
			local key = cha*128 + pitch
			local new_e = {'note',ticks,0,cha,pitch,data[3]}
			if chapitch2note_on_events[key] then
				table.insert(chapitch2note_on_events[key], new_e)
			else
				chapitch2note_on_events[key] = {new_e,}
			end
		else
			return { 'note_on',ticks,cha,pitch,data[3] }
		end
	elseif alsaevent[1] == M.SND_SEQ_EVENT_CONTROLLER then
		return { 'control_change',ticks,data[1],data[5],data[6] }
	elseif alsaevent[1] == M.SND_SEQ_EVENT_PGMCHANGE then
		return { 'patch_change',ticks,data[1],data[6] }
	elseif alsaevent[1] == M.SND_SEQ_EVENT_PITCHBEND then
		return { 'pitch_wheel_change',ticks,data[1],data[6] }
	elseif alsaevent[1] == M.SND_SEQ_EVENT_CHANPRESS then
		return { 'channel_after_touch',ticks,data[1],data[6] }
	else
		warn(function_name..': unsupported event-type '..alsaevent[1])
		return nil
	end
end
function M.alsa2scoreevent(alsaevent)
	return M.alsa2opusevent(alsaevent, true)
end
function M.scoreevent2alsa(event)
	warn('entered')
	local time_in_secs = 0.001*event[2]  -- ms ticks -> secs
	if event[1] == 'note' then
		-- note on and off with duration; event data type = snd_seq_ev_note_t
		return { M.SND_SEQ_EVENT_NOTE, M.SND_SEQ_TIME_STAMP_REAL,
		 0, 0, time_in_secs, { 0,0 }, { 0,0 },
		 { event[4], event[5], event[6], 0, event[3] } }
	elseif event[1] == 'control_change' then
		-- controller; snd_seq_ev_ctrl_t; channel, unused[3], param, value
		return { M.SND_SEQ_EVENT_CONTROLLER, M.SND_SEQ_TIME_STAMP_REAL,
		 0, 0, time_in_secs, { 0,0 }, { 0,0 },
		 { event[3], 0,0,0, event[4], event[5] } }
	elseif event[1] == 'patch_change' then
		-- program change; data type=snd_seq_ev_ctrl_t, param is ignored
		return { M.SND_SEQ_EVENT_PGMCHANGE, M.SND_SEQ_TIME_STAMP_REAL,
		 0, 0, time_in_secs, { 0,0 }, { 0,0 },
		 { event[3], 0,0,0, event[4], event[4] } }
	elseif event[1] == 'pitch_wheel_change' then
		-- pitchwheel; snd_seq_ev_ctrl_t; data is from -8192 to 8191
		return { M.SND_SEQ_EVENT_PITCHBEND, M.SND_SEQ_TIME_STAMP_REAL,
		 0, 0, time_in_secs, { 0,0 }, { 0,0 },
		 { event[3], 0,0,0, event[4], event[4] } }
	elseif event[1] == 'channel_after_touch' then
		-- channel_after_touch; snd_seq_ev_ctrl_t; data is from -8192 to 8191
		return { M.SND_SEQ_EVENT_CHANPRESS, M.SND_SEQ_TIME_STAMP_REAL,
		 0, 0, time_in_secs, { 0,0 }, { 0,0 },
		 { event[3], 0,0,0, event[4], event[4] } }
	elseif event[1] == 'time_signature' then  -- ticks, nn,dd, cc,bb
		-- time_signature; snd_seq_ev_ctrl_t; data is from -8192 to 8191
		return { M.SND_SEQ_EVENT_TIMESIGN, M.SND_SEQ_TIME_STAMP_REAL,
		 0, 0, time_in_secs, { 0,0 }, { 0,0 },
		 { event[3], 0,0,0, event[4], event[4] } }
	elseif event[1] == 'key_signature' then  -- ticks, sf,mi
		-- key_signature; snd_seq_ev_ctrl_t; data is from -8192 to 8191
		return { M.SND_SEQ_EVENT_KEYSIGN, M.SND_SEQ_TIME_STAMP_REAL,
		 0, 0, time_in_secs, { 0,0 }, { 0,0 },
		 { event[3], 0,0,0, event[4], event[5] } }
	elseif event[1] == 'set_tempo' then  -- ticks, us_per_beat
		-- set_tempo; snd_seq_ev_queue_control
		return { M.SND_SEQ_EVENT_TEMPO, M.SND_SEQ_TIME_STAMP_REAL,
		 0, 0, time_in_secs, { 0,0 }, { 0,0 },
		 { event[3], 0,0,0, 0, 0 } }
	else
		warn('midialsa.scoreevent2alsa: unsupported event '..event[1])
		return nil
	end
end

function M.rawevent2alsa()
end

-- could make M readOnly ?
local readonly_proxy = {}
local mt = { -- create metatable, see Programming in Lua p.127
	__index = M,
	__newindex = function (M,k,v)
		warn('midialsa: attempt to update the module table')
	end
}
setmetatable(readonly_proxy, mt)
-- return M
return readonly_proxy

--[=[

=pod

=head1 NAME

midialsa.lua - the ALSA library, plus some interface functions

=head1 SYNOPSIS

 local ALSA = require 'midialsa'
 ALSA.client( 'Lua client', 1, 1, false )
 ALSA.connectto( 0, 20, 0 )
 ALSA.connectfrom( 1, 14, 0 )
 while true then
     local alsaevent = ALSA.input()
     if alsaevent[1] == ALSA.SND_SEQ_EVENT_PORT_UNSUBSCRIBED then break end
     ALSA.output( alsaevent )
 end


=head1 DESCRIPTION

This module offers a Lua interface to the I<ALSA> library.
It translates into Lua the Python modules
I<alsaseq.py> and I<alsamidi.py> by Patricio Paez;
it also offers some functions to translate events from and to
the format used in Peter Billam's MIDI.lua Lua module
and Sean Burke's MIDI-Perl CPAN module.

This module is in turn translated also into a
call-compatible Perl CPAN module:
I<MIDI::ALSA> http://search.cpan.org/~pjb

=head1 FUNCTIONS

Functions based on those in I<alsaseq.py>:
client(), connectfrom(), connectto(), fd(), id(), input(), inputpending(),
output(), start(), status(), stop(), syncoutput()

Functions based on those in I<alsamidi.py>:
noteevent(), noteonevent(), noteoffevent(), pgmchangeevent(),
pitchbendevent(), chanpress()

Functions to interface with I<MIDI.lua>:
alsa2opusevent(), alsa2scoreevent(), scoreevent2alsa(), rawevent2alsa()

=over 3

=item I<client>(name, ninputports, noutputports, createqueue)

Create an ALSA sequencer client with zero or more input or output ports,
and optionally a timing queue.  ninputports and noutputports are created
if the quantity requested is between 1 and 4 for each.
If createqueue = true, it creates a queue for stamping the arrival time of
incoming events and scheduling future start times of outgoing events.

Unlike in the I<alsaseq.py> Python module, it returns success or failure.

=item I<connectfrom>( inputport, src_client, src_port )

Connect from src_client:src_port to inputport. Each input port can connect
from more than one client. The input() function will receive events
from any intput port and any of the clients connected to each of them.
Events from each client can be distinguised by their source field.

Unlike in the I<alsaseq.py> Python module, it returns success or failure.

=item I<connectto>( outputport, dest_client, dest_port )

Connect outputport to dest_client:dest_port. Each outputport can be
Connected to more than one client. Events sent to an output port using
the output()  funtion will be sent to all clients that are connected to
it using this function.

Unlike in the I<alsaseq.py> Python module, it returns success or failure.

=item I<disconnectfrom>( inputport, src_client, src_port )

Disconnect the connection
from the remote I<src_client:src_port> to my I<inputport>.
Returns success or failure.

=item I<disconnectto>( outputport, dest_client, dest_port )

Disconnect the connection
from my I<outputport> to the remote I<dest_client:dest_port>.
Returns success or failure.

=item I<fd>()

Return fileno of sequencer.

=item I<id>()

Return the client number, or 0 if the client is not yet created.

=item I<input>()

Wait for an ALSA event in any of the input ports and return it.
ALSA events are returned as an array with 8 elements:

 {type, flags, tag, queue, time, source, destination, data}

Unlike in the I<alsaseq.py> Python module,
the time element is in floating-point seconds.
The last three elements are also arrays:

 source = { src_client,  src_port }
 destination = { dest_client,  dest_port }
 data = { varies depending on type }

The I<source> and I<destination> arrays may be useful within an application
for handling events differently according to their source or destination.
The event-type constants, beginning with SND_SEQ_,
are available as module variables:

 ALSA = require 'midialsa'
 for k,v in pairs(ALSA) do print(k) end

Note that if the event is of type SND_SEQ_EVENT_PORT_UNSUBSCRIBED
then the remote client and port do not seem to be correct...

The data array is documented in
http://alsa-project.org/alsa-doc/alsa-lib/seq.html

=item I<inputpending>()

Return the number of bytes available in input buffer.
Use before input()  to wait till an event is ready to be read. 
If a connection terminates, then inputpending() returns,
and the next event will be of type SND_SEQ_EVENT_PORT_UNSUBSCRIBED

=item I<output>( {type, flags, tag, queue, time, source, destination, data} )

Send an ALSA-event-array to an output port.
The format of the event is dicussed in input() above.
The event will be output immediately
either if no queue was created in the client,
or if the I<queue> parameter is set to ALSA.SND_SEQ_QUEUE_DIRECT
and otherwise it will be queued and scheduled.

If only one port exists, all events are sent to that port. If two or
more output ports exist, the I<dest_port> of the event determines
which to use.
The smallest available port-number ( as created by client() )
will be used if I<dest_port> is less than it,
and the largest available port-number
will be used if I<dest_port> is greater than it.

An event sent to an output port will be sent to all clients
that were subscribed using the connectto() function.

If the queue buffer is full, output() will wait
until space is available to output the event.
Use status() to know how many events are scheduled in the queue.

=item I<start>(queue)

Start the queue. It is ignored if the client does not have a queue. 

=item I<status>(queue)

Return { status, time, events } of the queue.

 Status: 0 if stopped, 1 if running.
 Time: current time in seconds.
 Events: number of output events scheduled in the queue.

If the client does not have a queue the value {0,0,0} is returned.
Unlike in the I<alsaseq.py> Python module,
the I<time> element is in floating-point seconds.

=item I<stop>(queue)

Stop the queue. It is ignored if the client does not have a queue. 

=item I<syncoutput>(queue)

Wait until output events are processed.

=item I<noteevent>( ch, key, vel, start, duration )

Returns an ALSA-event-array, to be scheduled by output().
Unlike in the I<alsaseq.py> Python module,
the I<start> and I<duration> elements are in floating-point seconds.

=item I<noteonevent>( ch, key, vel )

Returns an ALSA-event-array to be sent directly with output().

=item I<noteoffevent>( ch, key, vel )

Returns an ALSA-event-array to be sent directly with output().

=item I<pgmchangeevent>( ch, value, start )

Returns an ALSA-event-array to be sent by output().
If I<start> is not used, the event will be sent directly;
if I<start> is provided, the event will be scheduled in a queue. 
Unlike in the I<alsaseq.py> Python module,
the I<start> element, when provided, is in floating-point seconds.

=item I<pitchbendevent>( ch, value, start )

Returns an ALSA-event-array to be sent by output().
If I<start> is not used, the event will be sent directly;
if I<start> is provided, the event will be scheduled in a queue. 
Unlike in the I<alsaseq.py> Python module,
the I<start> element, when provided, is in floating-point seconds.

=item I<chanpress>( ch, value, start )

Returns an ALSA-event-array to be sent by output().
If I<start> is not used, the event will be sent directly;
if I<start> is provided, the event will be scheduled in a queue. 
Unlike in the I<alsaseq.py> Python module,
the I<start> element, when provided, is in floating-point seconds.

=item I<alsa2opusevent>(alsaevent)

Returns an event in the millisecond-tick score-format
used by the I<MIDI.lua> and I<MIDI.py> modules,
based on the opus-format in Sean Burke's MIDI-Perl CPAN module. See:
 http://www.pjb.com.au/comp/lua/MIDI.html#events

=item I<alsa2scoreevent>(alsaevent)

Returns an event in the millisecond-tick score-format
used by the I<MIDI.lua> and I<MIDI.py> modules,
based on the score-format in Sean Burke's MIDI-Perl CPAN module. See:
 http://www.pjb.com.au/comp/lua/MIDI.html#events

Since it combines a I<note_on> and a I<note_off> event into one note event,
it will return I<nil> when called with the I<note_on> event;
the calling loop must therefore detect I<nil>
and not, for example, try to index it.

=item I<scoreevent2alsa>(event)

Returns an ALSA-event-array to be scheduled in a queue by output().
The input is an event in the millisecond-tick score-format
used by the I<MIDI.lua> and I<MIDI.py> modules,
based on the score-format in Sean Burke's MIDI-Perl CPAN module. See:
http://www.pjb.com.au/comp/lua/MIDI.html#events 
For example:

 ALSA.output(ALSA.scoreevent2alsa{'note',4000,1000,0,62,110})

=item I<rawevent2alsa>()

Unimplemented

=back

=head1 DOWNLOAD

This module is available as a LuaRock in
http://luarocks.org/repositories/rocks/index.html#midi
so you should be able to install it with the command:

 $ su
 Password:
 # luarocks install midialsa

or:

 # luarocks install http://www.pjb.com.au/comp/lua/midialsa-1.01-0.rockspec

The Perl version is available from CPAN at
http://search.cpan.org/perldoc?MIDI::ALSA

=head1 TO DO

There should be a way of checking the current status of a connection,
like isconnectedto() and isconnectedfrom() or something,
so that if a connection has vanished the application can handle it gracefully.

Perhaps there should be a general connect_between() mechanism,
allowing the interconnection of two other clients,
a bit like I<aconnect 32 20>

There should be a way of getting the textual information
about the various clients, like "TiMidity" or
"Roland XV-2020" or "Virtual Raw MIDI 2-0" and so on.

If an event is of type SND_SEQ_EVENT_PORT_UNSUBSCRIBED
then the remote client and port seem to be zeroed-out,
which makes it hard to know which client has disconnected.

output() and input() seem to filter out all non-sounding events,
like text_events and sysex; this ought to be adjustable.
 int snd_seq_set_client_event_filter (snd_seq_t * seq, int event_type) 	

=head1 AUTHOR

Peter J Billam, http://www.pjb.com.au/comp/contact.html

=head1 SEE ALSO

 aconnect -oil
 http://pp.com.mx/python/alsaseq
 http://search.cpan.org/perldoc?MIDI::ALSA
 http://www.pjb.com.au/comp/lua/midialsa.html
 http://luarocks.org/repositories/rocks/index.html#midialsa
 http://www.pjb.com.au/comp/lua/MIDI.html
 http://www.pjb.com.au/comp/lua/MIDI.html#events
 http://alsa-project.org/alsa-doc/alsa-lib/seq.html
 http://alsa-project.org/alsa-doc/alsa-lib/structsnd__seq__ev__note.html
 http://alsa-project.org/alsa-doc/alsa-lib/structsnd__seq__ev__ctrl.html
 http://alsa-project.org/alsa-doc/alsa-lib/structsnd__seq__ev__queue__control.html
 http://alsa-project.org/alsa-doc/alsa-lib/group___seq_client.html
 snd_seq_client_info_event_filter_clear
 snd_seq_get_any_client_info
 snd_seq_get_client_info
 snd_seq_client_info_t

=cut

]=]

