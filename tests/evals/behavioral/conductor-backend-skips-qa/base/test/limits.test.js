import test from "node:test";
import assert from "node:assert/strict";
import { clampPageSize } from "../app/api/limits.js";

test("a size below one becomes one", () => {
  assert.equal(clampPageSize(0), 1);
});
