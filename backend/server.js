import express from "express";
import crypto from "crypto";
import cors from "cors";
import dotenv from "dotenv";
import OpenAI from "openai";
import { toFile } from "openai/uploads";
import { createClient } from "@supabase/supabase-js";
import multer from "multer";

dotenv.config();

const app = express();
const port = process.env.PORT || 8787;

app.use(cors());
app.use(express.json({ limit: "5mb" }));

const documentUpload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 15 * 1024 * 1024,
  },
});


const passwordResetAttempts = new Map();


function normalizeSupabaseUrl(value) {
  return String(value || "")
    .trim()
    .replace(/\/rest\/v1\/?$/i, "")
    .replace(/\/auth\/v1\/?$/i, "")
    .replace(/\/+$/g, "");
}

const supabaseUrl = normalizeSupabaseUrl(process.env.SUPABASE_URL);
const supabaseServiceRoleKey = String(process.env.SUPABASE_SERVICE_ROLE_KEY || "").trim();
const supabaseAnonKey = String(process.env.SUPABASE_ANON_KEY || "").trim();

const supabaseAdmin =
  supabaseUrl && supabaseServiceRoleKey
    ? createClient(supabaseUrl, supabaseServiceRoleKey, {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      })
    : null;

const supabaseAuth =
  supabaseUrl && supabaseAnonKey
    ? createClient(supabaseUrl, supabaseAnonKey, {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
        },
      })
    : null;


const KORLIX_TEMPORARILY_DOWN_MESSAGE =
  "Korlix AI is temporarily down. Please try again later.";

function isKorlixTemporaryDownError(error) {
  const pieces = [
    error?.message,
    error?.details,
    error?.statusCode,
    error?.code,
    error?.type,
    error?.openaiPayload ? JSON.stringify(error.openaiPayload) : "",
    error ? String(error) : "",
  ];

  const combined = pieces
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  return (
    combined.includes("429") ||
    combined.includes("quota") ||
    combined.includes("insufficient_quota") ||
    combined.includes("billing") ||
    combined.includes("usage limit") ||
    combined.includes("current quota") ||
    combined.includes("rate limit")
  );
}

function getKorlixUserFacingError(error) {
  if (isKorlixTemporaryDownError(error)) {
    return KORLIX_TEMPORARILY_DOWN_MESSAGE;
  }

  return sanitize(error?.message || error || "Something went wrong.");
}


function sanitize(value) {
  const openAiKey = process.env.OPENAI_API_KEY || "";

  return String(value || "")
    .replace(openAiKey, "[hidden_openai_key]")
    .replace(supabaseServiceRoleKey, "[hidden_supabase_service_role_key]")
    .replace(supabaseAnonKey, "[hidden_supabase_anon_key]")
    .replace(/sk-[A-Za-z0-9_\-]+/g, "sk-[hidden]");
}

function isKorlixEmailLike(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || "").trim());
}

function getPasswordResetRedirectUrl(req) {
  const configured = String(
    process.env.KORLIX_PASSWORD_RESET_REDIRECT_URL ||
      process.env.SUPABASE_PASSWORD_RESET_REDIRECT_URL ||
      ""
  ).trim();

  if (configured) {
    return configured;
  }

  const forwardedProto = String(req.get("x-forwarded-proto") || "")
    .split(",")[0]
    .trim();
  const protocol = forwardedProto || req.protocol || "https";
  const host = req.get("host");

  if (host) {
    return `${protocol}://${host}/reset-password`;
  }

  return "https://chee-chai-chee-backend.onrender.com/reset-password";
}

function checkPasswordResetRateLimit(req, email) {
  const now = Date.now();
  const windowMs = 15 * 60 * 1000;
  const maxAttempts = 5;
  const ip = String(req.ip || req.get("x-forwarded-for") || "unknown")
    .split(",")[0]
    .trim();
  const key = `${ip}:${String(email || "").toLowerCase()}`;
  const existing = passwordResetAttempts.get(key) || [];
  const recent = existing.filter((timestamp) => now - timestamp < windowMs);

  if (recent.length >= maxAttempts) {
    passwordResetAttempts.set(key, recent);
    return false;
  }

  recent.push(now);
  passwordResetAttempts.set(key, recent);
  return true;
}

function secretMatches(provided, expected) {
  const a = Buffer.from(String(provided || ""));
  const b = Buffer.from(String(expected || ""));

  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

async function sendKorlixPasswordResetEmail({ email, req }) {
  if (!supabaseAuth) {
    const error = new Error("Supabase auth is not configured on the backend.");
    error.statusCode = 500;
    throw error;
  }

  const redirectTo = getPasswordResetRedirectUrl(req);

  const { error } = await supabaseAuth.auth.resetPasswordForEmail(email, {
    redirectTo,
  });

  if (error) {
    error.statusCode = error.status || 400;
    throw error;
  }

  return { redirectTo };
}

function renderKorlixPasswordResetPage() {
  const publicSupabaseUrl = supabaseUrl;
  const publicSupabaseAnonKey = supabaseAnonKey;

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Reset Korlix AI Password</title>
  <style>
    :root { color-scheme: dark; }
    body {
      min-height: 100vh;
      margin: 0;
      display: grid;
      place-items: center;
      padding: 24px;
      box-sizing: border-box;
      font-family: Arial, Helvetica, sans-serif;
      color: #e4ebee;
      background: radial-gradient(circle at top, #0a2b3d 0%, #071b27 44%, #040612 100%);
    }
    .card {
      width: min(460px, 100%);
      padding: 28px;
      border-radius: 28px;
      border: 1px solid rgba(46, 199, 223, 0.42);
      background: rgba(4, 6, 18, 0.78);
      box-shadow: 0 0 48px rgba(46, 199, 223, 0.18);
    }
    h1 { margin: 0 0 8px; letter-spacing: 2px; }
    p { color: #a9c6cf; line-height: 1.45; }
    label { display: block; margin: 18px 0 8px; font-weight: 800; }
    input {
      width: 100%;
      box-sizing: border-box;
      border-radius: 16px;
      border: 1px solid rgba(46, 199, 223, 0.38);
      background: #071b27;
      color: #e4ebee;
      padding: 14px 16px;
      font-size: 16px;
      outline: none;
    }
    button {
      width: 100%;
      margin-top: 20px;
      border: 0;
      border-radius: 999px;
      padding: 15px 18px;
      background: #143b4a;
      color: #e4ebee;
      font-size: 16px;
      font-weight: 900;
      cursor: pointer;
    }
    button:disabled { opacity: 0.62; cursor: not-allowed; }
    .message { margin-top: 16px; color: #69d9e8; font-weight: 700; }
    .error { margin-top: 16px; color: #ff7b7b; font-weight: 700; }
  </style>
</head>
<body>
  <main class="card">
    <h1>KORLIX AI</h1>
    <p>Choose a new password for your account. After it is updated, return to Korlix AI and sign in with the new password.</p>

    <form id="reset-form">
      <label for="password">New password</label>
      <input id="password" type="password" minlength="6" autocomplete="new-password" required />

      <label for="confirm-password">Confirm new password</label>
      <input id="confirm-password" type="password" minlength="6" autocomplete="new-password" required />

      <button id="submit-button" type="submit">Update password</button>
    </form>

    <div id="message" class="message" role="status"></div>
    <div id="error" class="error" role="alert"></div>
  </main>

  <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
  <script>
    const supabaseUrl = ${JSON.stringify(publicSupabaseUrl)};
    const supabaseAnonKey = ${JSON.stringify(publicSupabaseAnonKey)};
    const client = window.supabase.createClient(supabaseUrl, supabaseAnonKey);
    const form = document.getElementById('reset-form');
    const passwordInput = document.getElementById('password');
    const confirmInput = document.getElementById('confirm-password');
    const submitButton = document.getElementById('submit-button');
    const message = document.getElementById('message');
    const errorBox = document.getElementById('error');

    function showMessage(text) {
      message.textContent = text || '';
      errorBox.textContent = '';
    }

    function showError(text) {
      errorBox.textContent = text || 'Something went wrong.';
      message.textContent = '';
    }

    async function restoreRecoverySession() {
      const search = new URLSearchParams(window.location.search);
      const hash = new URLSearchParams(window.location.hash.replace(/^#/, ''));
      const code = search.get('code');
      const accessToken = hash.get('access_token');
      const refreshToken = hash.get('refresh_token');

      if (code) {
        const result = await client.auth.exchangeCodeForSession(code);
        if (result.error) throw result.error;
        window.history.replaceState({}, document.title, window.location.pathname);
        return;
      }

      if (accessToken && refreshToken) {
        const result = await client.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        });
        if (result.error) throw result.error;
        window.history.replaceState({}, document.title, window.location.pathname);
        return;
      }

      const sessionResult = await client.auth.getSession();
      if (!sessionResult.data.session) {
        throw new Error('This reset link is missing or expired. Request a new password reset email from the Korlix AI sign-in screen.');
      }
    }

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const password = passwordInput.value;
      const confirmPassword = confirmInput.value;

      if (password.length < 6) {
        showError('Password must be at least 6 characters.');
        return;
      }

      if (password !== confirmPassword) {
        showError('Passwords do not match.');
        return;
      }

      submitButton.disabled = true;
      submitButton.textContent = 'Updating password...';

      try {
        await restoreRecoverySession();
        const result = await client.auth.updateUser({ password });
        if (result.error) throw result.error;

        showMessage('Password updated successfully. You can now return to Korlix AI and sign in.');
        form.reset();
        await client.auth.signOut();
      } catch (error) {
        showError(error && error.message ? error.message : String(error));
      } finally {
        submitButton.disabled = false;
        submitButton.textContent = 'Update password';
      }
    });
  </script>
</body>
</html>`;
}



function normalizeKorlixCharacterId(characterId) {
  const raw = String(characterId || "").trim().toLowerCase();

  if (!raw) {
    return "";
  }

  const normalized = raw.replaceAll("-", "_").replaceAll(" ", "_");

  if (normalized === "ji_a" || normalized === "jia") {
    return "ji_a";
  }

  if (
    normalized === "chee_chai_chee" ||
    normalized === "cheechai" ||
    normalized === "cheechaichee"
  ) {
    return "chee_chai_chee";
  }

  return normalized;
}

const characterPersonalityMap = {
  jj: {
    name: "JJ",
    style:
      "JJ is the Basic starter character. Keep answers friendly, clear, helpful, and easy to understand.",
  },
  chee_chai_chee: {
    name: "Chee Chai Chee",
    style:
      "Chee Chai Chee is a dark cyber-mystic wizard. His answers should feel powerful, direct, strategic, mysterious, and useful.",
  },
  phil: {
    name: "Phil",
    style:
      "Phil is helpful, approachable, confident, and simple. He guides users clearly and makes tasks feel easy.",
  },
  yuna: {
    name: "Yuna",
    style:
      "Yuna is premium, elegant, sharp, creative, and strategic. She gives polished, thoughtful, high-value responses.",
  },
  ji_a: {
    name: "Ji-a",
    style:
      "Ji-a is calm, intelligent, polished, and emotionally sharp. She gives elegant, thoughtful, premium responses with clarity and confidence.",
  },
};

function getCharacterPersonality(characterId) {
  const normalizedCharacterId = normalizeKorlixCharacterId(characterId);
  return characterPersonalityMap[normalizedCharacterId] || characterPersonalityMap.jj;
}

function canSelectCharacterForTier(tier, characterId) {
  const normalizedCharacterId = normalizeKorlixCharacterId(characterId);

  if (tier === "enterprise" || tier === "ultra") {
    return true;
  }

  if (tier === "pro") {
    return ["jj", "phil", "chee_chai_chee"].includes(normalizedCharacterId);
  }

  return normalizedCharacterId === "jj";
}


const languageMap = {
  en: {
    name: "English",
    instruction: "Respond in polished English.",
  },
  es: {
    name: "Spanish",
    instruction: "Respond in natural, polished Spanish.",
  },
  fr: {
    name: "French",
    instruction: "Respond in natural, polished French.",
  },
};

function shouldUseLiveSearch(command) {
  const lower = String(command || "").toLowerCase();

  const liveKeywords = [
    "current",
    "today",
    "now",
    "latest",
    "recent",
    "2026",
    "this year",
    "news",
    "score",
    "standings",
    "stats",
    "ranking",
    "rankings",
    "best team",
    "nba",
    "basketball",
    "football",
    "soccer",
    "baseball",
    "stock",
    "price",
    "weather",
    "president",
    "ceo",
    "trending",
  ];

  return liveKeywords.some((word) => lower.includes(word));
}

function wantsFile(command) {
  const lower = String(command || "").toLowerCase();

  const fileWords = [
    "pdf",
    "word",
    "docx",
    "document",
    "download",
    "export",
    "file",
    "printable",
    "save as",
    "archivo",
    "documento",
    "exportar",
    "descargar",
    "imprimible",
    "fichier",
    "document",
    "exporter",
    "télécharger",
    "imprimable",
  ];

  return fileWords.some((word) => lower.includes(word));
}

function calculateCredits({ liveSearchNeeded, fileRequested }) {
  if (fileRequested) return 3;
  if (liveSearchNeeded) return 4;
  return 1;
}

function getTierLimits(tier) {
  const limits = {
    basic: {
      dailyRequestLimit: 3,
      dailyCreditLimit: 12,
      characterLimit: 1,
      videoGenerationsMonthly: 0,
      musicGenerationIncluded: false,
    },
    pro: {
      dailyRequestLimit: 30,
      dailyCreditLimit: 60,
      characterLimit: 3,
      videoGenerationsMonthly: 2,
      musicGenerationIncluded: false,
    },
    ultra: {
      dailyRequestLimit: 75,
      dailyCreditLimit: 200,
      characterLimit: 999,
      videoGenerationsMonthly: 10,
      musicGenerationIncluded: false,
    },
    enterprise: {
      dailyRequestLimit: 250,
      dailyCreditLimit: 1000,
      characterLimit: 999,
      videoGenerationsMonthly: 25,
      musicGenerationIncluded: false,
    },
  };

  return limits[tier] || limits.basic;
}

function getMonthKey(date = new Date()) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  return `${year}-${month}`;
}


function getRequestDeviceInfo(req) {
  const body = req.body || {};

  const rawDeviceId = String(
    body.device_id ||
      req.headers["x-korlix-device-id"] ||
      ""
  ).trim();

  let deviceId = rawDeviceId;

  const deviceLabel = String(
    body.device_label ||
      req.headers["x-korlix-device-label"] ||
      "Unknown device"
  ).trim();

  const platform = String(
    body.platform ||
      req.headers["x-korlix-platform"] ||
      "unknown"
  ).trim();

  // Fallback keeps older APKs from being locked out at sign-in.
  // New APKs should still send a real stable device_id.
  if (!deviceId) {
    const userAgent = String(req.headers["user-agent"] || "unknown-agent");
    const forwardedFor = String(
      req.headers["cf-connecting-ip"] ||
        req.headers["x-forwarded-for"] ||
        req.headers["x-real-ip"] ||
        "unknown-ip"
    );

    deviceId = `fallback_${crypto
      .createHash("sha256")
      .update(`${platform}|${deviceLabel}|${userAgent}|${forwardedFor}`)
      .digest("hex")
      .slice(0, 32)}`;
  }

  return {
    deviceId,
    deviceLabel,
    platform,
    explicitDeviceId: Boolean(rawDeviceId),
  };
}

function getTierDeviceLimit(profile) {
  const override = Number(profile?.max_devices_override || 0);

  if (Number.isFinite(override) && override > 0) {
    return override;
  }

  const tier = profile?.tier || "basic";

  if (tier === "ultra") {
    return 2;
  }

  if (tier === "enterprise") {
    return 2;
  }

  return 1;
}

function makeHttpError(message, statusCode = 400) {
  const error = new Error(message);
  error.statusCode = statusCode;
  return error;
}

async function registerDeviceSession({
  userId,
  profile,
  deviceInfo,
}) {
  if (!supabaseAdmin) {
    return null;
  }

  if (!deviceInfo.deviceId) {
    throw makeHttpError("Device ID is required for sign-in.", 400);
  }

  const { data: existing, error: existingError } = await supabaseAdmin
    .from("device_sessions")
    .select("*")
    .eq("user_id", userId)
    .eq("device_id", deviceInfo.deviceId)
    .maybeSingle();

  if (existingError) {
    throw existingError;
  }

  if (existing?.status === "active") {
    const { data, error } = await supabaseAdmin
      .from("device_sessions")
      .update({
        device_label: deviceInfo.deviceLabel || existing.device_label,
        platform: deviceInfo.platform || existing.platform,
        last_seen_at: new Date().toISOString(),
      })
      .eq("id", existing.id)
      .select("*")
      .single();

    if (error) {
      throw error;
    }

    return data;
  }

  const limit = getTierDeviceLimit(profile);

  const { data: activeDevices, error: activeError } = await supabaseAdmin
    .from("device_sessions")
    .select("id, device_id, device_label, platform, last_seen_at")
    .eq("user_id", userId)
    .eq("status", "active");

  if (activeError) {
    throw activeError;
  }

  const activeCount = activeDevices?.length || 0;

  if (activeCount >= limit) {
    const tier = profile?.tier || "basic";

    throw makeHttpError(
      `Device limit reached for your ${tier} plan. Sign out from another device before signing in here.`,
      403
    );
  }

  const { data, error } = await supabaseAdmin
    .from("device_sessions")
    .upsert(
      {
        user_id: userId,
        device_id: deviceInfo.deviceId,
        device_label: deviceInfo.deviceLabel,
        platform: deviceInfo.platform,
        status: "active",
        last_seen_at: new Date().toISOString(),
        revoked_at: null,
      },
      {
        onConflict: "user_id,device_id",
      }
    )
    .select("*")
    .single();

  if (error) {
    throw error;
  }

  return data;
}

async function touchActiveDeviceSession({
  userId,
  profile,
  deviceInfo,
  allowRegister = false,
}) {
  if (!supabaseAdmin || !deviceInfo.deviceId) {
    return null;
  }

  const { data: existing, error: existingError } = await supabaseAdmin
    .from("device_sessions")
    .select("*")
    .eq("user_id", userId)
    .eq("device_id", deviceInfo.deviceId)
    .maybeSingle();

  if (existingError) {
    throw existingError;
  }

  if (existing?.status === "active") {
    const { data, error } = await supabaseAdmin
      .from("device_sessions")
      .update({
        device_label: deviceInfo.deviceLabel || existing.device_label,
        platform: deviceInfo.platform || existing.platform,
        last_seen_at: new Date().toISOString(),
      })
      .eq("id", existing.id)
      .select("*")
      .single();

    if (error) {
      throw error;
    }

    return data;
  }

  if (allowRegister) {
    return registerDeviceSession({
      userId,
      profile,
      deviceInfo,
    });
  }

  throw makeHttpError(
    "This device is not authorized for this account. Please sign in again.",
    403
  );
}

async function revokeDeviceSession({
  userId,
  deviceId,
}) {
  if (!supabaseAdmin || !userId || !deviceId) {
    return null;
  }

  const { data, error } = await supabaseAdmin
    .from("device_sessions")
    .update({
      status: "revoked",
      revoked_at: new Date().toISOString(),
      last_seen_at: new Date().toISOString(),
    })
    .eq("user_id", userId)
    .eq("device_id", deviceId)
    .select("*");

  if (error) {
    throw error;
  }

  return data;
}


function getBearerToken(req) {
  const header = req.headers.authorization || "";

  if (!header.toLowerCase().startsWith("bearer ")) {
    return null;
  }

  return header.slice(7).trim();
}

async function getAuthenticatedUser(req) {
  if (!supabaseAdmin) {
    return null;
  }

  const token = getBearerToken(req);

  if (!token) {
    return null;
  }

  const { data, error } = await supabaseAdmin.auth.getUser(token);

  if (error || !data?.user) {
    throw new Error("Invalid or expired session. Please sign in again.");
  }

  const deviceInfo = getRequestDeviceInfo(req);

  // Device limits are enforced at sign-in.
  // Protected requests should not fail if an older APK did not send device headers.
  if (deviceInfo.explicitDeviceId) {
    try {
      const profile = await getOrCreateProfile(data.user);

      await touchActiveDeviceSession({
        userId: data.user.id,
        profile,
        deviceInfo,
        allowRegister: false,
      });
    } catch (deviceError) {
      console.warn(
        "Device session touch skipped:",
        sanitize(deviceError?.message)
      );
    }
  }

  return data.user;
}

async function requireUser(req) {
  const user = await getAuthenticatedUser(req);

  if (!user) {
    const error = new Error("Sign in required.");
    error.statusCode = 401;
    throw error;
  }

  return user;
}

async function getOrCreateProfile(user) {
  if (!supabaseAdmin || !user) {
    return null;
  }

  const { data: existingProfile, error: selectError } = await supabaseAdmin
    .from("user_profiles")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();

  if (selectError) {
    throw selectError;
  }

  if (existingProfile) {
    return existingProfile;
  }

  const { data: insertedProfile, error: insertError } = await supabaseAdmin
    .from("user_profiles")
    .insert({
      id: user.id,
      email: user.email,
      tier: "basic",
      selected_character: "jj",
    })
    .select("*")
    .single();

  if (insertError) {
    throw insertError;
  }

  await supabaseAdmin.from("user_character_access").upsert({
    user_id: user.id,
    character_id: "jj",
    granted_by: "basic_default",
  });

  return insertedProfile;
}

async function getOrCreateUsageCounter(userId) {
  if (!supabaseAdmin || !userId) {
    return null;
  }

  const today = new Date().toISOString().slice(0, 10);
  const monthKey = getMonthKey();

  const { data: existing, error: selectError } = await supabaseAdmin
    .from("usage_counters")
    .select("*")
    .eq("user_id", userId)
    .eq("usage_date", today)
    .maybeSingle();

  if (selectError) {
    throw selectError;
  }

  if (existing) {
    return existing;
  }

  const { data: inserted, error: insertError } = await supabaseAdmin
    .from("usage_counters")
    .insert({
      user_id: userId,
      usage_date: today,
      month_key: monthKey,
      standard_generations: 0,
      live_search_generations: 0,
      pdf_generations: 0,
      video_generations: 0,
      music_generations: 0,
      credits_used: 0,
    })
    .select("*")
    .single();

  if (insertError) {
    throw insertError;
  }

  return inserted;
}

function checkUsageAllowed({ profile, usageCounter, creditsNeeded }) {
  if (!profile || !usageCounter) {
    return {
      allowed: true,
      reason: null,
    };
  }

  const tier = profile.tier || "basic";
  const limits = getTierLimits(tier);

  const totalRequests =
    Number(usageCounter.standard_generations || 0) +
    Number(usageCounter.live_search_generations || 0) +
    Number(usageCounter.pdf_generations || 0);

  const creditsUsed = Number(usageCounter.credits_used || 0);

  if (totalRequests >= limits.dailyRequestLimit) {
    return {
      allowed: false,
      reason: `Daily generation limit reached for your ${tier} plan.`,
    };
  }

  if (creditsUsed + creditsNeeded > limits.dailyCreditLimit) {
    return {
      allowed: false,
      reason: `Daily credit limit reached for your ${tier} plan.`,
    };
  }

  return {
    allowed: true,
    reason: null,
  };
}

async function incrementUsage({
  usageCounter,
  liveSearchUsed,
  fileRequested,
  creditsNeeded,
}) {
  if (!supabaseAdmin || !usageCounter) {
    return null;
  }

  const updates = {
    standard_generations:
      Number(usageCounter.standard_generations || 0) +
      (!liveSearchUsed && !fileRequested ? 1 : 0),
    live_search_generations:
      Number(usageCounter.live_search_generations || 0) +
      (liveSearchUsed ? 1 : 0),
    pdf_generations:
      Number(usageCounter.pdf_generations || 0) + (fileRequested ? 1 : 0),
    credits_used: Number(usageCounter.credits_used || 0) + creditsNeeded,
    updated_at: new Date().toISOString(),
  };

  const { data, error } = await supabaseAdmin
    .from("usage_counters")
    .update(updates)
    .eq("id", usageCounter.id)
    .select("*")
    .single();

  if (error) {
    throw error;
  }

  return data;
}

async function saveGenerationHistory({
  user,
  profile,
  command,
  content,
  languageCode,
  fileRequested,
  searched,
  creditsNeeded,
}) {
  if (!supabaseAdmin || !user) {
    return null;
  }

  const { data, error } = await supabaseAdmin
    .from("generation_history")
    .insert({
      user_id: user.id,
      character_id: profile?.selected_character || "chee_chai_chee",
      language: languageCode,
      prompt: command,
      response: content,
      result_type: fileRequested ? "file" : "answer",
      searched,
      credits_used: creditsNeeded,
    })
    .select("*")
    .single();

  if (error) {
    throw error;
  }

  return data;
}


function isImageUpload(file) {
  const fileName = String(file?.originalname || "").toLowerCase();
  const mimeType = String(file?.mimetype || "").toLowerCase();

  return (
    mimeType.startsWith("image/") ||
    fileName.endsWith(".jpg") ||
    fileName.endsWith(".jpeg") ||
    fileName.endsWith(".png") ||
    fileName.endsWith(".webp")
  );
}

function isPdfUpload(file) {
  const fileName = String(file?.originalname || "").toLowerCase();
  const mimeType = String(file?.mimetype || "").toLowerCase();

  return fileName.endsWith(".pdf") || mimeType.includes("pdf");
}

function isDocxUpload(file) {
  const fileName = String(file?.originalname || "").toLowerCase();
  const mimeType = String(file?.mimetype || "").toLowerCase();

  return fileName.endsWith(".docx") || mimeType.includes("wordprocessingml.document");
}

function isTextLikeUpload(file) {
  const fileName = String(file?.originalname || "").toLowerCase();
  const mimeType = String(file?.mimetype || "").toLowerCase();

  return (
    fileName.endsWith(".txt") ||
    fileName.endsWith(".md") ||
    fileName.endsWith(".csv") ||
    mimeType.includes("text/") ||
    mimeType.includes("csv")
  );
}

function isNormalDocumentUpload(file) {
  return isPdfUpload(file) || isDocxUpload(file) || isTextLikeUpload(file);
}

function isAdvancedUpload(file) {
  return isImageUpload(file);
}

function hasProUploadAccess(_tier) {
  return true;
}


function hasAdvancedUploadAccess(_tier) {
  return true;
}


function getUploadMimeType(file) {
  const fileName = String(file?.originalname || "").toLowerCase();
  const rawMimeType = String(file?.mimetype || "")
    .toLowerCase()
    .split(";")[0]
    .trim();

  // Always trust the filename extension first. Mobile browsers and some
  // file pickers often send real files as application/octet-stream.
  if (fileName.endsWith(".png")) return "image/png";
  if (fileName.endsWith(".webp")) return "image/webp";
  if (fileName.endsWith(".jpg") || fileName.endsWith(".jpeg")) {
    return "image/jpeg";
  }

  if (fileName.endsWith(".pdf")) return "application/pdf";
  if (fileName.endsWith(".txt") || fileName.endsWith(".md")) return "text/plain";
  if (fileName.endsWith(".csv")) return "text/csv";

  if (fileName.endsWith(".doc")) return "application/msword";
  if (fileName.endsWith(".docx")) {
    return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  }

  if (fileName.endsWith(".xls")) return "application/vnd.ms-excel";
  if (fileName.endsWith(".xlsx")) {
    return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
  }

  if (fileName.endsWith(".ppt")) return "application/vnd.ms-powerpoint";
  if (fileName.endsWith(".pptx")) {
    return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
  }

  const genericMime =
    !rawMimeType ||
    rawMimeType === "application/octet-stream" ||
    rawMimeType === "binary/octet-stream";

  if (!genericMime) {
    return rawMimeType;
  }

  return "application/octet-stream";
}



async function loadPdfParse() {
  try {
    const mod = await import("pdf-parse/lib/pdf-parse.js");
    return mod.default || mod;
  } catch (_) {
    const mod = await import("pdf-parse");
    return mod.default || mod;
  }
}

async function loadMammoth() {
  const mod = await import("mammoth");
  return mod.default || mod;
}

async function extractUploadedDocumentText(file) {
  const fileName = String(file.originalname || "").toLowerCase();
  const mimeType = String(file.mimetype || "").toLowerCase();
  const buffer = file.buffer;

  if (!buffer || buffer.length === 0) {
    throw new Error("Uploaded file is empty.");
  }

  if (fileName.endsWith(".pdf") || mimeType.includes("pdf")) {
    const pdfParse = await loadPdfParse();
    const parsed = await pdfParse(buffer);
    return parsed.text || "";
  }

  if (
    fileName.endsWith(".docx") ||
    mimeType.includes("wordprocessingml.document")
  ) {
    const mammoth = await loadMammoth();
    const parsed = await mammoth.extractRawText({
      buffer,
    });

    return parsed.value || "";
  }

  if (
    fileName.endsWith(".txt") ||
    fileName.endsWith(".md") ||
    fileName.endsWith(".csv") ||
    mimeType.includes("text/") ||
    mimeType.includes("csv")
  ) {
    return buffer.toString("utf8");
  }

  return "";
}

function normalizeDocumentText(value) {
  return String(value || "")
    .replace(/\r\n/g, "\n")
    .replace(/\n{4,}/g, "\n\n\n")
    .trim();
}

function truncateDocumentText(value) {
  const clean = normalizeDocumentText(value);
  const maxChars = 18000;

  if (clean.length <= maxChars) {
    return {
      text: clean,
      truncated: false,
    };
  }

  return {
    text: clean.slice(0, maxChars),
    truncated: true,
  };
}

function buildFileAnalysisPrompt({
  command,
  language,
  fileName,
  extractedText,
  textWasTruncated,
  advancedMode,
}) {
  const extractedSection = extractedText
    ? `
Readable extracted text:
"""
${extractedText}
"""
`
    : "";

  return `
You are Korlix AI, a premium multilingual AI assistant platform powered by selectable AI characters.

The selected character is:
Chee Chai Chee

Chee Chai Chee is a dark cyber-mystic wizard character. His answers should be direct, useful, strategic, and clear.

The user selected this language:
${language.name}

Language rule:
${language.instruction}

The user uploaded:
${fileName}

The user asked:
"${command}"

${extractedSection}

File analysis rules:
- Answer based primarily on the uploaded file.
- If the answer is not in the file, say that clearly.
- Do not invent details that are not supported by the file.
- If the user asks for a summary, summarize clearly.
- If the user asks a question, answer directly first.
- If the file is truncated, say the answer is based on the readable portion processed.
${advancedMode ? "- If the upload is an image, scan, screenshot, handwriting photo, or scanned document, perform OCR-style reading from the visible content.\n- If handwriting is unclear, say which words are uncertain.\n- If the image is blurry, cropped, or low resolution, explain what could and could not be read." : ""}
- Do not mention PDF export unless the user asks for PDF/file/export/document.

Formatting rules:
- Use plain text only.
- Do not use markdown symbols like **bold**, ###, checkboxes, or emojis.
- Use short headings only when helpful.
- Use numbered lists or hyphen bullets when useful.
`;
}

async function createAdvancedFileResponse({
  client,
  file,
  command,
  language,
  extractedText = "",
  textWasTruncated = false,
}) {
  const model =
    process.env.OPENAI_DOCUMENT_MODEL ||
    process.env.OPENAI_ULTRA_MODEL ||
    process.env.OPENAI_MODEL ||
    "gpt-4o-mini";

  const fileName = String(file.originalname || "uploaded-file");
  const mimeType = getUploadMimeType(file);
  const base64 = file.buffer.toString("base64");

  const prompt = buildFileAnalysisPrompt({
    command,
    language,
    fileName,
    extractedText,
    textWasTruncated,
    advancedMode: true,
  });

  if (isImageUpload(file)) {
    return client.responses.create({
      model,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: prompt,
            },
            {
              type: "input_image",
              image_url: `data:${mimeType};base64,${base64}`,
            },
          ],
        },
      ],
    });
  }

  if (isPdfUpload(file)) {
    return client.responses.create({
      model,
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_file",
              filename: fileName,
              file_data: `data:application/pdf;base64,${base64}`,
            },
            {
              type: "input_text",
              text: prompt,
            },
          ],
        },
      ],
    });
  }

  return client.responses.create({
    model,
    input: prompt,
  });
}



function getOpenAIModelForTier(profile, options = {}) {
  const tier = String(profile?.tier || "basic").toLowerCase();

  if (tier === "ultra") {
    return process.env.OPENAI_ULTRA_MODEL || "gpt-5.5";
  }

  if (tier === "enterprise") {
    return (
      process.env.OPENAI_ENTERPRISE_MODEL ||
      process.env.OPENAI_ULTRA_MODEL ||
      "gpt-5.5"
    );
  }

  if (tier === "pro") {
    return (
      process.env.OPENAI_PRO_MODEL ||
      process.env.OPENAI_MODEL ||
      "gpt-4o-mini"
    );
  }

  return (
    process.env.OPENAI_BASIC_MODEL ||
    process.env.OPENAI_MODEL ||
    "gpt-4o-mini"
  );
}




function getUploadedImageMime(file) {
  const rawMime = String(file?.mimetype || "").toLowerCase();

  if (rawMime.startsWith("image/") && rawMime !== "image/*") {
    return rawMime;
  }

  const name = String(file?.originalname || "").toLowerCase();

  if (name.endsWith(".jpg") || name.endsWith(".jpeg")) {
    return "image/jpeg";
  }

  if (name.endsWith(".png")) {
    return "image/png";
  }

  if (name.endsWith(".webp")) {
    return "image/webp";
  }

  if (name.endsWith(".gif")) {
    return "image/gif";
  }

  return "image/jpeg";
}


function getVideoTierLimit(profile) {
  const override = Number(profile?.video_generation_limit_override || 0);

  if (Number.isFinite(override) && override > 0) {
    return override;
  }

  const tier = String(profile?.tier || "basic").toLowerCase();

  if (tier === "pro") {
    return 2;
  }

  if (tier === "ultra") {
    return 10;
  }

  if (tier === "enterprise") {
    return 25;
  }

  return 0;
}


function hasVideoGenerationAccess(profile) {
  return getVideoTierLimit(profile) > 0;
}


function getVideoMonthStart() {
  const now = new Date();

  return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))
    .toISOString();
}

async function countUserVideoGenerationsThisMonth(userId) {
  if (!supabaseAdmin || !userId) {
    return 0;
  }

  const monthStart = getVideoMonthStart();

  const { count, error } = await supabaseAdmin
    .from("generation_history")
    .select("id", {
      count: "exact",
      head: true,
    })
    .eq("user_id", userId)
    .eq("result_type", "video")
    .gte("created_at", monthStart);

  if (error) {
    throw error;
  }

  return count || 0;
}

const KORLIX_VIDEO_CREDIT_PACKS = {
  korlix_video_credits_3: 3,
  korlix_video_credits_10: 10,
  korlix_video_credits_25: 25,
};

function getKorlixVideoCreditPackAmount(productId) {
  return Number(KORLIX_VIDEO_CREDIT_PACKS[String(productId || "").trim()] || 0);
}

function korlixCreditSecretMatches(provided, expected) {
  const a = Buffer.from(String(provided || ""));
  const b = Buffer.from(String(expected || ""));

  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function getKorlixSupportBearerSecret(req) {
  const authorization = String(req.get("authorization") || "").trim();

  if (authorization.toLowerCase().startsWith("bearer ")) {
    return authorization.slice(7).trim();
  }

  return "";
}

function requireKorlixSupportSecret(req) {
  const configured = String(process.env.KORLIX_SUPPORT_SECRET || "").trim();

  if (!configured) {
    const error = new Error("KORLIX_SUPPORT_SECRET is not configured.");
    error.statusCode = 500;
    throw error;
  }

  const bearerSecret = getKorlixSupportBearerSecret(req);
  const headerSecret = String(req.get("x-korlix-support-secret") || "").trim();

  if (
    !korlixCreditSecretMatches(bearerSecret, configured) &&
    !korlixCreditSecretMatches(headerSecret, configured)
  ) {
    const error = new Error("Unauthorized.");
    error.statusCode = 401;
    throw error;
  }
}

function hashKorlixPurchaseToken(token) {
  const normalized = String(token || "").trim();

  if (!normalized) {
    return null;
  }

  return crypto.createHash("sha256").update(normalized).digest("hex");
}

async function getPurchasedVideoCreditBalance(userId) {
  if (!supabaseAdmin || !userId) {
    return 0;
  }

  const { data, error } = await supabaseAdmin
    .from("video_credit_ledger")
    .select("delta")
    .eq("user_id", userId);

  if (error) {
    throw error;
  }

  return (data || []).reduce((total, row) => total + Number(row.delta || 0), 0);
}

async function addVideoCreditLedgerEntry({
  userId,
  delta,
  source,
  productId = null,
  purchaseToken = null,
  description = null,
  metadata = {},
}) {
  if (!supabaseAdmin) {
    const error = new Error("Supabase is not configured on the backend.");
    error.statusCode = 500;
    throw error;
  }

  const purchaseTokenHash = hashKorlixPurchaseToken(purchaseToken);

  const payload = {
    user_id: userId,
    delta,
    source,
    product_id: productId,
    purchase_token_hash: purchaseTokenHash,
    description,
    metadata,
  };

  const { data, error } = await supabaseAdmin
    .from("video_credit_ledger")
    .insert(payload)
    .select("*")
    .single();

  if (error) {
    throw error;
  }

  return data;
}

async function findKorlixProfileForCreditGrant({ userId, email }) {
  if (!supabaseAdmin) {
    return null;
  }

  let query = supabaseAdmin.from("user_profiles").select("*").limit(1);

  if (userId) {
    query = query.eq("id", userId);
  } else {
    query = query.ilike("email", String(email || "").trim());
  }

  const { data, error } = await query.maybeSingle();

  if (error) {
    throw error;
  }

  return data;
}

async function getVideoCreditSummaryForUser({ userId, profile }) {
  const monthlyLimit = getVideoTierLimit(profile);
  const usedThisMonth = await countUserVideoGenerationsThisMonth(userId);
  const purchasedVideoCredits = await getPurchasedVideoCreditBalance(userId);
  const includedRemaining = Math.max(monthlyLimit - usedThisMonth, 0);

  return {
    tier: String(profile?.tier || "basic").toLowerCase(),
    monthlyLimit,
    usedThisMonth,
    includedRemaining,
    purchasedVideoCredits,
    canGenerateVideo: includedRemaining > 0 || purchasedVideoCredits > 0,
    packs: KORLIX_VIDEO_CREDIT_PACKS,
  };
}

async function spendPurchasedVideoCredit({ userId, videoId, prompt }) {
  const balance = await getPurchasedVideoCreditBalance(userId);

  if (balance <= 0) {
    const error = new Error("No purchased video credits remaining.");
    error.statusCode = 402;
    throw error;
  }

  return addVideoCreditLedgerEntry({
    userId,
    delta: -1,
    source: "video_generation",
    description: `Spent 1 purchased video credit for video ${videoId}`,
    metadata: {
      videoId,
      prompt: String(prompt || "").slice(0, 1000),
    },
  });
}


function normalizeVideoSeconds(value) {
  const seconds = Number(value || 8);

  if ([8, 12, 16, 20].includes(seconds)) {
    return seconds;
  }

  return 8;
}

function normalizeVideoSize(value) {
  const allowed = new Set([
    "720x1280",
    "1280x720",
    "1080x1920",
    "1920x1080",
  ]);

  const size = String(value || "1280x720").trim();

  return allowed.has(size) ? size : "1280x720";
}

async function createOpenAIVideoJob({
  prompt,
  size,
  seconds,
}) {
  const model = process.env.OPENAI_VIDEO_MODEL || "sora-2";

  const form = new FormData();
  form.append("model", model);
  form.append("prompt", prompt);
  form.append("size", size);
  form.append("seconds", String(seconds));

  const response = await fetch("https://api.openai.com/v1/videos", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    },
    body: form,
  });

  const bodyText = await response.text();
  let data;

  try {
    data = bodyText ? JSON.parse(bodyText) : {};
  } catch (_) {
    data = {
      raw: bodyText,
    };
  }

  if (!response.ok) {
    const message =
      data?.error?.message ||
      data?.message ||
      bodyText ||
      "OpenAI video generation failed.";

    const error = new Error(message);
    error.statusCode = response.status;
    error.openaiPayload = data;
    throw error;
  }

  return data;
}

async function retrieveOpenAIVideo(videoId) {
  const response = await fetch(`https://api.openai.com/v1/videos/${videoId}`, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    },
  });

  const bodyText = await response.text();
  let data;

  try {
    data = bodyText ? JSON.parse(bodyText) : {};
  } catch (_) {
    data = {
      raw: bodyText,
    };
  }

  if (!response.ok) {
    const message =
      data?.error?.message ||
      data?.message ||
      bodyText ||
      "OpenAI video status check failed.";

    const error = new Error(message);
    error.statusCode = response.status;
    throw error;
  }

  return data;
}

async function fetchOpenAIVideoContent(videoId) {
  const response = await fetch(
    `https://api.openai.com/v1/videos/${videoId}/content`,
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      },
    }
  );

  if (!response.ok) {
    const bodyText = await response.text().catch(() => "");
    const error = new Error(
      bodyText || "Could not retrieve generated video content."
    );
    error.statusCode = response.status;
    throw error;
  }

  const arrayBuffer = await response.arrayBuffer();

  return {
    buffer: Buffer.from(arrayBuffer),
    contentType: response.headers.get("content-type") || "video/mp4",
  };
}


async function createOpenAIResponse(client, { model, input, useSearch }) {
  const request = {
    model,
    input,
  };

  if (useSearch) {
    request.tools = [{ type: "web_search" }];
    request.tool_choice = "required";
  }

  return client.responses.create(request);
}


app.get("/reset-password", (_req, res) => {
  res.set("Cache-Control", "no-store").type("html").send(renderKorlixPasswordResetPage());
});

app.post("/api/auth/password-reset", async (req, res) => {
  const genericMessage =
    "If that email belongs to a Korlix AI account, a password reset link has been sent.";

  try {
    const email = String(req.body.email || "").trim().toLowerCase();

    if (!isKorlixEmailLike(email)) {
      return res.status(400).json({
        error: "Enter a valid email address.",
      });
    }

    if (!checkPasswordResetRateLimit(req, email)) {
      return res.status(429).json({
        error: "Too many reset requests. Try again later.",
      });
    }

    await sendKorlixPasswordResetEmail({ email, req });

    res.json({
      success: true,
      message: genericMessage,
    });
  } catch (error) {
    console.error("Password reset request failed:", sanitize(error?.message || error));

    res.json({
      success: true,
      message: genericMessage,
    });
  }
});

app.post("/api/support/password-reset", async (req, res) => {
  try {
    const supportSecret = String(process.env.KORLIX_SUPPORT_SECRET || "").trim();

    if (!supportSecret) {
      return res.status(500).json({
        error: "Support password reset endpoint is not configured.",
      });
    }

    const authorization = String(req.get("authorization") || "").trim();
    const bearerSecret = authorization.toLowerCase().startsWith("bearer ")
      ? authorization.slice(7).trim()
      : "";
    const headerSecret = String(req.get("x-korlix-support-secret") || "").trim();

    if (!secretMatches(bearerSecret, supportSecret) && !secretMatches(headerSecret, supportSecret)) {
      return res.status(401).json({
        error: "Unauthorized.",
      });
    }

    const email = String(req.body.email || "").trim().toLowerCase();

    if (!isKorlixEmailLike(email)) {
      return res.status(400).json({
        error: "Enter a valid email address.",
      });
    }

    const { redirectTo } = await sendKorlixPasswordResetEmail({ email, req });

    res.json({
      success: true,
      message: `Password reset email requested for ${email}.`,
      redirectTo,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});


app.post("/api/auth/signup", async (req, res) => {
  try {
    if (!supabaseAuth) {
      return res.status(500).json({
        error: "Supabase auth is not configured on the backend.",
      });
    }

    const email = String(req.body.email || "").trim().toLowerCase();
    const password = String(req.body.password || "").trim();
    const deviceInfo = getRequestDeviceInfo(req);

    if (!email || !password) {
      return res.status(400).json({
        error: "Email and password are required.",
      });
    }

    if (password.length < 6) {
      return res.status(400).json({
        error: "Password must be at least 6 characters.",
      });
    }

    const { data, error } = await supabaseAuth.auth.signUp({
      email,
      password,
    });

    if (error) {
      return res.status(error.status || 400).json({
        error: getKorlixUserFacingError(error),
      });
    }

    let profile = null;
    let deviceSession = null;

    if (data.user && data.session) {
      profile = await getOrCreateProfile(data.user);
      deviceSession = await registerDeviceSession({
        userId: data.user.id,
        profile,
        deviceInfo,
      });
    }

    res.json({
      success: true,
      message: data.session
        ? "Account created and signed in."
        : "Account created. Check your email to confirm your account, then sign in.",
      user: data.user
        ? {
            id: data.user.id,
            email: data.user.email,
          }
        : null,
      profile,
      deviceSession,
      session: data.session
        ? {
            access_token: data.session.access_token,
            refresh_token: data.session.refresh_token,
            expires_at: data.session.expires_at,
          }
        : null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});

app.post("/api/auth/signin", async (req, res) => {
  try {
    if (!supabaseAuth) {
      return res.status(500).json({
        error: "Supabase auth is not configured on the backend.",
      });
    }

    const email = String(req.body.email || "").trim().toLowerCase();
    const password = String(req.body.password || "").trim();
    const deviceInfo = getRequestDeviceInfo(req);

    if (!email || !password) {
      return res.status(400).json({
        error: "Email and password are required.",
      });
    }

    const { data, error } = await supabaseAuth.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      return res.status(error.status || 400).json({
        error: getKorlixUserFacingError(error),
      });
    }

    const profile = await getOrCreateProfile(data.user);

    const deviceSession = await registerDeviceSession({
      userId: data.user.id,
      profile,
      deviceInfo,
    });

    res.json({
      success: true,
      message: "Signed in.",
      user: data.user
        ? {
            id: data.user.id,
            email: data.user.email,
          }
        : null,
      profile,
      deviceSession,
      deviceLimit: getTierDeviceLimit(profile),
      session: data.session
        ? {
            access_token: data.session.access_token,
            refresh_token: data.session.refresh_token,
            expires_at: data.session.expires_at,
          }
        : null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});



app.get("/api/supabase-diagnostics", async (req, res) => {
  try {
    const healthUrl = `${supabaseUrl}/auth/v1/health`;

    const response = await fetch(healthUrl, {
      method: "GET",
      headers: {
        apikey: supabaseAnonKey,
        Authorization: `Bearer ${supabaseAnonKey}`,
      },
    });

    const body = await response.text();

    res.json({
      ok: response.ok,
      status: response.status,
      statusText: response.statusText,
      supabaseHost: new URL(supabaseUrl).host,
      bodyPreview: body.slice(0, 300),
    });
  } catch (error) {
    res.status(500).json({
      ok: false,
      supabaseHost: supabaseUrl ? new URL(supabaseUrl).host : null,
      errorName: error?.name || null,
      errorMessage: sanitize(error?.message || ""),
      errorCode: error?.code || error?.cause?.code || null,
      errorCause: sanitize(error?.cause?.message || ""),
    });
  }
});



app.post("/api/auth/refresh", async (req, res) => {
  try {
    if (!supabaseAuth) {
      return res.status(500).json({
        error: "Supabase auth is not configured on the backend.",
      });
    }

    const refreshToken = String(req.body.refresh_token || "").trim();
    const deviceInfo = getRequestDeviceInfo(req);

    if (!refreshToken) {
      return res.status(400).json({
        error: "Refresh token is required.",
      });
    }

    const { data, error } = await supabaseAuth.auth.refreshSession({
      refresh_token: refreshToken,
    });

    if (error) {
      return res.status(error.status || 400).json({
        error: getKorlixUserFacingError(error),
      });
    }

    const profile = await getOrCreateProfile(data.user);

    const deviceSession = await touchActiveDeviceSession({
      userId: data.user.id,
      profile,
      deviceInfo,
      allowRegister: true,
    });

    res.json({
      success: true,
      message: "Session refreshed.",
      user: data.user
        ? {
            id: data.user.id,
            email: data.user.email,
          }
        : null,
      profile,
      deviceSession,
      deviceLimit: getTierDeviceLimit(profile),
      session: data.session
        ? {
            access_token: data.session.access_token,
            refresh_token: data.session.refresh_token,
            expires_at: data.session.expires_at,
          }
        : null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});



app.post("/api/characters/select", async (req, res) => {
  try {
    if (!supabaseAdmin) {
      return res.status(500).json({
        error: "Supabase is not configured on the backend.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);
    const requestedCharacterId = String(req.body.character_id || "").trim();
    const characterId = normalizeKorlixCharacterId(requestedCharacterId);

    if (!characterId) {
      return res.status(400).json({
        error: "Character ID is required.",
      });
    }

    const { data: character, error: characterError } = await supabaseAdmin
      .from("characters")
      .select("*")
      .eq("id", characterId)
      .maybeSingle();

    if (characterError) {
      throw characterError;
    }

    if (!character) {
      return res.status(404).json({
        error: "Character not found.",
      });
    }

    if (!character.is_active || character.is_coming_soon) {
      return res.status(403).json({
        error: "This character is coming soon.",
      });
    }

    const tier = profile?.tier || "basic";

    if (!canSelectCharacterForTier(tier, characterId)) {
      return res.status(403).json({
        error: `This character is not available on your ${tier} plan.`,
        upgradeRequired: true,
        requiredTier: character.tier_required,
      });
    }

    const { data: updatedProfile, error: updateError } = await supabaseAdmin
      .from("user_profiles")
      .update({
        selected_character: characterId,
      })
      .eq("id", user.id)
      .select("*")
      .single();

    if (updateError) {
      throw updateError;
    }

    await supabaseAdmin.from("user_character_access").upsert({
      user_id: user.id,
      character_id: characterId,
      granted_by: "tier_select",
    });

    res.json({
      success: true,
      profile: updatedProfile,
      character,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});



app.post("/api/auth/signout", async (req, res) => {
  try {
    const user = await requireUser(req);
    const deviceInfo = getRequestDeviceInfo(req);

    if (deviceInfo.deviceId) {
      await revokeDeviceSession({
        userId: user.id,
        deviceId: deviceInfo.deviceId,
      });
    }

    res.json({
      success: true,
      message: "Signed out from this device.",
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});



app.get("/api/video-credits", async (req, res) => {
  try {
    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);
    const summary = await getVideoCreditSummaryForUser({
      userId: user.id,
      profile,
    });

    return res.json({
      success: true,
      ...summary,
    });
  } catch (error) {
    return res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});

app.post("/api/video-credits/support-grant", async (req, res) => {
  try {
    requireKorlixSupportSecret(req);

    const body = req.body || {};
    const userId = String(body.userId || body.user_id || "").trim();
    const email = String(body.email || "").trim().toLowerCase();
    const credits = Number(body.credits || 0);
    const reason = String(body.reason || "support_grant").trim();

    if (!userId && !email) {
      return res.status(400).json({
        error: "Provide userId or email.",
      });
    }

    if (!Number.isInteger(credits) || credits <= 0 || credits > 100) {
      return res.status(400).json({
        error: "credits must be an integer from 1 to 100.",
      });
    }

    const profile = await findKorlixProfileForCreditGrant({ userId, email });

    if (!profile) {
      return res.status(404).json({
        error: "User profile not found. Ask the user to sign in once first.",
      });
    }

    const entry = await addVideoCreditLedgerEntry({
      userId: profile.id,
      delta: credits,
      source: "support_grant",
      description: reason,
      metadata: {
        email: profile.email || email || null,
        grantedBy: "support",
      },
    });

    const balance = await getPurchasedVideoCreditBalance(profile.id);

    return res.json({
      success: true,
      message: `Granted ${credits} video credit(s).`,
      userId: profile.id,
      email: profile.email || email || null,
      balance,
      entryId: entry.id,
    });
  } catch (error) {
    return res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});


app.post("/api/video/generate", async (req, res) => {
  try {
    if (!process.env.OPENAI_API_KEY) {
      return res.status(400).json({
        error: "Missing OPENAI_API_KEY on backend.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);
    const tier = String(profile?.tier || "basic").toLowerCase();

    const creditSummaryBefore = await getVideoCreditSummaryForUser({
      userId: user.id,
      profile,
    });

    const prompt = String(req.body.prompt || "").trim();
    const languageCode = req.body.language || "en";
    const size = normalizeVideoSize(req.body.size);
    const seconds = normalizeVideoSeconds(req.body.seconds);

    if (!prompt) {
      return res.status(400).json({
        error: "Video prompt is required.",
      });
    }

    const shouldSpendPurchasedCredit =
      creditSummaryBefore.includedRemaining <= 0 &&
      creditSummaryBefore.purchasedVideoCredits > 0;

    if (
      creditSummaryBefore.includedRemaining <= 0 &&
      creditSummaryBefore.purchasedVideoCredits <= 0
    ) {
      return res.status(402).json({
        error:
          tier === "basic"
            ? "Basic does not include monthly video generations. Buy video credits to generate videos."
            : "No video generations remaining. Buy video credits to continue.",
        buyCreditsRequired: true,
        tier,
        monthlyLimit: creditSummaryBefore.monthlyLimit,
        usedThisMonth: creditSummaryBefore.usedThisMonth,
        includedRemaining: creditSummaryBefore.includedRemaining,
        purchasedVideoCredits: creditSummaryBefore.purchasedVideoCredits,
        packs: creditSummaryBefore.packs,
      });
    }

    const videoJob = await createOpenAIVideoJob({
      prompt,
      size,
      seconds,
    });

    if (shouldSpendPurchasedCredit) {
      await spendPurchasedVideoCredit({
        userId: user.id,
        videoId: videoJob.id,
        prompt,
      });
    }

    const creditsUsed = 25;

    await supabaseAdmin.from("generation_history").insert({
      user_id: user.id,
      character_id: profile?.selected_character || "jj",
      language: languageCode,
      prompt: `Video generation prompt:\n${prompt}`,
      response: `Video generation started. Video ID: ${videoJob.id}`,
      result_type: "video",
      searched: false,
      credits_used: creditsUsed,
    });

    const usageCounter = await getOrCreateUsageCounter(user.id);

    if (usageCounter) {
      await supabaseAdmin
        .from("usage_counters")
        .update({
          video_generations: Number(usageCounter.video_generations || 0) + 1,
          credits_used: Number(usageCounter.credits_used || 0) + creditsUsed,
          updated_at: new Date().toISOString(),
        })
        .eq("id", usageCounter.id);
    }

    const creditSummaryAfter = await getVideoCreditSummaryForUser({
      userId: user.id,
      profile,
    });

    return res.json({
      success: true,
      video: videoJob,
      videoId: videoJob.id,
      status: videoJob.status,
      progress: videoJob.progress || 0,
      tier,
      spentPurchasedCredit: shouldSpendPurchasedCredit,
      monthlyLimit: creditSummaryAfter.monthlyLimit,
      usedThisMonth: creditSummaryAfter.usedThisMonth,
      includedRemaining: creditSummaryAfter.includedRemaining,
      purchasedVideoCredits: creditSummaryAfter.purchasedVideoCredits,
      videoCredits: creditSummaryAfter,
    });
  } catch (error) {
    console.error(
      "Video generation error:",
      sanitize(error?.message),
      error?.openaiPayload || ""
    );

    return res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
      details: getKorlixUserFacingError(error),
    });
  }
});

app.get("/api/video/status/:videoId", async (req, res) => {
  try {
    await requireUser(req);

    const videoId = String(req.params.videoId || "").trim();

    if (!videoId) {
      return res.status(400).json({
        error: "Video ID is required.",
      });
    }

    const video = await retrieveOpenAIVideo(videoId);

    res.json({
      success: true,
      video,
      videoId: video.id,
      status: video.status,
      progress: video.progress || 0,
      error: video.error || null,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
      details: getKorlixUserFacingError(error),
    });
  }
});

app.get("/api/video/content/:videoId", async (req, res) => {
  try {
    await requireUser(req);

    const videoId = String(req.params.videoId || "").trim();

    if (!videoId) {
      return res.status(400).json({
        error: "Video ID is required.",
      });
    }

    const content = await fetchOpenAIVideoContent(videoId);

    res.setHeader("Content-Type", content.contentType);
    res.setHeader(
      "Content-Disposition",
      `inline; filename="korlix-video-${videoId}.mp4"`
    );
    res.setHeader("Cache-Control", "private, max-age=3600");

    res.send(content.buffer);
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
      details: getKorlixUserFacingError(error),
    });
  }
});



app.post("/api/location/record", async (req, res) => {
  try {
    if (!supabaseAdmin) {
      return res.status(500).json({
        error: "Supabase is not configured on the backend.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);

    const latitude = Number(req.body.latitude);
    const longitude = Number(req.body.longitude);
    const accuracy = Number(req.body.accuracy || 0);
    const feature = String(req.body.feature || "locator").trim();
    const queryType = String(req.body.query_type || "").trim();
    const platform = String(req.body.platform || "unknown").trim();

    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      return res.status(400).json({
        error: "Valid latitude and longitude are required.",
      });
    }

    const { data: event, error: insertError } = await supabaseAdmin
      .from("user_location_events")
      .insert({
        user_id: user.id,
        email: user.email || profile?.email || null,
        latitude,
        longitude,
        accuracy: Number.isFinite(accuracy) ? accuracy : null,
        feature,
        query_type: queryType,
        platform,
      })
      .select("*")
      .single();

    if (insertError) {
      throw insertError;
    }

    const { data: updatedProfile, error: updateError } = await supabaseAdmin
      .from("user_profiles")
      .update({
        email: user.email || profile?.email || null,
        last_location_lat: latitude,
        last_location_lng: longitude,
        last_location_accuracy: Number.isFinite(accuracy) ? accuracy : null,
        last_location_feature: feature,
        last_location_at: new Date().toISOString(),
      })
      .eq("id", user.id)
      .select("*")
      .single();

    if (updateError) {
      throw updateError;
    }

    res.json({
      success: true,
      event,
      profile: updatedProfile,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: "Location could not be recorded.",
      details: getKorlixUserFacingError(error),
    });
  }
});

app.post("/api/theme/set", async (req, res) => {
  try {
    if (!supabaseAdmin) {
      return res.status(500).json({
        error: "Supabase is not configured on the backend.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);
    const tier = String(profile?.tier || "basic").toLowerCase();

    if (tier !== "ultra" && tier !== "enterprise") {
      return res.status(403).json({
        error: "Color themes are available on Ultra Premium and Enterprise.",
        upgradeRequired: true,
        requiredTier: "ultra",
      });
    }

    const allowedThemes = new Set([
      "korlix_blue",
      "cyber_purple",
      "ultra_gold",
      "matrix_green",
      "dark_crimson",
    ]);

    const preferredTheme = String(req.body.theme || "korlix_blue").trim();

    if (!allowedThemes.has(preferredTheme)) {
      return res.status(400).json({
        error: "Invalid theme selected.",
      });
    }

    const { data, error } = await supabaseAdmin
      .from("user_profiles")
      .update({
        preferred_theme: preferredTheme,
      })
      .eq("id", user.id)
      .select("*")
      .single();

    if (error) {
      throw error;
    }

    res.json({
      success: true,
      profile: data,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});

app.get("/api/crm/me", async (req, res) => {
  try {
    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);

    res.json({
      success: true,
      user: {
        id: user.id,
        email: user.email,
      },
      profile,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});


app.get("/", (req, res) => {
  res.json({
    status: "Korlix AI backend is running",
  });
});

app.get("/api/health", (req, res) => {
  let supabaseHost = null;

  try {
    supabaseHost = supabaseUrl ? new URL(supabaseUrl).host : null;
  } catch (_) {
    supabaseHost = "invalid-url";
  }

  res.json({
    status: "Korlix AI backend is healthy",
    supabaseConfigured: Boolean(supabaseAdmin),
    supabaseAuthConfigured: Boolean(supabaseAuth),
    supabaseHost,
    openAIConfigured: Boolean(process.env.OPENAI_API_KEY),
  });
});

app.get("/api/me", async (req, res) => {
  try {
    if (!supabaseAdmin) {
      return res.status(500).json({
        error: "Supabase is not configured on the backend.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);

    const { data: characters, error: charactersError } = await supabaseAdmin
      .from("characters")
      .select("*")
      .order("sort_order", { ascending: true });

    if (charactersError) {
      throw charactersError;
    }

    const { data: characterAccess, error: accessError } = await supabaseAdmin
      .from("user_character_access")
      .select("*")
      .eq("user_id", user.id);

    if (accessError) {
      throw accessError;
    }

    const usageCounter = await getOrCreateUsageCounter(user.id);

    res.json({
      user: {
        id: user.id,
        email: user.email,
      },
      profile,
      usage: usageCounter,
      characters: characters || [],
      characterAccess: characterAccess || [],
      limits: getTierLimits(profile?.tier || "basic"),
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});

app.get("/api/history", async (req, res) => {
  try {
    if (!supabaseAdmin) {
      return res.status(500).json({
        error: "Supabase is not configured on the backend.",
      });
    }

    const user = await requireUser(req);

    const { data, error } = await supabaseAdmin
      .from("generation_history")
      .select("*")
      .eq("user_id", user.id)
      .order("created_at", { ascending: false })
      .limit(100);

    if (error) {
      throw error;
    }

    res.json({
      history: data || [],
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});

app.delete("/api/history/:id", async (req, res) => {
  try {
    if (!supabaseAdmin) {
      return res.status(500).json({
        error: "Supabase is not configured on the backend.",
      });
    }

    const user = await requireUser(req);
    const id = req.params.id;

    const { error } = await supabaseAdmin
      .from("generation_history")
      .delete()
      .eq("id", id)
      .eq("user_id", user.id);

    if (error) {
      throw error;
    }

    res.json({
      success: true,
    });
  } catch (error) {
    res.status(error.statusCode || 500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});

app.post("/api/reports", async (req, res) => {
  try {
    if (!supabaseAdmin) {
      return res.status(500).json({
        error: "Supabase is not configured on the backend.",
      });
    }

    const user = await getAuthenticatedUser(req).catch(() => null);

    const reason = String(req.body.reason || "").trim();
    const details = String(req.body.details || "").trim();
    const generationId = req.body.generation_id || null;

    if (!reason) {
      return res.status(400).json({
        error: "Report reason is required.",
      });
    }

    const { data, error } = await supabaseAdmin
      .from("reports")
      .insert({
        user_id: user?.id || null,
        generation_id: generationId,
        reason,
        details,
        status: "new",
      })
      .select("*")
      .single();

    if (error) {
      throw error;
    }

    res.json({
      success: true,
      report: data,
    });
  } catch (error) {
    res.status(500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});

app.post("/api/account/delete-request", async (req, res) => {
  try {
    if (!supabaseAdmin) {
      return res.status(500).json({
        error: "Supabase is not configured on the backend.",
      });
    }

    const user = await getAuthenticatedUser(req).catch(() => null);
    const email = String(req.body.email || user?.email || "").trim();
    const reason = String(req.body.reason || "").trim();

    if (!user && !email) {
      return res.status(400).json({
        error: "Email is required for account deletion requests.",
      });
    }

    const { data, error } = await supabaseAdmin
      .from("account_deletion_requests")
      .insert({
        user_id: user?.id || null,
        email,
        reason,
        status: "requested",
      })
      .select("*")
      .single();

    if (error) {
      throw error;
    }

    res.json({
      success: true,
      request: data,
    });
  } catch (error) {
    res.status(500).json({
      error: getKorlixUserFacingError(error),
    });
  }
});


function buildKorlixImageImprovePrompt(userPrompt) {
  const instructions = String(userPrompt || "").trim();

  return `
Improve the uploaded image and return an actual enhanced image.

User instructions:
${instructions || "Create a polished, professional, natural-looking enhanced version of this picture."}

Important preservation rules:
- Preserve the subject's identity, face shape, ethnicity, age appearance, pose, hair, outfit, and overall realism.
- Do not turn the subject into a cartoon, painting, illustration, doll, or unrealistic character.
- Improve lighting, sharpness, color, contrast, background polish, detail, and professional photographic quality.
- Keep the result photorealistic and respectful.
- Do not add distorted hands, extra fingers, fake text, watermarks, or unrealistic body proportions.
`.trim();
}

async function createKorlixImprovedImage({ file, prompt }) {
  const mimeType = getUploadMimeType(file);
  const model = process.env.OPENAI_IMAGE_EDIT_MODEL || "gpt-image-1";

  const client = new OpenAI({
    apiKey: process.env.OPENAI_API_KEY,
  });

  const imageFile = await toFile(
    file.buffer,
    file.originalname || "korlix-upload.png",
    {
      type: mimeType || "image/png",
    }
  );

  const result = await client.images.edit({
    model,
    image: imageFile,
    prompt: buildKorlixImageImprovePrompt(prompt),
    n: 1,
    size: process.env.OPENAI_IMAGE_SIZE || "1024x1024",
  });

  const first = result?.data?.[0] || {};
  const b64 = first.b64_json || null;
  const imageUrl = first.url || null;

  if (!b64 && !imageUrl) {
    throw new Error("OpenAI did not return an enhanced image.");
  }

  return {
    imageDataUrl: b64 ? `data:image/png;base64,${b64}` : null,
    imageUrl,
  };
}

function buildKorlixImageCreatePrompt(userPrompt) {
  const instructions = String(userPrompt || "").trim();

  return `
Create an original image based on the user's description.

User description:
${instructions}

Korlix quality rules:
- Return an actual generated image, not a text description.
- Make the image polished, high-quality, and visually coherent.
- Follow the user description closely.
- Avoid distorted hands, extra limbs, unreadable text, watermarks, and unrealistic artifacts unless the user explicitly asks for a surreal style.
- Keep the result safe, respectful, and appropriate for a general app audience.
`.trim();
}

async function createKorlixImaginedImage({ prompt }) {
  const model =
    process.env.OPENAI_IMAGE_GENERATION_MODEL ||
    process.env.OPENAI_IMAGE_EDIT_MODEL ||
    "gpt-image-1";

  const response = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      prompt: buildKorlixImageCreatePrompt(prompt),
      n: 1,
      size: process.env.OPENAI_IMAGE_SIZE || "1024x1024",
    }),
  });

  const text = await response.text();
  let data;

  try {
    data = JSON.parse(text);
  } catch (_error) {
    throw new Error(
      `OpenAI image generation returned a non-JSON response: ${text.slice(
        0,
        300
      )}`
    );
  }

  if (!response.ok) {
    const message =
      data?.error?.message ||
      data?.message ||
      `OpenAI image generation failed with status ${response.status}`;
    throw new Error(message);
  }

  const first = data?.data?.[0] || {};
  const b64 =
    first.b64_json ||
    first.image_base64 ||
    first.base64_json ||
    first.image?.b64_json ||
    first.image?.base64;

  const imageUrl = first.url || first.image_url || first.image?.url || null;

  if (!b64 && !imageUrl) {
    throw new Error("OpenAI did not return a generated image.");
  }

  return {
    imageDataUrl: b64 ? `data:image/png;base64,${b64}` : null,
    imageUrl,
  };
}

app.post("/api/image/create", async (req, res) => {
  try {
    if (!process.env.OPENAI_API_KEY) {
      return res.status(400).json({
        error: "Missing OPENAI_API_KEY on backend.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);
    const usageCounter = await getOrCreateUsageCounter(user.id);

    const body = req.body || {};
    const prompt = String(body.prompt || "").trim();
    const languageCode = body.language || "en";

    if (!prompt) {
      return res.status(400).json({
        error: "Describe the picture you want Korlix AI to create.",
      });
    }

    const creditsNeeded = 1;

    const usageCheck = checkUsageAllowed({
      profile,
      usageCounter,
      creditsNeeded,
    });

    if (!usageCheck.allowed) {
      return res.status(429).json({
        error: usageCheck.reason,
        tier: profile?.tier || "basic",
      });
    }

    const imageResult = await createKorlixImaginedImage({ prompt });

    const content = "Image generated.";

    const historyItem = await saveGenerationHistory({
      user,
      profile,
      command: `Imagine a picture:\n${prompt}`,
      content,
      languageCode,
      fileRequested: false,
      searched: false,
      creditsNeeded,
    });

    const updatedUsage = await incrementUsage({
      usageCounter,
      liveSearchUsed: false,
      fileRequested: false,
      creditsNeeded,
    });

    return res.json({
      success: true,
      title: "Imagined picture",
      language: languageCode,
      content,
      imageDataUrl: imageResult.imageDataUrl,
      imageUrl: imageResult.imageUrl,
      authenticated: true,
      tier: profile?.tier || "basic",
      creditsUsed: creditsNeeded,
      usage: updatedUsage,
      generationId: historyItem?.id || null,
    });
  } catch (error) {
    console.error("Image create error:", sanitize(error?.message || error));

    return res.status(error.statusCode || 500).json({
      error: "Image generation failed",
      details: getKorlixUserFacingError(error),
    });
  }
});



app.post("/api/image/improve", documentUpload.single("image"), async (req, res) => {
  try {
    if (!process.env.OPENAI_API_KEY) {
      return res.status(400).json({
        error: "Missing OPENAI_API_KEY on backend.",
      });
    }

    const file = req.file;
    const body = req.body || {};
    const prompt = String(body.prompt || "").trim();
    const languageCode = body.language || "en";

    if (!file) {
      return res.status(400).json({
        error: "Please upload an image first.",
      });
    }

    if (!isImageUpload(file)) {
      return res.status(400).json({
        error: "Improve my picture supports JPG, JPEG, PNG, or WEBP images.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);
    const tier = profile?.tier || "basic";
    const usageCounter = await getOrCreateUsageCounter(user.id);

    if (!hasAdvancedUploadAccess(tier)) {
      return res.status(403).json({
        error: "Image improvement is available on Ultra Premium and Enterprise.",
        upgradeRequired: true,
        requiredTier: "ultra",
      });
    }

    const creditsNeeded = 1;

    const usageCheck = checkUsageAllowed({
      profile,
      usageCounter,
      creditsNeeded,
    });

    if (!usageCheck.allowed) {
      return res.status(429).json({
        error: usageCheck.reason,
        tier,
      });
    }

    const imageResult = await createKorlixImprovedImage({
      file,
      prompt,
    });

    const content = "Enhanced image generated.";

    const historyItem = await saveGenerationHistory({
      user,
      profile,
      command: `Improve my picture: ${file.originalname}\nInstructions: ${prompt || "Default professional enhancement"}`,
      content,
      languageCode,
      fileRequested: false,
      searched: false,
      creditsNeeded,
    });

    const updatedUsage = await incrementUsage({
      usageCounter,
      liveSearchUsed: false,
      fileRequested: false,
      creditsNeeded,
    });

    return res.json({
      success: true,
      title: "Improved picture",
      language: languageCode,
      fileName: file.originalname,
      content,
      imageDataUrl: imageResult.imageDataUrl,
      imageUrl: imageResult.imageUrl,
      authenticated: true,
      tier,
      creditsUsed: creditsNeeded,
      usage: updatedUsage,
      generationId: historyItem?.id || null,
    });
  } catch (error) {
    console.error("Image improvement error:", sanitize(error?.message || error));

    return res.status(error.statusCode || 500).json({
      error: "Image improvement failed",
      details: getKorlixUserFacingError(error),
    });
  }
});



function extractKorlixResponseText(response) {
  if (typeof response?.output_text === "string" && response.output_text.trim()) {
    return response.output_text.trim();
  }

  const chunks = [];

  for (const item of response?.output || []) {
    for (const content of item?.content || []) {
      if (typeof content?.text === "string") {
        chunks.push(content.text);
      } else if (typeof content?.value === "string") {
        chunks.push(content.value);
      }
    }
  }

  return chunks.join("\n").trim();
}

function getKorlixUploadedFiles(req) {
  if (Array.isArray(req.files)) {
    return req.files;
  }

  if (req.files && typeof req.files === "object") {
    return Object.values(req.files).flat();
  }

  if (req.file) {
    return [req.file];
  }

  return [];
}

function assertKorlixSupportedUpload(file) {
  const fileName = String(file?.originalname || "").toLowerCase();

  const supported =
    fileName.endsWith(".jpg") ||
    fileName.endsWith(".jpeg") ||
    fileName.endsWith(".png") ||
    fileName.endsWith(".webp") ||
    fileName.endsWith(".pdf") ||
    fileName.endsWith(".txt") ||
    fileName.endsWith(".md") ||
    fileName.endsWith(".csv") ||
    fileName.endsWith(".doc") ||
    fileName.endsWith(".docx") ||
    fileName.endsWith(".xls") ||
    fileName.endsWith(".xlsx") ||
    fileName.endsWith(".ppt") ||
    fileName.endsWith(".pptx");

  if (!supported) {
    const error = new Error(
      `Unsupported file type: ${file?.originalname || "unknown file"}`
    );
    error.statusCode = 400;
    throw error;
  }
}

app.post("/api/analyze-documents", documentUpload.array("files", 8), async (req, res) => {
  try {
    if (!process.env.OPENAI_API_KEY) {
      return res.status(400).json({
        error: "Missing OPENAI_API_KEY on backend.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);
    const usageCounter = await getOrCreateUsageCounter(user.id);

    const files = getKorlixUploadedFiles(req);
    const body = req.body || {};
    const prompt = String(body.prompt || body.question || "").trim();
    const languageCode = body.language || "en";

    if (!files.length) {
      return res.status(400).json({
        error: "Please upload one or more files.",
      });
    }

    if (files.length > 8) {
      return res.status(400).json({
        error: "You can upload up to 8 files at once.",
      });
    }

    for (const file of files) {
      assertKorlixSupportedUpload(file);
    }

    const creditsNeeded = 1;

    const usageCheck = checkUsageAllowed({
      profile,
      usageCounter,
      creditsNeeded,
    });

    if (!usageCheck.allowed) {
      return res.status(429).json({
        error: usageCheck.reason,
        tier: profile?.tier || "basic",
      });
    }

    const client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    const content = [
      {
        type: "input_text",
        text: `
The user uploaded ${files.length} file${files.length === 1 ? "" : "s"}.

User question:
${prompt || "Please summarize and explain the uploaded files."}

Instructions:
- Analyze all uploaded files together.
- If the files relate to each other, compare and connect them.
- If the user asks about "these files", answer using every uploaded file.
- Be clear, practical, and specific.
`.trim(),
      },
    ];

    for (const file of files) {
      const mimeType = getUploadMimeType(file);
    if (mimeType === "application/octet-stream") {
      return res.status(400).json({
        error: `Unsupported single file type after MIME detection: ${file.originalname}`,
      });
    }

      const dataUrl = `data:${mimeType};base64,${file.buffer.toString("base64")}`;

      if (isImageUpload(file)) {
        content.push({
          type: "input_image",
          image_url: dataUrl,
        });
      } else {
        content.push({
          type: "input_file",
          filename: file.originalname || "uploaded-file",
          file_data: dataUrl,
        });
      }
    }

    const response = await client.responses.create({
      model:
        process.env.OPENAI_FILE_MODEL ||
        process.env.OPENAI_MODEL ||
        process.env.OPENAI_CHAT_MODEL ||
        "gpt-4o-mini",
      input: [
        {
          role: "user",
          content,
        },
      ],
    });

    const answer = extractKorlixResponseText(response);

    if (!answer) {
      throw new Error("No answer was returned for the uploaded files.");
    }

    const fileNames = files.map((file) => file.originalname).join(", ");

    const historyItem = await saveGenerationHistory({
      user,
      profile,
      command: `Uploaded files: ${fileNames}\n\nQuestion: ${prompt}`,
      content: answer,
      languageCode,
      fileRequested: true,
      searched: false,
      creditsNeeded,
    });

    const updatedUsage = await incrementUsage({
      usageCounter,
      liveSearchUsed: false,
      fileRequested: true,
      creditsNeeded,
    });

    return res.json({
      success: true,
      title:
        files.length === 1
          ? `File answer: ${files[0].originalname}`
          : `File answer: ${files.length} files`,
      content: answer,
      answer,
      files: files.map((file) => ({
        name: file.originalname,
        mimeType: getUploadMimeType(file),
        size: file.size,
      })),
      language: languageCode,
      authenticated: true,
      tier: profile?.tier || "basic",
      creditsUsed: creditsNeeded,
      usage: updatedUsage,
      generationId: historyItem?.id || null,
    });
  } catch (error) {
    console.error("Multi-file analysis error:", sanitize(error?.message || error));

    return res.status(error.statusCode || 500).json({
      error: "File analysis failed",
      details: getKorlixUserFacingError(error),
    });
  }
});



app.post("/api/analyze-document", documentUpload.single("file"), async (req, res) => {
  try {
    if (!process.env.OPENAI_API_KEY) {
      return res.status(400).json({
        error: "Missing OPENAI_API_KEY on backend.",
      });
    }

    const user = await requireUser(req);
    const profile = await getOrCreateProfile(user);
    const tier = profile?.tier || "basic";
    const usageCounter = await getOrCreateUsageCounter(user.id);

    const command = String(req.body.command || "").trim();
    const languageCode = req.body.language || "en";
    const language = languageMap[languageCode] || languageMap.en;
    const file = req.file;

    if (!file) {
      return res.status(400).json({
        error: "Please upload a document or image.",
      });
    }

    if (!command) {
      return res.status(400).json({
        error: "Ask a question about the uploaded file.",
      });
    }

    if (!hasProUploadAccess(tier)) {
      return res.status(403).json({
        error: "Document upload is available on Pro, Ultra Premium, and Enterprise.",
        upgradeRequired: true,
        requiredTier: "pro",
      });
    }

    const normalDocument = isNormalDocumentUpload(file);
    const advancedUpload = isAdvancedUpload(file);

    if (!normalDocument && !advancedUpload) {
      return res.status(400).json({
        error:
          "Unsupported file type. Upload PDF, DOCX, TXT, MD, CSV, JPG, JPEG, PNG, or WEBP.",
      });
    }

    if (advancedUpload && !hasAdvancedUploadAccess(tier)) {
      return res.status(403).json({
        error: "Image, scan, OCR, and handwriting uploads are available on Ultra Premium and Enterprise.",
        upgradeRequired: true,
        requiredTier: "ultra",
      });
    }

    const fileRequested = wantsFile(command);
    const useAdvancedMode = advancedUpload || (isPdfUpload(file) && hasAdvancedUploadAccess(tier));
    const creditsNeeded = 1;

    const usageCheck = checkUsageAllowed({
      profile,
      usageCounter,
      creditsNeeded,
    });

    if (!usageCheck.allowed) {
      return res.status(429).json({
        error: usageCheck.reason,
        tier,
      });
    }

    const client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    let response;
    let textWasTruncated = false;
    let usedVision = false;

    if (useAdvancedMode) {
      try {
        response = await createAdvancedFileResponse({
          client,
          file,
          command,
          language,
        });

        usedVision = true;
      } catch (advancedError) {
        if (!isPdfUpload(file)) {
          throw advancedError;
        }

        const rawText = await extractUploadedDocumentText(file);
        const textResult = truncateDocumentText(rawText);

        if (!textResult.text) {
          throw new Error(
            "This scanned PDF could not be read. Try uploading clearer page images."
          );
        }

        textWasTruncated = textResult.truncated;

        const model =
    process.env.OPENAI_DOCUMENT_MODEL ||
    process.env.OPENAI_ULTRA_MODEL ||
    process.env.OPENAI_MODEL ||
    "gpt-4o-mini";

        response = await createOpenAIResponse(client, {
          model,
          input: buildFileAnalysisPrompt({
            command,
            language,
            fileName: file.originalname,
            extractedText: textResult.text,
            textWasTruncated,
            advancedMode: false,
          }),
          useSearch: false,
        });
      }
    } else {
      const rawText = await extractUploadedDocumentText(file);
      const textResult = truncateDocumentText(rawText);

      if (!textResult.text) {
        return res.status(400).json({
          error:
            "No readable text was found. Scanned images and handwriting require Ultra Premium or Enterprise.",
          upgradeRequired: true,
          requiredTier: "ultra",
        });
      }

      textWasTruncated = textResult.truncated;

      const model =
    process.env.OPENAI_DOCUMENT_MODEL ||
    process.env.OPENAI_ULTRA_MODEL ||
    process.env.OPENAI_MODEL ||
    "gpt-4o-mini";

      response = await createOpenAIResponse(client, {
        model,
        input: buildFileAnalysisPrompt({
          command,
          language,
          fileName: file.originalname,
          extractedText: textResult.text,
          textWasTruncated,
          advancedMode: false,
        }),
        useSearch: false,
      });
    }

    const content = String(response.output_text || "").trim();

    if (!content) {
      throw new Error("No AI content returned.");
    }

    const historyItem = await saveGenerationHistory({
      user,
      profile,
      command: `Uploaded file: ${file.originalname}\nQuestion: ${command}`,
      content,
      languageCode,
      fileRequested,
      searched: false,
      creditsNeeded,
    });

    const updatedUsage = await incrementUsage({
      usageCounter,
      liveSearchUsed: false,
      fileRequested: false,
      creditsNeeded,
    });

    res.json({
      title: "Korlix AI File Answer",
      language: languageCode,
      fileName: file.originalname,
      fileRequested,
      usedVision,
      textWasTruncated,
      authenticated: true,
      tier,
      creditsUsed: creditsNeeded,
      usage: updatedUsage,
      generationId: historyItem?.id || null,
      content,
    });
  } catch (error) {
    console.error("File analysis error:", sanitize(error?.message));

    res.status(error.statusCode || 500).json({
      error: "File analysis failed",
      details: getKorlixUserFacingError(error),
    });
  }
});


app.post("/api/generate", async (req, res) => {
  try {
    const command = String(req.body.command || "").trim();
    const languageCode = req.body.language || "en";
    const language = languageMap[languageCode] || languageMap.en;

    if (!command) {
      return res.status(400).json({
        error: "Command is required",
      });
    }

    if (!process.env.OPENAI_API_KEY) {
      return res.status(400).json({
        error: "Missing OPENAI_API_KEY on backend.",
      });
    }

    const liveSearchNeeded = shouldUseLiveSearch(command);
    const fileRequested = wantsFile(command);
    const creditsNeeded = calculateCredits({
      liveSearchNeeded,
      fileRequested,
    });

    let user = null;
    let profile = null;
    let usageCounter = null;
    let updatedUsage = null;

    try {
      user = await getAuthenticatedUser(req);

      if (user) {
        profile = await getOrCreateProfile(user);
        usageCounter = await getOrCreateUsageCounter(user.id);

        const usageCheck = checkUsageAllowed({
          profile,
          usageCounter,
          creditsNeeded,
        });

        if (!usageCheck.allowed) {
          return res.status(429).json({
            error: usageCheck.reason,
            tier: profile?.tier || "basic",
          });
        }
      }
    } catch (authError) {
      return res.status(401).json({
        error: sanitize(authError?.message),
      });
    }

    const client = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    const normalModel = process.env.OPENAI_MODEL || "gpt-4o-mini";
    const searchModel = process.env.OPENAI_SEARCH_MODEL || normalModel;

    const modeInstruction = fileRequested
      ? `
The user requested a file/document-style output.
Create a polished deliverable with clean sections, practical details, and strong structure.
`
      : `
The user did not request a PDF, file, or document.
Answer like a premium AI assistant, not like a document generator.
Do not use generic sections like Overview, Step-by-Step Plan, Common Mistakes, or Next Move unless they truly fit the question.
For a normal question, give:
1. Direct answer
2. Why
3. Best options or contenders when useful
4. Final verdict
`;

    const searchInstruction = liveSearchNeeded
      ? `
This question needs current information.
Use live web search.
Bring up real contenders, recent data, standings, rankings, current performance, or relevant sources when useful.
For sports questions, do not dodge. Give a best pick or ranked shortlist and explain the evidence.
`
      : `
This question does not require live search unless the user explicitly asks for current information.
`;

    const selectedCharacterId = profile?.selected_character || "jj";
    const selectedCharacter = getCharacterPersonality(selectedCharacterId);

    
  // === MEMORY: fetch last 10 exchanges for this user + character ===
  let conversationHistoryText = '';
  try {
    const characterIdForHistory = profile && profile.selected_character ? profile.selected_character : 'chee_chai_chee';
    const userId = user && user.id ? user.id : null;
    if (userId) {
      const { data: historyRows } = await supabaseAdmin
        .from('generation_history')
        .select('prompt, response')
        .eq('user_id', userId)
        .eq('character_id', characterIdForHistory)
        .eq('result_type', 'answer')
        .order('created_at', { ascending: false })
        .limit(10);
      if (historyRows && historyRows.length > 0) {
        const reversed = historyRows.slice().reverse();
        conversationHistoryText = reversed.map(function(r) {
          return 'User: ' + (r.prompt || '') + '\nAssistant: ' + (r.response || '');
        }).join('\n');
      }
    }
  } catch (memErr) {
    console.error('Memory fetch error (non-fatal):', memErr && memErr.message ? memErr.message : memErr);
  }
  const memoryBlock = conversationHistoryText
    ? 'Recent conversation history:\n' + conversationHistoryText + '\n\n'
    : '';
  // === END MEMORY ===

const input = `
You are Korlix AI, a premium multilingual AI assistant platform powered by selectable AI characters.

The current selected character is:
${selectedCharacter.name}

Character behavior:
${selectedCharacter.style}

Do not be goofy. Do not sound childish.

The user selected this language:
${language.name}

Language rule:
${language.instruction}

${memoryBlock}The user wrote:
"${command}"

User tier:
${profile?.tier || "guest"}

${modeInstruction}

${searchInstruction}

Answer quality rules:
- Be direct.
- Be useful.
- Give judgment when the user asks for judgment.
- For "best" questions, do not hide behind vague wording.
- If there is no single answer, give the top contenders and your final pick.
- Use real evidence when available.
- Avoid filler.
- Avoid generic chatbot disclaimers.
- Avoid ending with "If you want".
- Do not mention PDF unless the user asked for a file or PDF.

Formatting rules:
- Use plain text only.
- Do not use markdown symbols like **bold**, ###, checkboxes, or emojis.
- Do not use strange symbols.
- Use short headings only when helpful.
- Use numbered lists for rankings or steps.
- Use hyphen bullets only when needed.

Return only the finished response.
`;

    let response;
    let searched = false;
    let fallbackUsed = false;

    if (liveSearchNeeded) {
      try {
        response = await createOpenAIResponse(client, {
          model: searchModel,
          input,
          useSearch: true,
        });

        searched = true;
      } catch (searchError) {
        console.error(
          "Live search failed, falling back:",
          sanitize(searchError?.message)
        );

        response = await createOpenAIResponse(client, {
          model: normalModel,
          input: `${input}

Important: Live search was attempted but failed. Give the most useful answer possible and clearly avoid pretending to know live standings.`,
          useSearch: false,
        });

        fallbackUsed = true;
      }
    } else {
      response = await createOpenAIResponse(client, {
        model: normalModel,
        input,
        useSearch: false,
      });
    }

    const content = String(response.output_text || "").trim();

    if (!content) {
      throw new Error("No AI content returned.");
    }

    let historyItem = null;

    if (user) {
      historyItem = await saveGenerationHistory({
        user,
        profile,
        command,
        content,
        languageCode,
        fileRequested,
        searched,
        creditsNeeded,
      });

      updatedUsage = await incrementUsage({
        usageCounter,
        liveSearchUsed: searched,
        fileRequested,
        creditsNeeded,
      });
    }

    res.json({
      title: "Korlix AI Output",
      language: languageCode,
      searched,
      fallbackUsed,
      fileRequested,
      authenticated: Boolean(user),
      tier: profile?.tier || "guest",
      creditsUsed: creditsNeeded,
      usage: updatedUsage,
      generationId: historyItem?.id || null,
      content,
    });
  } catch (error) {
    console.error("AI generation error:", sanitize(error?.message));

    res.status(500).json({
      error: getKorlixUserFacingError(error),
      details: getKorlixUserFacingError(error),
    });
  }
});


app.use("/api", (req, res) => {
  return res.status(404).json({
    error: `API route not found: ${req.method} ${req.originalUrl}`,
    routeNotDeployed: true,
    method: req.method,
    path: req.originalUrl,
  });
});

app.listen(port, () => {
  console.log(`Korlix AI backend running on port ${port}`);
});
