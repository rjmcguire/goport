import core.thread : Thread, Fiber, thread_isMainThread, getpid;
import core.atomic;
import std.conv;
import std.process : environment;
import std.datetime;
import std.stdio : stderr;

import core.sys.posix.signal : kill, SIGABRT;

import channel;

@property
void go(alias F)() {
	lazyStart();
	scheduler._ = new Fiber(F);
}
/// sleep for d duration, uses Fiber.yield if running in a Fiber.
void sleep(Duration d = dur!"usecs"(1)) {
	if (Fiber.getThis() is null) {
		Thread.sleep(d);
	} else {
		auto begin = Clock.currTime();
		for (;;Fiber.yield()) {
			auto now = Clock.currTime();
			if (now - begin > d) {
				break;
			}
		}
	}
}
/// If in a Fiber the fiber yields if in a Thread the thread yields.
void yield() {
	if (Fiber.getThis() is null) {
		Thread.yield();
	} else {
		Fiber.yield();
	}
}

void shutdown() {
	scheduler.close();
}

void donate() {
	for (;;) {
		Fiber fiber;
		try {
			fiber = scheduler._;
		} catch (ChannelClosedException cce) {
			writeln(cce);
			break;
		}

		// don't catch any exceptions from the user code
		try {
			fiber.call();
		} catch (Exception e) {
			// we catch Error here because I hate it when runtime exceptions are swallowed with no evident of happening
			// e.g. An assert(false) in a fiber would be hidden unless we caught this Error, 
			stderr.writeln(e);
		} catch (Error e) {
			// we catch Error here because I hate it when runtime exceptions are swallowed with no evident of happening
			// e.g. An assert(false) in a fiber would be hidden unless we caught this Error, 
			stderr.writeln(e);
			kill(getpid(), SIGABRT);
		}

		if (fiber.state != Fiber.State.TERM) {
			try {
				scheduler._ (fiber);
			} catch (ChannelClosedException cce) {
				break;
			}
		} else if (scheduler.empty) {
			// exit thread, not enough fibers left to warrent thread count
			writeln("exiting");
			break;
		}
	}
}

// TODO: Scheduler should take sleep time into account.
import std.stdio;
private:
auto num_threads = 1;
Thread[] threads;
void lazyStart() {
	if (threads.length < num_threads) {
		auto t = new Thread(&donate);
		t.start();
		threads ~= t;
	}
}

shared chan!Fiber scheduler; // channel contains Fibers waiting for their time slice
shared static this () {
	scheduler = makeChan!Fiber(100);

	// create the workers
	auto goprocs = environment.get("GOPROCS");
	if (goprocs != null) {
		num_threads = to!int(goprocs);
	}
	/+	foreach (i; 0..num_threads) {
		// create threads that process the live fibers
		auto t = new Thread(() {
				donate();
			});
		t.start();
	}+/
}
shared static ~this() {
	if (thread_isMainThread()) {
		shutdown();
	}
}
