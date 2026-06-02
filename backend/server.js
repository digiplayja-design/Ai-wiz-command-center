import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import OpenAI from "openai";
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

function sanitize(value) {
  const openAiKey = process.env.OPENAI_API_KEY || "";

  return String(value || "")
    .replace(openAiKey, "[hidden_openai_key]")
    .replace(supabaseServiceRoleKey, "[hidden_supabase_service_role_key]")
    .replace(supabaseAnonKey, "[hidden_supabase_anon_key]")
    .replace(/sk-[A-Za-z0-9_\-]+/g, "sk-[hidden]");
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
  return characterPersonalityMap[characterId] || characterPersonalityMap.jj;
}

function canSelectCharacterForTier(tier, characterId) {
  if (tier === "enterprise" || tier === "ultra") {
    return true;
  }

  if (tier === "pro") {
    return ["jj", "phil", "character_03"].includes(characterId);
  }

  return characterId === "jj";
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
      videoGenerationsMonthly: 0,
      musicGenerationIncluded: false,
    },
    ultra: {
      dailyRequestLimit: 75,
      dailyCreditLimit: 200,
      characterLimit: 999,
      videoGenerationsMonthly: 3,
      musicGenerationIncluded: false,
    },
    enterprise: {
      dailyRequestLimit: 250,
      dailyCreditLimit: 1000,
      characterLimit: 999,
      videoGenerationsMonthly: 0,
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

function hasProUploadAccess(tier) {
  return tier === "pro" || tier === "ultra" || tier === "enterprise";
}

function hasAdvancedUploadAccess(tier) {
  return tier === "ultra" || tier === "enterprise";
}

function getUploadMimeType(file) {
  const fileName = String(file?.originalname || "").toLowerCase();
  const mimeType = String(file?.mimetype || "").toLowerCase();

  if (mimeType) return mimeType;
  if (fileName.endsWith(".png")) return "image/png";
  if (fileName.endsWith(".webp")) return "image/webp";
  if (fileName.endsWith(".pdf")) return "application/pdf";
  if (fileName.endsWith(".jpg") || fileName.endsWith(".jpeg")) return "image/jpeg";

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


app.post("/api/auth/signup", async (req, res) => {
  try {
    if (!supabaseAuth) {
      return res.status(500).json({
        error: "Supabase auth is not configured on the backend.",
      });
    }

    const email = String(req.body.email || "").trim().toLowerCase();
    const password = String(req.body.password || "").trim();

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
        error: sanitize(error.message),
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
      session: data.session
        ? {
            access_token: data.session.access_token,
            refresh_token: data.session.refresh_token,
            expires_at: data.session.expires_at,
          }
        : null,
    });
  } catch (error) {
    res.status(500).json({
      error: sanitize(error?.message),
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
        error: sanitize(error.message),
      });
    }

    res.json({
      success: true,
      message: "Signed in.",
      user: data.user
        ? {
            id: data.user.id,
            email: data.user.email,
          }
        : null,
      session: data.session
        ? {
            access_token: data.session.access_token,
            refresh_token: data.session.refresh_token,
            expires_at: data.session.expires_at,
          }
        : null,
    });
  } catch (error) {
    res.status(500).json({
      error: sanitize(error?.message),
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
        error: sanitize(error.message),
      });
    }

    res.json({
      success: true,
      message: "Session refreshed.",
      user: data.user
        ? {
            id: data.user.id,
            email: data.user.email,
          }
        : null,
      session: data.session
        ? {
            access_token: data.session.access_token,
            refresh_token: data.session.refresh_token,
            expires_at: data.session.expires_at,
          }
        : null,
    });
  } catch (error) {
    res.status(500).json({
      error: sanitize(error?.message),
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
    const characterId = String(req.body.character_id || "").trim();

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
      error: sanitize(error?.message),
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
      error: sanitize(error?.message),
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
      error: sanitize(error?.message),
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
      error: sanitize(error?.message),
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
      error: sanitize(error?.message),
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
      error: sanitize(error?.message),
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
    const creditsNeeded = useAdvancedMode ? 5 : 4;

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
      details: sanitize(error?.message),
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

The user wrote:
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
      error: "AI generation failed",
      details: sanitize(error?.message),
    });
  }
});

app.listen(port, () => {
  console.log(`Korlix AI backend running on port ${port}`);
});
