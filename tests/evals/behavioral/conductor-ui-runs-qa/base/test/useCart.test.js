import test from "node:test";
import assert from "node:assert/strict";
import { cartTotal } from "../src/hooks/useCart.js";

test("an empty cart totals zero", () => {
  assert.equal(cartTotal([]), 0);
});
