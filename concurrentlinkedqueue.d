// Algorithm from: http://www.cs.rochester.edu/research/synchronization/pseudocode/queues.html#nbq
// Non-blocking queue.
import core.atomic;

unittest {
	import std.stdio;
	import goroutine;

	class A { int a; shared this(int i) {a=i;} }
	auto queue = new shared ConcurrentLinkedQueue!A;
	foreach(i; 0..1000_000_000)
		queue.put(new shared A(i));

	go!({foreach (i; 0..200000) writeln("1q: ", queue.popFront().a);});
	go!({foreach (i; 0..200000) writeln("2q: ", queue.popFront().a);});
	go!({foreach (i; 0..200000) writeln("3q: ", queue.popFront().a);});
	go!({foreach (i; 0..200000) writeln("4q: ", queue.popFront().a);});
	go!({foreach (i; 0..200000) writeln("5q: ", queue.popFront().a);});

	writeln("done");
	shutdown();
}



shared public class ConcurrentLinkedQueue(T) if (is(typeof(null) : T)) {
private:
	struct Node(T) {
		T item;
		shared Node!T* next;
		shared ~this() {
			import std.stdio;
			writeln("deleted");
		}
	}
	Node!T* head;
	Node!T* tail;

public:
	this() {
		head = new shared Node!T(null, null);
		tail = head;
	}

	bool put(shared T v) {
		if (v is null) throw new Exception("NullPointerException");
		auto n = new shared Node!T(v, null);
		for (;;) {
			auto currenttail = tail;
			auto next = currenttail.next;
			if (currenttail == tail) {
				if (next is null) {
					if (cas(&currenttail.next, next, n)) {
						cas(&tail, currenttail, n);
						return true;
					}
				} else {
					cas(&tail, currenttail, next);
				}
			}
		}
		assert(false, "should never reach here");
	}

	auto popFront() {
		for (;;) {
			auto currenthead = head;
			auto currenttail = tail;
			auto first = currenthead.next;
			if (currenthead == head) {
				if (currenthead == currenttail) {
					if (first is null) {
						return null;
					} else {
						cas(&tail, currenttail, first);
					}
				} else if (cas(&head, currenthead, first)) {
					auto item = first.item;
					if (!haslsb(&item)) {
						setlsb(&first.item);
						return item;
					}
				}
			}
		}
		assert(false, "should never reach here");
	}

	auto front() {
		for (;;) {
			auto currenthead = head;
			auto currenttail = tail;
			auto first = currenthead.next;
			if (currenthead == head) {
				if (currenthead == currenttail) {
					if (first is null) {
						return null;
					} else {
						cas(&tail, currenttail, first);
					}
				} else {
					auto item = first.item;
					if (!haslsb(&item)) {
						return item;
					} else {
						// here we remove deleted nodes
						cas(&head, currenthead, first);
					}
				}
			}
		}
		assert(false, "should never reach here");
	}

	@property
	auto empty() {
		return front is null;
	}

private:
	bool haslsb(shared T* t) {
		return ((cast(size_t)t) & 1) == 1;
	}
	T* setlsb(shared T* p) {
		return cast(T*)(cast(size_t)p|1);
	}
}






// ================= Basic Types Queue ========================================


shared public class ConcurrentLinkedQueue(T) if (is(T == bool)) {
private:
	struct Node(T) {
		T* item;
		shared Node!T* next;
	}
	Node!T* head;
	Node!T* tail;


public:
	this() {
		head = new shared Node!T(null, null);
		tail = head;
	}

	bool put(shared T value) {
		auto v = new shared T;
		*v = value;
		auto n = new shared Node!T(v, null);
		for (;;) {
			auto currenttail = tail;
			auto next = currenttail.next;
			if (currenttail == tail) {
				if (next is null) {
					if (cas(&currenttail.next, next, n)) {
						cas(&tail, currenttail, n);
						return true;
					}
				} else {
					cas(&tail, currenttail, next);
				}
			}
		}
		assert(false, "should never reach here");
	}

	auto popFront() {
		for (;;) {
			auto currenthead = head;
			auto currenttail = tail;
			auto first = currenthead.next;
			if (currenthead == head) {
				if (currenthead == currenttail) {
					if (first is null) {
						return null;
					} else {
						cas(&tail, currenttail, first);
					}
				} else if (cas(&head, currenthead, first)) {
					auto item = first.item;
					if (!haslsb(item)) {
						setlsb(first.item);
						return item;
					}
				}
			}
		}
		assert(false, "should never reach here");
	}

	auto front() {
		for (;;) {
			auto currenthead = head;
			auto currenttail = tail;
			auto first = currenthead.next;
			if (currenthead == head) {
				if (currenthead == currenttail) {
					if (first is null) {
						return null;
					} else {
						cas(&tail, currenttail, first);
					}
				} else {
					auto item = first.item;
					if (!haslsb(item)) {
						return item;
					} else {
						// here we remove deleted nodes
						cas(&head, currenthead, first);
					}
				}
			}
		}
		assert(false, "should never reach here");
	}

	@property
	auto empty() {
		return front is null;
	}

private:
	bool haslsb(shared T* t) {
		return ((cast(size_t)t) & 1) == 1;
	}
	T* setlsb(shared T* p) {
		return cast(T*)(cast(size_t)p|1);
	}
}
