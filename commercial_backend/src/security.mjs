import {
  createHash,
  createHmac,
  randomBytes,
  scrypt as scryptCallback,
  timingSafeEqual,
} from "node:crypto";
import { promisify } from "node:util";

const scrypt = promisify(scryptCallback);
const SCRYPT_N = 16_384;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const HASH_BYTES = 64;

function safeEqual(left, right) {
  const a = Buffer.from(String(left));
  const b = Buffer.from(String(right));
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function hashPassword(password) {
  if (typeof password !== "string" || password.length < 10) {
    throw new Error("Password must contain at least 10 characters.");
  }
  const salt = randomBytes(16);
  const derived = await scrypt(password, salt, HASH_BYTES, {
    N: SCRYPT_N,
    r: SCRYPT_R,
    p: SCRYPT_P,
    maxmem: 64 * 1024 * 1024,
  });
  return [
    "scrypt",
    SCRYPT_N,
    SCRYPT_R,
    SCRYPT_P,
    salt.toString("base64url"),
    Buffer.from(derived).toString("base64url"),
  ].join("$");
}

export async function verifyPassword(password, encoded) {
  if (typeof password !== "string" || typeof encoded !== "string") return false;
  if (/^[a-f0-9]{64}$/i.test(encoded)) {
    const legacy = createHash("sha256").update(password).digest("hex");
    return safeEqual(legacy.toLowerCase(), encoded.toLowerCase());
  }
  const [scheme, nRaw, rRaw, pRaw, saltRaw, hashRaw] = encoded.split("$");
  const N = Number(nRaw);
  const r = Number(rRaw);
  const p = Number(pRaw);
  if (
    scheme !== "scrypt" ||
    !Number.isInteger(N) ||
    !Number.isInteger(r) ||
    !Number.isInteger(p) ||
    N < 2 ||
    N > 32_768 ||
    r < 1 ||
    r > 16 ||
    p < 1 ||
    p > 4
  ) {
    return false;
  }
  try {
    const salt = Buffer.from(saltRaw, "base64url");
    const expected = Buffer.from(hashRaw, "base64url");
    if (salt.length < 16 || expected.length !== HASH_BYTES) return false;
    const actual = Buffer.from(
      await scrypt(password, salt, expected.length, {
        N,
        r,
        p,
        maxmem: 64 * 1024 * 1024,
      }),
    );
    return timingSafeEqual(actual, expected);
  } catch {
    return false;
  }
}

function encodeJson(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

export function signAccessToken(payload, secret, options = {}) {
  if (typeof secret !== "string" || secret.length < 32) {
    throw new Error("JWT secret must contain at least 32 characters.");
  }
  const now = options.nowSeconds ?? Math.floor(Date.now() / 1000);
  const ttl = options.ttlSeconds ?? 15 * 60;
  const header = encodeJson({ alg: "HS256", typ: "JWT" });
  const body = encodeJson({ ...payload, iat: now, exp: now + ttl });
  const signature = createHmac("sha256", secret)
    .update(`${header}.${body}`)
    .digest("base64url");
  return `${header}.${body}.${signature}`;
}

export function verifyAccessToken(token, secret, options = {}) {
  if (typeof token !== "string" || typeof secret !== "string") {
    throw new Error("Invalid access token.");
  }
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("Invalid access token.");
  const [headerRaw, bodyRaw, signature] = parts;
  const expected = createHmac("sha256", secret)
    .update(`${headerRaw}.${bodyRaw}`)
    .digest("base64url");
  if (!safeEqual(signature, expected)) throw new Error("Invalid access token.");
  let header;
  let payload;
  try {
    header = JSON.parse(Buffer.from(headerRaw, "base64url").toString("utf8"));
    payload = JSON.parse(Buffer.from(bodyRaw, "base64url").toString("utf8"));
  } catch {
    throw new Error("Invalid access token.");
  }
  if (header.alg !== "HS256" || header.typ !== "JWT") {
    throw new Error("Invalid access token.");
  }
  const now = options.nowSeconds ?? Math.floor(Date.now() / 1000);
  if (!Number.isFinite(payload.exp) || now >= payload.exp) {
    throw new Error("Access token expired.");
  }
  return payload;
}

export function randomToken(bytes = 32) {
  return randomBytes(bytes).toString("base64url");
}

export function hashToken(token) {
  return createHash("sha256").update(token).digest("hex");
}
