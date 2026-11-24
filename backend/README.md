# LUT Studio Multi-Provider AI Backend

Private personal-use API for the iOS photo editor. Provider keys remain on the server; they are never embedded in the iOS app.

## Provider routing

1. **Photo analysis:** Gemini 2.5 Flash is tried first. Groq Qwen vision is the fallback. Analysis returns a Turkish summary, lighting/color/composition notes, and suggested slash commands.
2. **Image editing:** Hugging Face Inference Providers is tried first using the configurable image-to-image model. OpenAI Images API is an optional fallback only when `OPENAI_API_KEY` is configured.
3. **On-device fallback:** If the cloud backend cannot edit the image, the iOS app falls back to Core Image / installed Core ML models.

The analysis providers do not themselves edit the photo. Groq and Gemini are used for vision understanding and recommendations; the image-to-image model performs the edit.

## Render environment variables

Required:
- `APP_ACCESS_TOKEN`: long random secret used by the iOS app to authenticate with this private backend.

Optional provider keys:
- `GEMINI_API_KEY`: Google AI Studio API key. Used first for photo analysis with `gemini-2.5-flash`.
- `GROQ_API_KEY`: Groq API key. Used for vision analysis if Gemini is unavailable or rate-limited.
- `HF_TOKEN`: Hugging Face user access token with Inference Providers permission. Used for image-to-image editing.
- `HF_IMAGE_MODEL`: optional Hugging Face image-to-image model ID. Default: `black-forest-labs/FLUX.1-Kontext-dev`.
- `OPENAI_API_KEY`: optional paid fallback. Not required for the new provider stack.

Do not add secrets to GitHub files, the iOS app, or chat messages. Enter them only in Render's Environment settings. Do not add a payment method or enable paid usage if you want to stay within free quotas; set provider-side spending limits where available.

## Deploy

1. Use the existing Render Blueprint from the repository. The root `render.yaml` uses the Free web-service plan.
2. Add `APP_ACCESS_TOKEN` and whichever provider keys you have to the Render Environment settings.
3. Deploy and check `https://YOUR-SERVICE.onrender.com/health`.
4. In the iOS AI panel, turn on cloud processing and enter:
   - Endpoint: `https://YOUR-SERVICE.onrender.com/v1/process`
   - App access token: the exact `APP_ACCESS_TOKEN` value.

## Costs and limits

- Gemini API free-tier access is limited by model, account, and changing rate limits. Free-tier data may be used to improve Google's products; do not send sensitive photos unless you accept Google's applicable terms.
- Groq's Free tier has model-specific RPM/RPD/TPM limits. It is not unlimited.
- Hugging Face currently documents $0.10 monthly Inference Providers credits for Free accounts, subject to change. After those credits are exhausted, requests require purchased credits; this backend does not intentionally enable automatic paid fallback.
- OpenAI image editing is optional and usage-billed. Leave `OPENAI_API_KEY` unset to avoid this provider.
- Render Free web services sleep after inactivity; the first request may be delayed while the service wakes.

## API contract

The app can call `POST /v1/analyze` before editing to receive a Gemini/Groq photo summary, lighting/color/composition notes, and suggested commands. Editing calls `POST /v1/process` with `image_base64`, `mime_type`, `commands`, `output_format`, and local Vision analysis.

Successful response:
- `image_base64`: edited image
- `provider`: image-edit provider/model
- `analysis_provider`: Gemini or Groq, when available
- `analysis`: analysis object
- `recommendations`: Turkish recommendations
- `recommended_commands`: suggested slash commands

If image editing is not configured or fails, the API returns HTTP 503. The iOS app then uses its existing local fallback.

## Security and privacy

- Require both the server-side app token and provider-specific keys. Store all secrets only in Render environment settings.
- Cloud mode sends the selected photo to the configured analysis and image-edit providers. Turn cloud mode off to keep the photo on the device.
- The service enforces an 18 MB decoded-image limit, a basic per-IP request limit, and upstream timeouts.
- This is a personal-use backend, not a public multi-user service. Add stronger authentication and distributed rate limiting before public distribution.

## Supported scope

The server deliberately excludes Ghibli/anime style transfer, object removal, outfit changes, and background removal. BGSTUDIO means studio-style lighting while preserving the existing background and composition.
