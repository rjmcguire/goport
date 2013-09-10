module server;

import std.stdio;
import std.socket;
import goroutine;

unittest {
	writeln("woot1");
	auto l = new TcpSocket;
	scope(exit) {
		writeln("listner shutdown");
		l.shutdown(SocketShutdown.BOTH);
		l.close();
	}
	l.bind(getAddress("localhost", 8080)[0]);
	l.listen(5);
	for(;;) {
		writeln("accept");// can only accept as many connections as there are threads because handle() never returns and send() doesn't switch between fibers
		auto s = l.accept;
		go!({handle(s);});
	}
}

void handle(Socket s) {
	scope(exit) {
		s.shutdown(SocketShutdown.BOTH);
		s.close();
	}
	for (;;) {
		auto r = s.send(cast(ubyte[])"done");
		if (r == EOF) {
			break;
			writeln("ex");
		}
		writeln("sent");
	}
	writeln("return");
}