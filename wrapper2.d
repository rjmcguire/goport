module wrapper2;
// compile with: dmd -g -debug -main -unittest wrapper2.d -I~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev ~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev/deimos/ev.d -L-lev

import deimos.ev;
import channel : chan, makeChan, select;
import goroutine : go;

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
			input._.add(loop);
		}
		ev_run(loop, EVRUN_ONCE);
	}
}

class EVReq {
	abstract void add(ev_loop_t* loop);
}
class EVReqIdle : EVReq {
	ev_idle watcher;
	shared chan!bool ready = makeChan!bool(1);
	override
	void add(ev_loop_t* loop) {
		watcher.data = cast(void*)this;
		ev_idle_init(&watcher, &cb);
		ev_idle_start(loop, &watcher);
	}
	extern(C) static void cb(ev_loop_t* loop, ev_idle *idle, int revents) {
		EVReqIdle self = cast(EVReqIdle)idle.data;
		assert(idle is &self.watcher);
		self.ready._ = true;
		writeln("okay");
	}
}


unittest {
	import std.stdio;
	auto l = new Loop();
	auto idler = new EVReqIdle();
	l.input._ = idler;
	auto idler2 = new EVReqIdle();
	l.input._ = idler2;
	go!({writeln("run"); l.run(); });

	final switch(select(idler.ready, idler2.ready)) {
		case 0:
			writeln("woot");
			break;
		case 1:
			writeln("wart");
			break;
	}
}