import {createServer} from 'node:http';
import worker from './index.js';

const cache = new Map();
globalThis.caches = {default:{
 async match(request) {
  const entry = cache.get(request.url);
  if (entry && entry.until > Date.now()) return entry.response.clone();
  cache.delete(request.url);
 },
 async put(request, response) {
  if (cache.size >= 128) cache.delete(cache.keys().next().value);
  cache.set(request.url, {response:response.clone(), until:Date.now() + 120_000});
 },
}};

createServer(async (request, response) => {
 try {
  const result = await worker.fetch(new Request(new URL(request.url, 'http://127.0.0.1:8787')), process.env);
  response.writeHead(result.status, Object.fromEntries(result.headers));
  response.end(await result.text());
 } catch {
  response.writeHead(502, {'content-type':'application/json', 'access-control-allow-origin':'*'});
  response.end(JSON.stringify({error:'Flight lookup failed'}));
 }
}).listen(8787, '127.0.0.1', () => console.log('Flight Worker listening on http://127.0.0.1:8787'));
