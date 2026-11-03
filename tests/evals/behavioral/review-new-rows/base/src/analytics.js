// Stand-in for a product-analytics client.
const events = [];
function track(name, props) {
  events.push({ name, props });
}
module.exports = { track, events };
