module server;
// compile with: dmd -unittest -main server_test.d goroutine.d channel.d -I~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev ~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev/deimos/ev.d -L-lev
import std.socket : Socket, TcpSocket, getAddress, SocketShutdown;
import std.stdio;
import goroutine : donate, shutdown;
import ev_wrapper;
import std.datetime;

void main() {
	auto l = new TcpSocket;
	scope(exit) {
		l.shutdown(SocketShutdown.BOTH);
		l.close();
		writeln("listener shutdown");
	}
	l.bind(getAddress("localhost", 8080)[0]);
	l.listen(5);

	auto server_ev = schedule(l, EV_READ, (Socket l, bool error) {
		if (error) {writeln("listen got error");}
		writeln("accepting");
		auto c = l.accept();

		EVReqSocketIO reader_ev;
		reader_ev = schedule(c, EV_READ, (Socket c, bool error) {
			if (error) {writeln("read got error");}
			writeln("readable! on ", reader_ev);
			ubyte[4096] buf;
			auto n = c.receive(buf);
			if (n == 0) {
				writeln("connection probably lost, reqceived zero bytes on ready for reading");
				reader_ev.stop();
				return;
			}
			assert(n > 0);
			writeln("read: ", buf[0..n]);
			reader_ev.stop();
			EVReqSocketIO writer_ev;
			writer_ev = schedule(c, EV_WRITE, (Socket c, bool error) {
				if (error) {writeln("write got error");}
				auto n1 = c.send(buf[0..n]);
				writeln("wrote n:", n1);
				writer_ev.stop();
				reader_ev.restart();
				});
		});
	});

	schedule(1, 2, () { writeln("tick"); });

	EVReqFileIO file_ev;
	file_ev = schedule(stdin, EV_READ, (File f, bool error) {
		if (error) {writeln("file read got error");}
		ubyte[4096] backbuf;
		auto buf = f.rawRead(backbuf);
		if (f.eof) file_ev.stop;
		writeln(f, buf);
	});

	import core.stdc.signal;
	schedule(SIGINT, () {shutdown(); writeln("sigint!");});

	writeln("callback setup complete.");
	donate();
	/*writeln("sleeping for 100000");
	sleep(dur!"seconds"(100000));*/
	write("exit");
}
