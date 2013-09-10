module server;
// compile with: dmd -unittest -main server_test.d goroutine.d channel.d -I~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev ~/Documents/Programming/d/src/github.com/D-Programming-Deimos/libev/deimos/ev.d -L-lev

import std.stdio, std.socket, std.c.linux.socket : socket, sockaddr, sockaddr_in,socklen_t, accept, recv, send;
import deimos.ev;

extern(C)void read_cb(ev_loop_t* loop, ev_io* watcher, int revents) {
	if (revents & EV_ERROR) writeln("error!");
	if (revents & EV_READ) {
		ubyte[4096] buf;
		auto read = recv(watcher.fd, cast(void*)buf.ptr, 4096, 0);
		if (read < 0) {
			writeln("read error");
			return;
		}
		if (read == 0) {
			// stop and free watcher if socket is closing
			ev_io_stop(loop, watcher);
			writeln("peer might be closing");
			return;
		} else {
			writeln("message: ", buf[0..read]);
		}
		send(watcher.fd, cast(void*)buf.ptr, read, 0);
	}
}
extern(C)static void accept_cb (ev_loop_t* loop, ev_io *w, int revents) {
	if (revents & EV_ERROR) {
		writeln("got error");
		return;
	}
	if (revents & EV_READ) {
			writeln("accepting");
			// ================== SETUP READ CLIENT ===================
			ev_io* client_w = new ev_io;

			sockaddr client_addr;
			socklen_t client_len = client_addr.sizeof;
			auto client_sd = accept(w.fd, &client_addr, &client_len);
			if (client_sd < 0) {
				writeln("accept error: ", client_sd);
				return;
			}

			writeln("connection successful, ", client_addr);
			ev_io_init(client_w, &read_cb, client_sd, EV_READ);
			ev_io_start(loop, client_w);
			// ================== SETUP READ CLIENT ===================
	}
}

void main() {
	writeln("woot1");
	auto l = new TcpSocket;
	scope(exit) {
		l.shutdown(SocketShutdown.BOTH);
		l.close();
		writeln("listener shutdown");
	}
	l.bind(getAddress("localhost", 8080)[0]);
	l.listen(5);

	ev_loop_t* evloop = ev_default_loop(0);
	ev_io io_watcher;
	ev_io_init(&io_watcher, &accept_cb, l.handle, EV_READ);
	ev_io_start(evloop, &io_watcher);

	writeln("ready");
	bool running = true;
	while (running)
		ev_run(evloop, EVRUN_ONCE);
}
