import http from "node:http";
import { Buffer } from "node:buffer";
import { timingSafeEqual } from "node:crypto";
import { InferenceClient } from "@huggingface/inference";

const PORT = Number(process.env.PORT || 8080);
const APP_ACCESS_TOKEN = process.env.APP_ACCESS_TOKEN;
const GROQ_API_KEY = process.env.GROQ_API_KEY;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY;
const HF_TOKEN = process.env.HF_TOKEN;
const HF_IMAGE_MODEL = process.env.HF_IMAGE_MODEL || "black-forest-labs/FLUX.1-Kontext-dev";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const MAX_BODY_BYTES = 24 * 1024 * 1024;
const WINDOW_MS = 60_000;
const MAX_REQUESTS_PER_WINDOW = 12;
const clients = new Map();

const COMMAND_GUIDANCE = {
  glowUp: "Apply natural premium portrait enhancement: balanced exposure, subtle skin tone refinement, realistic detail and restrained contrast. Preserve exact identity and facial geometry.",
  beStudio: "Create polished studio-photography lighting while retaining the existing background, scene, objects and composition. Do not cut out or replace the background.",
  softLight: "Apply soft, flattering, diffused light with gentle highlights and natural shadows. Preserve identity and scene.",
  proShot: "Give the photo a professional camera-shot finish with natural dynamic range, refined color, realistic texture and controlled sharpening. Preserve identity and composition.",
  old2New: "Restore this old or degraded photograph: reduce scratches, noise and fading, recover plausible natural color when appropriate, and preserve identity, face shape, expression, age appearance, clothing and composition. Do not invent details.",
  hdReal: "Improve perceived photographic detail and clarity naturally without changing identity, geometry, scene content or composition. Avoid artificial textures and halos.",
  colorFix: "Correct white balance, exposure and color casts with realistic, faithful colors. Preserve skin tones and original scene.",
  nightFix: "Improve visibility in a dark or night photograph, lift useful shadows and reduce noise while preserving a believable night atmosphere and practical light sources.",
  longExposure: "Apply a tasteful still-image long-exposure aesthetic with smooth directional motion rendering only where visually plausible. Keep the main subject recognizable and avoid changing the scene.",
  motionBlur: "Apply controlled directional motion blur consistent with the existing composition while retaining the main subject's recognizable features.",
  goldenHour: "Create warm golden-hour illumination, gentle sunlit highlights and natural warm color grading without changing the scene or subject identity.",
  faceRestore: "Carefully restore facial clarity and fine detail while preserving exact identity, facial geometry, expression, age appearance and natural skin texture. Do not beautify into a different person."
};

const commandAliases = new Map(Object.keys(COMMAND_GUIDANCE).map((key) => [key, key]));

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
}

function authorized(req) {
  if (!APP_ACCESS_TOKEN) return false;
  const provided = Buffer.from(String(req.headers["x-app-token"] || ""));
  const expected = Buffer.from(APP_ACCESS_TOKEN);
  return provided.length === expected.length && timingSafeEqual(provided, expected);
}

function rateLimit(req) {
  const key = req.socket.remoteAddress || "unknown";
  const now = Date.now();
  const current = clients.get(key);
  if (!current || now - current.startedAt > WINDOW_MS) {
    clients.set(key, { startedAt: now, count: 1 });
    return true;
  }
  current.count += 1;
  return current.count <= MAX_REQUESTS_PER_WINDOW;
}

async function readJSON(req) {
  const chunks = [];
  let total = 0;
  for await (const chunk of req) {
    total += chunk.length;
    if (total > MAX_BODY_BYTES) throw new Error("İstek boyutu çok büyük. Daha küçük bir fotoğraf deneyin.");
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function parseModelJSON(text) {
  const cleaned = String(text || "").replace(/^\s*```(?:json)?/i, "").replace(/```\s*$/, "").trim();
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("Model analiz yanıtı JSON olarak okunamadı.");
  return JSON.parse(cleaned.slice(start, end + 1));
}

const ANALYSIS_PROMPT = "Analyze this photograph for a photo-editing app. Return ONLY JSON with keys: summary (short Turkish sentence), lighting (short Turkish phrase), color (short Turkish phrase), composition (short Turkish phrase), recommendations (array of at most 4 short Turkish suggestions), recommended_commands (array using only GLOWUP, BGSTUDIO, SOFTLIGHT, PROSHOT, OLD2NEW, HDREAL, COLORFIX, NIGHTFIX, LONGEXPOSURE, MOTIONBLUR, GOLDENHOUR, FACEFIX). Do not identify people. Do not infer sensitive traits. Preserve the actual scene; do not recommend object removal, outfit change or background removal.";

async function analyzeWithGemini(imageBytes, mime) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(GEMINI_API_KEY)}`;
  const response = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      contents: [{ parts: [{ text: ANALYSIS_PROMPT }, { inline_data: { mime_type: mime, data: imageBytes.toString("base64") } }] }],
      generationConfig: { responseMimeType: "application/json", temperature: 0.2, maxOutputTokens: 500 }
    }),
    signal: AbortSignal.timeout(45_000)
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message || `Gemini HTTP ${response.status}`);
  const text = data?.candidates?.[0]?.content?.parts?.map((part) => part.text || "").join("");
  return { ...parseModelJSON(text), provider: "Google Gemini Flash" };
}

async function analyzeWithGroq(imageBytes, mime) {
  const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: { authorization: `Bearer ${GROQ_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      model: "qwen/qwen3.8-27b",
      messages: [{ role: "user", content: [
        { type: "text", text: ANALYSIS_PROMPT },
        { type: "image_url", image_url: { url: `data:${mime};base64,${imageBytes.toString("base64")}` } }
      ] }],
      temperature: 0.2,
      max_completion_tokens: 500
    }),
    signal: AbortSignal.timeout(45_000)
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message || `Groq HTTP ${response.status}`);
  return { ...parseModelJSON(data?.choices?.[0]?.message?.content), provider: "Groq Qwen Vision" };
}

async function analyzePhoto(imageBytes, mime) {
  const failures = [];
  if (GEMINI_API_KEY) {
    try { return await analyzeWithGemini(imageBytes, mime); }
    catch (error) { failures.push(`Gemini: ${error.message}`); }
  }
  if (GROQ_API_KEY) {
    try { return await analyzeWithGroq(imageBytes, mime); }
    catch (error) { failures.push(`Groq: ${error.message}`); }
  }
  if (failures.length) throw new Error(failures.join(" | "));
  return null;
}

function makePrompt(commands, analysis) {
  const selected = [...new Set(commands.map((item) => commandAliases.get(item)).filter(Boolean))];
  if (selected.length === 0) throw new Error("Desteklenen bir slash komutu gönderilmedi.");
  const instructions = selected.map((command) => COMMAND_GUIDANCE[command]);
  const analysisContext = analysis
    ? `\nPhoto analysis from ${analysis.provider || "vision model"}: ${analysis.summary || ""}. Lighting: ${analysis.lighting || "unknown"}. Color: ${analysis.color || "unknown"}. Composition: ${analysis.composition || "unknown"}.`
    : "";
  return [
    "Edit the supplied photograph. Treat the input as the source of truth.",
    ...instructions,
    "Global preservation rules: retain the same people and exact identity; do not change facial features, face shape, expression, age, hairstyle or clothing. Do not add or remove people, objects or text. Do not perform object removal, outfit changes, background removal or Ghibli/anime style transfer. Keep original framing and composition.",
    "Make a coherent, photorealistic edit. Avoid excessive smoothing, plastic skin, oversharpening, halos, invented details and artificial HDR.",
    analysisContext
  ].join("\n\n");
}

async function editWithHuggingFace(imageBytes, mime, prompt) {
  const hf = new InferenceClient(HF_TOKEN);
  const source = new Blob([imageBytes], { type: mime });
  const result = await hf.imageToImage({
    model: HF_IMAGE_MODEL,
    inputs: source,
    parameters: {
      prompt,
      negative_prompt: "different person, changed face, altered identity, changed clothing, changed background, added objects, removed objects, cartoon, anime, plastic skin, oversharpening",
      num_inference_steps: 24,
      guidance_scale: 4
    }
  });
  const bytes = Buffer.from(await result.arrayBuffer());
  if (!bytes.length || bytes.length > 18 * 1024 * 1024) throw new Error("Hugging Face geçerli veya uygun boyutta görsel döndürmedi.");
  return bytes;
}

async function editWithOpenAI(imageBytes, mime, prompt, commands) {
  const commandSet = new Set(commands);
  const precision = ["faceRestore", "old2New", "proShot", "hdReal"].some((item) => commandSet.has(item));
  const model = precision ? "gpt-image-2.6-sunburst" : "gpt-image-2.6-flare";
  const form = new FormData();
  form.append("model", model);
  form.append("prompt", prompt);
  form.append("quality", "high");
  form.append("output_format", "jpeg");
  form.append("image[]", new Blob([imageBytes], { type: mime }), mime === "image/png" ? "source.png" : "source.jpg");
  const response = await fetch("https://api.openai.com/v1/images/edits", {
    method: "POST",
    headers: { authorization: `Bearer ${OPENAI_API_KEY}` },
    body: form,
    signal: AbortSignal.timeout(180_000)
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message || `OpenAI HTTP ${response.status}`);
  const output = data?.data?.[0]?.b64_json;
  if (!output) throw new Error("OpenAI görsel döndürmedi.");
  return { bytes: Buffer.from(output, "base64"), provider: `OpenAI ${model}` };
}

async function handleProcess(req, res) {
  if (!APP_ACCESS_TOKEN) return send(res, 503, { error: "Sunucuda APP_ACCESS_TOKEN ayarlanmamış." });
  if (!authorized(req)) return send(res, 401, { error: "Uygulama erişim anahtarı geçersiz." });
  if (!rateLimit(req)) return send(res, 429, { error: "Çok fazla istek gönderildi. Bir dakika sonra tekrar deneyin." });

  let payload;
  try { payload = await readJSON(req); }
  catch (error) { return send(res, 400, { error: error.message || "Geçersiz JSON isteği." }); }

  const encoded = payload.image_base64;
  if (typeof encoded !== "string" || encoded.length < 100) return send(res, 400, { error: "Fotoğraf verisi eksik." });
  const mime = payload.mime_type === "image/png" ? "image/png" : "image/jpeg";
  const imageBytes = Buffer.from(encoded, "base64");
  if (!imageBytes.length || imageBytes.length > 18 * 1024 * 1024) return send(res, 413, { error: "Fotoğraf 18 MB sınırını aşıyor." });

  const commands = Array.isArray(payload.commands) ? payload.commands : [];
  let analysis = null;
  try { analysis = await analyzePhoto(imageBytes, mime); }
  catch (error) { console.warn("Vision analysis unavailable:", error.message); }

  let prompt;
  try { prompt = makePrompt(commands, analysis); }
  catch (error) { return send(res, 400, { error: error.message }); }

  let edited;
  const failures = [];
  if (HF_TOKEN) {
    try {
      const bytes = await editWithHuggingFace(imageBytes, mime, prompt);
      edited = { bytes, provider: `Hugging Face • ${HF_IMAGE_MODEL}` };
    } catch (error) { failures.push(`Hugging Face: ${error.message}`); }
  }
  if (!edited && OPENAI_API_KEY) {
    try { edited = await editWithOpenAI(imageBytes, mime, prompt, commands); }
    catch (error) { failures.push(`OpenAI: ${error.message}`); }
  }
  if (!edited) {
    const reason = failures.length ? failures.join(" | ") : "Görsel düzenleme için HF_TOKEN gerekli. İsteğe bağlı yedek olarak OPENAI_API_KEY eklenebilir.";
    return send(res, 503, {
      error: reason,
      analysis,
      recommendations: Array.isArray(analysis?.recommendations) ? analysis.recommendations : [],
      analysis_provider: analysis?.provider || null
    });
  }

  return send(res, 200, {
    image_base64: edited.bytes.toString("base64"),
    provider: edited.provider,
    analysis,
    analysis_provider: analysis?.provider || null,
    analysis_summary: analysis?.summary || null,
    recommendations: Array.isArray(analysis?.recommendations) ? analysis.recommendations.slice(0, 4) : [],
    recommended_commands: Array.isArray(analysis?.recommended_commands) ? analysis.recommended_commands.slice(0, 4) : []
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    return send(res, 200, {
      ok: true,
      service: "lut-studio-multi-provider-backend",
      providers: {
        gemini_analysis: Boolean(GEMINI_API_KEY),
        groq_vision_fallback: Boolean(GROQ_API_KEY),
        huggingface_image_edit: Boolean(HF_TOKEN),
        openai_fallback: Boolean(OPENAI_API_KEY)
      }
    });
  }
  if (req.method === "POST" && req.url === "/v1/process") {
    if (!req.headers["content-type"]?.includes("application/json")) return send(res, 415, { error: "Content-Type application/json gerekli." });
    return handleProcess(req, res);
  }
  return send(res, 404, { error: "Endpoint bulunamadı." });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`LUT Studio multi-provider backend listening on port ${PORT}`);
});
