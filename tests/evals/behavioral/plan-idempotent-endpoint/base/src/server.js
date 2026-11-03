// Minimal router: routes[method + ' ' + path] = handler(req, res).
const routes = {};
function route(method, path, handler) { routes[method + ' ' + path] = handler; }
function handle(req, res) {
  const h = routes[req.method + ' ' + req.path];
  return h ? h(req, res) : res.status(404).end();
}
module.exports = { route, handle };
