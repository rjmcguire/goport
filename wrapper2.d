module wrapper2;
// compile with: dmd -g -debug -main -unittest wrapper2.d -I~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev ~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev/deimos/ev.d -L-lev

import deimos.ev;
import channel : chan, makeChan, select;
import goroutine : go, shutdown, yield;

	import std.stdio;



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
			writeln("add");
			input._.add(loop);
			writeln("added");
		}
		writeln("go");
		ev_run(loop, EVRUN_ONCE);
			writeln("done");
	}
}
class EVReq {
	enum Type { Idle, Timer }
	abstract void add(ev_loop_t* loop);
}
class EVReqT(EVReq.Type T) : EVReq {
	shared chan!bool ready = makeChan!bool(1);
	mixin WATCHER!(T, typeof(this));

	override
	void add(ev_loop_t* loop) {
		watcher.data = cast(void*)this;
		static if (T==EVReq.Type.Idle) {
			ev_idle_init(&watcher, &cb);
			ev_idle_start(loop, &watcher);
		} static if (T==EVReq.Type.Timer) {
			ev_timer_init(&watcher, &cb, time, repeat_interval);
			ev_timer_start(loop, &watcher);
		} else {
			assert(0, "unknown evreq type");
		}
	}
}
mixin template WATCHER(EVReq.Type T, SelfType) {
	static if (T==EVReq.Type.Idle) {
		ev_idle watcher;
		extern(C) static void cb(ev_loop_t* loop, ev_idle *idle, int revents) {
			SelfType self = cast(SelfType)idle.data;
			assert(idle is &self.watcher);
			self.ready._ = true;
			writeln("okay");
		}
	} else static if (T==EVReq.Type.Timer) {
		double time, repeat_interval;
		this(double time, double repeat_interval) {
			this.time = time;
			this.repeat_interval = repeat_interval;
		}
		ev_timer watcher;
		extern(C) static void cb(ev_loop_t* loop, ev_timer* timer, int revents) {
			SelfType self = cast(SelfType)timer.data;
			assert(timer is &self.watcher);
			writeln("timer will okay");
			self.ready._ = true;
			writeln("timer okay");
		}
	}
}


unittest {
	import std.stdio;
	auto l = new Loop();
	/*auto idler = new EVReqT!(EVReq.Type.Idle)();
	l.input._ = idler;
	auto idler2 = new EVReqT!(EVReq.Type.Idle)();
	l.input._ = idler2;*/
	auto timer = new EVReqT!(EVReq.Type.Timer)(10, 0);
	l.input._ = timer;


	go!({for (;;) {writeln("run"); l.run(); yield(); } });
	final switch(select(timer.ready)) {//idler.ready, idler2.ready)) {
		case 0:
			writeln("woot");
			break;
		case 1:
			writeln("wart");
			break;
	}
	shutdown();
}