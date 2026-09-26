// Tiny static server for testing the Web export locally: node tools/serve.js [port]
// POST /log prints lines to stdout (used by tools/duo.html to relay in-game logs).
const http = require("http"), fs = require("fs"), path = require("path");
const root = path.join(__dirname, "..", "build", "web");
const port = +process.argv[2] || 8060;
const types = { ".html": "text/html", ".js": "text/javascript", ".wasm": "application/wasm",
  ".pck": "application/octet-stream", ".png": "image/png", ".json": "application/json" };
http.createServer((req, res) => {
  if (req.method === "POST" && req.url.startsWith("/log")) {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => { console.log(body); res.writeHead(204); res.end(); });
    return;
  }
  let p = decodeURIComponent(req.url.split("?")[0]);
  if (p.endsWith("/")) p += "index.html";
  const file = path.join(root, p);
  if (!file.startsWith(root)) { res.writeHead(403); return res.end(); }
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); return res.end("not found"); }
    res.writeHead(200, { "Content-Type": types[path.extname(file)] || "application/octet-stream", "Cache-Control": "no-store" });
    res.end(data);
  });
}).listen(port, () => console.log(`Serving ${root} at http://localhost:${port}`));
