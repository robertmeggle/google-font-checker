# google-font-checker
Small bash script to check websites against used google fonts (GDPR fast check)


# check-google-fonts.sh

A **pure Bash** script to detect **Google Fonts usage** (both `fonts.googleapis.com` and `fonts.gstatic.com`)  
on any public website — even when the font URLs are **hidden, escaped, or dynamically embedded** in JavaScript or CSS.

---

## 🔍 Features

=> Detects **Google Fonts CSS endpoints** (`fonts.googleapis.com/css2?...`)  
=> Extracts **actual font files** (`fonts.gstatic.com/*.woff2`, `.woff`, `.ttf`, `.otf`)  
=> Decodes obfuscated URLs (`\u002F`, `\/`, `%2F`, HTML entities like `&colon;`)  
=> Follows nested CSS `@import` chains (up to 4 levels deep)  
=> Supports **scheme-relative URLs** (`//fonts.gstatic.com/...`)  
=> No external dependencies — runs with standard Linux tools (`bash`, `curl`, `awk`, `grep`, `sed`, `sort`)  
=> Works even if Google Fonts links are **hidden inside inline scripts** or **JSON blobs**  
=> Outputs a simple **YES/NO** summary and lists all discovered resources

---

## Requirements

- **Linux / macOS** with:
  - `bash` ≥ 4
  - `curl`
  - `awk`, `grep`, `sed`, `sort`, `tr`
- Internet access to fetch external resources

> No Python, Node, or browser automation required.

---

## Usage

Clone or copy this repository and make the script executable:

```bash
chmod +x check-google-fonts.sh <domain> [-v]
```

Then run:
```bash
bash check-google-fonts.sh https://example.com
```

Optionally, use -v for verbose mode (shows recursion steps):
```bash
bash check-google-fonts.sh https://example.com -v
```

# Example output

~~~
./google-font.checker.sh https://example.com -v
[*] Fetching HTML from https://example.com
[*] CSS recursion level 1, 5 URL(s)
[*] Scanning external JS for hidden references
===========================================
Destination: https://example.com
===========================================

*** Google Fonts stylesheets found (fonts.googleapis.com): ***
  https://fonts.googleapis.com/css2?family=Barlow:wght@400;500;600;700;800;900&display=swap

*** Found font files (fonts.gstatic.com, *.woff/woff2/ttf/otf): ***
  https://fonts.gstatic.com/s/barlow/v13/7cHpv4kjgoGqM7EPCw.ttf
  https://fonts.gstatic.com/s/barlow/v13/7cHpv4kjgoGqM7EPCw.ttfhttps://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3_-gc4A.ttfhttps://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E30-8c4A.ttfhttps://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3t-4c4A.ttfhttps://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3q-0c4A.ttfhttps://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3j-wc4A.ttf
  https://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E30-8c4A.ttf
  https://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3_-gc4A.ttf
  https://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3j-wc4A.ttf
  https://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3q-0c4A.ttf
  https://fonts.gstatic.com/s/barlow/v13/7cHqv4kjgoGqM7E3t-4c4A.ttf

GOOGLE_FONTS_PRESENT=YES

~~~

or

~~~
./google-font.checker.sh https://example.com -v  
[*] Fetching HTML from https://example.com
[*] CSS recursion level 1, 3 URL(s)
[*] Scanning external JS for hidden references
===========================================
Destination: https://example.com
===========================================

*** Google Fonts stylesheets found (fonts.googleapis.com): ***
  (none)

*** Found font files (fonts.gstatic.com, *.woff/woff2/ttf/otf): ***
  (none)

GOOGLE_FONTS_PRESENT=NO
~~~