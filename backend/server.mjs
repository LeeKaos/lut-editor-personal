import http from "node:http";
import { Buffer } from "node:buffer";

const PORT = Number(process.env.PORT || 8080);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const APP_ACCESS_TOKEN = process.env.APP_ACCESS_TOKEN;
const MAX_BODY_BYTES = 24 * 1024 * 1024;
const WINDOW_MS = 60_000;
const MAX_REQUESTS_PER_WINDOW = 12;
const clients = new Map();

const COMMAND_GUIDANCE = {
  glowUp: "Apply a natural premium portrait enhancement: balanced exposure, subtle skin tone refinement, realistic detail and restrained contrast. Preserve the person's exact identity and facial geometry.",
  beStudio: "Create a polished studio-photography lighting treatment while retaining the existing background, scene, objects and composition. Do not cut out or replace the background.",
  softLight: "Apply soft, flattering, diffused light with gentle highlights and natural shadows. Preserve identity and scene.",
  proShot: "Give the photo a professional camera-shot finish with natural dynamic range, refined color, realistic texture and controlled sharpening. Preserve identity and composition.",
  old2New: "Restore this old or degraded photograph: reduce scratches, noise and fading, recover plausible natural color when appropriate, and preserve the original person's identity, face shape, expression, age appearance, clothing and composition. Do not invent details.",
  hdReal: "Improve perceived photographic detail and clarity naturally without changing identity, geometry, scene content or composition. Avoid artificial textures and halos.",
  colorFix: "Correct white balance, exposure and color casts with realistic, faithful colors. Preserve skin tones and original scene.",
  nightFix: "Improve visibility in a dark or night photograph, lift useful shadows and reduce noise while preserving a believable night atmosphere and practical light sources.",
  longExposure: "Apply a tasteful still-image long-exposure aesthetic with smooth directional motion rendering only where visually plausible. Keep the main subject recognizable and avoid changing the scene.",
  motionBlur: "Apply controlled directional motion blur consistent with the existing composition while retaining the main subject's recognizable features.",
  goldenHour: "Create warm golden-hour illumination, gentle sunlit highlights and natural warm color grading without changing the scene or subject identity.",
  faceRestore: "Carefully restore facial clarity and fine detail while preserving the exact identity, facial geometry, expression, age appearance and natural skin texture. Do not beautify into a different person."
};

const commandAliases = new Map([
  ["glowUp", "glowUp"], ["beStudio", "beStudio"], ["softLight", "softLight"],
  ["proShot", "proShot"], ["old2New", "old2New"], ["hdReal", "hdReal"],
  ["colorFix", "colorFix"], ["nightFix", "nightFix"], ["longExposure", "longExposure"],
  ["motionBlur", "motionBlur"], ["goldenHour", "goldenHour"], ["faceRestore", "faceRestore"]
]);

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
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

function makePrompt(commands, analysis) {
  const selected = [...new Set(commands.map((item) => commandAliases.get(item)).filter(Boolean))];
  if (selected.length === 0) throw new Error("Desteklenen bir slash komutu gönderilmedi.");
  const instructions = selected.map((command) => COMMAND_GUIDANCE[command]);
  const context = analysis && typeof analysis === "object"
    ? `\nPhoto analysis (advisory): dimensions ${Number(analysis.image_width) || "unknown"}x${Number(analysis.image_height) || "unknown"}, detected faces ${Number(analysis.face_count) || 0}, portrait orientation ${Boolean(analysis.portrait_orientation)}, scene labels ${Array.isArray(analysis.scene_labels) ? analysis.scene_labels.slice(0, 5).join(", ") : "none"}.`
    : "";
  return [
    "Edit the supplied photograph. Treat the input as the source of truth.",
    ...instructions,
    "Global preservation rules: retain the same people and exact identity; do not change facial features, face shape, expression, age, hairstyle or clothing. Do not add or remove people, objects or text. Do not perform object removal, outfit changes, background removal or Ghibli/anime style transfer. Keep the original framing and composition unless the selected command explicitly requires a subtle photographic treatment.",
    "Make a coherent, photorealistic edit. Avoid excessive smoothing, plastic skin, oversharpening, halos, invented details and artificial HDR.",
    context
  ].join("\n\n");
}

async function handleProcess(req, res) {
  if (!OPENAI_API_KEY) return send(res, 503, { error: "Sunucuda OPENAI_API_KEY ayarlanmamış." });
  if (APP_ACCESS_TOKEN && req.headers["x-app-token"] !== APP_ACCESS_TOKEN) {
    return send(res, 401, { error: "Uygulama erişim anahtarı geçersiz." });
  }
  if (!rateLimit(req)) return send(res, 429, { error: "Çok fazla istek gönderildi. Bir dakika sonra tekrar deneyin." });

  let payload;
  try {
    payload = await readJSON(req);
  } catch (error) {
    return send(res, 400, { error: error.message || "Geçersiz JSON isteği." });
  }

  const encoded = payload.image_base64;
  if (typeof encoded !== "string" || encoded.length < 100) return send(res, 400, { error: "Fotoğraf verisi eksik." });
  const mime = payload.mime_type === "image/png" ? "image/png" : "image/jpeg";
  const imageBytes = Buffer.from(encoded, "base64");
  if (!imageBytes.length || imageBytes.length > 18 * 1024 * 1024) return send(res, 413, { error: "Fotoğraf 18 MB sınırını aşıyor." });

  const commands = Array.isArray(payload.commands) ? payload.commands : [];
  let prompt;
  try {
    prompt = makePrompt(commands, payload.analysis);
  } catch (error) {
    return send(res, 400, { error: error.message });
  }

  const commandSet = new Set(commands);
  const precisionCommands = ["faceRestore", "old2New", "proShot", "hdReal"];
  const usePrecision = precisionCommands.some((item) => commandSet.has(item));
  const model = usePrecision ? "gpt-image-2.6-sunburst" : "gpt-image-2.6-flare";

  const form = new FormData();
  form.append("model", model);
  form.append("prompt", prompt);
  form.append("quality", "high");
  form.append("output_format", "jpeg");
  form.append("image[]", new Blob([imageBytes], { type: mime }), mime === "image/png" ? "source.png" : "source.jpg");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 180_000);
  try {
    const response = await fetch("https://api.openai.com/v1/images/edits", {
      method: "POST",
      headers: { authorization: `Bearer ${OPENAI_API_KEY}` },
      body: form,
      signal: controller.signal
    });
    const data = await response.json();
    if (!response.ok) {
      const message = data?.error?.message || `OpenAI API isteği başarısız (HTTP ${response.status}).`;
      return send(res, response.status >= 500 ? 502 : response.status, { error: message });
    }
    const output = data?.data?.[0]?.b64_json;
    if (typeof output !== "string" || output.length < 100) return send(res, 502, { error: "OpenAI geçerli bir görsel döndürmedi." });
    return send(res, 200, { image_base64: output, model, revised_prompt: data.data[0].revised_prompt || null });
  } catch (error) {
    const message = error.name === "AbortError" ? "Görsel işleme zaman aşımına uğradı." : "OpenAI servisine bağlanılamadı.";
    return send(res, 502, { error: message });
  } finally {
    clearTimeout(timeout);
  }
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") return send(res, 200, { ok: true, service: "lut-studio-openai-image-backend" });
  if (req.method === "POST" && req.url === "/v1/process") {
    if (!req.headers["content-type"]?.includes("application/json")) return send(res, 415, { error: "Content-Type application/json gerekli." });
    return handleProcess(req, res);
  }
  return send(res, 404, { error: "Endpoint bulunamadı." });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`LUT Studio AI backend listening on port ${PORT}`);
});
