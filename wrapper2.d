module wrapper2;
// compile with: dmd -g -debug -main -unittest wrapper2.d -I~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev ~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev/deimos/ev.d -L-lev

import deimos.ev;
import channel : chan, makeChan, select;
import goroutine : go, shutdown, yield;

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
		writefln("adding with: %f %f", offset, repeat_interval);
		ev_periodic_init(&watcher, &cb, offset, repeat_interval, null);
		ev_periodic_start (loop, &watcher);
	}
	extern(C) static void cb(ev_loop_t* loop, ev_periodic* timer, int revents) {
		import std.conv;
		writeln("bang, ", Clock.currTime());
		typeof(this) self = cast(typeof(this))timer.data;
		assert(timer is &self.watcher);
		if (self.repeat_interval <= 0) {
			ev_periodic_stop(loop, timer);
		}
		self.ready._ = true;
	}
}


unittest {
	import std.stdio;
	auto l = new Loop();
	/*auto idler = new EVReqIdle();
	l.input._ = idler;
	auto idler2 = new EVReqT!(EVReq.Type.Idle)();
	l.input._ = idler2;*/
	auto timer = new EVReqTimer(5, 1);
	l.input._ = timer;
	auto timer2 = new EVReqWallTimer(0,10);
	l.input._ = timer2;


	go!({for (;;) {l.run();} });
	for (;;) {
		final switch(select(timer.ready, timer2.ready)) {//idler.ready, idler2.ready)) {
			case 0:
				timer.ready._();
				writeln("woot");
				break;
			case 1:
				timer2.ready._();
				writeln("wart");
				break;
		}
	}
	shutdown();
}