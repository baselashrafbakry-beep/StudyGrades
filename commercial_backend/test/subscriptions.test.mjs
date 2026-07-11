import assert from "node:assert/strict";
import test from "node:test";

import {
  activatePaidSubscription,
  entitlementForUser,
  productForCheckout,
} from "../src/subscriptions.mjs";

test("checkout prices come from server configuration, not client input", () => {
  const env = {
    PRICE_STARTER_MONTHLY_EGP: "50",
    PRICE_STARTER_ANNUAL_EGP: "500",
  };

  const product = productForCheckout("starter", "monthly", env);

  assert.equal(product.amountCents, 5_000);
  assert.equal(product.durationDays, 30);
  assert.throws(() => productForCheckout("enterprise", "monthly", env));
});

test("successful annual payment extends from the current paid expiry", () => {
  const user = {
    subscription: {
      plan: "starter",
      status: "active",
      expires_at: "2026-08-01T00:00:00.000Z",
    },
  };

  const updated = activatePaidSubscription(user, {
    plan: "starter",
    billingCycle: "annual",
    paidAt: new Date("2026-07-03T00:00:00.000Z"),
  });

  assert.equal(updated.subscription.expires_at, "2027-08-01T00:00:00.000Z");
});

test("device and seat limit flags fail closed", () => {
  const entitlement = entitlementForUser({
    subscription: {
      plan: "school",
      status: "active",
      expires_at: "2099-01-01T00:00:00.000Z",
    },
  }, {
    activeDevices: 21,
    assignedSeats: 1,
  });

  assert.equal(entitlement.device_limit_reached, true);
  assert.equal(entitlement.is_usable, false);
});

test("legacy developer records retain server-side lifetime administration", () => {
  const entitlement = entitlementForUser({ role: "developer" });

  assert.equal(entitlement.plan, "enterprise");
  assert.equal(entitlement.status, "active");
  assert.equal(entitlement.lifetime, true);
  assert.equal(entitlement.limits.user_management, true);
  assert.equal(entitlement.is_usable, true);
});

test("legacy non-developer records remain unlicensed", () => {
  const entitlement = entitlementForUser({ role: "teacher" });

  assert.equal(entitlement.plan, "trial");
  assert.equal(entitlement.is_usable, false);
});

test("server transcription fails closed until a provider is available", () => {
  const entitlement = entitlementForUser({
    role: "teacher",
    subscription: {
      plan: "professional",
      status: "active",
      expires_at: "2099-01-01T00:00:00.000Z",
      limits: { server_transcription: true },
    },
  });

  assert.equal(entitlement.limits.server_transcription, false);
});
