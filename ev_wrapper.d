module ev_wrapper;
import deimos.ev;
import std.socket, std.c.linux.socket : socket, sockaddr, sockaddr_in,socklen_t, accept, recv, send;
import std.stdio;
import channel, goroutine;

public import deimos.ev : EV_ERROR, EV_READ, EV_WRITE;

EVLoop loop;
shared static this() {
	/*auto t = new Thread(() {loop();});
	t.start();*/

	//go!({loop();});
	//// make sure the events system is running before main is called
	//while(!loop.initialized) {
	//	sleep(dur!"usecs"(10));
	//}

	loop();
}


struct EVLoop {
	void opCall() {
		EVLoop ret;
		ret.started = makeChan!bool(1);
		ret.loop = cast(shared)ev_default_loop(0);
		ret.scheduleCallback_chan = makeChan!EVReq(100);
		ret.scheduleStop_chan = makeChan!StopEVReq(100);

		ev_async_init(cast(ev_async*)&wakeup, &mustWake);
		ev_async_start(cast(void*)loop, cast(ev_async*)&wakeup);
		started._ = true;
	}
	bool initialized() {
		return scheduleCallback_chan !is null;
	}
	void wake() {
		started._ = started._;
		writeln("wking ", loop, &wakeup);
		ev_async_send(cast(void*)loop, cast(ev_async*)&wakeup);
	}
	void start() {
		//scheduleCallback_chan._ = new EVReqIdle();
		writeln("started");
		for (;;) {
			while (!scheduleCallback_chan.empty) {
				auto req = scheduleCallback_chan._;
				writeln("got schedule request: ", req);
				req.add(cast(void*)loop);
			}
			while (!scheduleStop_chan.empty) {
				auto req = scheduleStop_chan._;
				writeln("got stop req");
				req.stop(cast(void*)loop);
			}
			//writeln("ev_run");
			ev_run(cast(void*)loop, EVRUN_ONCE);
			//writeln("ev_run done");
			yield();
		}
	}
	
private:
	shared static chan!bool started;
	shared static ev_async wakeup;
	shared static chan!EVReq scheduleCallback_chan;
	shared static chan!StopEVReq scheduleStop_chan;
	shared static void* loop;
	extern(C)static void mustWake(ev_loop_t* loop, ev_async* as, int revents) {}

}
auto schedule(Socket s, uint ev_mask, void delegate(Socket, bool error) cb) {
	writeln("hey", loop.scheduleCallback_chan is null);
	auto ret = new EVReqSocketIO(s, ev_mask, cb);
	loop.scheduleCallback_chan._ = ret;
	writeln("boom");
	loop.wake();
	return ret;
}
auto schedule(File f, uint ev_mask, void delegate(File, bool error) cb) {
	writeln("hey2", loop.scheduleCallback_chan is null);
	auto ret = new EVReqFileIO(f, ev_mask, cb);
	loop.scheduleCallback_chan._ = ret;
	writeln("boom2");
	loop.wake();
	return ret;
}
auto schedule(ev_tstamp after, ev_tstamp repeat_delay, void function() callback) {
	auto ret = new EVReqTicker(after, repeat_delay, () { writeln("tick"); });
	loop.scheduleCallback_chan._ = ret;
	loop.wake();
	return ret;
}
auto schedule(uint signum, void function() callback) {
	auto ret = new EVReqSignal(signum, callback);
	loop.scheduleCallback_chan._ = ret;
	loop.wake();
	return ret;
}

class EVReq {
	Type type; enum Type {IO,Timer,Signal,Child,FileSystem,Idle,BeforeBlock,AfterBlock,AfterFork,BeforeDestroy,WakeUp};
	uint ev_mask;
	this(Type t, uint ev_mask) {
		type = t;
	}
	abstract void add(ev_loop_t* loop);
	abstract void stop(ev_loop_t* loop);
	void stop() {
		loop.scheduleStop_chan._ = StopEVReq(this);
	}
}
struct StopEVReq {
	EVReq req;
	void stop(ev_loop_t* loop) {
		req.stop(loop);
	}
}
class EVReqIdle : EVReq {
	ev_idle idle;

	this() {
		super(Type.Idle, 0);
	}
	override
	void add(ev_loop_t* loop) {
		ev_idle_init(&idle, &cb);
		ev_idle_start(loop, &idle);
	}
	extern(C) static void cb(ev_loop_t* loop, ev_idle *idle, int revents) {
		//writeln("idling");
	}
	override
	void stop(ev_loop_t* loop) {
		ev_idle_stop(loop, &idle);
	}
}
class EVReqIO : EVReq {
	ev_io* io_ptr;
	uint ev_mask;
	this(uint ev_mask) {
		super(Type.IO, ev_mask);
		this.io_ptr = new ev_io;
		io_ptr.data = cast(void*)this;
		writeln("ptr = ", io_ptr.data);
		this.ev_mask = ev_mask;
	}
	abstract void call(uint revents);
	extern(C) static void callback(ev_loop_t* loop, ev_io *ev, int revents) {
		EVReqIO self = cast(EVReqIO)ev.data;
		self.call(revents);
	}
	/*** !!!! are we allowed to call this whenever?! there is no protection here! what if evrun is looking at io_ptr at the time ***/
	override
	void stop(ev_loop_t* loop) {
		ev_io_stop(loop, io_ptr);
	}
	alias EVReq.stop stop;
	void restart() {
		loop.scheduleCallback_chan._ = this;
	}
}
class EVReqSocketIO : EVReqIO {
	Socket s;
	void delegate(Socket, bool) cb;
	// called in user code
	this(Socket s, uint ev_mask, void delegate(Socket, bool error) cb) {
		super(ev_mask);
		writeln("sock ptr = ", &this);
		this.s = s;
		this.cb = cb;
		ev_io_init(io_ptr, &callback, s.handle, ev_mask);
	}


	/// This will get called in the evrun thread
	override
	void add(ev_loop_t* loop) {
		writeln("adding");
		ev_io_start(loop, io_ptr);

	}
	override void call(uint revents) {
		writeln("got err? ", revents & EV_ERROR);
		cb(s, (revents & EV_ERROR) == EV_ERROR);
	}
}
class EVReqFileIO : EVReqIO {
	File f;
	void delegate(File, bool) cb;
	this(File f, uint ev_mask, void delegate(File,bool) cb) {
		super(ev_mask);
		writeln("file");
		this.f = f;
		this.cb = cb;
		ev_io_init(io_ptr, &callback, f.fileno, ev_mask);
	}
	override
	void add(ev_loop_t* loop) {
		writeln("adding file");
		ev_io_start(loop, io_ptr);
	}
	override
	void call(uint revents) {
		cb(f, (revents & EV_ERROR) == EV_ERROR);
	}
}

class EVReqTicker : EVReq {
	ev_timer timer_ptr;
	void function() cb;
	this(ev_tstamp after, ev_tstamp repeat_delay, void function() cb) {
		super(Type.Timer, 0);
		timer_ptr.data = cast(void*)this;
		this.cb = cb;
		ev_timer_init(&timer_ptr, &callback, after, repeat_delay);
	}
	extern(C) static void callback(ev_loop_t* loop, ev_timer* timer, int revent) {
		EVReqTicker self = cast(EVReqTicker)timer.data;
		self.cb();
	}
	override
	void add(ev_loop_t* loop) {
		writeln("adding timer");
		ev_timer_start(loop, &timer_ptr);
	}
	override
	void stop(ev_loop_t* loop) {
		ev_timer_stop(loop, &timer_ptr);
	}
	alias EVReq.stop stop;
}

class EVReqSignal : EVReq {
	ev_signal signal_ptr;
	void function() cb;
	this(int signum, void function() cb) {
		super(Type.Signal, 0);
		signal_ptr.data = cast(void*)this;
		this.cb = cb;
		ev_signal_init(&signal_ptr, &callback, signum);
	}
	override
	void add(ev_loop_t* loop) {
		ev_signal_start(loop, &signal_ptr);
	}
	extern(C) static void callback(ev_loop_t* loop, ev_signal *signal_ptr, int revents) {
		EVReqSignal self = cast(EVReqSignal)signal_ptr.data;
		self.cb();
	}
	override
	void stop(ev_loop_t* loop) {
		ev_signal_stop(loop, &signal_ptr);
	}

}


class EVReqChild : EVReq {
	ev_child child_ptr;
	void function(int pid, int rpid, int rstatus) cb;
	/** default watch all pids (watch_pid), and only activate when a process terminates (trace) */
	this(void function(int pid, int rpid, int rstatus) cb, int watch_pid = 0, int trace=0) {
		super(Type.Child, 0);
		child_ptr.data = cast(void*)this;
		this.cb = cb;
		ev_child_init(&child_ptr, &callback, watch_pid, trace);
	}
	override
	void add(ev_loop_t* loop) {
		ev_child_start(loop, &child_ptr);
	}
	extern(C) static void callback(ev_loop_t* loop, ev_child *child_ptr, int revents) {
		EVReqChild self = cast(EVReqChild)child_ptr.data;
		self.cb(child_ptr.pid, child_ptr.rpid, child_ptr.rstatus);
	}
	override
	void stop(ev_loop_t* loop) {
		ev_child_stop(loop, &child_ptr);
	}

}



/+
struct EV {
*	void watchReadable(int fd, Callback cb) {}
*	void watchWriteable(int fd, Callback cb) {}
*	void createTimer() {}
*	void watchForSignal(sig, Callback cb) {}
*	void watchChildProcesses(sig, Callback cb) {}
*	void watchFile(string filename, Callback cb) {}
*	void callWhenIdle(Callback cb) {}
	void callBeforeBlock(Callback cb) {}
	void callAfterBlock(Callback cb) {}
	void callAfterFork(Callback cb) {}
	// ev_embed not used or implemented
	void callBeforeLoopDestroy(Callback cb) {/* ev_cleanup*/}
*	void forceWakeUp() {/*ev_async*/}
}+/