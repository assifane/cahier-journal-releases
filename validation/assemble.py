import os, sys, re, json, math, base64, hashlib, pathlib, subprocess, urllib.request, urllib.error

REPO = "assifane/cahier-journal-releases"
API = "https://api.github.com/repos/" + REPO
PUB = "-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEASru1bm0Kp99Uns59gcWY7MMEAhL/6E7GDlANSGG2dco=\n-----END PUBLIC KEY-----\n"
CHUNK = 8 * 1024 * 1024

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def api(route, method="GET", body=None):
    headers = {"Authorization": "Bearer " + os.environ["GH_TOKEN"], "User-Agent": "RiyadaCahier-Release-Assembly", "Accept": "application/vnd.github+json"}
    if body is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(API + route, data=json.dumps(body).encode() if body is not None else None, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=120) as response:
        data = response.read()
        return json.loads(data) if data else None

def asset_bytes(asset):
    request = urllib.request.Request(API + "/releases/assets/" + str(asset["id"]), headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"], "User-Agent": "RiyadaCahier-Release-Assembly", "Accept": "application/octet-stream"})
    try:
        with urllib.request.build_opener(NoRedirect()).open(request, timeout=120) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        if error.code not in (301, 302, 303, 307, 308):
            raise
        url = error.headers["Location"]
        from urllib.parse import urlparse
        target = urlparse(url)
        if target.scheme != "https" or target.hostname not in ("release-assets.githubusercontent.com", "objects.githubusercontent.com"):
            raise ValueError("Untrusted asset redirect")
        # The GitHub credential is never forwarded to the CDN.
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "RiyadaCahier-Release-Assembly"}), timeout=120) as response:
            data = response.read()
    digest = "sha256:" + hashlib.sha256(data).hexdigest()
    if len(data) != asset["size"] or asset.get("digest") != digest:
        raise ValueError("Part digest mismatch")
    return data

def main():
    if os.environ.get("GITHUB_REPOSITORY") != REPO:
        raise ValueError("Repository mismatch")
    tag = os.environ["RELEASE_TAG"]
    if not re.fullmatch(r"(?:test-v|v)\d+\.\d+\.\d+", tag):
        raise ValueError("Invalid release tag")
    releases = api("/releases?per_page=100")
    release = next(r for r in releases if r["tag_name"] == tag)
    if not release["draft"]:
        raise ValueError("Assembly requires a draft")
    assets = {a["name"]: a for a in release["assets"]}
    envelope = json.loads(asset_bytes(assets["update.json"]))
    payload = base64.b64decode(envelope["payload"], validate=True)
    signature = base64.b64decode(envelope["signature"], validate=True)
    pathlib.Path("public.pem").write_text(PUB)
    pathlib.Path("payload.bin").write_bytes(payload)
    pathlib.Path("signature.bin").write_bytes(signature)
    subprocess.run(["openssl", "pkeyutl", "-verify", "-pubin", "-inkey", "public.pem", "-rawin", "-in", "payload.bin", "-sigfile", "signature.bin"], check=True, stdout=subprocess.DEVNULL)
    manifest = json.loads(payload)
    version = manifest["version"]
    test = tag.startswith("test-")
    name = ("CahierJournal-Test-Setup-" if test else "CahierJournal-Setup-") + version + ".exe"
    expected_url = "https://github.com/" + REPO + "/releases/download/" + tag + "/" + name
    if tag != ("test-v" if test else "v") + version or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Version mismatch")
    if manifest.get("channel", "stable") != ("test" if test else "stable") or manifest["product"] != ("riyadacahier-desktop-test" if test else "riyadacahier-desktop"):
        raise ValueError("Channel mismatch")
    if manifest["url"] != expected_url or manifest["platform"] != "win32-x64" or not 0 < manifest["size"] <= 1024**3:
        raise ValueError("Invalid manifest")
    sha512, sha256, size = hashlib.sha512(), hashlib.sha256(), 0
    parts = []
    with open(name, "wb") as output:
        for index in range(math.ceil(manifest["size"] / CHUNK)):
            part = assets["upload.part.%04d" % index]
            data = asset_bytes(part)
            if len(data) != min(CHUNK, manifest["size"] - size):
                raise ValueError("Part size mismatch")
            output.write(data)
            size += len(data)
            sha512.update(data)
            sha256.update(data)
            parts.append(part)
    if size != manifest["size"] or base64.b64encode(sha512.digest()).decode() != manifest["sha512"]:
        raise ValueError("Assembled installer mismatch")
    digest = "sha256:" + sha256.hexdigest()
    existing = assets.get(name)
    if existing:
        if existing.get("digest") != digest or existing["size"] != size:
            raise ValueError("Existing installer differs")
        final = existing
    else:
        url = "https://uploads.github.com/repos/" + REPO + "/releases/" + str(release["id"]) + "/assets?name=" + name
        request = urllib.request.Request(url, data=pathlib.Path(name).read_bytes(), method="POST", headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"], "User-Agent": "RiyadaCahier-Release-Assembly", "Content-Type": "application/octet-stream"})
        with urllib.request.urlopen(request, timeout=180) as response:
            final = json.load(response)
        if final.get("digest") != digest or final["size"] != size:
            raise ValueError("Uploaded installer mismatch")
    if not api("/releases/" + str(release["id"]))["draft"]:
        raise ValueError("Draft changed during assembly")
    for part in parts:
        api("/releases/assets/" + str(part["id"]), method="DELETE")
    print(json.dumps({"assembled": True, "tag": tag, "sha256": sha256.hexdigest(), "draft": True, "published": False}))

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("Assembly failed:", type(error).__name__)
        sys.exit(1)
