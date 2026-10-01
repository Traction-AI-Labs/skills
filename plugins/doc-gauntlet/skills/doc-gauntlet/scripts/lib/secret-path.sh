#!/usr/bin/env bash

is_known_secret_path() {
  local file="$1"
  local basename="${file##*/}"
  if [[ "$file" =~ (^|/)\.env[^/]*$ && "$basename" != ".env.example" ]]; then
    return 0
  fi
  [[ "$file" =~ (^|/)(secrets?|credentials?)(/|$) || "$file" =~ (^|/)id_(rsa|dsa|ecdsa|ed25519)$ || "$file" =~ (^|/)(service[-_]?account[^/]*|private[-_]?key[^/]*|credentials?[^/]*|secrets?[^/]*)\.(json|ya?ml|toml|ini)$ || "$file" =~ \.(pem|key|crt|cer|p12|pfx|jks|keystore)$ ]]
}

sanitize_diagnostic() {
  python3 -c '
import re, sys
text = sys.stdin.read()
text = re.sub(r"(?im)((?:authorization|proxy-authorization)\s*:)[^\r\n]*", r"\1 <redacted>", text)
text = re.sub(r"(?im)(((?:set-)?cookie)\s*:).*$", r"\1 <redacted>", text)
text = re.sub(r"(?i)((?:api[_-]?key|token|password|passwd|client[_-]?secret|secret)[\"\x27]?\s*[:=]\s*)(?:\"[^\"]*\"|\x27[^\x27]*\x27|[^\s,;]+)", r"\1<redacted>", text)
text = re.sub(r"(?i)(?:sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9_]{8,}|xox[baprs]-[A-Za-z0-9-]{8,})", "<redacted>", text)
lines = text.splitlines()
if len(lines) > 40:
    lines = lines[:8] + ["<diagnostic truncated>"] + lines[-24:]
text = "\n".join(lines)
if len(text) > 8000:
    text = text[:4000] + "\n<diagnostic truncated>\n" + text[-3000:]
sys.stdout.write(text)
'
}
