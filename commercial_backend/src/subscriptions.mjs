const PLAN_LIMITS = Object.freeze({
  trial: {
    max_students_per_class: 25,
    max_pending_sync: 30,
    max_devices: 1,
    max_seats: 1,
    trial_days: 14,
    server_transcription: false,
    export_reports: false,
    advanced_analytics: false,
    user_management: false,
  },
  starter: {
    max_students_per_class: 60,
    max_pending_sync: 120,
    max_devices: 1,
    max_seats: 1,
    trial_days: 0,
    server_transcription: false,
    export_reports: true,
    advanced_analytics: false,
    user_management: false,
  },
  professional: {
    max_students_per_class: 120,
    max_pending_sync: 300,
    max_devices: 3,
    max_seats: 1,
    trial_days: 0,
    server_transcription: true,
    export_reports: true,
    advanced_analytics: true,
    user_management: false,
  },
  school: {
    max_students_per_class: 500,
    max_pending_sync: 1000,
    max_devices: 20,
    max_seats: 25,
    trial_days: 0,
    server_transcription: true,
    export_reports: true,
    advanced_analytics: true,
    user_management: true,
  },
  enterprise: {
    max_students_per_class: 0,
    max_pending_sync: 1000,
    max_devices: 0,
    max_seats: 0,
    trial_days: 0,
    server_transcription: true,
    export_reports: true,
    advanced_analytics: true,
    user_management: true,
  },
});

const PRICE_KEYS = Object.freeze({
  starter: {
    monthly: "PRICE_STARTER_MONTHLY_EGP",
    annual: "PRICE_STARTER_ANNUAL_EGP",
  },
  professional: {
    monthly: "PRICE_PROFESSIONAL_MONTHLY_EGP",
    annual: "PRICE_PROFESSIONAL_ANNUAL_EGP",
  },
  school: {
    monthly: "PRICE_SCHOOL_MONTHLY_EGP",
    annual: "PRICE_SCHOOL_ANNUAL_EGP",
  },
});

export function planLimits(plan) {
  const limits = PLAN_LIMITS[plan];
  if (!limits) throw new Error("Unsupported subscription plan.");
  return { ...limits };
}

export function productForCheckout(plan, billingCycle, env) {
  const envKey = PRICE_KEYS[plan]?.[billingCycle];
  if (!envKey) throw new Error("Unsupported checkout product.");
  const amountEgp = Number(env[envKey]);
  if (!Number.isFinite(amountEgp) || amountEgp <= 0) {
    throw new Error(`Missing or invalid server price: ${envKey}`);
  }
  return {
    plan,
    billingCycle,
    amountCents: Math.round(amountEgp * 100),
    currency: "EGP",
    durationDays: billingCycle === "annual" ? 365 : 30,
  };
}

export function activatePaidSubscription(user, { plan, billingCycle, paidAt }) {
  const now = new Date(paidAt);
  if (Number.isNaN(now.getTime())) throw new Error("Invalid payment timestamp.");
  const currentExpiry = new Date(user.subscription?.expires_at ?? 0);
  const base =
    user.subscription?.status === "active" && currentExpiry > now
      ? currentExpiry
      : now;
  const days = billingCycle === "annual" ? 365 : 30;
  const expiresAt = new Date(base.getTime() + days * 86_400_000);
  return {
    ...user,
    subscription: {
      plan,
      status: "active",
      starts_at: now.toISOString(),
      expires_at: expiresAt.toISOString(),
      lifetime: false,
      limits: planLimits(plan),
    },
  };
}

export function entitlementForUser(user, usage = {}) {
  const subscription =
    user.subscription ??
    (user.role === "developer"
      ? { plan: "enterprise", status: "active", lifetime: true }
      : {});
  const plan = PLAN_LIMITS[subscription.plan] ? subscription.plan : "trial";
  const limits = { ...planLimits(plan), ...(subscription.limits ?? {}) };
  // Server transcription is not offered until a production transcription
  // endpoint and provider are configured. Stored legacy limits must not expose
  // a paid feature that the API cannot fulfil.
  limits.server_transcription = false;
  const expiresAt = new Date(subscription.expires_at ?? 0);
  const activeByStatus = ["active", "trialing"].includes(subscription.status);
  const activeByDate =
    subscription.lifetime === true ||
    (Number.isFinite(expiresAt.getTime()) && expiresAt > new Date());
  const deviceLimitReached =
    limits.max_devices > 0 &&
    Number(usage.activeDevices ?? 0) > limits.max_devices;
  const seatLimitReached =
    limits.max_seats > 0 &&
    Number(usage.assignedSeats ?? 0) > limits.max_seats;
  return {
    ...subscription,
    plan,
    limits,
    device_limit_reached: deviceLimitReached,
    seat_limit_reached: seatLimitReached,
    is_usable:
      (subscription.lifetime === true || (activeByStatus && activeByDate)) &&
      !deviceLimitReached &&
      !seatLimitReached,
  };
}
