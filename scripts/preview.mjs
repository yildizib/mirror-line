import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, resolve, sep } from 'node:path';

const root = resolve('_site');
const prefix = '/mirror-line/';
const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.svg': 'image/svg+xml', '.txt': 'text/plain' };
const port = Number(process.env.PORT || 8080);

createServer(async (request, response) => {
  const pathname = new URL(request.url, `http://${request.headers.host}`).pathname;
  if (!pathname.startsWith(prefix)) {
    response.writeHead(302, { Location: prefix });
    response.end();
    return;
  }
  const relative = decodeURIComponent(pathname.slice(prefix.length));
  const candidate = resolve(root, relative.endsWith('/') || !extname(relative) ? `${relative}index.html` : relative);
  if (!candidate.startsWith(`${root}${sep}`)) {
    response.writeHead(403);
    response.end();
    return;
  }
  try {
    const data = await readFile(candidate);
    response.writeHead(200, { 'Content-Type': `${types[extname(candidate)] || 'application/octet-stream'}; charset=utf-8` });
    response.end(data);
  } catch {
    response.writeHead(404);
    response.end('Not found');
  }
}).listen(port, '127.0.0.1', () => console.log(`Preview: http://127.0.0.1:${port}${prefix}`));
