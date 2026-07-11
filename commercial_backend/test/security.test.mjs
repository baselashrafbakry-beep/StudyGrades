import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import {
  hashPassword,
  signAccessToken,
  verifyAccessToken,
  verifyPassword,
} from "../src/security.mjs";

test("scrypt password hashes verify without storing plaintext", async () => {
  const encoded = await hashPassword("correct horse battery staple");

  assert.match(encoded, /^scrypt\$/);
  assert.equal(
    await verifyPassword("correct horse battery staple", encoded),
    true,
  );
  assert.equal(await verifyPassword("wrong", encoded), false);
  assert.equal(encoded.includes("correct horse"), false);
});

test("legacy sha256 passwords can be verified for one-time migration", async () => {
  const legacy = createHash("sha256").update("legacy-password").digest("hex");

  assert.equal(await verifyPassword("legacy-password", legacy), true);
  assert.equal(await verifyPassword("wrong", legacy), false);
});

test("access tokens reject tampering and expiry", () => {
  const secret = "a-secure-test-secret-that-is-long-enough";
  const token = signAccessToken(
    { sub: "42", role: "teacher", session_id: "session-1" },
    secret,
    { nowSeconds: 1_000, ttlSeconds: 60 },
  );

  assert.equal(verifyAccessToken(token, secret, { nowSeconds: 1_059 }).sub, "42");
  assert.throws(() => verifyAccessToken(`${token}x`, secret));
  assert.throws(() => verifyAccessToken(token, secret, { nowSeconds: 1_061 }));
});
