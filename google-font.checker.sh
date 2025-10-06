#!/usr/bin/env bash
# Usage: bash check-google-fonts.sh https://example.com [-v]
# Pure Bash/awk/sed/grep version that:
# - fetches HTML with a realistic UA
# - decodes masked content (\uXXXX, \/ , %XX, basic HTML entities)
# - collects *all* stylesheet URLs (incl. css2 endpoints without .css)
# - explicitly fetches any fonts.googleapis.com CSS it finds anywhere (HTML/CSS/JS)
# - follows @import chains (limited depth) and extracts concrete fonts.gstatic.com *.woff/woff2/ttf/otf files
# - also handles scheme-relative URLs like //fonts.gstatic.com/...
# - prints a clear YES/NO summary
#
# Requires: bash, curl, grep, sed, awk, tr, sort.

set -u  # intentionally no -e/-o pipefail to avoid silent aborts on edge pipes

URL="${1:-}"
VERBOSE="${2:-}"

if [[ -z "$URL" || "$URL" == "-h" || "$URL" == "--help" ]]; then
  echo "Usage: bash $0 <url> [-v]"
  exit 0
fi

log() { [[ "${VERBOSE:-}" == "-v" ]] && echo "[*] $*" >&2; }

# --- realistic UA and language to avoid "bot-minimal" responses ---
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari"
ALANG="de-DE,de;q=0.9,en;q=0.8"
fetch() { curl -sL --compressed -A "$UA" -H "accept-language: $ALANG" "$1" 2>/dev/null || true; }

# --- tiny decoder: handles \/  \uXXXX  %XX  &#x..;  &#..;  and a few named entities ---
decode_all() {
  # Reads STDIN, writes decoded text to STDOUT using only awk/sed/grep.
  awk '
  BEGIN { ORS=""; }
  { s = s $0 "\n"; }
  END {
    # 1) JS escaped slashes
    gsub(/\\\//, "/", s);
    # 2) \uXXXX -> char (covers ASCII punctuation relevant to URLs)
    while (match(s, /\\u[0-9A-Fa-f]{4}/)) {
      hex = substr(s, RSTART+2, 4);
      c = sprintf("%c", strtonum("0x" hex));
      s = substr(s,1,RSTART-1) c substr(s,RSTART+6);
    }
    # 3) URL-encoding %XX
    while (match(s, /%[0-9A-Fa-f]{2}/)) {
      hex = substr(s, RSTART+1, 2);
      c = sprintf("%c", strtonum("0x" hex));
      s = substr(s,1,RSTART-1) c substr(s,RSTART+3);
    }
    # 4) HTML entities (hex then decimal)
    while (match(s, /&#x[0-9A-Fa-f]+;/)) {
      hx = substr(s, RSTART+3, RLENGTH-4);
      c  = sprintf("%c", strtonum("0x" hx));
      s  = substr(s,1,RSTART-1) c substr(s,RSTART+RLENGTH);
    }
    while (match(s, /&#[0-9]+;/)) {
      dv = substr(s, RSTART+2, RLENGTH-3) + 0;
      c  = sprintf("%c", dv);
      s  = substr(s,1,RSTART-1) c substr(s,RSTART+RLENGTH);
    }
    # 5) Common named entities we may encounter inside HTML/JS
    gsub(/&amp;/,  "&", s);
    gsub(/&quot;/, "\"", s);
    gsub(/&lt;/,   "<", s);
    gsub(/&gt;/,   ">", s);
    gsub(/&colon;/, ":", s);
    gsub(/&sol;/,   "/", s);
    print s;
  }'
}

# --- basic origin parsing for relative URL normalization ---
proto="$(printf '%s' "$URL" | awk -F/ '{print $1}')"
host="$(printf '%s' "$URL" | awk -F/ '{print $3}')"
ORIGIN="${proto}//${host}"

norm_url() {
  # Normalize CSS url(...) and plain relative/absolute links into absolute URLs
  local u="$1"
  u="${u#url(}"; u="${u%)}"
  u="${u%\"}"; u="${u#\"}"; u="${u%\'}"; u="${u#\'}"
  u="$(printf '%s' "$u" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$u" ]] && return 1
  case "$u" in
    http://*|https://*) printf '%s\n' "$u" ;;
    //*)                 printf 'https:%s\n' "$u" ;;         # scheme-relative -> https
    /*)                  printf '%s%s\n' "$ORIGIN" "$u" ;;
    *)                   printf '%s/%s\n' "$ORIGIN" "$u" ;;
  esac
}

# --- 1) Fetch and decode the HTML ---
log "Fetching HTML from $URL"
RAW_HTML="$(fetch "$URL")"
if [[ -z "$RAW_HTML" ]]; then
  echo "Destination: $URL"
  echo "HNote: Empty response (possibly bot block/JS app)..."
  echo "GOOGLE_FONTS_PRESENT=UNKNOWN"
  exit 0
fi
HTML="$(printf '%s' "$RAW_HTML" | tr -d '\n' | decode_all)"

# --- 2) Collect initial stylesheet links (incl. css2 without .css) and inline @import absolute targets ---
mapfile -t CSS_LINKS < <(printf '%s' "$HTML" \
  | grep -Eoi '<link[^>]+rel=["'\'']?stylesheet["'\'']?[^>]*>' || true \
  | grep -Eoi 'href=["'\''][^"'\'' >]+' || true \
  | sed -E 's/^href=["'\'']([^"'\'' >]+).*/\1/' || true)

mapfile -t INLINE_IMPORTS_ABS < <(printf '%s' "$HTML" \
  | grep -Eoi '@import +url\(([^)]+)\)|@import +"[^"]+"|@import +'\''[^'\'']+'\''' || true \
  | grep -Eo 'https?://[^)"'\'';]+' || true)

# --- 3) Also collect *any* fonts.googleapis.com occurrences anywhere (HTML/JS text) ---
#     This is the crucial bit: even if no <link rel="stylesheet"> exists,
#     we will fetch those CSS endpoints explicitly because they contain the *.woff2 links.
mapfile -t GF_CSS_ANY < <(printf '%s' "$HTML" \
  | grep -Eio 'https?://fonts\.googleapis\.com/[^"'\'' )]+' \
  | sort -u || true)

# --- 4) Collect external JS (sometimes CSS is injected via JS and already visible as string) ---
mapfile -t JS_LINKS < <(printf '%s' "$HTML" \
  | grep -Eoi '<script[^>]+src=["'\''][^"'\'' >]+' || true \
  | sed -E 's/.*src=["'\'']([^"'\'' >]+).*/\1/' || true)

# --- Set up queues and result arrays ---
declare -A VIS=()
declare -a QUEUE=()
declare -a GOOGLE_CSS=()   # fonts.googleapis.com CSS endpoints we end up fetching
declare -a FONT_FILES=()   # concrete fonts.gstatic.com *.woff/woff2/ttf/otf

# Seed the CSS queue with <link rel=stylesheet> and inline absolute @imports
for u in "${CSS_LINKS[@]}" "${INLINE_IMPORTS_ABS[@]}"; do
  nu="$(norm_url "$u" 2>/dev/null || true)"
  [[ -n "${nu:-}" ]] && QUEUE+=("$nu")
done
# Seed queue with any Google Fonts CSS references found *anywhere*
for u in "${GF_CSS_ANY[@]}"; do
  nu="$(norm_url "$u" 2>/dev/null || true)"
  [[ -n "${nu:-}" ]] && QUEUE+=("$nu")
done

# --- Temporary file to collect decoded CSS bodies for secondary scanning ---
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

MAX_DEPTH=4
depth=0

# --- 5) Recursively fetch CSS, decode, gather @imports, extract font file URLs ---
while [[ "${#QUEUE[@]}" -gt 0 && $depth -lt $MAX_DEPTH ]]; do
  ((depth++))
  log "CSS recursion level $depth, ${#QUEUE[@]} URL(s)"
  next=()
  for css_url in "${QUEUE[@]}"; do
    [[ -n "${VIS[$css_url]:-}" ]] && continue
    VIS["$css_url"]=1

    c_raw="$(fetch "$css_url")"
    [[ -z "$c_raw" ]] && continue

    # decode CSS body (handles escaped/encoded URLs inside CSS text)
    c="$(printf '%s' "$c_raw" | tr -d '\n' | decode_all)"

    [[ "$css_url" =~ fonts\.googleapis\.com ]] && GOOGLE_CSS+=("$css_url")

    # keep for bulk scanning later (optional)
    printf '%s\n' "$c" >> "$TMP"

    # Extract further @import targets (relative or absolute) from this CSS
    while IFS= read -r imp; do
      nu="$(norm_url "$imp" 2>/dev/null || true)"
      [[ -n "${nu:-}" ]] && next+=("$nu")
    done < <(printf '%s' "$c" \
      | grep -Eoi '@import +url\(([^)]+)\)|@import +"[^"]+"|@import +'\''[^'\'']+'\''' || true \
      | grep -Eo '(url\([^)]*\)|"(.*?)"|'\''(.*?)'\'')' || true \
      | sed -E 's/url\(|\)|"|'\''//g' || true)

    # Extract concrete font file URLs from this CSS:
    #  - explicit scheme: https?://fonts.gstatic.com/...
    #  - scheme-relative: //fonts.gstatic.com/...
    while IFS= read -r f; do
      # Normalize scheme-relative to https:// before pushing
      if [[ "$f" =~ ^//fonts\.gstatic\.com/ ]]; then
        f="https:${f}"
      fi
      FONT_FILES+=("$f")
    done < <(printf '%s' "$c" \
      | grep -Eo '(https?:)?//fonts\.gstatic\.com/[^)"'\'' ]+\.(woff2?|ttf|otf)' || true)
  done
  QUEUE=("${next[@]}")
done

# --- 6) Additionally: fetch external JS, decode, and scan for hidden references (belt & suspenders) ---
if [[ "${#JS_LINKS[@]}" -gt 0 ]]; then
  log "Scanning external JS for hidden references"
fi
EXTRA=$({
  printf '%s\n' "$HTML"
  for j in "${JS_LINKS[@]}"; do
    nu="$(norm_url "$j" 2>/dev/null || true)"; [[ -n "${nu:-}" ]] && fetch "$nu"
  done
} \
| tr -d '\n' \
| decode_all \
| grep -Eio '(https?:)?//fonts\.(googleapis|gstatic)\.com/[^"'\'' )]+' \
| sort -u || true)

# Merge & dedupe
GOOGLE_CSS=( $( { printf '%s\n' "${GOOGLE_CSS[@]}"; printf '%s\n' "$EXTRA"; } \
  | grep -Ei '(https?:)?//fonts\.googleapis\.com/' | sed -E 's#^//#https://#' | sort -u) )

FONT_FILES=( $( { printf '%s\n' "${FONT_FILES[@]}"; printf '%s\n' "$EXTRA"; cat "$TMP"; } \
  | tr -d '\n' | decode_all \
  | grep -Eio '(https?:)?//fonts\.gstatic\.com/[^"'\'' )]+\.(woff2?|ttf|otf)' \
  | sed -E 's#^//#https://#' \
  | sort -u) )

# --- 7) Output ---
echo "==========================================="
echo "Destination: $URL"
echo "==========================================="

echo
echo "*** Google Fonts stylesheets found (fonts.googleapis.com): ***"
if [[ "${#GOOGLE_CSS[@]}" -gt 0 ]]; then
  printf '  %s\n' "${GOOGLE_CSS[@]}"
else
  echo "  (none)"
fi

echo
echo "*** Found font files (fonts.gstatic.com, *.woff/woff2/ttf/otf): ***"
if [[ "${#FONT_FILES[@]}" -gt 0 ]]; then
  printf '  %s\n' "${FONT_FILES[@]}"
else
  echo "  (none)"
fi

echo
if [[ "${#GOOGLE_CSS[@]}" -gt 0 || "${#FONT_FILES[@]}" -gt 0 ]]; then
  echo "GOOGLE_FONTS_PRESENT=YES"
else
  echo "GOOGLE_FONTS_PRESENT=NO"
fi
