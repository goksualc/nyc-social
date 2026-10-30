// Tiny stand-in for the Supabase gateway: maps /rest/v1/* to a bare PostgREST so the iOS SDK (which targets
// <url>/rest/v1) can talk to it in integration tests. Test harness only.
const http = require('http');
const target = { host: '127.0.0.1', port: Number(process.env.POSTGREST_PORT || 3000) };
http.createServer((req, res) => {
  if (!req.url.startsWith('/rest/v1/')) { res.writeHead(404); return res.end('{}'); }
  const upstream = http.request({ ...target, method: req.method, path: req.url.replace('/rest/v1', ''), headers: req.headers },
    (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res); });
  upstream.on('error', (e) => { res.writeHead(502); res.end(JSON.stringify({ message: String(e) })); });
  req.pipe(upstream);
}).listen(Number(process.env.PROXY_PORT || 54321), '127.0.0.1');
