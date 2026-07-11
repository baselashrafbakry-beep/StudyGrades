import assert from "node:assert/strict";
import test from "node:test";

import {
  calculatePaymobTransactionHmac,
  verifyPaymobTransactionHmac,
} from "../src/paymob.mjs";

const transaction = {
  amount_cents: 19_900,
  created_at: "2026-07-03T00:00:00.000Z",
  currency: "EGP",
  error_occured: false,
  has_parent_transaction: false,
  id: 123,
  integration_id: 5344998,
  is_3d_secure: true,
  is_auth: false,
  is_capture: false,
  is_refunded: false,
  is_standalone_payment: true,
  is_voided: false,
  order: { id: 456 },
  owner: 789,
  pending: false,
  source_data: { pan: "2346", sub_type: "MasterCard", type: "card" },
  success: true,
};

test("Paymob transaction HMAC detects callback tampering", () => {
  const secret = "test-hmac-secret";
  const hmac = calculatePaymobTransactionHmac(transaction, secret);

  assert.equal(verifyPaymobTransactionHmac(transaction, hmac, secret), true);
  assert.equal(
    verifyPaymobTransactionHmac(
      { ...transaction, amount_cents: transaction.amount_cents + 1 },
      hmac,
      secret,
    ),
    false,
  );
});
