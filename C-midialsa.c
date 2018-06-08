/*
    midialsa.c - ALSA sequencer bindings for Python

    Copyright (c) 2007 Patricio Paez <pp@pp.com.mx>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>
*/

#include <lua.h>
#include <lauxlib.h>
#include <alsa/asoundlib.h>

snd_seq_t *seq_handle;
int queue_id = -1;
int ninputports, noutputports, createqueue;
int firstoutputport, lastoutputport;

static int stackDump (lua_State *L) {
	int i;
	int top = lua_gettop(L);
	for (i=1; i<=top; i++) {  /* repeat for each level */
		int t = lua_type(L, i);
		switch (t) {
			case LUA_TSTRING: {
				printf("'%s'", lua_tostring(L, i));
				break;
			}
			case LUA_TBOOLEAN: {
				printf(lua_toboolean(L, i) ? "true": "false");
				break;
			}
			case LUA_TNUMBER: {
				printf("%g", lua_tonumber(L, i));
				break;
			}
			default: {
				printf("%s", lua_typename(L, i));
				break;
			}
		}
		printf("  ");
	}
	printf("\n");
}
static int midialsa_client(lua_State *L) {
	/* Lua stack: client_name, ninputports, noutputports, createqueue */
	size_t len;
	const char *client_name  = lua_tolstring(L, 1, &len);
	lua_Integer ninputports  = lua_tointeger(L, 2);
	lua_Integer noutputports = lua_tointeger(L, 3);
	int createqueue          = lua_toboolean(L, 4);

	int portid, n;
	if (snd_seq_open(&seq_handle, "default", SND_SEQ_OPEN_DUPLEX, 0) < 0) {
		fprintf(stderr, "Error creating ALSA client.\n");
		lua_pushboolean(L, 0);
		return 1;
	}
	snd_seq_set_client_name(seq_handle, client_name );

	if ( createqueue )
		queue_id = snd_seq_alloc_queue(seq_handle);
	else
		queue_id = SND_SEQ_QUEUE_DIRECT;

	for ( n=0; n < ninputports; n++ ) {
		if (( portid = snd_seq_create_simple_port(seq_handle, "Input port",
				SND_SEQ_PORT_CAP_WRITE|SND_SEQ_PORT_CAP_SUBS_WRITE,
				SND_SEQ_PORT_TYPE_APPLICATION)) < 0) {
			fprintf(stderr, "Error creating input port %d.\n", n );
			lua_pushboolean(L, 0);
			return 1;
		}
		if( createqueue ) {
			/* set timestamp info of port  */
			snd_seq_port_info_t *pinfo;
			snd_seq_port_info_alloca(&pinfo);
			snd_seq_get_port_info(seq_handle, portid, pinfo);
			snd_seq_port_info_set_timestamping(pinfo, 1);
			snd_seq_port_info_set_timestamp_queue(pinfo, queue_id);
			snd_seq_port_info_set_timestamp_real(pinfo, 1);
			snd_seq_set_port_info(seq_handle, portid, pinfo);
		}
	}

	for ( n=0; n < noutputports; n++ ) {
		if (( portid = snd_seq_create_simple_port(seq_handle, "Output port",
				SND_SEQ_PORT_CAP_READ|SND_SEQ_PORT_CAP_SUBS_READ,
				SND_SEQ_PORT_TYPE_APPLICATION)) < 0) {
			fprintf(stderr, "Error creating output port %d.\n", n );
			lua_pushboolean(L, 0);
			return 1;
		}
	}
	firstoutputport = ninputports;
	lastoutputport  = noutputports + ninputports - 1;
	lua_pushboolean(L, 1);
	return 1;
}

static int midialsa_start(lua_State *L) {
	int rc = snd_seq_start_queue(seq_handle, queue_id, NULL);
	snd_seq_drain_output(seq_handle);
	lua_pushboolean(L, rc);
	return 1;
}

static int midialsa_stop(lua_State *L) {
	int rc = snd_seq_stop_queue(seq_handle, queue_id, NULL);
	snd_seq_drain_output(seq_handle);
	lua_pushboolean(L, rc);
	return 1;
}

static int midialsa_status(lua_State *L) {
	snd_seq_queue_status_t *queue_status;
	int running, events;
	const snd_seq_real_time_t *current_time;
	snd_seq_queue_status_malloc( &queue_status );
	snd_seq_get_queue_status( seq_handle, queue_id, queue_status );
	current_time = snd_seq_queue_status_get_real_time( queue_status );
	running      = snd_seq_queue_status_get_status( queue_status );
	events       = snd_seq_queue_status_get_events( queue_status );
	snd_seq_queue_status_free( queue_status );
	double sec   = current_time->tv_sec;
	double nsec  = current_time->tv_nsec;
	fprintf(stderr, "running=%d sec=%g nsec=%g\n", running, sec, nsec );
	/* returns: running, time, events */
	lua_pushboolean(L, running);
	lua_pushnumber(L, sec + 1.0e-9*nsec);
	lua_pushinteger(L, events);
	/* stackDump(L); */
	return 3;
}

static int midialsa_connectfrom(lua_State *L) {
	/* Lua stack: inputport, src_client, src_port */
	lua_Integer myport     = lua_tointeger(L, 1);
	lua_Integer src_client = lua_tointeger(L, 2);
	lua_Integer src_port   = lua_tointeger(L, 3);
	int rc = snd_seq_connect_from( seq_handle, myport, src_client, src_port);
	/* returns 0 on success, or a negative error code */
	/* http://alsa-project.org/alsa-doc/alsa-lib/seq.html */
	lua_pushboolean(L, rc==0);
	return 1;
}

static int midialsa_connectto(lua_State *L) {
	/* Lua stack: outputport, dest_client, dest_port */
	lua_Integer myport      = lua_tointeger(L, 1);
	lua_Integer dest_client = lua_tointeger(L, 2);
	lua_Integer dest_port   = lua_tointeger(L, 3);
	int rc = snd_seq_connect_to( seq_handle, myport, dest_client, dest_port);
	/* returns 0 on success, or a negative error code */
	/* http://alsa-project.org/alsa-doc/alsa-lib/seq.html */
	lua_pushboolean(L, rc==0);
	return 1;
}

static int midialsa_fd(lua_State *L) {
	int npfd;
	struct pollfd *pfd;
	npfd = snd_seq_poll_descriptors_count(seq_handle, POLLIN);
	pfd = (struct pollfd *)alloca(npfd * sizeof(struct pollfd));
	snd_seq_poll_descriptors(seq_handle, pfd, npfd, POLLIN);
	lua_pushinteger(L, pfd->fd);
	return 1;
}

static int midialsa_id(lua_State *L) {
	lua_pushinteger(L, snd_seq_client_id( seq_handle ));
	return 1;
}

static int midialsa_input(lua_State *L) {
	snd_seq_event_t *ev;
	snd_seq_event_input( seq_handle, &ev );
	/* returns: (type, flags, tag, queue, time, src_client, src_port,
	   dest_client, dest_port, data...)
	   We flatten out the list here so as not to have to use userdata
	   and we use one Time in secs, rather than separate secs and nsecs
	*/
	lua_pushinteger(L, ev->type);
	lua_pushinteger(L, ev->flags);
	lua_pushinteger(L, ev->tag);
	lua_pushinteger(L, ev->queue);
	lua_pushnumber( L, ev->time.time.tv_sec + 1.0e-9 * ev->time.time.tv_nsec);
	lua_pushinteger(L, ev->source.client);
	lua_pushinteger(L, ev->source.port);
	lua_pushinteger(L, ev->dest.client);
	lua_pushinteger(L, ev->dest.port);

	switch( ev->type ) {
		case SND_SEQ_EVENT_NOTE:
		case SND_SEQ_EVENT_NOTEON:
		case SND_SEQ_EVENT_NOTEOFF:
		case SND_SEQ_EVENT_KEYPRESS:
			lua_pushinteger(L, ev->data.note.channel);
			lua_pushinteger(L, ev->data.note.note);
			lua_pushinteger(L, ev->data.note.velocity);
			lua_pushinteger(L, ev->data.note.off_velocity);
			lua_pushinteger(L, ev->data.note.duration);
			return 14;
			break;

		case SND_SEQ_EVENT_CONTROLLER:
		case SND_SEQ_EVENT_PGMCHANGE:
		case SND_SEQ_EVENT_CHANPRESS:
		case SND_SEQ_EVENT_PITCHBEND:
			lua_pushinteger(L, ev->data.control.channel);
			lua_pushinteger(L, ev->data.control.unused[0]);
			lua_pushinteger(L, ev->data.control.unused[1]);
			lua_pushinteger(L, ev->data.control.unused[2]);
			lua_pushinteger(L, ev->data.control.param);
			lua_pushinteger(L, ev->data.control.value);
			return 15;
            break;

		default:
			/* lua_pushinteger(L, ev->data.note.channel);
			lua_pushinteger(L, ev->data.note.note);
			lua_pushinteger(L, ev->data.note.velocity);
			lua_pushinteger(L, ev->data.note.off_velocity);
			lua_pushinteger(L, ev->data.note.duration); */
			return 9;
	}
}

static int midialsa_inputpending(lua_State *L) {
	if (queue_id < 0) { lua_pushinteger(L,0) ; return 1; }
	lua_pushinteger(L, snd_seq_event_input_pending(seq_handle, 1));
	return 1;
}

static int midialsa_output(lua_State *L) {
	/* Lua stack: type, flags, tag, queue, time (float, in secs),
	 src_client, src_port, dest_client, dest_port, data... */
	snd_seq_event_t ev;
	ev.type          = lua_tointeger(L, 1);
	ev.flags         = lua_tointeger(L, 2);
	ev.tag           = lua_tointeger(L, 3);
	ev.queue         = lua_tointeger(L, 4);
	double t         = lua_tonumber( L, 5); 
	ev.time.time.tv_sec       = (int) t;
	ev.time.time.tv_nsec = (int) (1.0e9 * (t - (double) ev.time.time.tv_sec));
	ev.source.client = lua_tointeger(L, 6);
	ev.source.port   = lua_tointeger(L, 7);
	ev.dest.client   = lua_tointeger(L, 8);
	ev.dest.port     = lua_tointeger(L, 9);
	static int * data;
        
	/* printf ( "event.type: %d source.client=%d dest.client=%d\n", ev.type, ev.source.client, ev.dest.client ); */
	switch( ev.type ) {
		case SND_SEQ_EVENT_NOTE:
		case SND_SEQ_EVENT_NOTEON:
		case SND_SEQ_EVENT_NOTEOFF:
		case SND_SEQ_EVENT_KEYPRESS:
			ev.data.note.channel      = lua_tointeger(L, 10);
			ev.data.note.note         = lua_tointeger(L, 11);
			ev.data.note.velocity     = lua_tointeger(L, 12);
			ev.data.note.off_velocity = lua_tointeger(L, 13);
			ev.data.note.duration     = lua_tointeger(L, 14);
			/* printf ( "note=%d velocity=%d\n", ev.data.note.note, ev.data.note.velocity ); */
			break;

		case SND_SEQ_EVENT_CONTROLLER:
		case SND_SEQ_EVENT_PGMCHANGE:
		case SND_SEQ_EVENT_CHANPRESS:
		case SND_SEQ_EVENT_PITCHBEND:
			ev.data.control.channel   = lua_tointeger(L, 10);
			ev.data.control.unused[0] = lua_tointeger(L, 11);
			ev.data.control.unused[1] = lua_tointeger(L, 12);
			ev.data.control.unused[2] = lua_tointeger(L, 13);
			ev.data.control.param     = lua_tointeger(L, 14);
			ev.data.control.value     = lua_tointeger(L, 15);
			/* printf ( "param: %d\n", ev.data.control.param );
			   printf ( "value: %d\n", ev.data.control.value );
			*/
			break;
	}
	/* If not a direct event, use the queue */
	if ( ev.queue != SND_SEQ_QUEUE_DIRECT )
		ev.queue = queue_id;
	/* Modify source port if out of bounds */
	if ( ev.source.port < firstoutputport ) 
		snd_seq_ev_set_source(&ev, firstoutputport );
	else if ( ev.source.port > lastoutputport )
		snd_seq_ev_set_source(&ev, lastoutputport );
	/* printf ( "event.queue: %d source.port=%d dest.port=%d\n", ev.queue, ev.source.port, ev.dest.port ); */
	/* Use subscribed ports, except if ECHO event */
	if ( ev.type != SND_SEQ_EVENT_ECHO ) snd_seq_ev_set_subs(&ev);
	int rc = snd_seq_event_output_direct( seq_handle, &ev );
	lua_pushinteger(L, rc);
	return 1;
}

static int midialsa_syncoutput(lua_State *L) {
	snd_seq_sync_output_queue( seq_handle );
    return 0;
}

struct constant {  /* Gems p. 334 */
	const char * name;
	int value;
};
static const struct constant constants[] = {
	{"SND_SEQ_EVENT_BOUNCE", SND_SEQ_EVENT_BOUNCE},
	{"SND_SEQ_EVENT_CHANPRESS", SND_SEQ_EVENT_CHANPRESS},
	{"SND_SEQ_EVENT_CLIENT_CHANGE", SND_SEQ_EVENT_CLIENT_CHANGE},
	{"SND_SEQ_EVENT_CLIENT_EXIT", SND_SEQ_EVENT_CLIENT_EXIT},
	{"SND_SEQ_EVENT_CLIENT_START", SND_SEQ_EVENT_CLIENT_START},
	{"SND_SEQ_EVENT_CLOCK", SND_SEQ_EVENT_CLOCK},
	{"SND_SEQ_EVENT_CONTINUE", SND_SEQ_EVENT_CONTINUE},
	{"SND_SEQ_EVENT_CONTROL14", SND_SEQ_EVENT_CONTROL14},
	{"SND_SEQ_EVENT_CONTROLLER", SND_SEQ_EVENT_CONTROLLER},
	{"SND_SEQ_EVENT_ECHO", SND_SEQ_EVENT_ECHO},
	{"SND_SEQ_EVENT_KEYPRESS", SND_SEQ_EVENT_KEYPRESS},
	{"SND_SEQ_EVENT_KEYSIGN", SND_SEQ_EVENT_KEYSIGN},
	{"SND_SEQ_EVENT_NONE", SND_SEQ_EVENT_NONE},
	{"SND_SEQ_EVENT_NONREGPARAM", SND_SEQ_EVENT_NONREGPARAM},
	{"SND_SEQ_EVENT_NOTE", SND_SEQ_EVENT_NOTE},
	{"SND_SEQ_EVENT_NOTEOFF", SND_SEQ_EVENT_NOTEOFF},
	{"SND_SEQ_EVENT_NOTEON", SND_SEQ_EVENT_NOTEON},
	{"SND_SEQ_EVENT_OSS", SND_SEQ_EVENT_OSS},
	{"SND_SEQ_EVENT_PGMCHANGE", SND_SEQ_EVENT_PGMCHANGE},
	{"SND_SEQ_EVENT_PITCHBEND", SND_SEQ_EVENT_PITCHBEND},
	{"SND_SEQ_EVENT_PORT_CHANGE", SND_SEQ_EVENT_PORT_CHANGE},
	{"SND_SEQ_EVENT_PORT_EXIT", SND_SEQ_EVENT_PORT_EXIT},
	{"SND_SEQ_EVENT_PORT_START", SND_SEQ_EVENT_PORT_START},
	{"SND_SEQ_EVENT_PORT_SUBSCRIBED", SND_SEQ_EVENT_PORT_SUBSCRIBED},
	{"SND_SEQ_EVENT_PORT_UNSUBSCRIBED", SND_SEQ_EVENT_PORT_UNSUBSCRIBED},
	{"SND_SEQ_EVENT_QFRAME", SND_SEQ_EVENT_QFRAME},
	{"SND_SEQ_EVENT_QUEUE_SKEW", SND_SEQ_EVENT_QUEUE_SKEW},
	{"SND_SEQ_EVENT_REGPARAM", SND_SEQ_EVENT_REGPARAM},
	{"SND_SEQ_EVENT_RESET", SND_SEQ_EVENT_RESET},
	{"SND_SEQ_EVENT_RESULT", SND_SEQ_EVENT_RESULT},
	{"SND_SEQ_EVENT_SENSING", SND_SEQ_EVENT_SENSING},
	{"SND_SEQ_EVENT_SETPOS_TICK", SND_SEQ_EVENT_SETPOS_TICK},
	{"SND_SEQ_EVENT_SETPOS_TIME", SND_SEQ_EVENT_SETPOS_TIME},
	{"SND_SEQ_EVENT_SONGPOS", SND_SEQ_EVENT_SONGPOS},
	{"SND_SEQ_EVENT_SONGSEL", SND_SEQ_EVENT_SONGSEL},
	{"SND_SEQ_EVENT_START", SND_SEQ_EVENT_START},
	{"SND_SEQ_EVENT_STOP", SND_SEQ_EVENT_STOP},
	{"SND_SEQ_EVENT_SYNC_POS", SND_SEQ_EVENT_SYNC_POS},
	{"SND_SEQ_EVENT_SYSEX", SND_SEQ_EVENT_SYSEX},
	{"SND_SEQ_EVENT_SYSTEM", SND_SEQ_EVENT_SYSTEM},
	{"SND_SEQ_EVENT_TEMPO", SND_SEQ_EVENT_TEMPO},
	{"SND_SEQ_EVENT_TICK", SND_SEQ_EVENT_TICK},
	{"SND_SEQ_EVENT_TIMESIGN", SND_SEQ_EVENT_TIMESIGN},
	{"SND_SEQ_EVENT_TUNE_REQUEST", SND_SEQ_EVENT_TUNE_REQUEST},
	{"SND_SEQ_EVENT_USR0", SND_SEQ_EVENT_USR0},
	{"SND_SEQ_EVENT_USR1", SND_SEQ_EVENT_USR1},
	{"SND_SEQ_EVENT_USR2", SND_SEQ_EVENT_USR2},
	{"SND_SEQ_EVENT_USR3", SND_SEQ_EVENT_USR3},
	{"SND_SEQ_EVENT_USR4", SND_SEQ_EVENT_USR4},
	{"SND_SEQ_EVENT_USR5", SND_SEQ_EVENT_USR5},
	{"SND_SEQ_EVENT_USR6", SND_SEQ_EVENT_USR6},
	{"SND_SEQ_EVENT_USR7", SND_SEQ_EVENT_USR7},
	{"SND_SEQ_EVENT_USR8", SND_SEQ_EVENT_USR8},
	{"SND_SEQ_EVENT_USR9", SND_SEQ_EVENT_USR9},
	{"SND_SEQ_EVENT_USR_VAR0", SND_SEQ_EVENT_USR_VAR0},
	{"SND_SEQ_EVENT_USR_VAR1", SND_SEQ_EVENT_USR_VAR1},
	{"SND_SEQ_EVENT_USR_VAR2", SND_SEQ_EVENT_USR_VAR2},
	{"SND_SEQ_EVENT_USR_VAR3", SND_SEQ_EVENT_USR_VAR3},
	{"SND_SEQ_EVENT_USR_VAR4", SND_SEQ_EVENT_USR_VAR4},
	{"SND_SEQ_QUEUE_DIRECT", SND_SEQ_QUEUE_DIRECT},
	{"SND_SEQ_TIME_STAMP_REAL", SND_SEQ_TIME_STAMP_REAL},
	{NULL, 0}
};

static const luaL_Reg prv[] = {  /* private functions */
	{"client",          midialsa_client},
	{"connectfrom",     midialsa_connectfrom},
	{"connectto",       midialsa_connectto},
	{"start",           midialsa_start},
	{"status",          midialsa_status},
	{"stop",            midialsa_stop},
	{"fd",              midialsa_fd},
	{"id",              midialsa_id},
	{"input",           midialsa_input},
	{"inputpending",    midialsa_inputpending},
	{"output",          midialsa_output},
	{"syncoutput",      midialsa_syncoutput},
	{NULL, NULL}
};

static int initialise(lua_State *L) {  /* Lua Programming Gems p. 335 */
	/* Lua stack: aux table, prv table, dat table */
	int index;  /* define constants in module namespace */
	for (index = 0; constants[index].name != NULL; ++index) {
		lua_pushinteger(L, constants[index].value);
		lua_setfield(L, 3, constants[index].name);
	}
	lua_pushvalue(L, 1); /* set the aux table as environment */
	lua_replace(L, LUA_ENVIRONINDEX);
	lua_pushvalue(L, 2); /* register the private functions */
	luaL_register(L, NULL, prv);
	return 0;
}

int luaopen_midialsa(lua_State *L) {
	lua_pushcfunction(L, initialise);
	return 1;
}
