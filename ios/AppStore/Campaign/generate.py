#!/usr/bin/env python3
"""Generate one campaign slide with Nano Banana Pro. Key comes from GEMINI_API_KEY, never from a file here.
Usage: generate.py <prompt.txt> <out.png> [reference.png ...]"""
import base64, json, os, sys, urllib.request
MODEL = "gemini-3-pro-image"
prompt, out, refs = open(sys.argv[1]).read(), sys.argv[2], sys.argv[3:]
parts = [{"inlineData": {"mimeType": "image/png", "data": base64.b64encode(open(r, "rb").read()).decode()}} for r in refs]
parts.append({"text": prompt})
body = {"contents": [{"parts": parts}],
        "generationConfig": {"responseModalities": ["IMAGE"], "imageConfig": {"aspectRatio": "9:16", "imageSize": "2K"}}}
req = urllib.request.Request(f"https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent",
                             data=json.dumps(body).encode(),
                             headers={"x-goog-api-key": os.environ["GEMINI_API_KEY"], "Content-Type": "application/json"})
try:
    res = json.load(urllib.request.urlopen(req, timeout=300))
except urllib.error.HTTPError as e:
    sys.exit(f"HTTP {e.code}: {e.read().decode()[:600]}")
for part in res.get("candidates", [{}])[0].get("content", {}).get("parts", []):
    if "inlineData" in part:
        open(out, "wb").write(base64.b64decode(part["inlineData"]["data"]))
        print(out, part["inlineData"].get("mimeType"), res.get("usageMetadata", {}).get("totalTokenCount"))
        break
else:
    sys.exit("No image returned: " + json.dumps(res)[:600])
