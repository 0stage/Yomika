# Yomika

Browser-based Japanese EPUB reader (UI in Spanish). Click a word for a JMdict lookup, parse mode with Kuromoji,
furigana, vocabulary/grammar decks, per-book progress. EPUBs and covers stay in the browser (IndexedDB); only
progress and decks sync to the cloud. Originally written by the user's partner, now being prepared for hosting.

## Layout

| File | Purpose |
|---|---|
| `public/index.html` | The whole app (HTML, CSS, one large minified-style `<script>`). Everything under `public/` is what gets published; the local launcher serves it too. |
| `wrangler.jsonc` | Cloudflare Workers static-assets config: publishes only `./public` (keeps docs, scripts and rules out of the site). |
| `YomikaLocal.ps1`, `Iniciar-Yomika.bat` | Windows-only local launcher: serves the HTML on 127.0.0.1:1455 and proxies the ChatGPT-plan login/translation. Optional now. |
| `firestore.rules` | Per-user Firestore rules; requires a verified email. |
| `yomika-firebase-setup.md` | Firebase console setup steps, data layout. |
| `README.md`, `LEEME-Yomika.txt` | Identical, outdated ZIP-style instructions (still describe the ChatGPT login). |

## Decisions made

- **Hosting:** all on Cloudflare (Pages for the static page, a Worker later for the translation proxy and any cron).
  Target cost about $0/year, plus an optional custom domain.
- **Accounts and data:** Firebase Auth (email/password, verification required) + Firestore on the free Spark plan.
  Supabase was removed.
- **Translation:** AI translation is switched off (`AI_TRANSLATION_ENABLED=false` in `public/index.html`). It will be plugged
  back in as a later step through a provider-agnostic Cloudflare Worker (API key held server-side, checks the
  Firebase ID token, per-user limits, monthly spend cap).
- **ChatGPT-plan login cannot be hosted.** OpenAI documents it for local/open-source use; hosted use needs their
  interest form. Do not try to work around it. Keep it only in the local launcher.

## Branch state

- `main` has everything up to PR #1 (review fixes, Firebase migration, single HTML file, Firebase config).
- Branch `deploy/cloudflare` (local, not pushed yet): moves `index.html` into `public/`, adds `wrangler.jsonc`, points the
  launcher at `public\index.html`. Needed because Cloudflare's current flow runs `npx wrangler deploy`.
  `wrangler deploy --dry-run` could not be run locally (Wrangler needs Node 22, machine has 20.5), so the config is
  unvalidated until the first Cloudflare build.

## Firestore data model

```
users/{uid}/progress/{sha256-of-epub}   { progress:{ch,fr,v,u}, updatedAt }
users/{uid}/decks/{deckId}              { name, created, updatedAt, chunkCount, wordCount, hashes }
users/{uid}/decks/{deckId}/chunks/{n}   { words:[...] }   (400 words per doc, 1 MiB doc limit)
```

All cloud access goes through the `cloudStore` adapter in `public/index.html`. Deck sync (`doSyncDecks`) tracks `cloud` and
`syncedAt` on local decks, fetches metadata first, merges conflicts by word union, and honours remote deletions.

## Status of testing

- Script syntax checked with Node. Deck sync and `cloudStore` pass 11 tests against an in-memory fake Firestore
  (scratch harness, not in the repo). EPUB sanitiser checked with jsdom.
- **Verified manually (localhost, real Firebase project yomika-6decc):** email/password sign-up with email
  confirmation, sign-in, Firestore rules published, reading progress synced, saved words/decks synced and visible in a
  second browser. Firebase Auth (Email/Password) and Firestore (production mode, default database) are set up.
- **Still unverified:** password reset, guest-to-account import, sign-out/in edge cases, parse mode, the keyboard fix,
  image URL cleanup, large libraries.
- Dictionary: load `jmdict-eng-*.json.zip` (or `jmdict-all`) from jmdict-simplified. A non-English file such as
  `jmdict-spa` gives "no English entries found" because the app only keeps English glosses.
- Local testing: `python -m http.server 8000 --bind 127.0.0.1 --directory public`, open `http://localhost:8000` (not
  127.0.0.1). On Windows two servers can share a port, so stop old ones before restarting.

## Still to do

1. ~~Create the Firebase project~~ Done (config is in `public/index.html`). Still add the hosted domain to Firebase Authorized
   domains after deploying.
2. **Finish browser testing**: password reset, guest import, parse mode, large EPUB library.
3. ~~Merge the two HTML files~~ Done: a single `public/index.html` remains and the launcher serves it.
4. **Rewrite `README.md`** as a developer/deploy guide and delete or fix `LEEME-Yomika.txt`. Add `.gitattributes`
   for line endings (git warns about LF/CRLF) and a licence if wanted.
5. **Deploy to Cloudflare** (Workers static assets via `wrangler.jsonc`, HTTPS, custom domain optional). Cloudflare settings: build command empty, deploy command `npx wrangler deploy`, production branch `main`. Then add the live domain to Firebase Authorized domains.
6. **Translation step**: build the Cloudflare Worker. Verify the Firebase ID token against Google's public keys,
   adapter per provider (OpenAI, Anthropic, Gemini, Workers AI, ...), per-user daily limits, prompt-length cap, set
   a spend limit at the provider. In the page, replace `callOpenAI` and the disabled account/consent markup with a
   call to the Worker. Test the Japanese grammar JSON output on sample sentences before choosing a provider.
   Optionally apply to OpenAI's interest form if hosted "Sign in with ChatGPT" is wanted.
7. **Dictionary**: JMdict is currently loaded by the user. Options: host it and cache in IndexedDB (mind the CC BY-SA
   attribution), or add a second dictionary behind a small `lookup()` interface. Read how tightly `look()` is
   coupled to JMdict's data shape first.
8. **Open questions / known leftovers**
   - `look()` has hard-coded cases for 今日は and はわたし, and the grammar rules include もっともっと; they look
     tuned to one book. Left untouched on purpose.
   - Vocabulary index deck can grow until localStorage (about 5 MB) fills; users now get a warning, but decks should
     eventually move to IndexedDB.
   - After sign-out, that account's local EPUBs and decks stay in the browser (shared-computer privacy).
   - No CSP (the app relies on inline script and handlers).
   - Public sign-up is open; consider blocking new sign-ups once the needed accounts exist.
   - Old Supabase data is not migrated.
   - Trace how sync handles two devices editing at once with the user's real data.

## Working notes

- The script is dense; edit it with exact-string replacements and re-check syntax:
  `node -e "const s=require('fs').readFileSync('public/index.html','utf8');for(const x of s.matchAll(/<script>([\s\S]*?)<\/script>/g))new Function(x[1])"`
- Never commit API keys. Only the Firebase web config belongs in the page.
- Do not add a Claude co-author trailer to commit messages (the user asked for this).
