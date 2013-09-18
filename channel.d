import goroutine : sleep, yield;
import std.datetime : dur;
import std.traits : isInstanceOf;
//void select(T)(T...) if (isMadeOf(chan)) { go through each arg and first !arg.empty is winner }
import std.stdio;
import sync.semaphore;
import core.sync.condition;
import concurrentlinkedqueue;


/**
 * chan allows messaging between threads without having to deal with locks, similar to how chan works in golang
 */
shared
class chan(T) {
	const size_t maxItems;
	bool blockOnFull = false;
	Semaphore sem;
	__gshared Condition emptyLock;
	ConcurrentLinkedQueue!T queue;
	private bool closed_; @property bool closed() {synchronized (this) {return closed_;}} void close() { synchronized(this) { closed_ = true; } emptyLock.notifyAll(); }

	this(int maxItems = 1024, bool blockOnFull = true) {
		sem = new shared Semaphore(maxItems);
		queue = new shared ConcurrentLinkedQueue!T();
		emptyLock = new Condition(new Mutex);

		this.maxItems = maxItems;
		this.blockOnFull = blockOnFull;
	}

	@property
	void _(T value) {
		if (blockOnFull) {
			while (!sem.wait(dur!"seconds"(1))) {
				if (closed) {
					throw new ChannelClosedException();
				}
			}
		}
		if (closed) {
			throw new ChannelClosedException();
		}
		queue.put(cast(shared) value);
		emptyLock.notifyAll();
	}
	@property
	T _() {
		if (closed) throw new ChannelClosedException;
		emptyLock.mutex.lock();
		while (empty) {
			emptyLock.wait();
			if (closed) throw new ChannelClosedException;
		}
		emptyLock.mutex.unlock();

		auto ret = queue.popFront();
		assert(ret !is null);
		sem.notify();
		return cast(T)ret;
	}
	T popFront() {
		return _();
	}
	T front() {
		return cast(T)queue.front;
	}
	void put(T v) {
		_(v);
	}

	// check if there is something to read, chan will block if this returns false and you call _().
	// NOTE: if another thread empties the chan between a call to this function and a call to _() the
	// calling fiber/Thread will block
	@property
	bool empty() {
		return queue.empty;
	}

	// check if there is space in the chan to write to, chan will block if this returns false and you call _(T).
	// NOTE: if another thread fills the chan between a call to this function and a call to _(T) the
	// calling fiber/Thread will block
	@property
	bool writable() {
		auto ret = sem.tryWait();
		scope(exit) sem.notify;
		return ret;
	}

	void opOpAssign(string U)(T v) if (U == "~") {
		_(v);
	}
	@property
	T get() {
		return _();
	}
	T opCall() {
		return _();
	}
	alias get this;
}
shared(chan!T) makeChan(T)(int n, bool blockOnFull = true) {
	return new shared chan!T(n, blockOnFull);
}




int select(Args...)(Args args) if (allischan!Args()) {
	import std.random : uniform;

	const WAIT = 1; // WAIT implements dynamic polling dropoff for the select loop, took cpu usage from 12% when idle to 0% when idle on a laptop
	double wait = WAIT;
	while (true) {
		int[] ready;
		int closed;
		ready.reserve(args.length);
		foreach (i, arg; args) {
			if (arg.closed)
				closed++;
			if (!arg.empty) {
				ready ~= i;
				}
		}
		if (closed >= args.length) {
			return -1;
		}
		if (ready.length > 0) {
			wait = WAIT;
			auto idx = uniform(0,ready.length);
			return ready[idx];
		} else {
			wait *= 1.01;
		}
		sleep(dur!"hnsecs"(cast(long)std.math.floor(wait)));
	}
}
int select(Args...)(Args args) if (!allischan!Args()) {
	import std.conv;
	foreach (i, arg; Args) {
		static if (!isInstanceOf!(chan, arg)) {
			static assert(0, "select(Args args) only accepts parameters of type: shared(chan) not argument "~ to!string(i+1) ~" of type: "~ arg.stringof);
		}
	}
	assert(0, "should never reach here");
}


bool allischan(Args...)() {
	foreach (arg; Args) {
		static if (!isInstanceOf!(chan, arg)) {
			return false;
		}
	}
	return true;
}

class ChannelException : Exception {
	this(string msg, string file = __FILE__, int line = __LINE__) {
		super(msg,file,line);
	}
}
class ChannelFullException : ChannelException {
	this(string msg = "Channel Full", string file = __FILE__, int line = __LINE__) {
		super(msg,file,line);
	}
}
class ChannelClosedException : ChannelException {
	this(string msg = "Channel Closed", string file = __FILE__, int line = __LINE__) {
		super(msg,file,line);
	}
}