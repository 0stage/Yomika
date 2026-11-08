# Yomika

Browser-based Japanese EPUB reader (UI in Spanish). Click a word for a JMdict lookup, parse mode with Kuromoji,
furigana, vocabulary/grammar decks, per-book progress. EPUBs and covers stay in the browser (IndexedDB); only
progress and decks sync to the cloud. Originally written by the user's partner, now being prepared for hosting.

## Layout

| File | Purpose |
|---|---|
| `index.html` | The whole app (HTML, CSS, one large minified-style `<script>`). Also the file the local launcher serves. |
| `YomikaLocal.ps1`, `Iniciar-Yomika.bat` | Windows-only local launcher: serves the HTML on 127.0.0.1:1455 and proxies the ChatGPT-plan login/translation. Optional now. |
| `firestore.rules` | Per-user Firestore rules; requires a verified email. |
| `yomika-firebase-setup.md` | Firebase console setup steps, data layout. |
| `README.md`, `LEEME-Yomika.txt` | Identical, outdated ZIP-style instructions (still describe the ChatGPT login). |

## Decisions made

- **Hosting:** all on Cloudflare (Pages for the static page, a Worker later for the translation proxy and any cron).
  Target cost about $0/year, plus an optional custom domain.
- **Accounts and data:** Firebase Auth (email/password, verification required) + Firestore on the free Spark plan.
  Supabase was removed on this branch.
- **Translation:** AI translation is switched off (`AI_TRANSLATION_ENABLED=false` in `index.html`). It will be plugged
  back in as a later step through a provider-agnostic Cloudflare Worker (API key held server-side, checks the
  Firebase ID token, per-user limits, monthly spend cap).
- **ChatGPT-plan login cannot be hosted.** OpenAI documents it for local/open-source use; hosted use needs their
  interest form. Do not try to work around it. Keep it only in the local launcher.

## Branch state

Branch `fix/review-findings` (based on `main`, nothing pushed):

1. `50753dc` original code plus translation disabled.
2. `62fb12b` review fixes: `asISO` bug, keyboard shortcuts ignored inside inputs, no more rewriting the whole
   library on each page turn, visible warning when localStorage writes fail, EPUB sanitising (on* handlers,
   javascript: URLs, iframe/object/embed/form), quote-safe `esc()`, SRI hashes, object-URL leak, retry for
   Kuromoji, unsupported dropped files rejected, English UI strings translated.
3. `260b6cf` Supabase replaced by Firebase Auth + Firestore.

## Firestore data model

```
users/{uid}/progress/{sha256-of-epub}   { progress:{ch,fr,v,u}, updatedAt }
users/{uid}/decks/{deckId}              { name, created, updatedAt, chunkCount, wordCount, hashes }
users/{uid}/decks/{deckId}/chunks/{n}   { words:[...] }   (400 words per doc, 1 MiB doc limit)
```

All cloud access goes through the `cloudStore` adapter in `index.html`. Deck sync (`doSyncDecks`) tracks `cloud` and
`syncedAt` on local decks, fetches metadata first, merges conflicts by word union, and honours remote deletions.

## Status of testing

- Script syntax checked with Node. Deck sync and `cloudStore` pass 11 tests against an in-memory fake Firestore
  (scratch harness, not in the repo). EPUB sanitiser checked with jsdom.
- **Not yet verified in a browser or against a real Firebase project:** login/verification/reset flow, Firestore
  rules, reading flow after the progress-sync change, parse mode, the keyboard fix, image URL cleanup.

## Still to do

1. **Create the Firebase project** and fill `FIREBASE_CONFIG` at the top of the script in `index.html`
   (apiKey, authDomain, projectId, appId are empty). Until then the page is guest-only. Follow
   `yomika-firebase-setup.md`, including publishing `firestore.rules` and adding the hosted domain to Authorized
   domains.
2. **Test in a real browser**: guest mode, login on two devices, deck sync, progress sync, large EPUB library.
3. ~~Merge the two HTML files~~ Done: only `index.html` remains and the launcher serves it.
4. **Rewrite `README.md`** as a developer/deploy guide and delete or fix `LEEME-Yomika.txt`. Add `.gitattributes`
   for line endings (git warns about LF/CRLF) and a licence if wanted.
5. **Deploy to Cloudflare Pages** (static page, HTTPS, custom domain optional).
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
  `node -e "const s=require('fs').readFileSync('index.html','utf8');for(const x of s.matchAll(/<script>([\s\S]*?)<\/script>/g))new Function(x[1])"`
- Never commit API keys. Only the Firebase web config belongs in the page.
- Commit messages end with the Claude co-author trailer.
