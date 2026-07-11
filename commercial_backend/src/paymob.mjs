import { createHmac, timingSafeEqual } from "node:crypto";

const TRANSACTION_HMAC_FIELDS = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_3d_secure",
  "is_auth",
  "is_capture",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order.id",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
];

function valueAtPath(object, path) {
  return path.split(".").reduce((value, key) => value?.[key], object);
}

export function calculatePaymobTransactionHmac(transaction, secret) {
  if (!secret) throw new Error("Paymob HMAC secret is not configured.");
  const canonical = TRANSACTION_HMAC_FIELDS.map((field) =>
    String(valueAtPath(transaction, field) ?? ""),
  ).join("");
  return createHmac("sha512", secret).update(canonical).digest("hex");
}

export function verifyPaymobTransactionHmac(transaction, provided, secret) {
  if (!/^[a-f0-9]{128}$/i.test(String(provided ?? ""))) return false;
  const expected = Buffer.from(
    calculatePaymobTransactionHmac(transaction, secret),
    "hex",
  );
  const actual = Buffer.from(String(provided), "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
