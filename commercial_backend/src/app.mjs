import { randomUUID } from "node:crypto";

import {
  hashPassword,
  hashToken,
  randomToken,
  signAccessToken,
  verifyAccessToken,
  verifyPassword,
} from "./security.mjs";
import {
  activatePaidSubscription,
  entitlementForUser,
  planLimits,
  productForCheckout,
} from "./subscriptions.mjs";
import { verifyPaymobTransactionHmac } from "./paymob.mjs";
import { normalizeCatalog } from "./catalog.mjs";

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "x-content-type-options": "nosniff",
};

const PAYMENT_RETURN_HTML = `<!doctype html>
<html lang="ar" dir="rtl">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>StudyGrades - نتيجة الدفع</title>
    <style>
      body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #f4f8fc; color: #17324d; font-family: system-ui, sans-serif; }
      main { width: min(34rem, calc(100% - 2rem)); padding: 2rem; box-sizing: border-box; border: 1px solid #c8d9ea; border-radius: 8px; background: #fff; text-align: center; }
      h1 { margin: 0 0 1rem; font-size: 1.5rem; }
      p { margin: 0; line-height: 1.8; }
    </style>
  </head>
  <body>
    <main>
      <h1>تم استلام نتيجة الدفع</h1>
      <p>يمكنك العودة إلى تطبيق StudyGrades وتحديث حالة الاشتراك. يعتمد التفعيل على إشعار الدفع الآمن من Paymob.</p>
    </main>
  </body>
</html>`;

function json(status, body) {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

function html(status, body) {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy":
        "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
    },
  });
}

function attachHeaders(response, values) {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(values)) {
    if (value != null && value !== "") headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function readJson(request, maxBytes = 128 * 1024) {
  const text = await request.text();
  if (Buffer.byteLength(text) > maxBytes) throw new HttpError(413, "Request too large.");
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(400, "Invalid JSON body.");
  }
}

class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

function routePath(request) {
  const pathname = new URL(request.url).pathname.replace(/\/+$/, "/");
  const marker = "/api/mobile";
  const index = pathname.indexOf(marker);
  if (index < 0) return pathname;
  const suffix = pathname.slice(index + marker.length);
  return suffix.startsWith("/") ? suffix : `/${suffix}`;
}

function safeUser(user, entitlement) {
  return {
    id: user.id,
    username: user.username,
    email: user.email ?? "",
    role: user.role,
    full_name: user.full_name ?? "",
    phone: user.phone ?? "",
    is_active: user.is_active === true,
    created_at: user.created_at,
    last_login: user.last_login,
    avatar: user.avatar,
    subscription: entitlement,
  };
}

function requiredEnv(env, key) {
  const value = env[key];
  if (!value) throw new HttpError(503, `Server configuration missing: ${key}`);
  return value;
}

function passwordPolicyError(password, currentPassword) {
  if (password.length < 10 || password.length > 128) {
    return "The new password must be between 10 and 128 characters.";
  }
  if (!/\p{L}/u.test(password) || !/\p{N}/u.test(password)) {
    return "The new password must contain at least one letter and one number.";
  }
  if (password === currentPassword) {
    return "The new password must be different from the current password.";
  }
  return null;
}

function paymentCustomer(user) {
  const email = String(user.email ?? "").trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpError(400, "A valid account email is required before checkout.");
  }
  const digits = String(user.phone ?? "").replace(/\D/g, "");
  let phone;
  if (/^01\d{9}$/.test(digits)) {
    phone = `+20${digits.slice(1)}`;
  } else if (/^201\d{9}$/.test(digits)) {
    phone = `+${digits}`;
  } else {
    throw new HttpError(
      400,
      "A valid Egyptian mobile number is required before checkout.",
    );
  }
  const names = String(user.full_name ?? user.username).trim().split(/\s+/);
  const firstName = names[0];
  if (!firstName) {
    throw new HttpError(400, "The account name is required before checkout.");
  }
  return {
    firstName,
    lastName: names.slice(1).join(" ") || firstName,
    email,
    phone,
  };
}

function positiveIntegerValue(raw, name, fallback) {
  if ((raw == null || raw === "") && fallback != null) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value <= 0) {
    throw new HttpError(400, `Invalid ${name}.`);
  }
  return value;
}

function positiveQueryParameter(url, name, fallback) {
  return positiveIntegerValue(url.searchParams.get(name), name, fallback);
}

function checkoutProduct(plan, billingCycle, env) {
  try {
    return productForCheckout(plan, billingCycle, env);
  } catch (error) {
    const message = error?.message ?? "Invalid checkout product.";
    if (message.startsWith("Unsupported")) {
      throw new HttpError(400, message);
    }
    if (message.startsWith("Missing or invalid server price")) {
      throw new HttpError(503, message);
    }
    throw error;
  }
}

const ROLE_LEVELS = Object.freeze({
  teacher: 10,
  manager: 50,
  admin: 80,
  developer: 100,
});

function roleLevel(role) {
  return ROLE_LEVELS[String(role ?? "")] ?? 0;
}

function validateManagedRole(actor, role) {
  const normalized = String(role ?? "teacher").trim().toLowerCase();
  if (!["teacher", "manager", "admin"].includes(normalized)) {
    throw new HttpError(400, "Unsupported managed user role.");
  }
  if (roleLevel(normalized) >= roleLevel(actor.role)) {
    throw new HttpError(403, "You cannot assign this user role.");
  }
  return normalized;
}

function managedSubscription(raw, previous = null) {
  const source = raw && typeof raw === "object" ? raw : {};
  const plan = String(source.plan ?? previous?.plan ?? "trial")
    .trim()
    .toLowerCase();
  if (!["trial", "starter", "professional", "school"].includes(plan)) {
    throw new HttpError(400, "Unsupported managed subscription plan.");
  }
  const status = String(
    source.status ?? previous?.status ?? (plan === "trial" ? "trialing" : "active"),
  )
    .trim()
    .toLowerCase();
  if (!["none", "trialing", "active", "past_due", "canceled", "expired"].includes(status)) {
    throw new HttpError(400, "Unsupported managed subscription status.");
  }
  const now = new Date();
  const defaultDays = plan === "trial" ? 14 : 30;
  const parsedExpiry = new Date(source.expires_at ?? previous?.expires_at ?? 0);
  const expiresAt = Number.isNaN(parsedExpiry.getTime()) || parsedExpiry <= now
    ? new Date(now.getTime() + defaultDays * 86_400_000)
    : parsedExpiry;
  if (expiresAt > new Date(now.getTime() + 5 * 366 * 86_400_000)) {
    throw new HttpError(400, "Subscription expiry is too far in the future.");
  }
  return {
    plan,
    status,
    starts_at: source.starts_at ?? previous?.starts_at ?? now.toISOString(),
    expires_at: expiresAt.toISOString(),
    lifetime: false,
    limits: planLimits(plan),
  };
}

export function createApp({ repository, env, paymobFetch = fetch }) {
  const corsHeadersFor = (request) => {
    const origin = request.headers.get("origin");
    if (!origin) return {};
    const allowedOrigins = String(env.ALLOWED_ORIGINS ?? "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean);
    if (!allowedOrigins.includes(origin)) {
      return { vary: "Origin" };
    }
    return {
      "access-control-allow-origin": origin,
      "access-control-allow-methods": "GET,POST,PUT,DELETE,OPTIONS",
      "access-control-allow-headers":
        "authorization,content-type,idempotency-key,x-device-id",
      "access-control-max-age": "600",
      vary: "Origin",
    };
  };

  const withCors = (request, response) =>
    attachHeaders(response, corsHeadersFor(request));

  const authenticate = async (request, { requireUsableSubscription = true } = {}) => {
    const header = request.headers.get("authorization") ?? "";
    if (!header.startsWith("Bearer ")) throw new HttpError(401, "Authentication required.");
    let claims;
    try {
      claims = verifyAccessToken(header.slice(7), requiredEnv(env, "JWT_SECRET"));
    } catch {
      throw new HttpError(401, "Invalid or expired access token.");
    }
    if (repository.isSessionActive) {
      const active = await repository.isSessionActive(claims.session_id, claims.sub);
      if (!active) throw new HttpError(401, "Session is no longer active.");
    }
    const user = await repository.getUserById(claims.sub);
    if (!user?.is_active) throw new HttpError(403, "Account is disabled.");
    if (
      Number(claims.credentials_version ?? 0) !==
      Number(user.credentials_version ?? 0)
    ) {
      throw new HttpError(401, "Session credentials are no longer valid.");
    }
    const usage = repository.getUsage
      ? await repository.getUsage(user.id)
      : { activeDevices: 1, assignedSeats: 1 };
    const entitlement = entitlementForUser(user, usage);
    if (requireUsableSubscription && !entitlement.is_usable) {
      throw new HttpError(403, "Subscription is inactive or its limits were exceeded.", {
        subscription: entitlement,
      });
    }
    return { claims, user, entitlement };
  };

  const login = async (request) => {
    const body = await readJson(request, 16 * 1024);
    const username = String(body.username ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const deviceId = String(request.headers.get("x-device-id") ?? "").trim();
    if (!/^[A-Za-z0-9._:-]{8,128}$/.test(deviceId)) {
      throw new HttpError(400, "A valid device identifier is required.");
    }
    if (!username || !password || password.length > 256) {
      throw new HttpError(400, "Username and password are required.");
    }
    const user = await repository.findUserByUsername(username);
    if (!user || !user.is_active || !(await verifyPassword(password, user.password))) {
      throw new HttpError(401, "Invalid username or password.");
    }
    const baseEntitlement = entitlementForUser(user);
    const usage = await repository.registerDevice(user.id, deviceId, {
      maxDevices: baseEntitlement.limits.max_devices,
    });
    const entitlement = entitlementForUser(user, usage);
    if (
      !entitlement.is_usable &&
      (entitlement.device_limit_reached || entitlement.seat_limit_reached)
    ) {
      throw new HttpError(403, "Subscription is inactive or its limits were exceeded.", {
        subscription: entitlement,
      });
    }
    if (/^[a-f0-9]{64}$/i.test(user.password)) {
      user.password = await hashPassword(password);
      await repository.saveUser(user);
    }
    const sessionId = randomUUID();
    const refresh = randomToken();
    const now = Date.now();
    const credentialsVersion = Number(user.credentials_version ?? 0);
    await repository.createSession({
      id: sessionId,
      user_id: user.id,
      device_id: deviceId,
      refresh_hash: hashToken(refresh),
      created_at: new Date(now).toISOString(),
      expires_at: new Date(now + 30 * 86_400_000).toISOString(),
      credentials_version: credentialsVersion,
      revoked: false,
    });
    const access = signAccessToken(
      {
        sub: String(user.id),
        role: user.role,
        session_id: sessionId,
        credentials_version: credentialsVersion,
      },
      requiredEnv(env, "JWT_SECRET"),
    );
    await repository.appendLog?.({
      action: "login",
      user_id: user.id,
      username: user.username,
      timestamp: new Date().toISOString(),
      details: { device_id_suffix: deviceId.slice(-6) },
    });
    return json(200, { access, refresh, user: safeUser(user, entitlement) });
  };

  const refreshAccess = async (request) => {
    const body = await readJson(request, 8 * 1024);
    const previousRefresh = String(body.refresh ?? "");
    if (previousRefresh.length < 32 || previousRefresh.length > 512) {
      throw new HttpError(401, "Invalid refresh token.");
    }
    const nextRefresh = randomToken();
    const session = await repository.rotateRefreshToken(
      hashToken(previousRefresh),
      {
        refresh_hash: hashToken(nextRefresh),
        rotated_at: new Date().toISOString(),
      },
    );
    if (!session || new Date(session.expires_at) <= new Date()) {
      throw new HttpError(401, "Invalid or expired refresh token.");
    }
    const user = await repository.getUserById(session.user_id);
    if (!user?.is_active) throw new HttpError(401, "Account is unavailable.");
    if (
      Number(session.credentials_version ?? 0) !==
      Number(user.credentials_version ?? 0)
    ) {
      await repository.revokeSession?.(session.id);
      throw new HttpError(401, "Session credentials are no longer valid.");
    }
    const access = signAccessToken(
      {
        sub: String(user.id),
        role: user.role,
        session_id: session.id,
        credentials_version: Number(user.credentials_version ?? 0),
      },
      requiredEnv(env, "JWT_SECRET"),
    );
    return json(200, { access, refresh: nextRefresh });
  };

  const logout = async (request) => {
    const auth = await authenticate(request, { requireUsableSubscription: false });
    await repository.revokeSession?.(auth.claims.session_id);
    return json(200, { logged_out: true });
  };

  const getAccount = async (request) => {
    const auth = await authenticate(request, { requireUsableSubscription: false });
    return json(200, { user: safeUser(auth.user, auth.entitlement) });
  };

  const changePassword = async (request) => {
    const auth = await authenticate(request, { requireUsableSubscription: false });
    const body = await readJson(request, 16 * 1024);
    const currentPassword = String(body.current_password ?? "");
    const newPassword = String(body.new_password ?? "");
    if (!currentPassword || currentPassword.length > 256) {
      throw new HttpError(400, "The current password is required.");
    }
    const policyError = passwordPolicyError(newPassword, currentPassword);
    if (policyError) throw new HttpError(400, policyError);
    if (!(await verifyPassword(currentPassword, auth.user.password))) {
      throw new HttpError(401, "The current password is incorrect.");
    }

    const updatedUser = {
      ...auth.user,
      password: await hashPassword(newPassword),
      credentials_version: Number(auth.user.credentials_version ?? 0) + 1,
      password_changed_at: new Date().toISOString(),
    };
    await repository.saveUser(updatedUser);
    if (repository.revokeUserSessions) {
      await repository.revokeUserSessions(auth.user.id);
    } else {
      await repository.revokeSession?.(auth.claims.session_id);
    }
    await repository.appendLog?.({
      action: "password_changed",
      user_id: auth.user.id,
      username: auth.user.username,
      timestamp: new Date().toISOString(),
      details: {},
    });
    return json(200, { reauthentication_required: true });
  };

  const requireUserManager = async (request) => {
    const auth = await authenticate(request);
    if (
      !["developer", "admin"].includes(auth.user.role) ||
      auth.entitlement.limits.user_management !== true
    ) {
      throw new HttpError(403, "User management permission is required.");
    }
    return auth;
  };

  const listManagedUsers = async (request) => {
    await requireUserManager(request);
    const users = await repository.listUsers();
    return json(200, {
      users: users.map((user) => safeUser(user, entitlementForUser(user))),
    });
  };

  const createManagedUser = async (request) => {
    const auth = await requireUserManager(request);
    const body = await readJson(request, 32 * 1024);
    const username = String(body.username ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const email = String(body.email ?? "").trim().toLowerCase();
    if (!/^[a-z0-9._-]{3,64}$/.test(username)) {
      throw new HttpError(400, "Username must contain 3 to 64 safe characters.");
    }
    const policyError = passwordPolicyError(password, "");
    if (policyError) throw new HttpError(400, policyError);
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpError(400, "A valid email address is required.");
    }
    const users = await repository.listUsers();
    if (users.some((user) => String(user.username).trim().toLowerCase() === username)) {
      throw new HttpError(409, "Username already exists.");
    }
    if (
      email &&
      users.some((user) => String(user.email ?? "").trim().toLowerCase() === email)
    ) {
      throw new HttpError(409, "Email address already exists.");
    }
    const role = validateManagedRole(auth.user, body.role);
    const createdAt = new Date().toISOString();
    let created;
    try {
      created = await repository.createUser({
        username,
        email,
        role,
        full_name: String(body.full_name ?? "").trim().slice(0, 160),
        phone: String(body.phone ?? "").trim().slice(0, 32),
        is_active: body.is_active !== false,
        created_at: createdAt,
        credentials_version: 0,
        password: await hashPassword(password),
        subscription: managedSubscription(body.subscription),
      });
    } catch (error) {
      if (/already exists/i.test(String(error?.message ?? ""))) {
        throw new HttpError(409, error.message);
      }
      throw error;
    }
    await repository.appendLog?.({
      action: "user_created",
      user_id: auth.user.id,
      username: auth.user.username,
      timestamp: createdAt,
      details: { target_user_id: created.id, target_username: created.username },
    });
    return json(201, { user: safeUser(created, entitlementForUser(created)) });
  };

  const updateManagedUser = async (request, userId) => {
    const auth = await requireUserManager(request);
    const target = await repository.getUserById(userId);
    if (!target) throw new HttpError(404, "Managed user was not found.");
    if (
      String(target.id) === String(auth.user.id) ||
      roleLevel(target.role) >= roleLevel(auth.user.role)
    ) {
      throw new HttpError(403, "You cannot modify this user.");
    }
    const body = await readJson(request, 32 * 1024);
    const nextRole = body.role == null
      ? target.role
      : validateManagedRole(auth.user, body.role);
    const email = body.email == null
      ? target.email
      : String(body.email).trim().toLowerCase();
    if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      throw new HttpError(400, "A valid email address is required.");
    }
    const users = await repository.listUsers();
    if (
      email &&
      users.some(
        (user) =>
          String(user.id) !== String(target.id) &&
          String(user.email ?? "").trim().toLowerCase() === email,
      )
    ) {
      throw new HttpError(409, "Email address already exists.");
    }
    const updated = {
      ...target,
      email,
      role: nextRole,
      full_name: body.full_name == null
        ? target.full_name
        : String(body.full_name).trim().slice(0, 160),
      phone: body.phone == null
        ? target.phone
        : String(body.phone).trim().slice(0, 32),
      is_active: body.is_active == null ? target.is_active : body.is_active === true,
      subscription: body.subscription == null
        ? target.subscription
        : managedSubscription(body.subscription, target.subscription),
      updated_at: new Date().toISOString(),
    };
    if (body.new_password != null) {
      const newPassword = String(body.new_password);
      const policyError = passwordPolicyError(newPassword, "");
      if (policyError) throw new HttpError(400, policyError);
      updated.password = await hashPassword(newPassword);
      updated.credentials_version = Number(target.credentials_version ?? 0) + 1;
      updated.password_changed_at = new Date().toISOString();
    }
    await repository.saveUser(updated);
    if (body.new_password != null || updated.is_active === false) {
      await repository.revokeUserSessions?.(target.id);
    }
    await repository.appendLog?.({
      action: updated.is_active ? "user_updated" : "user_deactivated",
      user_id: auth.user.id,
      username: auth.user.username,
      timestamp: new Date().toISOString(),
      details: { target_user_id: target.id, target_username: target.username },
    });
    return json(200, { user: safeUser(updated, entitlementForUser(updated)) });
  };

  const deactivateManagedUser = async (request, userId) => {
    const auth = await requireUserManager(request);
    const target = await repository.getUserById(userId);
    if (!target) throw new HttpError(404, "Managed user was not found.");
    if (
      String(target.id) === String(auth.user.id) ||
      roleLevel(target.role) >= roleLevel(auth.user.role)
    ) {
      throw new HttpError(403, "You cannot deactivate this user.");
    }
    await repository.saveUser({
      ...target,
      is_active: false,
      deactivated_at: new Date().toISOString(),
      deactivated_by: auth.user.id,
    });
    await repository.revokeUserSessions?.(target.id);
    await repository.appendLog?.({
      action: "user_deactivated",
      user_id: auth.user.id,
      username: auth.user.username,
      timestamp: new Date().toISOString(),
      details: { target_user_id: target.id, target_username: target.username },
    });
    return new Response(null, { status: 204, headers: JSON_HEADERS });
  };

  const getHierarchy = async (request) => {
    const auth = await authenticate(request);
    if (!repository.getHierarchy) {
      throw new HttpError(503, "Academic catalog storage is unavailable.");
    }
    const hierarchy = await repository.getHierarchy(auth.user.id);
    if (!Array.isArray(hierarchy)) {
      throw new HttpError(500, "Academic catalog data is malformed.");
    }
    return json(200, { hierarchy });
  };

  const getStudents = async (request) => {
    const auth = await authenticate(request);
    if (!repository.getClassroom) {
      throw new HttpError(503, "Academic catalog storage is unavailable.");
    }
    const url = new URL(request.url);
    const classId = positiveQueryParameter(url, "class_id");
    const termId = positiveQueryParameter(url, "term_id", 1);
    const weekNumber = positiveQueryParameter(url, "week_number", 1);
    const subject = String(url.searchParams.get("subject") ?? "").trim();
    if (!subject || subject.length > 100) {
      throw new HttpError(400, "Invalid subject.");
    }
    const classroom = await repository.getClassroom(
      auth.user.id,
      classId,
      subject,
      { termId, weekNumber },
    );
    if (!classroom) throw new HttpError(404, "Classroom was not found.");
    if (!Array.isArray(classroom.students)) {
      throw new HttpError(500, "Classroom student data is malformed.");
    }
    const maxStudents = Number(
      auth.entitlement.limits.max_students_per_class ?? 0,
    );
    const students =
      maxStudents > 0
        ? classroom.students.slice(0, maxStudents)
        : classroom.students.slice();
    return json(200, { ...classroom, students });
  };

  const importCatalog = async (request) => {
    const auth = await authenticate(request);
    const canImportOwnCatalog =
      ["developer", "admin", "manager"].includes(auth.user.role) &&
      auth.entitlement.limits.user_management === true;
    if (!canImportOwnCatalog) {
      throw new HttpError(403, "Catalog import permission is required.");
    }
    const body = await readJson(request, 2 * 1024 * 1024);
    const targetUserId = positiveIntegerValue(
      body.target_user_id ?? auth.user.id,
      "target_user_id",
    );
    if (auth.user.role !== "developer" && String(targetUserId) !== String(auth.user.id)) {
      throw new HttpError(403, "Only a developer can import another account's catalog.");
    }
    const targetUser = await repository.getUserById(targetUserId);
    if (!targetUser) throw new HttpError(404, "Catalog account was not found.");
    if (!repository.saveCatalog) {
      throw new HttpError(503, "Academic catalog storage is unavailable.");
    }
    let normalized;
    try {
      normalized = normalizeCatalog(body);
    } catch (error) {
      throw new HttpError(400, error.message);
    }
    const catalog = {
      ...normalized.catalog,
      updated_at: new Date().toISOString(),
      updated_by: auth.user.id,
    };
    await repository.saveCatalog(targetUserId, catalog);
    await repository.appendLog?.({
      action: "catalog_imported",
      user_id: auth.user.id,
      username: auth.user.username,
      timestamp: new Date().toISOString(),
      details: { target_user_id: targetUserId, ...normalized.summary },
    });
    return json(200, { imported: true, summary: normalized.summary });
  };

  const syncGrades = async (request) => {
    const auth = await authenticate(request);
    const body = await readJson(request, 512 * 1024);
    const grades = Array.isArray(body.grades) ? body.grades : null;
    if (!grades || grades.length > 500) throw new HttpError(400, "Invalid grades payload.");
    const idempotencyKey = request.headers.get("idempotency-key");
    if (!/^[a-f0-9]{64}$/i.test(String(idempotencyKey ?? ""))) {
      throw new HttpError(400, "A valid Idempotency-Key is required.");
    }
    const result = repository.saveGrades
      ? await repository.saveGrades(auth.user.id, body, idempotencyKey)
      : { synced: grades.length };
    return json(200, result);
  };

  const createIntention = async (request) => {
    const auth = await authenticate(request, { requireUsableSubscription: false });
    const body = await readJson(request, 16 * 1024);
    const product = checkoutProduct(
      String(body.plan ?? ""),
      String(body.billing_cycle ?? ""),
      env,
    );
    const customer = paymentCustomer(auth.user);
    const reference = `SG-${auth.user.id}-${randomUUID()}`;
    const payment = {
      reference,
      user_id: auth.user.id,
      plan: product.plan,
      billing_cycle: product.billingCycle,
      amount_cents: product.amountCents,
      currency: product.currency,
      status: "pending",
      created_at: new Date().toISOString(),
    };
    await repository.createPayment(payment);
    let paymobResponse;
    try {
      paymobResponse = await paymobFetch("https://accept.paymob.com/v1/intention/", {
        method: "POST",
        headers: {
          authorization: `Token ${requiredEnv(env, "PAYMOB_SECRET_KEY")}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          amount: product.amountCents,
          currency: product.currency,
          payment_methods: [Number(requiredEnv(env, "PAYMOB_CARD_INTEGRATION_ID"))],
          items: [
            {
              name: `StudyGrades ${product.plan} ${product.billingCycle}`,
              amount: product.amountCents,
              description: `StudyGrades ${product.billingCycle} subscription`,
              quantity: 1,
            },
          ],
          billing_data: {
            first_name: customer.firstName,
            last_name: customer.lastName,
            email: customer.email,
            phone_number: customer.phone,
            country: "EG",
            city: "Cairo",
            street: "NA",
            building: "NA",
            floor: "NA",
            apartment: "NA",
          },
          special_reference: reference,
          extras: {
            reference,
            user_id: String(auth.user.id),
            plan: product.plan,
            billing_cycle: product.billingCycle,
          },
        }),
      });
    } catch {
      await repository.updatePayment(reference, {
        status: "intention_failed",
        updated_at: new Date().toISOString(),
      });
      throw new HttpError(502, "Payment provider could not be reached.");
    }
    const responseBody = await paymobResponse.json().catch(() => ({}));
    if (!paymobResponse.ok || !responseBody.client_secret) {
      await repository.updatePayment(reference, {
        status: "intention_failed",
        updated_at: new Date().toISOString(),
      });
      throw new HttpError(502, "Payment provider rejected the intention request.");
    }
    await repository.updatePayment(reference, {
      paymob_intention_id: responseBody.id,
      status: "intention_created",
      updated_at: new Date().toISOString(),
    });
    const publicKey = encodeURIComponent(requiredEnv(env, "PAYMOB_PUBLIC_KEY"));
    const clientSecret = encodeURIComponent(responseBody.client_secret);
    return json(201, {
      reference,
      checkout_url: `https://accept.paymob.com/unifiedcheckout/?publicKey=${publicKey}&clientSecret=${clientSecret}`,
    });
  };

  const handlePaymobWebhook = async (request) => {
    const body = await readJson(request, 256 * 1024);
    const transaction = body.obj ?? body;
    const providedHmac = new URL(request.url).searchParams.get("hmac");
    if (
      !verifyPaymobTransactionHmac(
        transaction,
        providedHmac,
        requiredEnv(env, "PAYMOB_HMAC_SECRET"),
      )
    ) {
      throw new HttpError(401, "Invalid Paymob callback signature.");
    }
    const reference = String(
      transaction.order?.merchant_order_id ??
        transaction.order?.special_reference ??
        transaction.special_reference ??
        transaction.extras?.reference ??
        "",
    );
    if (!reference) throw new HttpError(400, "Payment reference is missing.");
    const payment = await repository.getPayment(reference);
    if (!payment) throw new HttpError(404, "Payment reference was not found.");
    if (payment.status === "paid") return json(200, { received: true });
    if (
      Number(transaction.integration_id) !==
        Number(requiredEnv(env, "PAYMOB_CARD_INTEGRATION_ID")) ||
      Number(transaction.amount_cents) !== Number(payment.amount_cents) ||
      String(transaction.currency) !== payment.currency
    ) {
      throw new HttpError(409, "Payment callback does not match the order.");
    }
    const successful =
      transaction.success === true &&
      transaction.pending !== true &&
      transaction.error_occured !== true &&
      transaction.is_voided !== true &&
      transaction.is_refunded !== true;
    if (!successful) {
      const declinedPatch = {
        status: "declined",
        paymob_transaction_id: transaction.id,
        updated_at: new Date().toISOString(),
      };
      if (repository.recordPaymentDeclined) {
        await repository.recordPaymentDeclined(reference, declinedPatch);
      } else {
        await repository.updatePayment(reference, declinedPatch);
      }
      return json(200, { received: true });
    }
    let fulfillmentPayment = payment;
    if (repository.claimPaymentForFulfillment) {
      const claim = await repository.claimPaymentForFulfillment(reference, {
        paymob_transaction_id: transaction.id,
        fulfillment_started_at: new Date().toISOString(),
      });
      if (claim.status === "missing") {
        throw new HttpError(404, "Payment reference was not found.");
      }
      if (claim.status === "already_paid" || claim.status === "in_progress") {
        return json(200, { received: true });
      }
      if (claim.status !== "claimed" || !claim.payment) {
        throw new HttpError(409, "Payment callback could not be claimed.");
      }
      fulfillmentPayment = claim.payment;
    }
    const user = await repository.getUserById(fulfillmentPayment.user_id);
    if (!user) throw new HttpError(404, "Payment account was not found.");
    const paidAt = new Date(transaction.created_at);
    const updatedUser = activatePaidSubscription(user, {
      plan: fulfillmentPayment.plan,
      billingCycle: fulfillmentPayment.billing_cycle,
      paidAt: Number.isNaN(paidAt.getTime()) ? new Date() : paidAt,
    });
    await repository.saveUser(updatedUser);
    await repository.updatePayment(reference, {
      status: "paid",
      paymob_transaction_id: transaction.id,
      paid_at: updatedUser.subscription.starts_at,
      fulfillment_completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    });
    await repository.appendLog?.({
      action: "subscription_activated",
      user_id: user.id,
      username: user.username,
      timestamp: new Date().toISOString(),
      details: {
        reference,
        plan: fulfillmentPayment.plan,
        billing_cycle: fulfillmentPayment.billing_cycle,
      },
    });
    return json(200, { received: true });
  };

  return async function handle(request) {
    try {
      if (request.method === "OPTIONS") {
        return withCors(request, new Response(null, { status: 204, headers: JSON_HEADERS }));
      }
      const path = routePath(request);
      if (request.method === "GET" && path === "/") {
        return withCors(
          request,
          json(200, { service: "StudyGrades API", status: "running", version: "2.0.0" }),
        );
      }
      if (request.method === "POST" && ["/token/", "/login/", "/auth/login/"].includes(path)) {
        return withCors(request, await login(request));
      }
      if (request.method === "POST" && path === "/token/refresh/") {
        return withCors(request, await refreshAccess(request));
      }
      if (request.method === "POST" && path === "/logout/") {
        return withCors(request, await logout(request));
      }
      if (request.method === "GET" && path === "/account/me/") {
        return withCors(request, await getAccount(request));
      }
      if (request.method === "POST" && path === "/account/password/") {
        return withCors(request, await changePassword(request));
      }
      if (request.method === "GET" && path === "/admin/users/") {
        return withCors(request, await listManagedUsers(request));
      }
      if (request.method === "POST" && path === "/admin/users/") {
        return withCors(request, await createManagedUser(request));
      }
      const managedUserMatch = path.match(/^\/admin\/users\/(\d+)\/$/);
      if (request.method === "PUT" && managedUserMatch) {
        return withCors(
          request,
          await updateManagedUser(request, managedUserMatch[1]),
        );
      }
      if (request.method === "DELETE" && managedUserMatch) {
        return withCors(
          request,
          await deactivateManagedUser(request, managedUserMatch[1]),
        );
      }
      if (request.method === "GET" && path === "/hierarchy/") {
        return withCors(request, await getHierarchy(request));
      }
      if (request.method === "GET" && path === "/students/") {
        return withCors(request, await getStudents(request));
      }
      if (request.method === "PUT" && path === "/admin/catalog/") {
        return withCors(request, await importCatalog(request));
      }
      if (request.method === "POST" && path === "/grades/sync/") {
        return withCors(request, await syncGrades(request));
      }
      if (request.method === "POST" && path === "/billing/intention/") {
        return withCors(request, await createIntention(request));
      }
      if (request.method === "GET" && path === "/billing/paymob/return/") {
        return withCors(request, html(200, PAYMENT_RETURN_HTML));
      }
      if (request.method === "POST" && path === "/billing/paymob/webhook/") {
        return withCors(request, await handlePaymobWebhook(request));
      }
      return withCors(request, json(404, { detail: "Endpoint not found." }));
    } catch (error) {
      if (error instanceof HttpError) {
        return withCors(
          request,
          json(error.status, { detail: error.message, ...error.details }),
        );
      }
      console.error("Unhandled API error", error);
      return withCors(request, json(500, { detail: "Internal server error." }));
    }
  };
}
