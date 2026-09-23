#!/usr/bin/env python3
"""Convert a small, deterministic subset of uBO filter syntax to WebKit JSON.
The app performs a second conversion with SafariConverterLib for its fallback path.
"""
import argparse, hashlib, json, re, urllib.request
from pathlib import Path

SOURCES = {
    "ubo-assets": "https://raw.githubusercontent.com/uBlockOrigin/uAssets/master/filters/filters.txt",
    "easylist": "https://easylist.to/easylist/easylist.txt",
    "easyprivacy": "https://easylist.to/easylist/easyprivacy.txt",
    "peter-lowe": "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=adblock&showintro=0&mimetype=plaintext",
}
MAX_RULES = 149_000

def convert_line(line):
    line = line.strip()
    if not line or line.startswith(("!", "[")):
        return None
    if "##+" in line:
        return None
    if "##" in line or "#@#" in line:
        selector = line.split("#@#", 1)[1] if "#@#" in line else line.split("##", 1)[1]
        domain = line.split("#@#", 1)[0] if "#@#" in line else line.split("##", 1)[0]
        if "#@#" in line:
            return None
        domains = [d for d in domain.split(",") if d and not d.startswith("~")]
        trigger = {"url-filter": ".*"}
        if domains:
            trigger["if-domain"] = [f"*.{d}" for d in domains]
        return {"trigger": trigger, "action": {"type": "css-display-none", "selector": selector}}
    if line.startswith("@@") or line.startswith("/") or line.startswith("##+"):
        return None
    if line.startswith("||"):
        host = re.split(r"[/$^]", line[2:])[0]
        if not host or "*" in host:
            return None
        escaped = re.escape(host)
        return {"trigger": {"url-filter": rf"^https?://([^/]+\.)?{escaped}(/|$)", "load-type": ["third-party"]}, "action": {"type": "block"}}
    if line.startswith("|") and line.endswith("|"):
        value = re.escape(line.strip("|"))
        return {"trigger": {"url-filter": value}, "action": {"type": "block"}}
    return None

def convert(text):
    rules = []
    dropped = 0
    for line in text.splitlines():
        rule = convert_line(line)
        if rule is None and line.strip() and not line.lstrip().startswith(("!", "[")):
            dropped += 1
        elif rule:
            rules.append(rule)
    shards = [rules[i:i+MAX_RULES] for i in range(0, len(rules), MAX_RULES)] or [[]]
    return shards, dropped

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output", required=True)
    p.add_argument("--fixture", action="append", metavar="ID=PATH")
    args = p.parse_args()
    out = Path(args.output); out.mkdir(parents=True, exist_ok=True)
    fixtures = dict(item.split("=", 1) for item in (args.fixture or []))
    manifest = {"schemaVersion": 1, "generatedAt": __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(), "converter": "ora-focused-adblock-v1", "lists": []}
    for ident, url in SOURCES.items():
        if ident in fixtures:
            raw = Path(fixtures[ident]).read_bytes()
            source_version = "fixture"
        else:
            with urllib.request.urlopen(url, timeout=60) as response:
                raw = response.read()
            source_version = response.headers.get("last-modified") or response.headers.get("etag") or "unknown"
        text = raw.decode("utf-8", "replace")
        shards, dropped = convert(text)
        files = []
        for index, shard in enumerate(shards):
            name = f"{ident}-{index}.json"
            (out / name).write_text(json.dumps(shard, separators=(",", ":"), sort_keys=True))
            files.append({"path": name, "sha256": hashlib.sha256((out / name).read_bytes()).hexdigest(), "ruleCount": len(shard)})
        manifest["lists"].append({"id": ident, "sourceURL": url, "sourceVersion": source_version, "droppedRuleCount": dropped, "shards": files})
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")

if __name__ == "__main__": main()
