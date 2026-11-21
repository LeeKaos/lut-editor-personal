# LUT Studio OpenAI Image Backend

Private personal-use API that receives a photo and slash commands from the iOS app, sends one edit request to OpenAI's Images API, and returns the edited image.

## Deploy on Render

1. Push this branch and create a Render Blueprint from the repository. The root `render.yaml` points to `backend/` and uses its Dockerfile.
2. In the Render service environment settings, add:
   - `OPENAI_API_KEY`: your OpenAI API key (never put this in the iOS app or Git).
   - `APP_ACCESS_TOKEN`: a long random secret generated for this app, distinct from the OpenAI key.
3. Deploy and wait for the service to become healthy.
4. Test `https://YOUR-SERVICE.onrender.com/health`; expect `{"ok":true,...}`.
5. In the iOS AI panel, enable cloud processing and set:
   - Endpoint: `https://YOUR-SERVICE.onrender.com/v1/process`
   - App access token: the same `APP_ACCESS_TOKEN` value. The app stores it in iOS Keychain.

## API contract

The iOS app sends JSON:
- `image_base64`: JPEG image bytes encoded as Base64
- `mime_type`
- `commands`: supported command raw values, e.g. `["glowUp","proShot"]`
- `output_format`
- `analysis`: Vision-derived dimensions, face count, orientation and scene labels

The server calls `POST https://api.openai.com/v1/images/edits` using multipart form data and returns `{"image_base64":"..." }`.

## Model routing

- `gpt-image-2.6-flare`: faster everyday looks.
- `gpt-image-2.6-sunburst`: higher-precision detail and restoration requests such as FACEFIX, OLD2NEW, PROSHOT and HDREAL.

The model choice is server-side. The app never receives the OpenAI API key.

## Security and privacy

- Both environment secrets are mandatory. The app token is compared using Node's timing-safe comparison; the service is still intended for a single-user private deployment, not a public multi-user service.
- The server enforces an 18 MB decoded-image limit, a basic per-IP request limit, HTTPS at the hosting layer, and a 180-second upstream timeout.
- Do not log request bodies or image payloads. Configure host logs and retention appropriately.
- OpenAI processes the photo to fulfill the edit request. Review the applicable OpenAI API data controls and privacy terms before uploading personal images.
- Keep `OPENAI_API_KEY` and `APP_ACCESS_TOKEN` in the hosting provider's secret environment settings only.
- This is a personal-use starter backend. Before public distribution, add robust authentication, distributed rate limiting, abuse monitoring, request-size controls at the edge, and a formal privacy notice.

## Supported scope

The server deliberately excludes Ghibli/anime style transfer, object removal, outfit changes and background removal. BGSTUDIO means studio-style lighting while preserving the existing background and composition.
