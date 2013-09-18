module wrapper2;
// dmd -g -d -debug  wrapper2.d channel.d goroutine.d concurrentlinkedqueue.d -I~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev ~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev/deimos/ev.d sync/semaphore.d  -L-lev

import deimos.ev;
import channel : chan, makeChan, select;
import goroutine : go, shutdown;

	import std.stdio;

		import std.datetime;


class Loop {
	ev_loop_t* loop;
	ev_async wakeup; void wake() { ev_async_send(loop, &wakeup); }
	shared chan!EVReq input;

	this() {
		input = makeChan!EVReq(100);
		loop = ev_default_loop(0);
		extern(C) void dummy(ev_loop_t* loop, ev_async* async, int revents) {};
		ev_async_init(&wakeup, &dummy);
		ev_async_start(loop, &wakeup);
	}
	void run() {
		while (!input.empty) {
			synchronized(this) input._.add(loop);
		}
		synchronized(this) {
			ev_run(loop, EVRUN_ONCE);
		}
	}
}
class EVReq {
	shared chan!bool ready;
	this() {
		 ready = makeChan!bool(1);
	}
	abstract void add(ev_loop_t* loop);
}
class EVReqIdle : EVReq {
	ev_idle watcher;
	extern(C) static void cb(ev_loop_t* loop, ev_idle *idle, int revents) {
		typeof(this) self = cast(typeof(this))idle.data;
		assert(idle is &self.watcher);
		self.ready._ = true;
	}
	override
	void add(ev_loop_t* loop) {
		watcher.data = cast(void*)this;
		writeln("p: ", (cast(Object*)&this.ready).toHash);
		ev_idle_init(&watcher, &cb);
		ev_idle_start(loop, &watcher);
	}
}
class EVReqTimer : EVReq {
	ev_timer watcher;
	double time, repeat_interval;
	this(double time, double repeat_interval) {
		this.time = time;
		this.repeat_interval = repeat_interval;
	}
	extern(C) static void cb(ev_loop_t* loop, ev_timer* timer, int revents) {
		typeof(this) self = cast(typeof(this))timer.data;
		assert(timer is &self.watcher);
		if (self.repeat_interval <= 0) {
			ev_timer_stop(loop, timer);
		}
		self.ready._ = true;
	}
	override
	void add(ev_loop_t* loop) {
		assert(this !is null);
		watcher.data = cast(void*)this;
		ev_timer_init(&watcher, &cb, time, repeat_interval);
		ev_timer_start(loop, &watcher);
	}
}
class EVReqWallTimer : EVReq {
	ev_periodic watcher;
	double offset, repeat_interval;
	this (double offset, double repeat_interval) {
		this.offset = offset;
		this.repeat_interval = repeat_interval;
	}
	override
	void add(ev_loop_t* loop) {
		watcher.data = cast(void*)this;
		ev_periodic_init(&watcher, &cb, offset, repeat_interval, null);
		ev_periodic_start (loop, &watcher);
	}
	extern(C) static void cb(ev_loop_t* loop, ev_periodic* timer, int revents) {
		import std.conv;
		typeof(this) self = cast(typeof(this))timer.data;
		assert(timer is &self.watcher);
		if (self.repeat_interval <= 0) {
			ev_periodic_stop(loop, timer);
		}
		self.ready._ = true;
	}
}

class EVReqFile : EVReq {
	ev_io watcher;
	File file;
	int events;
	ev_loop_t* lastLoopSeen;
	this (File file, int events) {
		this.file = file;
		this.events = events;
	}
	override
	void add(ev_loop_t* loop) {
		watcher.data = cast(void*)this;
		ev_io_init(&watcher, &cb, file.fileno, events);
		ev_io_start (loop, &watcher);
	}
	extern(C) static void cb(ev_loop_t* loop, ev_io* watcherp, int revents) {
		import std.conv;
		typeof(this) self = cast(typeof(this))watcherp.data;
		assert(watcherp is &self.watcher);
		self.lastLoopSeen = loop;
		self.ready._ = true;
	}

	void stop() {
		ev_io_stop(lastLoopSeen, &watcher);
	}
}


class EVReqSocket : EVReq {
	import std.socket;
	ev_io watcher;
	Socket sock;
	int events;
	ev_loop_t* lastLoopSeen;
	this (Socket sock, int events) {
		sock.blocking = false;
		this.sock = sock;
		this.events = events;
	}
	override
	void add(ev_loop_t* loop) {
		watcher.data = cast(void*)this;
		ev_io_init(&watcher, &cb, sock.handle, events);
		ev_io_start (loop, &watcher);
	}
	extern(C) static void cb(ev_loop_t* loop, ev_io* watcherp, int revents) {
		typeof(this) self = cast(typeof(this))watcherp.data;
		assert(watcherp is &self.watcher);
		self.lastLoopSeen = loop;
		self.ready._ = true;
	}

	void stop() {
		ev_io_stop(lastLoopSeen, &watcher);
	}
}


void main() {
	import std.stdio;
	auto l = new Loop();
	/*auto idler = new EVReqIdle();
	l.input._ = idler;
	auto idler2 = new EVReqT!(EVReq.Type.Idle)();
	l.input._ = idler2;*/
	auto timer = new EVReqTimer(5, 1);
	l.input ~= timer;
	auto timer2 = new EVReqWallTimer(0,10);
	l.input ~= timer2;

	auto file = new EVReqFile(stdin, EV_READ);
	l.input ~= file;

	// Socket example
	import std.socket : TcpSocket, getAddress, SocketShutdown, SocketAcceptException, Socket;
	auto s = new TcpSocket();
	scope(exit) { s.shutdown(SocketShutdown.BOTH); s.close(); }
	s.bind(getAddress("localhost", 8080)[0]);
	s.listen(5);
	auto socket = new EVReqSocket(s, EV_READ);
	l.input ~= socket;
	// END Socket example

	go!({for (;;) { l.run(); }});
	for (;;) {
		final switch(select(timer.ready, timer2.ready, file.ready,socket.ready)) {//idler.ready, idler2.ready)) {
			case 0:
				bool b = timer.ready;
				writeln("woot");
				break;
			case 1:
				timer2.ready();
				writeln("wart", Clock.currTime());
				break;
			case 2:
				file.ready();
				auto line = file.file.readln;
				if (file.file.eof) {
					file.stop();
					break;
				}
				import std.string : strip;
				writeln("file: ", line.strip);
				break;
			case 3:
				socket.ready();
				Socket cs;
				try {
					cs = socket.sock.accept();
				} catch (SocketAcceptException e){
					break;
				}

				auto n = cs.send(cast(void[])"data\n");
				if (n == EOF) {
					break;
				}
				cs.shutdown(SocketShutdown.BOTH);
				cs.close();
		}
	}
	//shutdown();
}