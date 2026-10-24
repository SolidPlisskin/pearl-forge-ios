# Pearl Forge — Windows build guide

Everything needed to build a Windows version of Pearl Forge as a single portable `.exe` that runs from a flash drive. It was written from the working iPhone app (Swift/SwiftUI, latest commit on `main` in the private GitHub repo `SolidPlisskin/pearl-forge-ios`, October 2026). The iPhone source travels with this guide in `Pearl Forge source/`; the appendices quote the parts that must carry over word for word.

**No API keys are in this guide or the source.** The app asks for them on first run and stores them encrypted.

## How to use this guide

On the Windows PC:

1. Make an empty folder, for example `C:\Projects\PearlForgeWindows`, and unzip this kit into it.
2. Open Claude Code in that folder (desktop app or terminal) and paste:

   > Build a Windows version of my app Pearl Forge. Read `PEARL_FORGE_WINDOWS_BUILD_GUIDE.md` first; the iPhone app's source is in `Pearl Forge source/` for reference. Follow the guide's stack, data format and prompts exactly (prompts word for word). Build it screen by screen like the plan in section 12, show me each milestone, and finish with a single portable `.exe` I can run from a flash drive.

3. Build it a milestone at a time and try each one, as the iPhone app was built.

---

## 1. What Pearl Forge is

You record a rough spoken thought. Pearl Forge transcribes it faithfully, polishes the wording **without changing the meaning**, and speaks the result back **in your own cloned voice**. The original recording and every polished version ("pearl") are kept.

Features to carry over:

| Area | What it does |
|---|---|
| **Create** | Record (or import an audio file) **or** type text. Choose how much polishing: Clean, Tighten or Summarize for recordings; As written, Clean, Tighten or Summarize for typed text. Choose **Speak in** (29 languages) to translate. Then transcribe (ElevenLabs Scribe) → polish/translate (chosen AI) → save → speak (ElevenLabs, your voice). Edit the text and regenerate the audio. Share the audio. |
| **Lectures** | Say or type "Give a lecture on …". Before anything is spent, a card shows the topic, length (3/5/10/15/20 min), which Claude researches it (Sonnet 5.5 or Opus 5.5), language, and an **estimated cost** split into Claude and ElevenLabs, plus the ElevenLabs credits left this month. Claude researches PubMed and the web, writes a talk, and it's spoken in your voice. Afterwards: the text, its verified sources, and **what it actually cost**. |
| **History** | Every recording, newest first: search, favourites (swipe), delete. A **Topics** view groups recordings by topic, with **Play all in order** (oldest first, newest pearl of each). |
| **Recording detail** | Title, date, gist, topics (auto-sort or edit by hand), the untouched original (play it, read the transcript), every pearl, **Forge a new pearl** (any mode, any AI, any language, plus a free-text request), and **Find reading**. Lectures show "What you asked for", the lecture, its sources, and its cost; no "Forge a new pearl". |
| **Pearl** | Read/edit the text, regenerate the audio, play, share (audio and text), delete. Shows mode, the request, which AI and model wrote it, and when. |
| **Reading** | Every saved reference (research papers, articles, essays, blog posts, books), filterable by kind and topic; opens in the browser. |
| **AI** | Which service polishes by default: Claude, ChatGPT (OpenAI), Gemini (Google) or OpenRouter. Each has its own key and model picker (model list loaded from the service, searchable, plus "type a model id"). A separate **Finding reading** model (Claude only, default Sonnet 5.5). |
| **Settings** | ElevenLabs key, voice picker (your own cloned voices listed first), and where recordings are stored. |

## 2. The Windows stack (recommended)

**C# / .NET 10 (LTS) with WPF, published as one self-contained file.** One `.exe`, no installer, no .NET install needed on the PC, native Windows look, runs from a flash drive.

| Need | Use |
|---|---|
| UI | WPF, MVVM. Five sections in a left navigation bar or tabs: Create, History, Reading, AI, Settings. Follow Windows light/dark mode. |
| HTTP | `HttpClient` with a 900-second timeout (long recordings and lectures take minutes). |
| JSON | `System.Text.Json`. Keep exactly the field names in section 7 (snake_case where shown) so files stay compatible with the iPhone app. |
| Recording | NAudio `WaveInEvent`, 44.1 kHz mono, then encode to AAC `.m4a` with Media Foundation (`MediaFoundationEncoder.EncodeToAac`; built into Windows 10/11). Fall back to `.wav` if encoding fails; Scribe accepts both. Show a live level meter and timer; refuse recordings under 1 second. |
| Playback | NAudio (`MediaFoundationReader` or `Mp3FileReader` + `WaveOutEvent`): play/pause, scrubber, elapsed/total, and a queue for "Play all in order". |
| Links | Open in the default browser (`Process.Start` with `UseShellExecute = true`). |
| Keys | Encrypted vault on the drive (section 9). Never in code, settings, logs or the repo. |
| Packaging | `dotnet publish` single-file (section 10). |

Alternatives, if you prefer: **Python 3.12 + PySide6 + PyInstaller `--onefile`** (quick to iterate, larger exe, slower start), or **Tauri** (tiny exe, web UI, needs the WebView2 runtime that Windows 10/11 usually has). The rest of this guide applies to any of them.

### Portable data layout

Everything lives next to the `.exe`, found at run time from the exe's own folder (never a fixed drive letter: a flash drive can be `E:` on one PC and `F:` on another).

```
PearlForge.exe
PearlForge Data\
├── settings.json          non-secret choices (voice, models, modes, recordings folder)
├── keys.vault             API keys, encrypted (section 9)
├── RecordingIndex.json    cache of every recording's details and texts, for instant startup
└── Recordings\            one folder per recording (section 7)
```

Settings › Storage can point the recordings at another folder instead. If that's the iCloud Drive folder the iPhone app uses (iCloud for Windows puts it at `C:\Users\<you>\iCloudDrive\Pearl Forge`), the PC and iPhone share recordings, because the folder format is identical. Never overwrite a recording folder that already exists when moving recordings.

## 3. How the iPhone code maps over

| iPhone file (in `Pearl Forge source/PearlForge/`) | Windows equivalent |
|---|---|
| `Pipeline/PipelineConfig.swift` | `PipelineConfig` constants (section 4) |
| `Pipeline/PipelineHTTP.swift` | HTTP helper + readable error messages |
| `Pipeline/ElevenLabsClient.swift` | Scribe, text-to-speech (chunking), voices, credits |
| `Pipeline/AnthropicClient.swift` | Claude: models list, one-shot completion |
| `Pipeline/OpenAICompatibleClient.swift` | OpenAI / Gemini / OpenRouter chat completions + model lists |
| `Pipeline/Polisher.swift` | Provider list, names, key pages, endpoints |
| `Pipeline/RefinementPrompts.swift` | **Polishing prompts, verbatim** (Appendix A) |
| `Pipeline/Translation.swift` | Languages + translation prompt (Appendix A) |
| `Pipeline/Insights.swift` | Topic sorting (Appendix A) |
| `Pipeline/ResearchLoop.swift`, `ReferenceFinder.swift`, `PubMedClient.swift` | Claude + web search + PubMed research, source checking |
| `Pipeline/Lecture.swift`, `Costs.swift` | Lecture detection, prompt, writer; prices and estimates |
| `Pipeline/Forge.swift` | The steps: transcribe, refine, translate, speak |
| `Recordings/RecordingFiles.swift`, `RecordingLibrary.swift`, `CoordinatedFiles.swift` | Data model, folder layout, saving, topics, references |
| `Settings/KeychainStore.swift`, `SettingsModel.swift`, `PolishersModel.swift` | Key vault, voice and AI choices |
| `Audio/*` | Recorder and player |
| `Create/CreateModel.swift` | Create screen logic (incl. lecture plan) |
| `Screens/*` | One file per screen |

## 4. Constants

```
ElevenLabs base     https://api.elevenlabs.io/v1
Transcription       scribe_v1
Speech model        eleven_multilingual_v2
Speech chunk        2,500 characters
Anthropic base      https://api.anthropic.com/v1
anthropic-version   2023-06-01
Default polisher    Claude, model claude-opus-5-5
Reading model       claude-sonnet-5-5 (Find reading), changeable in the AI tab
Lecture models      claude-sonnet-5-5 (default), claude-opus-5-5
max_tokens          16000
Request timeout     900 seconds
```

## 5. The cloud calls, exactly

Turn every HTTP error into a sentence for the person: `"<what failed> (<status>): <message>"`, where the message comes from `error.message` (Anthropic/OpenAI), `detail.message` or `detail` (ElevenLabs), or the start of the body. Gemini sometimes wraps its error in a one-item list.

### 5.1 ElevenLabs

**Transcribe (Scribe).** `POST /v1/speech-to-text`, header `xi-api-key`, multipart form:
`model_id=scribe_v1`, `tag_audio_events=false`, `diarize=false`, `file=<the recording>`. Reply `{"text": "..."}`; trim it, and an empty transcript is an error ("Is the recording audible?").

**Speak.** `POST /v1/text-to-speech/{voice_id}`, headers `xi-api-key`, `Content-Type: application/json`, `Accept: audio/mpeg`, body:
```json
{"text": "<chunk>", "model_id": "eleven_multilingual_v2", "previous_text": "<previous chunk>", "next_text": "<next chunk>"}
```
Split text over 2,500 characters into chunks: first on blank lines (paragraphs), then on sentence ends (`(?<=[.!?])\s+`), packing sentences into chunks up to the limit. Send `previous_text`/`next_text` (neighbouring chunks) so the delivery stays continuous, and join the returned MP3 bytes in order. Algorithm: `splitForSpeech` in Appendix B. Don't send `language_code` (Multilingual v2 doesn't take it).

**Voices.** `GET /v1/voices` → `voices[]` with `voice_id`, `name`, `category`. List the person's own voices first (`category` is `cloned`, `professional` or `generated`), then the library, alphabetically. Loading this list doubles as the ElevenLabs key check. Keep the chosen voice id and name; if the saved voice is gone, pick the first.

**Credits.** `GET /v1/user/subscription` → `tier`, `character_count` (used), `character_limit`, `next_character_count_reset_unix`. Remaining = limit − used. If the key lacks the "User: read" permission this fails; just leave credits unknown.

### 5.2 Claude (Anthropic)

`POST /v1/messages`, headers `x-api-key`, `anthropic-version: 2023-06-01`, `Content-Type: application/json`, and `anthropic-workspace-id` only if the person entered one.

One-shot completion (polish, translate, sort topics):
```json
{"model": "claude-opus-5-5", "max_tokens": 16000, "system": "<system prompt>",
 "messages": [{"role": "user", "content": "<transcript or text>"}],
 "fallbacks": "default"}
```
- For `claude-fable-5-1`, `claude-fable-5`, `claude-mythos-5-1`, `claude-opus-5-5`, `claude-opus-5`, `claude-sonnet-5-5`: add header `anthropic-beta: server-side-fallback-2026-07-01` and `"fallbacks": "default"` (if a safety check declines, Anthropic re-runs it on its recommended fallback model). Other models: leave both out.
- For `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-6`, `claude-sonnet-4-6`: add `"thinking": {"type": "adaptive"}`. Newer models think by default; don't send `thinking` to them (never `budget_tokens`, never `"disabled"`).
- Read only the `text` blocks of `content`, joined and trimmed. Record `model` from the reply (it differs when the fallback stepped in).
- `stop_reason: "refusal"` → "Claude declined…". `"max_tokens"` → "cut off before the end" error (never save a truncated pearl). Empty text → error.

Model list (also the key check, and free): `GET /v1/models?limit=1000` → `data[]` with `id`, `display_name`, `created_at`; newest first.

### 5.3 OpenAI, Gemini, OpenRouter (OpenAI-compatible)

Base URLs: OpenAI `https://api.openai.com/v1`, Gemini `https://generativelanguage.googleapis.com/v1beta/openai`, OpenRouter `https://openrouter.ai/api/v1`. Header `Authorization: Bearer <key>`; OpenRouter also `X-Title: Pearl Forge`.

`POST {base}/chat/completions` with `{"model": "...", "messages": [{"role": "system", ...}, {"role": "user", ...}]}`. No length limit is sent, so each model's own maximum applies. Read `choices[0].message.content` (a string, or a list of parts whose `text` you join); strip a leading `<think>…</think>` block; `finish_reason: "length"` → cut off; a `refusal` field or `finish_reason: "content_filter"` → declined.

Models: `GET {base}/models`, newest first, chat models only (Gemini ids arrive as `models/…`; strip that). Filters: see `isChatModel` in `OpenAICompatibleClient.swift`. OpenRouter's model list works without a key, so check its key with `GET {base}/key`.

### 5.4 PubMed (free, no key)

`GET https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=pubmed&term=<query>&retmax=<1–10>&sort=relevance&retmode=json&tool=PearlForge` → `esearchresult.idlist`.
Then `efetch.fcgi?db=pubmed&id=<ids,comma-separated>&rettype=abstract&retmode=xml&tool=PearlForge`. Parse PMID, article title, journal title, year, authors (`LastName Initials`; show three then "et al."), abstract (fold inline markup like `<i>` into the text), DOI. Keep esearch's order. Paper URL: `https://pubmed.ncbi.nlm.nih.gov/<PMID>/`.

### 5.5 Research with Claude (Find reading and Lectures)

One conversation, looped in code until Claude calls the finishing tool (`save_references` for Find reading, `write_lecture` for lectures):

- Tools: `{"type": "web_search_20250305", "name": "web_search", "max_uses": N}` (Find reading 6; lectures 4–10 by length), the client tool `pubmed_search`, and the finishing tool (`"strict": true`). Exact schemas: Appendix A.
- Top-level `"cache_control": {"type": "ephemeral"}` (each step resends earlier search results; caching makes that cheap). Fallback header and `fallbacks` as in 5.2.
- Use the **basic** `web_search_20250305`. The filtered `web_search_20260209` hid results from verification in live tests, so every source failed the check.
- Each step: send; add up `usage` (`input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, `output_tokens`, `server_tool_use.web_search_requests`); collect every URL from any `web_search_result`, `web_search_result_location` or `web_fetch_result` object anywhere in `content`; then by `stop_reason`:
  - `pause_turn`: append the assistant `content` unchanged and send again.
  - `tool_use`: if the finishing tool was called, stop and use its input. Otherwise run each `pubmed_search` (return the papers as JSON, abstracts cut to 1,200 characters, or "No PubMed results…"), append the assistant content **unchanged** (it may contain thinking blocks that must be sent back exactly), then one user message with all the `tool_result` blocks.
  - `end_turn` without finishing: once, append it and ask "Please call <tool> now…"; after that, error.
  - `refusal`, `max_tokens`: clear errors. Give up after 12 steps (16 for lectures).
- **Source checking:** keep a source only if its URL (normalised: lowercase host without `www.`, path without trailing slash, query kept, fragment dropped) matches a collected search-result URL; save it with the URL exactly as the search returned it. If it names a PMID (or a PubMed link) that `pubmed_search` returned, use PubMed's own title, journal, year and authors. Count the dropped ones and say so. Find reading keeps at most 10.
- Report progress as it goes: web and PubMed search counts and the latest query.

## 6. Screens and behaviour

**Create**
- Record | Type switch. Record: big red button, timer, level meter, "Import a recording instead". Type: multi-line box.
- Recording: **How much refinement?** Clean / Tighten / Summarize (remember the last choice). Typed: Polish menu with As written (default) / Clean / Tighten / Summarize. Both: **Speak in** (the language I spoke/wrote in, or one of 29).
- Button text: "Refine & speak", "Refine, translate & speak", "Translate & speak", "Speak in my voice" or "Polish & speak"; **"Plan lecture"** when typed text is a lecture request; "Try again" after an error.
- Steps: transcribe (recordings) → **lecture check** → polish or translate (typed As written with no language needs no AI; typed As written with a language uses the translation prompt; everything else uses the polishing prompt, with `Say it in <Language>, the way a native speaker would.` as the speaker's request when a language is chosen) → save → speak → play. A failed step can be retried without redoing earlier ones. Recordings (not typed text) are then sorted into topics in the background with the active AI.
- After: the editable text, the player, "Regenerate audio from your edits" when edited, "Share audio", and a note that it's saved in History.

**Lecture flow** (when the transcript or typed text is a lecture request, section 8)
- Card: what you asked (quoted), Topic (editable), Length (About 3/5/10/15/20 min), Researched by (Claude Sonnet 5.5 / Claude Opus 5.5, remembered), Speak in.
- **Estimated cost**: Research & writing (range), Your voice (credits and dollars), Total, a warning if credits needed exceed credits left, and the line "You have N ElevenLabs credits left until <date>."
- **Give the lecture** → progress ("Researching and writing your lecture…", with search counts and the latest query) → save → speak. Keep the PC awake while it works. Also offer "Not a lecture: refine what I said" (or "speak what I wrote") and, for typed text, "Edit what I wrote".
- After: the lecture text (editable, regenerate audio), player, **Sources** (each opens in the browser; "checked against the actual search results"; N unconfirmed left out), and **What it cost** (Claude dollars + model + web searches; voice credits and dollars).
- Saved as a recording with `lecture` details (section 7), sorted into topics using its title and summary, and its sources appear in Reading.

**History**: search (title, texts), favourites filter, swipe to favourite or delete, Recordings | Topics switch. Rows show title, date, pearl count (or "Typed ·", or "Lecture · about N min"), topics. Topics view: each topic with its count; a topic page lists its recordings oldest first with **Play all in order** (the newest spoken pearl of each, one after another, with previous/next/stop and "2 of 7 · title").

**Recording detail**: as in section 1. Forge a new pearl: mode (Clean/Tighten/Summarize), which AI (any set-up service), Speak in, and "Anything to change this time?" (free text); the request sent is the language request plus your text. The original transcript is always the starting point. Find reading: "Searching PubMed and the web… this can take a minute or two", then "Found N new references" / "Nothing new" / "No good matches" / "links couldn't be confirmed".

**AI**: Polishing with (choose among set-up services, each showing its model); Finding reading (model; footer with the per-search cost); AI services list with key status (Not set / Saved / Checking… / Works / Not working + message, Check again). Provider page: key (with link to the key page), Model (pick from the loaded list, search, or type an id), "Refresh models", "Polish with <service>". Key pages: console.anthropic.com/settings/keys, platform.openai.com/api-keys, aistudio.google.com/apikey, openrouter.ai/settings/keys. Claude also takes an optional Workspace id.

**Settings**: ElevenLabs key (status as above), Voice (your voices, then library; Refresh voices), Storage (where recordings are; choose a folder; moving never overwrites).

## 7. Data format (identical to the iPhone app)

Each recording is a folder named `yyyy-MM-dd_HHmmss_<first six words>` (local time; ASCII letters and digits of the first six words of the first pearl's text, or of a lecture's title, joined with `_`, at most 40 characters, "note" if empty):

```
2026-10-24_093012_I_think_theres_a_decent_chance\
├── original.m4a               the untouched recording (none for typed text)
├── original_transcript.txt    what you said or typed, exactly
├── pearl-01-clean.txt         each pearl's text…
├── pearl-01-clean.mp3         …and its audio in your voice
├── pearl-02-tighten.txt
├── pearl-02-tighten.mp3
└── meta.json
```

Pearl files are `pearl-<two-digit number>-<mode>.txt/.mp3`, modes `clean`, `tighten`, `summarize`, `aswritten`, `lecture`. Title = first line of the first pearl's text (max 80 characters), or the lecture's title. Dates are ISO 8601 UTC. `meta.json` is pretty-printed with sorted keys. Optional fields are left out when empty. Real examples generated by the iPhone app's code are in Appendix C.

Reference `kind` is one of `research`, `article`, `essay`, `blog`, `book`, `other`. When reading folders, a meta.json without `pearls` (the first iPhone version) means one pearl: `mode`, `voice_id`, `output_file`, `refined_by` at the top level, text in `refined_transcript.txt`.

## 8. Lecture rules

**Detection** (`LectureRequest.parse`, Appendix A, case-insensitive): the text must **start** with the request. Optional lead-ins ("hey", "ok", "so", "um", "Pearl,", "please", "can/could/would/will you"), then a verb (give, do, make, write, prepare, create, deliver, record, play, read) with optional "me/us", or "I want / I need / I'd like (to hear)"; then optional a/an/the; then optional length ("5-minute", "ten minute") or size word (short/quick/brief/little → 5 min; long/longer/full/detailed/in-depth/deep → 20 min); then the word **lecture**; then optional on/about/regarding/covering/…; then the topic. Also "Lecture me/us on/about …". A trailing "…for about 10 minutes" sets the length and is removed from the topic. Leading fillers (uh, um, like, so) are trimmed from the topic; a topic that's empty or just a preposition isn't a request. Lengths snap to the nearest of 3, 5, 10, 15, 20 (default 10). Everything after "lecture on" is passed to Claude, so extra instructions ("part one of two; end with …") work.

**Words and credits:** about 150 words per minute; the prompt asks for that and caps it at +10%. Credits ≈ 1,000 per minute (one per character).

**Web searches allowed:** under 5 min → 4, under 10 → 5, under 15 → 7, under 20 → 8, 20 → 10.

**Prompt and `write_lecture` tool:** Appendix A (`LecturePrompt`). User message: `Give a lecture on: <topic>`. After writing: drop markdown (headings, `**`, `__`); require at least 200 characters; empty title → topic with a capital letter.

## 9. Keys and security

- The person enters each key once in the app. **Never hardcode keys**, never write them to `settings.json`, logs, error messages or the repo.
- On a flash drive, Windows' own protection (DPAPI) is tied to one PC's user account, so use a **portable vault**: `keys.vault` encrypted with AES-256-GCM, key derived from a passphrase with PBKDF2-HMAC-SHA256 (600,000 iterations) or Argon2id, random salt and nonce. Ask for the passphrase once per launch. Optional "Remember on this PC" may store the vault key with DPAPI (CurrentUser) in `%LOCALAPPDATA%\PearlForge`.
- Keys stored: ElevenLabs key; Claude key and optional workspace id; OpenAI, Gemini and OpenRouter keys.
- Show keys masked; "Remove key" deletes it.

## 10. Packaging and running from a flash drive

```
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:EnableCompressionInSingleFile=true
```
Copy `bin\Release\net10.0-windows\win-x64\publish\PearlForge.exe` to the flash drive (use `win-arm64` for ARM PCs). The first run creates `PearlForge Data\` beside it.

- **SmartScreen:** an unsigned exe shows "Windows protected your PC" → More info → Run anyway (once per PC).
- **Microphone:** Settings → Privacy & security → Microphone → turn on "Let desktop apps access your microphone".
- **Don't email the .exe:** Gmail blocks executables. Carry it on the drive.
- Give the app an icon from `Design/render-icon.swift`'s design (iridescent pearl on deep teal with a red record button), as an `.ico`.

## 11. Costs (October 2026 list prices)

| Item | Price |
|---|---|
| Claude Opus 5.5 | $4 input, $20 output per million tokens; cache write $5; cache read $0.20 |
| Claude Sonnet 5.5 | $2 input, $10 output; cache write $2.50; cache read $0.10 |
| Claude Fable 5.1 | $10 input, $50 output; cache write $12.50; cache read $0.25 |
| Web search | $10 per 1,000 searches |
| ElevenLabs Multilingual v2 | 1 credit per character. Value per 1,000 credits: Starter $0.20 ($6/30k), Creator $0.18 ($22/121k), Pro/Scale/Business $0.165 ($99/600k); free plan $0 |

Measured live: Find reading ≈ $0.07 (Sonnet) / $0.25 (Opus); topic sort ≈ $0.01; lectures: Sonnet 5 min (PubMed only) $0.065, Sonnet 10 min (5 web searches) $0.22, Opus 5 min $0.28.

**Lecture estimate** (`LectureEstimate` in Appendix A): typical usage for M minutes with s = 0.6 × allowed searches and t = 150 × M × 1.4 script tokens: input 50, cache write 7,000 + 6,500·s + 1.5·t, cache read 9,000 + 4,500·s, output 1,000 + 2.4·t, web searches round(s). Price it for the chosen model = the base. Range ×0.5 to ×1.5 until there are past lectures; then multiply by the median of the last five (actual ÷ base) ratios (clamped 0.25–4) and use ×0.75 to ×1.3. Save the base with each lecture so later estimates learn. Voice = M × 1,000 credits × plan rate. Actual Claude cost = usage × prices.

## 12. Build plan (milestones)

1. Project skeleton, portable data folder, settings, key vault, Settings screen (ElevenLabs key check, voice picker).
2. Recorder + player; Create: record → transcribe → polish with Claude (verbatim prompts) → speak → save in the folder format. Try it with your voice.
3. History + recording detail + pearl screen; forge new pearls; regenerate audio; share.
4. Typed text, As written, Speak in (translation).
5. AI tab: OpenAI, Gemini, OpenRouter, model lists, default polisher.
6. Topics (auto-sort, edit, Play all in order).
7. Find reading + Reading tab (research loop, PubMed, source checking).
8. Lectures (detection, plan card with estimate and credits, research and writing, sources, actual cost).
9. Icon, polish, publish the single-file exe, test from a flash drive on a second PC.

## 13. Acceptance checklist

- [ ] Runs from a flash drive on a PC with nothing installed; data stays on the drive; works when the drive letter changes.
- [ ] Keys entered once, stored encrypted, never visible in any file.
- [ ] A recording polished in each mode keeps hedges and meaning (the prompts are verbatim).
- [ ] Audio is in your cloned voice; long text plays continuously across chunks.
- [ ] Recording folders and meta.json match section 7 (open one in the iPhone app via iCloud Drive to confirm).
- [ ] Find reading saves only verified sources; PubMed papers show PubMed's details.
- [ ] "Give a lecture on …" shows the estimate first, nothing is spent before "Give the lecture", and the actual cost appears afterwards.
- [ ] Errors read as plain sentences, and a failed step can be retried.

## Appendix A — Prompts, tools and rules (verbatim source)

Copied unchanged from the iPhone app. Carry every prompt over **word for word**, including line breaks; `\(…)` is Swift string interpolation (insert the value). The polishing prompt is `systemBase + "\n\n" + mode instruction`, plus `"\n\n" + speakerRequest(notes)` when there is a request.

### `Pipeline/RefinementPrompts.swift`

```swift
// Pearl Forge's refinement instructions, carried over word-for-word from the
// working Pinokio build (pearl-ui/pipeline.py: SYSTEM_BASE and
// MODE_INSTRUCTIONS). The wording is the product — change it only on purpose.

import Foundation

/// How much refinement Claude applies. Raw values match the Pinokio build's
/// mode keys so saved recordings stay readable across both versions.
enum RefinementMode: String, CaseIterable, Identifiable, Codable {
    case clean
    case tighten
    case summarize
    /// Typed text spoken exactly as written (or only translated), not polished.
    case asWritten = "aswritten"
    /// A lecture researched and written for you; never offered as a polish.
    case lecture

    var id: String { rawValue }

    /// The modes that polish, offered for recordings and new pearls.
    static let polishingModes: [RefinementMode] = [.clean, .tighten, .summarize]

    var title: String {
        switch self {
        case .clean: return "Clean"
        case .tighten: return "Tighten"
        case .summarize: return "Summarize"
        case .asWritten: return "As written"
        case .lecture: return "Lecture"
        }
    }

    /// The short description shown next to the mode name.
    var subtitle: String {
        switch self {
        case .clean: return "light tidy-up, keeps almost everything"
        case .tighten: return "reorganise and de-clutter, keep the nuance"
        case .summarize: return "condensed to the core, still your view"
        case .asWritten: return "your exact words, not polished"
        case .lecture: return "researched and written for you"
        }
    }

    /// The subtitle as a sentence: "Light tidy-up, keeps almost everything."
    var subtitleSentence: String {
        subtitle.prefix(1).uppercased() + subtitle.dropFirst() + "."
    }

    var instruction: String {
        switch self {
        case .clean: return RefinementPrompts.clean
        case .tighten: return RefinementPrompts.tighten
        case .summarize: return RefinementPrompts.summarize
        case .asWritten, .lecture: return ""
        }
    }
}

enum RefinementPrompts {
    /// The full system prompt for one refinement request. Without notes it is
    /// exactly the Pinokio build's prompt; your notes for a pearl are added
    /// after it.
    static func system(for mode: RefinementMode, notes: String? = nil) -> String {
        let prompt = systemBase + "\n\n" + mode.instruction
        guard let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return prompt
        }
        return prompt + "\n\n" + speakerRequest(notes)
    }

    /// What you asked to be different for one pearl. Not part of the Pinokio
    /// prompts; added only when you write a request.
    static func speakerRequest(_ notes: String) -> String {
        """
        SPEAKER'S REQUEST FOR THIS VERSION:
        \(notes)

        Apply this request on top of the mode above. Everything else in the rules above still holds; depart from a rule only where the request explicitly asks you to.
        """
    }

    static let systemBase = """
    You are Pearl Forge. You are given the verbatim transcript of a voice note in which the speaker is thinking out loud. Your job is to improve HOW CLEARLY the thought is expressed, WITHOUT changing the thought itself. The result will be read back aloud in the speaker's own voice, in the first person, so it must sound like the speaker on an articulate day — not like a different narrator.

    These rules are absolute. Never break them, in any mode:
    - Never increase certainty. If the speaker hedges ("maybe", "I think", "I'm not sure", "probably", "it seems"), keep the hedge. A possibility must never become a flat claim.
    - Never remove qualifications, caveats, conditions, or the sense that the speaker is exploring rather than concluding.
    - Never add facts, opinions, conclusions, analogies, or examples the speaker did not say. Do not insert your own analysis or your own conclusions.
    - Keep the speaker's personality: their humour, their analogies, their unusual associations, and digressions that genuinely add to the idea. Do not flatten the writing into generic or corporate prose.
    - Keep it first person and in the speaker's own words as much as possible. Improve the expression; do not replace the voice.

    Output ONLY the refined text. No preamble, no title, no notes, no quotation marks wrapping the whole thing, no explanation of what you changed.
    """

    static let clean = """
    MODE: Clean.
    Make only light, mechanical edits — the way a careful transcriptionist tidies up dictation. Remove filler words ("um", "uh", "like", "you know"), false starts, stutters, and word-for-word repetition. Fix obvious grammar and broken run-on sentences. KEEP the original order of ideas, the conversational tone, and nearly all of the substance. Do NOT reorganise, condense, or rewrite in a more polished register.
    """

    static let tighten = """
    MODE: Tighten.
    Improve how the explanation is built. Combine sentences that make the same point, move closely related points next to each other, fix awkward ordering, and smooth the transitions so the argument flows. KEEP every important nuance and qualification, and keep the speaker's distinctive phrasing and the digressions that add value. Do not shorten by dropping ideas — only by removing waste and repetition.
    """

    static let summarize = """
    MODE: Summarize.
    Produce a genuinely condensed version, in the speaker's first-person voice, containing the central argument, the major supporting points, the important qualifications, and the final conclusions. This mode deliberately sacrifices detail — but it must still represent the speaker's ACTUAL position and their uncertainty, never a more confident, tidier, or more generic version of it.
    """
}
```

### `Pipeline/Translation.swift`

```swift
import Foundation

/// A language your voice can speak.
struct SpeechLanguage: Hashable, Identifiable, Codable {
    let code: String
    let name: String

    var id: String { code }
}

/// The languages ElevenLabs' Multilingual v2 voice model speaks, the model
/// Pearl Forge uses for your voice.
enum SpeechLanguages {
    static let all: [SpeechLanguage] = [
        ("ar", "Arabic"), ("bg", "Bulgarian"), ("zh", "Chinese (Mandarin)"), ("hr", "Croatian"), ("cs", "Czech"),
        ("da", "Danish"), ("nl", "Dutch"), ("en", "English"), ("fil", "Filipino"), ("fi", "Finnish"),
        ("fr", "French"), ("de", "German"), ("el", "Greek"), ("hi", "Hindi"), ("id", "Indonesian"),
        ("it", "Italian"), ("ja", "Japanese"), ("ko", "Korean"), ("ms", "Malay"), ("pl", "Polish"),
        ("pt", "Portuguese"), ("ro", "Romanian"), ("ru", "Russian"), ("sk", "Slovak"), ("es", "Spanish"),
        ("sv", "Swedish"), ("ta", "Tamil"), ("tr", "Turkish"), ("uk", "Ukrainian"),
    ].map { SpeechLanguage(code: $0.0, name: $0.1) }

    static func named(_ code: String?) -> SpeechLanguage? {
        all.first { $0.code == code }
    }

    /// The request added to a pearl's instructions to have it written in
    /// another language. It reads like the request you'd type yourself.
    static func request(for language: SpeechLanguage) -> String {
        "Say it in \(language.name), the way a native speaker would."
    }
}

/// Faithful translation of text you typed, for speaking it in your voice
/// without polishing it first.
enum TranslationPrompt {
    static func system(for language: SpeechLanguage) -> String {
        """
        Translate the user's text into \(language.name). It will be read aloud in the user's own cloned voice, so it must sound like them speaking \(language.name) naturally.

        - Keep the meaning exactly. Don't add, drop, soften or strengthen anything; keep any uncertainty or hedging, the first person, and the user's tone and register.
        - Prefer the phrasing a native \(language.name) speaker would actually use over a word-for-word rendering.
        - Keep names of people and places as they are.
        - If the text is already in \(language.name), return it unchanged.

        Output only the translation: no quotation marks, notes, alternatives or pronunciation guides.
        """
    }
}

extension Forge {
    /// Translates text into a language with the chosen AI, keeping its meaning.
    static func translate(_ text: String, to language: SpeechLanguage,
                          with choice: PolisherChoice) async throws -> Refinement {
        guard let key = KeychainStore.read(choice.provider.credential) else {
            throw PipelineError(message: "Add your \(choice.provider.name) key in the AI tab first.")
        }
        let system = TranslationPrompt.system(for: language)
        let reply: Completion
        switch choice.provider {
        case .anthropic:
            reply = try await AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
                .complete(system: system, user: text, model: choice.model, failure: "Translation failed")
        case .openai, .gemini, .openrouter:
            reply = try await OpenAICompatibleClient(provider: choice.provider, apiKey: key)
                .complete(system: system, user: text, model: choice.model, failure: "Translation failed")
        }
        if reply.stopReason == "refusal" {
            throw PipelineError(message: "\(choice.provider.name) declined to translate this.")
        }
        if reply.wasCutOff {
            throw PipelineError(message: "The translation was cut off before the end. Try a shorter text.")
        }
        guard !reply.text.isEmpty else {
            throw PipelineError(message: "The translation came back empty. Please try again.")
        }
        return Refinement(text: reply.text, provider: choice.provider, model: reply.model)
    }
}
```

### `Pipeline/Insights.swift`

```swift
import Foundation

/// What a recording is about: its broad topics and a one-line gist.
struct RecordingInsights: Equatable {
    let categories: [String]
    let gist: String
}

/// Sorts recordings into topics such as "Relationships" or "Work & Career",
/// reusing the topics you already have so related thoughts gather together.
enum TopicSorter {
    /// Topics offered to the AI as a starting vocabulary.
    static let starterTopics = [
        "Relationships", "Work & Career", "Parenting & Family", "Friendship",
        "Health & Body", "Mind & Emotions", "Money", "Creativity",
        "Learning & Ideas", "Philosophy & Meaning", "Faith & Spirituality",
        "Personal Growth", "Technology", "Society & Politics",
    ]

    static let maxTopics = 3

    static func system(existing: [String]) -> String {
        let known = existing.isEmpty ? starterTopics : existing + starterTopics.filter { starter in
            !existing.contains { $0.caseInsensitiveCompare(starter) == .orderedSame }
        }
        return """
        You sort a person's voice notes into broad life topics so that related thoughts can be found together later. You are given the verbatim transcript of one voice note.

        Choose 1 to \(maxTopics) topics that the note is substantially about. Prefer these topics, spelled exactly as written, whenever one fits:
        \(known.map { "- \($0)" }.joined(separator: "\n"))
        Only create a new topic if none of these fits; keep a new one broad, in Title Case, and at most three words.

        Also write a gist: one sentence, in the first person, saying what the speaker is thinking about. Keep their uncertainty (if they say "maybe" or "I'm not sure", so does the gist). At most 25 words.

        Reply with only this JSON and nothing else:
        {"categories": ["Topic"], "gist": "I'm wondering whether..."}
        """
    }

    /// Reads the AI's reply, matching topics to the existing spelling.
    static func parse(_ reply: String, existing: [String]) throws -> RecordingInsights {
        struct Raw: Decodable {
            let categories: [String]?
            let gist: String?
        }
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end,
              let raw = try? JSONDecoder().decode(Raw.self, from: Data(reply[start...end].utf8))
        else {
            throw PipelineError(message: "The topics came back in an unexpected format. Please try again.")
        }
        let known = existing + starterTopics
        var categories: [String] = []
        for name in raw.categories ?? [] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let canonical = known.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame } ?? trimmed
            if !categories.contains(where: { $0.caseInsensitiveCompare(canonical) == .orderedSame }) {
                categories.append(canonical)
            }
        }
        guard !categories.isEmpty else {
            throw PipelineError(message: "No topics came back. Please try again.")
        }
        return RecordingInsights(categories: Array(categories.prefix(maxTopics)),
                                 gist: (raw.gist ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

extension Forge {
    /// Sorts a transcript into topics using the chosen AI.
    static func sortIntoTopics(_ transcript: String, existing: [String],
                               with choice: PolisherChoice) async throws -> RecordingInsights {
        guard !transcript.isEmpty else {
            throw PipelineError(message: "This recording's transcript couldn't be loaded.")
        }
        guard let key = KeychainStore.read(choice.provider.credential) else {
            throw PipelineError(message: "Add your \(choice.provider.name) key in the AI tab first.")
        }
        let system = TopicSorter.system(existing: existing)
        let reply: Completion
        switch choice.provider {
        case .anthropic:
            reply = try await AnthropicClient(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID))
                .complete(system: system, user: transcript, model: choice.model, failure: "Sorting into topics failed")
        case .openai, .gemini, .openrouter:
            reply = try await OpenAICompatibleClient(provider: choice.provider, apiKey: key)
                .complete(system: system, user: transcript, model: choice.model, failure: "Sorting into topics failed")
        }
        if reply.stopReason == "refusal" {
            throw PipelineError(message: "\(choice.provider.name) declined to sort this recording.")
        }
        return try TopicSorter.parse(reply.text, existing: existing)
    }
}
```

### `Pipeline/ReferenceFinder.swift`

```swift
import Foundation

/// Finds reading related to a recording (research papers from PubMed, and
/// essays, articles and blog posts from the web) using Claude with web search.
/// Every reference is checked against the actual search results, so a title
/// or link the AI made up is never saved.
struct ReferenceFinder {
    let apiKey: String
    let workspaceID: String?
    let model: String

    private static let maxReferences = 10

    struct Result {
        let references: [Reference]
        /// How many suggestions were dropped because they couldn't be matched
        /// to a real search result.
        let unverified: Int
    }

    func find(transcript: String, gist: String?, categories: [String]) async throws -> Result {
        let loop = ResearchLoop(apiKey: apiKey, workspaceID: workspaceID, model: model, system: Self.system,
                                finishTool: Self.saveTool, maxWebSearches: 6, maxSteps: 12,
                                failure: "Finding references failed",
                                nudge: "Please call save_references now with the references you found (an empty list is fine).")
        do {
            let outcome = try await loop.run(user: Self.userMessage(transcript, gist: gist, categories: categories))
            return Self.verify(outcome.input["references"] as? [[String: Any]] ?? [],
                               seenURLs: outcome.seenURLs, papers: outcome.papers)
        } catch let stop as ResearchLoop.Stop {
            let message = switch stop {
            case .refusal: "Claude declined to search for this recording."
            case .cutOff: "The search ran too long. Please try again."
            case .unfinished: "The search finished without saving any references. Please try again."
            case .tooManySteps: "The search took too many steps. Please try again."
            }
            throw PipelineError(message: message)
        }
    }

    // MARK: Checking the results

    /// Keeps only references that match a real search result. PubMed papers
    /// get their details from PubMed itself.
    static func verify(_ suggested: [[String: Any]], seenURLs: [String: String], papers: [String: PubMedPaper]) -> Result {
        var kept: [Reference] = []
        var keptURLs = Set<String>()
        var unverified = 0

        for item in suggested {
            func field(_ key: String) -> String {
                (item[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let url = field("url")
            let pmid = [field("pmid"), pubMedID(in: url)].first { !$0.isEmpty && papers[$0] != nil } ?? ""

            var reference: Reference
            if let paper = papers[pmid] {
                reference = Reference(id: UUID(), title: paper.title.isEmpty ? field("title") : paper.title,
                                      url: paper.url, source: paper.journal.isEmpty ? "PubMed" : paper.journal,
                                      kind: .research, year: paper.year.isEmpty ? nil : paper.year,
                                      authors: paper.authorLine.isEmpty ? nil : paper.authorLine,
                                      note: field("note"), pmid: paper.pmid, found: Date())
            } else if let normalized = normalize(url), let found = seenURLs[normalized] {
                // Saved with the address exactly as the search found it.
                reference = Reference(id: UUID(), title: field("title"), url: found, source: field("source"),
                                      kind: Reference.Kind(rawValue: field("kind")) ?? .other,
                                      year: field("year").isEmpty ? nil : field("year"),
                                      authors: field("authors").isEmpty ? nil : field("authors"),
                                      note: field("note"), pmid: nil, found: Date())
            } else {
                unverified += 1
                continue
            }
            if reference.title.isEmpty { reference.title = reference.source }
            guard let key = normalize(reference.url), keptURLs.insert(key).inserted else { continue }
            kept.append(reference)
        }
        return Result(references: Array(kept.prefix(maxReferences)), unverified: unverified)
    }

    /// Every URL that appeared in web search or fetch results, keyed by its
    /// normalized form.
    static func collectURLs(in value: Any, into urls: inout [String: String]) {
        if let list = value as? [Any] {
            for item in list { collectURLs(in: item, into: &urls) }
        } else if let object = value as? [String: Any] {
            let resultTypes: Set<String> = ["web_search_result", "web_search_result_location", "web_fetch_result"]
            if let type = object["type"] as? String, resultTypes.contains(type),
               let url = object["url"] as? String, let normalized = normalize(url), urls[normalized] == nil {
                urls[normalized] = url
            }
            for (_, child) in object { collectURLs(in: child, into: &urls) }
        }
    }

    /// A URL reduced to host, path and query, so small differences
    /// (http/https, "www.", a trailing slash, a #section) still match.
    static func normalize(_ string: String) -> String? {
        guard var components = URLComponents(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased(), !host.isEmpty
        else { return nil }
        components.fragment = nil
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        let query = components.percentEncodedQuery.map { "?" + $0 } ?? ""
        return bareHost + path + query
    }

    /// "12345678" from a pubmed.ncbi.nlm.nih.gov link.
    static func pubMedID(in url: String) -> String {
        guard let components = URLComponents(string: url), components.host?.contains("pubmed.ncbi.nlm.nih.gov") == true
        else { return "" }
        return components.path.split(separator: "/").first { $0.allSatisfy(\.isNumber) }.map(String.init) ?? ""
    }

    // MARK: Prompt and tools

    static let system = """
    You are Pearl Forge's research assistant. The speaker recorded a voice note while thinking out loud, and you are given what they said. Find reading that would help them think further about the ideas in it.

    - Peer-reviewed research: use pubmed_search when the thought touches on something researchers study, such as relationships, parenting, emotions, behaviour, health, sleep, learning or work. Read the abstracts and keep only papers that are genuinely on point.
    - Essays, long-form articles and thoughtful blog posts: use web search. Prefer substantive, reputable sources (established publications, universities, respected writers) over listicles, SEO content, product pages and forums.
    - Aim for 3 to 8 items in total, with a mix of kinds when good ones exist. A few strong items beat a long list. If nothing good exists, save an empty list.
    - Never invent a source, title, author or URL. Only save items that appeared in your search results, with their exact URL.
    - For each item, write a short note on what it says that relates to the speaker's thought, in plain language. Describe the source; don't give advice and don't add opinions of your own.

    When you're done, call save_references exactly once.
    """

    static func userMessage(_ transcript: String, gist: String?, categories: [String]) -> String {
        var message = "What I said:\n\n\(transcript)"
        if !categories.isEmpty { message += "\n\nTopics: \(categories.joined(separator: ", "))" }
        if let gist, !gist.isEmpty { message += "\nIn short: \(gist)" }
        return message
    }

    static let saveTool: [String: Any] = [
        "name": "save_references",
        "description": "Save the references you chose for the speaker. Call this exactly once, after searching. Include only items that appeared in your web search or pubmed_search results, with their exact URL.",
        "strict": true,
        "input_schema": [
            "type": "object",
            "additionalProperties": false,
            "required": ["references"],
            "properties": [
                "references": [
                    "type": "array",
                    "items": ResearchLoop.sourceSchema(
                        noteDescription: "One or two sentences on what this source says that relates to the speaker's thought."),
                ],
            ],
        ],
    ]
}

extension Forge {
    /// Finds reading related to a recording, using the Claude model chosen in
    /// the AI tab.
    static func findReferences(for entry: RecordingEntry, claudeModel: String) async throws -> ReferenceFinder.Result {
        guard let key = KeychainStore.read(.anthropicKey) else {
            throw PipelineError(message: "Finding references uses Claude's web search. Add your Claude key in the AI tab first.")
        }
        guard !entry.transcript.isEmpty else {
            throw PipelineError(message: "This recording's transcript couldn't be loaded.")
        }
        return try await ReferenceFinder(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID), model: claudeModel)
            .find(transcript: entry.transcript, gist: entry.meta.gist, categories: entry.meta.categories ?? [])
    }
}
```

### `Pipeline/ResearchLoop.swift`

```swift
import Foundation

/// How far Claude's research has got: how many searches so far, and the
/// latest one.
struct ResearchProgress: Equatable {
    var webSearches = 0
    var pubMedSearches = 0
    var latestQuery: String?

    var searches: Int { webSearches + pubMedSearches }
}

/// A conversation in which Claude searches the web and PubMed until it calls
/// the finishing tool (save_references, write_lecture, …). Every address that
/// came back from a search is kept, so the sources Claude names can be checked
/// against them, and what the calls used is added up so their cost is known.
struct ResearchLoop {
    let apiKey: String
    let workspaceID: String?
    let model: String
    let system: String
    let finishTool: [String: Any]
    var maxWebSearches = 6
    var maxSteps = 12
    /// Starts the message of a failed request: "Finding references failed: …".
    var failure = "The search failed"
    /// Sent once if Claude stops without calling the finishing tool.
    var nudge: String?
    var onProgress: (@MainActor (ResearchProgress) -> Void)?

    /// How the conversation ended when Claude didn't call the finishing tool.
    enum Stop: Error {
        case refusal, cutOff, unfinished, tooManySteps
    }

    struct Outcome {
        /// What Claude passed to the finishing tool.
        let input: [String: Any]
        let seenURLs: [String: String]
        let papers: [String: PubMedPaper]
        let usage: ClaudeUsage
        /// The model that answered; differs from the one asked for only when
        /// Anthropic's fallback stepped in.
        let answeredBy: String
    }

    private var finishName: String { finishTool["name"] as? String ?? "" }

    func run(user: String) async throws -> Outcome {
        var messages: [[String: Any]] = [["role": "user", "content": user]]
        var seenURLs: [String: String] = [:]
        var papers: [String: PubMedPaper] = [:]
        var usage = ClaudeUsage()
        var progress = ResearchProgress()
        var answeredBy = model
        var nudged = false

        for _ in 0..<maxSteps {
            let response = try await send(messages)
            usage.add(response["usage"] as? [String: Any])
            if let model = response["model"] as? String { answeredBy = model }
            let content = response["content"] as? [[String: Any]] ?? []
            ReferenceFinder.collectURLs(in: content, into: &seenURLs)
            for block in content where block["type"] as? String == "server_tool_use" {
                progress.webSearches += 1
                progress.latestQuery = (block["input"] as? [String: Any])?["query"] as? String ?? progress.latestQuery
            }

            switch response["stop_reason"] as? String {
            case "pause_turn":
                // A long search paused; send the turn back unchanged to resume.
                messages.append(["role": "assistant", "content": content])

            case "tool_use":
                let calls = content.filter { $0["type"] as? String == "tool_use" }
                if let finish = calls.first(where: { $0["name"] as? String == finishName }) {
                    return Outcome(input: finish["input"] as? [String: Any] ?? [:], seenURLs: seenURLs,
                                   papers: papers, usage: usage, answeredBy: answeredBy)
                }
                var results: [[String: Any]] = []
                for call in calls {
                    if let query = (call["input"] as? [String: Any])?["query"] as? String {
                        progress.pubMedSearches += 1
                        progress.latestQuery = query
                    }
                    results.append(await run(call, papers: &papers))
                }
                messages.append(["role": "assistant", "content": content])
                messages.append(["role": "user", "content": results])

            case "end_turn" where !nudged:
                // It stopped without finishing; ask once more.
                nudged = true
                messages.append(["role": "assistant", "content": content])
                messages.append(["role": "user", "content": nudge ?? "Please call \(finishName) now."])

            case "refusal":
                throw Stop.refusal
            case "max_tokens":
                throw Stop.cutOff
            default:
                throw Stop.unfinished
            }
            await onProgress?(progress)
        }
        throw Stop.tooManySteps
    }

    // MARK: Request

    private func send(_ messages: [[String: Any]]) async throws -> [String: Any] {
        var request = URLRequest(url: PipelineConfig.anthropicBase.appendingPathComponent("messages"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        let client = AnthropicClient(apiKey: apiKey, workspaceID: workspaceID)
        client.applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": PipelineConfig.refinementMaxTokens,
            "system": system,
            "messages": messages,
            "tools": [Self.webSearchTool(maxUses: maxWebSearches), Self.pubMedTool, finishTool],
            // Each step resends the earlier search results; caching them makes
            // those repeats much cheaper.
            "cache_control": ["type": "ephemeral"],
        ]
        if AnthropicClient.fallbackModels.contains(model) {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        if AnthropicClient.adaptiveThinkingModels.contains(model) {
            body["thinking"] = ["type": "adaptive"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await PipelineHTTP.send(request, failure: failure)
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PipelineError(message: "\(failure): the reply couldn't be read.")
        }
        return response
    }

    /// Runs one of Pearl Forge's own tools and returns its result block.
    private func run(_ call: [String: Any], papers: inout [String: PubMedPaper]) async -> [String: Any] {
        let id = call["id"] as? String ?? ""
        let input = call["input"] as? [String: Any] ?? [:]
        guard call["name"] as? String == "pubmed_search", let query = input["query"] as? String, !query.isEmpty else {
            return ["type": "tool_result", "tool_use_id": id, "is_error": true,
                    "content": "Unknown tool or missing query."]
        }
        do {
            let found = try await PubMedClient.search(query, maxResults: input["max_results"] as? Int ?? 6)
            for paper in found { papers[paper.pmid] = paper }
            let summary: [[String: Any]] = found.map { paper in
                ["pmid": paper.pmid, "url": paper.url, "title": paper.title, "journal": paper.journal,
                 "year": paper.year, "authors": paper.authorLine, "abstract": String(paper.abstract.prefix(1200))]
            }
            let json = String(decoding: try JSONSerialization.data(withJSONObject: summary), as: UTF8.self)
            return ["type": "tool_result", "tool_use_id": id,
                    "content": found.isEmpty ? "No PubMed results for that query. Try broader or different terms." : json]
        } catch {
            return ["type": "tool_result", "tool_use_id": id, "is_error": true, "content": error.localizedDescription]
        }
    }

    // MARK: Tools

    /// The basic web search tool. The filtered version (web_search_20260209)
    /// runs searches inside code, and in live tests some of the results Claude
    /// read never came back as checkable search results, so every reference
    /// failed verification. The basic version always returns them.
    static func webSearchTool(maxUses: Int) -> [String: Any] {
        ["type": "web_search_20250305", "name": "web_search", "max_uses": maxUses]
    }

    static let pubMedTool: [String: Any] = [
        "name": "pubmed_search",
        "description": "Search PubMed, the US National Library of Medicine's database of peer-reviewed biomedical and life-sciences research (including psychology, psychiatry, child development, relationships and health). Returns titles, journals, years and abstracts. Call this whenever the subject touches on something researchers study. Use PubMed search terms, not a sentence: a few key terms joined with AND/OR.",
        "input_schema": [
            "type": "object",
            "properties": [
                "query": ["type": "string",
                          "description": "PubMed query, for example: (emotional numbing OR desensitization) AND moral development"],
                "max_results": ["type": "integer", "description": "How many papers to return, 1 to 10. Default 6."],
            ],
            "required": ["query"],
        ],
    ]

    /// The fields of one source, shared by save_references and write_lecture.
    static func sourceSchema(noteDescription: String) -> [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "url", "source", "kind", "year", "authors", "pmid", "note"],
            "properties": [
                "title": ["type": "string"],
                "url": ["type": "string",
                        "description": "The exact URL from the search results. For PubMed papers: https://pubmed.ncbi.nlm.nih.gov/<PMID>/"],
                "source": ["type": "string", "description": "The site, publication or journal."],
                "kind": ["type": "string", "enum": Reference.Kind.allCases.map(\.rawValue)],
                "year": ["type": "string", "description": "Year published, or empty if unknown."],
                "authors": ["type": "string", "description": "Authors, or empty if unknown."],
                "pmid": ["type": "string", "description": "The PubMed ID for papers from pubmed_search; otherwise empty."],
                "note": ["type": "string", "description": noteDescription],
            ],
        ]
    }
}
```

### `Pipeline/Lecture.swift`

```swift
import Foundation

/// The lecture lengths on offer, and what each one means in words, ElevenLabs
/// credits and searches.
enum LectureLength {
    static let options = [3, 5, 10, 15, 20]
    static let standard = 10

    /// Spoken English runs at about 150 words a minute.
    static func words(minutes: Int) -> Int { minutes * 150 }

    /// The longest a lecture should run: 10% over.
    static func maxWords(minutes: Int) -> Int { words(minutes: minutes) * 11 / 10 }

    /// ElevenLabs credits for speaking it, one per character. Lectures run
    /// about six characters a word (counting spaces and punctuation), and in
    /// live tests Claude wrote up to its 10% allowance, so about 1,000 a
    /// minute.
    static func characters(minutes: Int) -> Int { minutes * 1_000 }

    /// How many web searches Claude may run. Longer lectures cover more
    /// ground; PubMed searches are free and come on top.
    static func webSearches(minutes: Int) -> Int {
        switch minutes {
        case ..<5: return 4
        case ..<10: return 5
        case ..<15: return 7
        case ..<20: return 8
        default: return 10
        }
    }

    /// The offered length closest to the one asked for.
    static func nearest(to minutes: Int) -> Int {
        options.min { abs($0 - minutes) < abs($1 - minutes) } ?? standard
    }
}

/// "Give a lecture on the science of sleep", spotted in what you said or typed.
struct LectureRequest: Equatable {
    var topic: String
    /// The length you asked for ("a five-minute lecture"), if you said one.
    var minutes: Int?

    /// The request in `text`, when the text starts by asking for a lecture:
    /// "Give a lecture on…", "Can you give me a 5-minute lecture about…",
    /// "Lecture me on…". A thought that merely mentions a lecture isn't one.
    static func parse(_ text: String) -> LectureRequest? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range) else { return nil }
        func group(_ name: String) -> String? {
            Range(match.range(withName: name), in: text).map { String(text[$0]) }
        }
        var topic = group("topic") ?? group("topic2") ?? ""
        var minutes = group("length").flatMap(number) ?? group("size").map(sizeMinutes)

        // "…on jazz for about ten minutes": the length said at the end.
        let topicRange = NSRange(topic.startIndex..., in: topic)
        if let tail = trailingLength.firstMatch(in: topic, range: topicRange),
           let digits = Range(tail.range(withName: "length"), in: topic).flatMap({ number(String(topic[$0])) }),
           let whole = Range(tail.range, in: topic) {
            minutes = digits
            topic.removeSubrange(whole)
        }
        topic = topic.replacingOccurrences(of: #"^(?:(?:uh|um|er|erm|like|so)\b[\s,]*)+"#, with: "",
                                           options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—.!?…\"“”").union(.whitespacesAndNewlines))
        // "Give a lecture on" with nothing after it isn't a request yet.
        let prepositions: Set = ["on", "about", "regarding", "covering", "concerning", "explaining", "into", "of", "for"]
        guard topic.count >= 2, !prepositions.contains(topic.lowercased()) else { return nil }
        return LectureRequest(topic: topic, minutes: minutes)
    }

    private static let lead = #"""
        ^\s*(?:(?:hey|hi|ok|okay|so|um|uh|er|erm|well|alright|all\s+right|right|now)[\s,]+)*
        (?:pearl(?:\s+forge)?[\s,:]+)?(?:please[\s,]+)?
        """#

    private static let lengthWords = "one|two|three|four|five|six|seven|eight|nine|ten|twelve|fifteen|twenty|thirty"

    private static let pattern = try! NSRegularExpression(pattern: lead + #"""
        (?:
          (?:
            (?:(?:can|could|would|will)\s+you\s+(?:please\s+)?)?
            (?:give|do|make|write|prepare|create|deliver|record|play|read)\s+(?:(?:me|us)\s+)?
            | i\s*(?:want|need|would\s+like|['’]?d\s+like)\s+(?:to\s+hear\s+)?
          )
          (?:a|an|the)?\s*
          (?:(?<length>\d{1,2}|\#(lengthWords))[\s-]*min(?:ute)?s?(?:[\s-]+long)?\s+
            |(?<size>short|quick|brief|little|long|longer|full|detailed|in[\s-]depth|deep)\s+)?
          lecture\b
          (?:[\s,:;\-–—]+(?:on|about|regarding|covering|concerning|explaining|into|of|for)\b)?
          [\s,:;\-–—]*(?<topic>\S.*?)
        | lecture\s+(?:me|us)\s+(?:on|about)\s+(?<topic2>\S.*?)
        )
        [\s.!?…]*$
        """#, options: [.caseInsensitive, .dotMatchesLineSeparators, .allowCommentsAndWhitespace])

    private static let trailingLength = try! NSRegularExpression(pattern: #"""
        [\s,;\-–—]+(?:(?:for|lasting|taking|that['’]?s|that\s+is|of)\s+)?(?:(?:about|around|roughly|maybe)\s+)?
        (?<length>\d{1,2}|\#(lengthWords))[\s-]*min(?:ute)?s?(?:\s+long)?$
        """#, options: [.caseInsensitive, .allowCommentsAndWhitespace])

    private static func number(_ text: String) -> Int? {
        let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
                     "nine": 9, "ten": 10, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30]
        let value = Int(text) ?? words[text.lowercased()]
        return value.flatMap { $0 > 0 ? $0 : nil }
    }

    private static func sizeMinutes(_ size: String) -> Int {
        ["short", "quick", "brief", "little"].contains(size.lowercased()) ? 5 : 20
    }
}

/// Instructions for researching and writing a lecture.
enum LecturePrompt {
    static func system(minutes: Int, language: SpeechLanguage?) -> String {
        let languageRule = language.map {
            "- Write the lecture in \($0.name), the way a native speaker would, even when your sources are in other languages."
        } ?? "- Write the lecture in the language the request is in."
        return """
        You are Pearl Forge's lecture writer. Someone asked for a lecture on a topic. Research it, then write the lecture. It will be read aloud in their own cloned voice, so it should sound like them giving a clear, engaging talk.

        Research first, as much as you need to get the substance right:
        - Use pubmed_search when the topic touches on anything researchers study: health, medicine, the body, the mind, emotions, relationships, parenting, behaviour, learning, sleep or nutrition. Read the abstracts, and give more weight to systematic reviews, meta-analyses and large studies than to single small ones.
        - Use web search for background, history, context and the current state of understanding. Prefer universities, established publications, government and professional bodies, and respected writers over SEO content, product pages and forums.

        Then write the lecture and call write_lecture exactly once.

        The lecture:
        - About \(LectureLength.words(minutes: minutes)) words, which is about \(minutes) minutes spoken, and no more than \(LectureLength.maxWords(minutes: minutes)) words.
        - Written for the ear: plain, natural spoken sentences. No headings, lists, bullet points, tables, emoji, markdown, URLs or citation markers. Write numbers, dates and units the way they're said aloud.
        - Shaped like a good talk: open with why the topic matters, say briefly where you're going, take the main ideas in a sensible order with concrete examples, and close with a short recap of the key points.
        - Accurate and honest: every factual claim must come from your research. Say plainly where evidence is mixed, early or disputed, and never overstate certainty. Name sources in passing where it helps ("a 2019 review of 30 studies found…", "according to the CDC…"). Never invent studies, numbers, quotes or sources.
        - Spoken as the person giving the talk, in the first person where it's natural, but never invent experiences, credentials or stories for them.
        - Educational rather than personal advice. For health, legal or money topics, explain what's known and mention once that individual situations differ.
        \(languageRule)

        In write_lecture, list the sources the lecture actually draws on, using only items from your search results, with their exact URLs.
        """
    }

    static func user(topic: String) -> String {
        "Give a lecture on: \(topic)"
    }

    static let writeTool: [String: Any] = [
        "name": "write_lecture",
        "description": "Hand over the finished lecture. Call this exactly once, after researching.",
        "strict": true,
        "input_schema": [
            "type": "object",
            "additionalProperties": false,
            "required": ["title", "summary", "script", "sources"],
            "properties": [
                "title": ["type": "string", "description": "A short title for the lecture, at most eight words."],
                "summary": ["type": "string", "description": "One sentence on what the lecture covers."],
                "script": ["type": "string",
                           "description": "The whole lecture exactly as it should be spoken, with paragraphs separated by blank lines."],
                "sources": [
                    "type": "array",
                    "items": ResearchLoop.sourceSchema(noteDescription: "One sentence on what the lecture uses from this source."),
                ],
            ],
        ],
    ]
}

/// A researched lecture, ready to speak.
struct WrittenLecture {
    let title: String
    let summary: String
    let script: String
    /// The sources it draws on, each one checked against the search results.
    let references: [Reference]
    /// Sources Claude named that couldn't be matched to a search result.
    let unverified: Int
    let usage: ClaudeUsage
    /// The model that wrote it.
    let model: String
    /// What Claude charged, from the usage it reported; nil for a model whose
    /// prices Pearl Forge doesn't know.
    var cost: Double? { ClaudePrice.byModel[model].map { $0.cost(of: usage) } }
}

/// Researches a topic with Claude (the web and PubMed) and writes a lecture
/// about it, with its sources.
struct LectureWriter {
    let apiKey: String
    let workspaceID: String?
    let model: String

    func write(topic: String, minutes: Int, language: SpeechLanguage?,
               onProgress: (@MainActor (ResearchProgress) -> Void)? = nil) async throws -> WrittenLecture {
        let loop = ResearchLoop(apiKey: apiKey, workspaceID: workspaceID, model: model,
                                system: LecturePrompt.system(minutes: minutes, language: language),
                                finishTool: LecturePrompt.writeTool,
                                maxWebSearches: LectureLength.webSearches(minutes: minutes), maxSteps: 16,
                                failure: "The lecture failed",
                                nudge: "Please write the lecture now and call write_lecture with it.",
                                onProgress: onProgress)
        let outcome: ResearchLoop.Outcome
        do {
            outcome = try await loop.run(user: LecturePrompt.user(topic: topic))
        } catch let stop as ResearchLoop.Stop {
            let message = switch stop {
            case .refusal: "Claude declined to research this topic."
            case .cutOff: "The lecture ran longer than Claude can write in one go. Try a shorter length."
            case .unfinished: "Claude stopped before writing the lecture. Please try again."
            case .tooManySteps: "The research took too many steps. Please try again."
            }
            throw PipelineError(message: message)
        }
        func field(_ key: String) -> String {
            (outcome.input[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let script = Self.forSpeaking(field("script"))
        guard script.count >= 200 else {
            throw PipelineError(message: "The lecture came back empty. Please try again.")
        }
        let checked = ReferenceFinder.verify(outcome.input["sources"] as? [[String: Any]] ?? [],
                                             seenURLs: outcome.seenURLs, papers: outcome.papers)
        let title = field("title")
        return WrittenLecture(title: title.isEmpty ? topic.prefix(1).uppercased() + topic.dropFirst() : title,
                              summary: field("summary"), script: script, references: checked.references,
                              unverified: checked.unverified, usage: outcome.usage, model: outcome.answeredBy)
    }

    /// Drops any markdown that slipped in (headings, bold), which would
    /// otherwise be read out or trip up the voice.
    static func forSpeaking(_ script: String) -> String {
        script.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Forge {
    /// Researches and writes a lecture with the given Claude model.
    static func writeLecture(topic: String, minutes: Int, language: SpeechLanguage?, model: String,
                             onProgress: (@MainActor (ResearchProgress) -> Void)? = nil) async throws -> WrittenLecture {
        guard let key = KeychainStore.read(.anthropicKey) else {
            throw PipelineError(message: "Lectures are researched with Claude's web search. Add your Claude key in the AI tab first.")
        }
        return try await LectureWriter(apiKey: key, workspaceID: KeychainStore.read(.anthropicWorkspaceID), model: model)
            .write(topic: topic, minutes: minutes, language: language, onProgress: onProgress)
    }
}
```

### `Pipeline/Costs.swift`

```swift
import Foundation

/// What Claude calls used, as the API reports it, for working out what they
/// cost.
struct ClaudeUsage: Codable, Equatable {
    var input = 0
    var cacheWrite = 0
    var cacheRead = 0
    var output = 0
    var webSearches = 0

    /// Adds one response's "usage".
    mutating func add(_ usage: [String: Any]?) {
        guard let usage else { return }
        input += usage["input_tokens"] as? Int ?? 0
        cacheWrite += usage["cache_creation_input_tokens"] as? Int ?? 0
        cacheRead += usage["cache_read_input_tokens"] as? Int ?? 0
        output += usage["output_tokens"] as? Int ?? 0
        webSearches += (usage["server_tool_use"] as? [String: Any])?["web_search_requests"] as? Int ?? 0
    }
}

/// Anthropic's list prices in dollars per million tokens, from
/// platform.claude.com/docs/en/about-claude/pricing (October 2026).
struct ClaudePrice {
    let input: Double
    /// Writing to the 5-minute prompt cache.
    let cacheWrite: Double
    let cacheRead: Double
    let output: Double

    /// Web search is $10 per 1,000 searches, on top of the tokens it reads.
    static let perWebSearch = 0.01

    static let byModel: [String: ClaudePrice] = [
        "claude-opus-5-5": ClaudePrice(input: 4, cacheWrite: 5, cacheRead: 0.20, output: 20),
        "claude-sonnet-5-5": ClaudePrice(input: 2, cacheWrite: 2.50, cacheRead: 0.10, output: 10),
        "claude-fable-5-1": ClaudePrice(input: 10, cacheWrite: 12.50, cacheRead: 0.25, output: 50),
    ]

    func cost(of usage: ClaudeUsage) -> Double {
        let tokens = Double(usage.input) * input + Double(usage.cacheWrite) * cacheWrite
            + Double(usage.cacheRead) * cacheRead + Double(usage.output) * output
        return tokens / 1_000_000 + Double(usage.webSearches) * Self.perWebSearch
    }
}

/// Your ElevenLabs plan's credits. Speaking with Multilingual v2 uses one
/// credit per character.
struct VoiceCredits: Equatable {
    let tier: String
    let used: Int
    let limit: Int
    let resets: Date?

    var remaining: Int { max(0, limit - used) }

    /// Roughly what 1,000 credits are worth on this plan: its monthly price
    /// over its monthly credits (elevenlabs.io/pricing, October 2026). Nil on
    /// the free plan, where credits cost nothing.
    var dollarsPerThousand: Double? { Self.dollarsPerThousand(tier: tier) }

    static func dollarsPerThousand(tier: String?) -> Double? {
        let tier = tier?.lowercased() ?? ""
        if tier.hasPrefix("free") { return nil }
        if tier.hasPrefix("starter") { return 0.20 }                       // $6 for 30,000
        if ["pro", "scale", "business"].contains(where: tier.hasPrefix) { return 0.165 } // $99 for 600,000
        return 0.18                                                        // Creator: $22 for 121,000
    }
}

/// What a lecture should cost, worked out before anything is spent.
struct LectureEstimate: Equatable {
    /// Claude's research and writing. A range, because how much it reads
    /// varies from topic to topic.
    let claudeLow: Double
    let claudeHigh: Double
    /// The middle of the range before it was adjusted by past lectures. Saved
    /// with the lecture so later estimates can learn how far off it was.
    let claudeBase: Double
    /// ElevenLabs credits for speaking it: one per character.
    let credits: Int
    /// What those credits are worth on your plan.
    let voiceDollars: Double?
    /// How many of your past lectures adjusted the Claude estimate.
    let learnedFrom: Int

    var totalLow: Double { claudeLow + (voiceDollars ?? 0) }
    var totalHigh: Double { claudeHigh + (voiceDollars ?? 0) }

    /// Typical Claude usage for a lecture of a given length, from live runs
    /// with Claude Sonnet 5.5 (October 2026): a 5-minute lecture researched on
    /// PubMed alone used 11,000 tokens written to the cache, 12,000 read back
    /// and 3,600 out ($0.07); a 10-minute one with 5 web searches used 43,500,
    /// 31,000 and 6,100 ($0.22). Each web search adds what it read; the
    /// writing (and the thinking behind it) grows with the length.
    static func typicalUsage(minutes: Int) -> ClaudeUsage {
        let searches = Double(LectureLength.webSearches(minutes: minutes)) * 0.6
        let scriptTokens = Double(LectureLength.words(minutes: minutes)) * 1.4
        return ClaudeUsage(input: 50,
                           cacheWrite: Int(7_000 + searches * 6_500 + scriptTokens * 1.5),
                           cacheRead: Int(9_000 + searches * 4_500),
                           output: Int(1_000 + scriptTokens * 2.4),
                           webSearches: Int(searches.rounded()))
    }

    /// The estimate for a lecture. `pastRatios` are past lectures' actual
    /// Claude cost over their unadjusted estimate, newest first; they nudge
    /// this estimate toward what your lectures really cost.
    static func make(minutes: Int, model: String, credits: VoiceCredits?, pastRatios: [Double]) -> LectureEstimate? {
        guard let price = ClaudePrice.byModel[model] else { return nil }
        let base = price.cost(of: typicalUsage(minutes: minutes))
        let recent = pastRatios.prefix(5).sorted()
        let factor = recent.isEmpty ? 1 : min(4, max(0.25, recent[recent.count / 2]))
        let middle = base * factor
        // Wide until a few real lectures have shown how far off it runs.
        let (low, high) = recent.count >= 2 ? (0.75, 1.3) : (0.5, 1.5)
        let characters = LectureLength.characters(minutes: minutes)
        let rate = credits.map(\.dollarsPerThousand) ?? VoiceCredits.dollarsPerThousand(tier: nil)
        return LectureEstimate(claudeLow: middle * low, claudeHigh: middle * high, claudeBase: base,
                               credits: characters, voiceDollars: rate.map { Double(characters) / 1000 * $0 },
                               learnedFrom: recent.count)
    }
}

extension Double {
    /// "$0.27", "$1.60", or "under 1¢".
    var dollars: String {
        self < 0.01 ? "under 1¢" : formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }
}

/// "$0.20–0.45", or a single amount when both ends round the same.
func dollarRange(_ low: Double, _ high: Double) -> String {
    let lowText = low.dollars, highText = high.dollars
    guard lowText != highText else { return lowText }
    return lowText + "–" + highText.replacingOccurrences(of: "$", with: "")
}
```

## Appendix B — Reference implementations of the cloud calls and data model

How the iPhone app makes each call and saves each file. Port the behaviour; the language changes.

### `Pipeline/PipelineConfig.swift`

```swift
import Foundation

/// Endpoints, models, and limits for Pearl Forge's three cloud calls. The
/// defaults match the Pinokio build's pipeline.py.
enum PipelineConfig {
    // ElevenLabs: speech-to-text, text-to-speech, and the voice list.
    static let elevenLabsBase = URL(string: "https://api.elevenlabs.io/v1")!
    static let transcriptionModel = "scribe_v1"
    static let speechModel = "eleven_multilingual_v2"

    // Anthropic: the refinement step.
    static let anthropicBase = URL(string: "https://api.anthropic.com/v1")!
    static let anthropicVersion = "2023-06-01"
    static let refinementModel = "claude-opus-5-5"
    static let refinementMaxTokens = 16000

    /// ElevenLabs accepts long inputs, but splitting very long text keeps each
    /// request comfortable and lets us pass neighbouring text for prosody
    /// continuity.
    static let speechChunkCharacters = 2500

    /// Long recordings take a while to transcribe and refine.
    static let requestTimeout: TimeInterval = 900
}
```

### `Pipeline/PipelineHTTP.swift`

```swift
import Foundation

/// A failure in one of the cloud calls, worded for the person using the app.
struct PipelineError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

/// Shared request plumbing for the ElevenLabs and Anthropic clients.
enum PipelineHTTP {
    /// Sends the request and returns the body. HTTP errors become a
    /// PipelineError like "Could not list your voices (401): Invalid API key".
    static func send(_ request: URLRequest, failure: String) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status < 400 else {
            throw PipelineError(message: "\(failure) (\(status)): \(readableMessage(from: data))")
        }
        return data
    }

    /// Pulls the human-readable message out of an API error body, falling back
    /// to the start of the raw body.
    private static func readableMessage(from data: Data) -> String {
        var parsed = try? JSONSerialization.jsonObject(with: data)
        // Gemini sometimes wraps its error in a one-item list.
        if let list = parsed as? [Any], let first = list.first {
            parsed = first
        }
        if let json = parsed as? [String: Any] {
            // Anthropic: {"error": {"message": "..."}}
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            // ElevenLabs: {"detail": {"message": "..."}} or {"detail": "..."}
            if let detail = json["detail"] as? [String: Any], let message = detail["message"] as? String {
                return message
            }
            if let detail = json["detail"] as? String {
                return detail
            }
        }
        return String(decoding: data.prefix(500), as: UTF8.self)
    }
}

/// A multipart/form-data request body, for uploading the recording.
struct MultipartForm {
    private let boundary = "PearlForge-\(UUID().uuidString)"
    private var parts = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    /// The finished body, with the closing boundary.
    var body: Data {
        parts + Data("--\(boundary)--\r\n".utf8)
    }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        parts.append(data)
        append("\r\n")
    }

    private mutating func append(_ string: String) {
        parts.append(Data(string.utf8))
    }
}
```

### `Pipeline/ElevenLabsClient.swift`

```swift
import Foundation
import UniformTypeIdentifiers

/// A voice on the ElevenLabs account.
struct Voice: Identifiable, Hashable {
    let id: String
    let name: String
    /// ElevenLabs' category: "cloned", "professional", "generated", "premade", …
    let category: String?

    /// Voices the account owner made (clones and designed voices), as opposed
    /// to ElevenLabs' stock library.
    var isOwn: Bool {
        ["cloned", "professional", "generated"].contains(category ?? "")
    }
}

/// ElevenLabs calls: the voice list, speech-to-text (Scribe), and
/// text-to-speech in the chosen voice.
struct ElevenLabsClient {
    let apiKey: String

    // MARK: Voices

    /// The account's voices, its own voices first, then alphabetical.
    func listVoices() async throws -> [Voice] {
        var request = URLRequest(url: PipelineConfig.elevenLabsBase.appendingPathComponent("voices"),
                                 timeoutInterval: 60)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let data = try await PipelineHTTP.send(request, failure: "Could not list your voices")

        struct Response: Decodable {
            struct RawVoice: Decodable {
                let voiceID: String?
                let name: String?
                let category: String?

                enum CodingKeys: String, CodingKey {
                    case voiceID = "voice_id"
                    case name, category
                }
            }
            let voices: [RawVoice]?
        }

        let voices = try JSONDecoder().decode(Response.self, from: data).voices ?? []
        return voices
            .compactMap { raw -> Voice? in
                guard let id = raw.voiceID, !id.isEmpty else { return nil }
                return Voice(id: id, name: raw.name ?? "(unnamed voice)", category: raw.category)
            }
            .sorted { lhs, rhs in
                if lhs.isOwn != rhs.isOwn { return lhs.isOwn }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    // MARK: Credits

    /// Your plan and its credits this month. Needs a key that's allowed to
    /// read your account (ElevenLabs' "User" read permission).
    func credits() async throws -> VoiceCredits {
        var request = URLRequest(url: PipelineConfig.elevenLabsBase.appending(path: "user/subscription"),
                                 timeoutInterval: 60)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let data = try await PipelineHTTP.send(request, failure: "Could not read your ElevenLabs credits")

        struct Response: Decodable {
            let tier: String?
            let characterCount: Int?
            let characterLimit: Int?
            let nextCharacterCountResetUnix: Double?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        guard let used = response.characterCount, let limit = response.characterLimit else {
            throw PipelineError(message: "ElevenLabs didn't say how many credits you have.")
        }
        return VoiceCredits(tier: response.tier ?? "", used: used, limit: limit,
                            resets: response.nextCharacterCountResetUnix.map(Date.init(timeIntervalSince1970:)))
    }

    // MARK: Speech-to-text

    /// A faithful transcript of the recording at `fileURL`.
    func transcribe(audioAt fileURL: URL) async throws -> String {
        let mimeType = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
            ?? "application/octet-stream"
        var form = MultipartForm()
        form.addField("model_id", PipelineConfig.transcriptionModel)
        // Keep the transcript plain: no "(laughter)" style event tags, and no
        // speaker diarisation (this is one person thinking aloud).
        form.addField("tag_audio_events", "false")
        form.addField("diarize", "false")
        form.addFile("file", filename: fileURL.lastPathComponent, mimeType: mimeType,
                     data: try Data(contentsOf: fileURL))

        var request = URLRequest(url: PipelineConfig.elevenLabsBase.appendingPathComponent("speech-to-text"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.body
        let data = try await PipelineHTTP.send(request, failure: "Transcription failed")

        struct Response: Decodable { let text: String? }
        let text = (try JSONDecoder().decode(Response.self, from: data).text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PipelineError(message: "The transcription came back empty. Is the recording audible?")
        }
        return text
    }

    // MARK: Text-to-speech

    /// Speech for `text` in the given voice, as MP3 data. Long text is spoken
    /// in chunks, each told its neighbours so the delivery stays continuous.
    func synthesize(_ text: String, voiceID: String) async throws -> Data {
        guard !voiceID.isEmpty else {
            throw PipelineError(message: "No voice is selected. Pick your ElevenLabs voice in Settings first.")
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw PipelineError(message: "There is no text to turn into speech.")
        }

        let url = PipelineConfig.elevenLabsBase
            .appendingPathComponent("text-to-speech")
            .appendingPathComponent(voiceID)
        let chunks = Self.splitForSpeech(text)
        var audio = Data()
        for (index, chunk) in chunks.enumerated() {
            var body = ["text": chunk, "model_id": PipelineConfig.speechModel]
            // Pass neighbouring text so prosody stays continuous across chunks.
            if index > 0 { body["previous_text"] = chunks[index - 1] }
            if index < chunks.count - 1 { body["next_text"] = chunks[index + 1] }

            var request = URLRequest(url: url, timeoutInterval: PipelineConfig.requestTimeout)
            request.httpMethod = "POST"
            request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
            request.httpBody = try JSONEncoder().encode(body)
            audio.append(try await PipelineHTTP.send(request, failure: "Voice generation failed"))
        }
        return audio
    }

    /// Splits long text into chunks on paragraph, then sentence, boundaries.
    /// A straight port of the Pinokio build's _split_for_tts.
    static func splitForSpeech(_ text: String, limit: Int = PipelineConfig.speechChunkCharacters) -> [String] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > limit else { return [text] }

        var chunks: [String] = []
        var buffer = ""
        for piece in split(text, on: #"\n\s*\n"#) {
            let sentences = split(piece.trimmingCharacters(in: .whitespacesAndNewlines), on: #"(?<=[.!?])\s+"#)
            for sentence in sentences where !sentence.isEmpty {
                if buffer.count + sentence.count + 1 > limit && !buffer.isEmpty {
                    chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                    buffer = ""
                }
                buffer = (buffer + " " + sentence).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !buffer.isEmpty {
                chunks.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer = ""
            }
        }
        let nonEmpty = chunks.filter { !$0.isEmpty }
        return nonEmpty.isEmpty ? [text] : nonEmpty
    }

    /// Like Python's re.split: the pieces between matches, empty ones included.
    private static func split(_ text: String, on pattern: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var pieces: [String] = []
        var start = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            pieces.append(ns.substring(with: NSRange(location: start, length: match.range.location - start)))
            start = match.range.location + match.range.length
        }
        pieces.append(ns.substring(from: start))
        return pieces
    }
}
```

### `Pipeline/AnthropicClient.swift`

```swift
import Foundation

/// Anthropic calls: the model list and the meaning-preserving refinement.
struct AnthropicClient {
    let apiKey: String
    /// Sent as "anthropic-workspace-id" when the key is organization-scoped.
    let workspaceID: String?

    /// Models whose safety checks can hand a declined request to Anthropic's
    /// recommended fallback model.
    static let fallbackModels: Set<String> = [
        "claude-fable-5-1", "claude-fable-5", "claude-mythos-5-1",
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
    ]

    /// Models that think only when asked; newer ones think by default.
    static let adaptiveThinkingModels = ["claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-sonnet-4-6"]

    /// Your account's Claude models, newest first. Listing models is free; no
    /// tokens are spent, so this doubles as the key check.
    func listModels() async throws -> [AIModel] {
        var components = URLComponents(url: PipelineConfig.anthropicBase.appendingPathComponent("models"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: "1000")]
        var request = URLRequest(url: components.url!, timeoutInterval: 60)
        applyHeaders(to: &request)
        let data = try await PipelineHTTP.send(request, failure: "Your Anthropic key didn't work")

        struct List: Decodable {
            struct Item: Decodable {
                let id: String
                let displayName: String?
                let createdAt: String?
            }
            let data: [Item]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        return (try decoder.decode(List.self, from: data).data ?? [])
            .map { AIModel(id: $0.id, name: $0.displayName ?? $0.id, created: $0.createdAt.flatMap(iso.date)) }
            .sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
    }

    /// Improves how clearly the transcript is expressed without changing what
    /// it says, following the given polishing instructions.
    func refine(_ transcript: String, system: String, model: String) async throws -> Refinement {
        let reply = try await complete(system: system, user: transcript, model: model,
                                       failure: "Refinement failed")
        if reply.stopReason == "refusal" {
            throw PipelineError(message: "Claude declined to refine this recording. Try again, or try a different mode.")
        }
        // A cut-off refinement would silently drop the end of your thought.
        if reply.stopReason == "max_tokens" {
            throw PipelineError(message: "The refined version was cut off before the end. The recording may be too long for one pass; try Summarize or a shorter recording.")
        }
        guard !reply.text.isEmpty else {
            throw PipelineError(message: "The refinement came back empty. Please try again.")
        }
        return Refinement(text: reply.text, provider: .anthropic, model: reply.model)
    }

    /// One system prompt and one user message; returns the visible reply.
    func complete(system: String, user: String, model: String,
                  failure: String = "Claude request failed") async throws -> Completion {
        var request = URLRequest(url: PipelineConfig.anthropicBase.appendingPathComponent("messages"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let usesFallback = Self.fallbackModels.contains(model)
        if usesFallback {
            // If a safety check declines the request, Anthropic re-runs it on
            // its recommended fallback model instead of returning a refusal.
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }

        struct Body: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            struct Thinking: Encodable { let type: String }
            let model: String
            let maxTokens: Int
            let system: String
            let messages: [Message]
            let fallbacks: String?
            let thinking: Thinking?
        }
        // On current models leaving out `thinking` runs adaptive thinking,
        // which helps with the careful meaning-preservation judgement; older
        // ones are asked for it. Only the visible text is read back out.
        let body = Body(model: model,
                        maxTokens: PipelineConfig.refinementMaxTokens,
                        system: system,
                        messages: [.init(role: "user", content: user)],
                        fallbacks: usesFallback ? "default" : nil,
                        thinking: Self.adaptiveThinkingModels.contains(model) ? .init(type: "adaptive") : nil)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let data = try await PipelineHTTP.send(request, failure: failure)

        struct Response: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let model: String?
            let content: [Block]?
            let stopReason: String?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        let text = (response.content ?? [])
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Completion(text: text, model: response.model ?? model, stopReason: response.stopReason)
    }

    func applyHeaders(to request: inout URLRequest) {
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(PipelineConfig.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if let workspaceID, !workspaceID.isEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }
    }
}
```

### `Pipeline/OpenAICompatibleClient.swift`

```swift
import Foundation

/// Calls to services that speak OpenAI's chat format: OpenAI itself, Google
/// Gemini, and OpenRouter.
struct OpenAICompatibleClient {
    let provider: PolisherProvider
    let apiKey: String

    // MARK: Models

    /// The service's chat models, newest first.
    func listModels() async throws -> [AIModel] {
        var request = URLRequest(url: provider.compatibleBase.appendingPathComponent("models"), timeoutInterval: 60)
        applyHeaders(to: &request)
        let data = try await PipelineHTTP.send(request, failure: "Your \(provider.name) key didn't work")

        struct List: Decodable {
            struct Item: Decodable {
                struct Architecture: Decodable { let outputModalities: [String]? }
                let id: String
                let name: String?
                let created: Double?
                let architecture: Architecture?
            }
            let data: [Item]?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let items = try decoder.decode(List.self, from: data).data ?? []

        return items.compactMap { item -> AIModel? in
            // Gemini lists ids as "models/gemini-…".
            let id = item.id.hasPrefix("models/") ? String(item.id.dropFirst("models/".count)) : item.id
            guard isChatModel(id, outputs: item.architecture?.outputModalities) else { return nil }
            return AIModel(id: id, name: item.name ?? id,
                           created: item.created.map { Date(timeIntervalSince1970: $0) })
        }
        .sorted { lhs, rhs in
            switch (lhs.created, rhs.created) {
            case let (l?, r?) where l != r: return l > r
            default: return lhs.id.localizedStandardCompare(rhs.id) == .orderedDescending
            }
        }
    }

    /// Confirms the key works. OpenRouter lists its models without a key, so
    /// its key is checked separately.
    func checkKey() async throws {
        guard provider == .openrouter else {
            _ = try await listModels()
            return
        }
        var request = URLRequest(url: provider.compatibleBase.appendingPathComponent("key"), timeoutInterval: 60)
        applyHeaders(to: &request)
        _ = try await PipelineHTTP.send(request, failure: "Your OpenRouter key didn't work")
    }

    /// Leaves out models that can't write text replies (images, speech,
    /// embeddings, …), so the list is just the ones that can polish.
    private func isChatModel(_ id: String, outputs: [String]?) -> Bool {
        let lower = id.lowercased()
        switch provider {
        case .openai:
            let families = ["gpt-", "chatgpt-", "o1", "o3", "o4", "o5"]
            let excluded = ["audio", "realtime", "tts", "transcribe", "image", "search", "embedding",
                            "instruct", "moderation", "codex", "dall-e", "whisper", "computer-use",
                            "deep-research", "babbage", "davinci"]
            let datedSnapshot = lower.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
            return families.contains { lower.hasPrefix($0) }
                && !excluded.contains { lower.contains($0) }
                && !datedSnapshot
        case .gemini:
            let excluded = ["embedding", "image", "tts", "live", "audio", "veo", "imagen", "aqa"]
            return (lower.contains("gemini") || lower.contains("gemma")) && !excluded.contains { lower.contains($0) }
        case .openrouter:
            return outputs?.contains("text") ?? true
        case .anthropic:
            return true
        }
    }

    // MARK: Polishing

    /// Sends the polishing instructions and transcript, and returns the reply.
    func refine(_ transcript: String, system: String, model: String) async throws -> Refinement {
        let reply = try await complete(system: system, user: transcript, model: model,
                                       failure: "Polishing with \(provider.name) failed")
        if reply.stopReason == "refusal" {
            throw PipelineError(message: "\(provider.name) declined to polish this recording. Try again, or try a different AI.")
        }
        // A cut-off refinement would silently drop the end of your thought.
        if reply.stopReason == "length" {
            throw PipelineError(message: "The polished version was cut off before the end. The recording may be too long for this model; try Summarize, a shorter recording, or a different model.")
        }
        guard !reply.text.isEmpty else {
            throw PipelineError(message: "The polished version came back empty. Please try again.")
        }
        return Refinement(text: reply.text, provider: provider, model: reply.model)
    }

    /// One system message and one user message; returns the reply. A refusal
    /// is reported as the stop reason "refusal".
    func complete(system: String, user: String, model: String,
                  failure: String? = nil) async throws -> Completion {
        let failure = failure ?? "\(provider.name) request failed"
        var request = URLRequest(url: provider.compatibleBase.appendingPathComponent("chat/completions"),
                                 timeoutInterval: PipelineConfig.requestTimeout)
        request.httpMethod = "POST"
        applyHeaders(to: &request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Body: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let messages: [Message]
        }
        // No length limit is sent: each model's own maximum applies, so a
        // long recording isn't cut short.
        request.httpBody = try JSONEncoder().encode(Body(model: model, messages: [
            .init(role: "system", content: system),
            .init(role: "user", content: user),
        ]))

        let data = try await PipelineHTTP.send(request, failure: failure)

        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: FlexibleText?
                    let refusal: String?
                }
                let message: Message?
                let finishReason: String?
            }
            struct APIError: Decodable { let message: String? }
            let model: String?
            let choices: [Choice]?
            let error: APIError?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)

        guard let choice = response.choices?.first else {
            throw PipelineError(message: "\(failure): \(response.error?.message ?? "no reply came back.")")
        }
        let refused = choice.message?.refusal?.isEmpty == false || choice.finishReason == "content_filter"
        return Completion(text: Refinement.strippingThinking(choice.message?.content?.text ?? ""),
                          model: response.model ?? model,
                          stopReason: refused ? "refusal" : choice.finishReason)
    }

    private func applyHeaders(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if provider == .openrouter {
            // Labels the usage in your OpenRouter activity list.
            request.setValue("Pearl Forge", forHTTPHeaderField: "X-Title")
        }
    }
}

/// Message text that arrives either as a plain string or as a list of parts.
struct FlexibleText: Decodable {
    let text: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            text = string
        } else {
            struct Part: Decodable { let text: String? }
            text = ((try? container.decode([Part].self)) ?? []).compactMap(\.text).joined()
        }
    }
}
```

### `Pipeline/Polisher.swift`

```swift
import Foundation

/// The AI services that can polish a transcript.
enum PolisherProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case openai
    case gemini
    case openrouter

    var id: String { rawValue }

    var name: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "ChatGPT"
        case .gemini: return "Gemini"
        case .openrouter: return "OpenRouter"
        }
    }

    var company: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google"
        case .openrouter: return "Hundreds of models, one key"
        }
    }

    var credential: Credential {
        switch self {
        case .anthropic: return .anthropicKey
        case .openai: return .openAIKey
        case .gemini: return .geminiKey
        case .openrouter: return .openRouterKey
        }
    }

    var keysPageLabel: String {
        switch self {
        case .anthropic: return "Get your key at console.anthropic.com"
        case .openai: return "Get your key at platform.openai.com"
        case .gemini: return "Get your key at aistudio.google.com"
        case .openrouter: return "Get your key at openrouter.ai"
        }
    }

    var keysPage: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .openrouter: return URL(string: "https://openrouter.ai/settings/keys")!
        }
    }

    /// The service's OpenAI-compatible endpoint (Claude uses its own API).
    var compatibleBase: URL {
        switch self {
        case .anthropic: return PipelineConfig.anthropicBase
        case .openai: return URL(string: "https://api.openai.com/v1")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        case .openrouter: return URL(string: "https://openrouter.ai/api/v1")!
        }
    }

    /// The model used until you choose one.
    var defaultModel: String? {
        self == .anthropic ? PipelineConfig.refinementModel : nil
    }

    /// One line about the service for its setup page.
    var about: String {
        switch self {
        case .anthropic:
            return "Claude is what Pearl Forge was designed around. It's the default."
        case .openai:
            return "OpenAI's models, billed to your OpenAI API account (separate from a ChatGPT subscription)."
        case .gemini:
            return "Google's models, billed to your Google AI Studio account. AI Studio has a free tier."
        case .openrouter:
            return "One key and one bill for models from many companies, including Claude, GPT, Gemini, Llama, Mistral, DeepSeek and Grok."
        }
    }
}

/// A service and one of its models: who polishes a pearl.
struct PolisherChoice: Hashable {
    let provider: PolisherProvider
    let model: String
}

/// A model a service offers.
struct AIModel: Identifiable, Hashable {
    let id: String
    let name: String
    let created: Date?
}

/// The polished text, and which service and model actually wrote it (the
/// model can differ from the one requested when Anthropic's fallback
/// stepped in).
struct Refinement {
    let text: String
    let provider: PolisherProvider
    let model: String
}

/// A plain reply from any AI service.
struct Completion {
    let text: String
    let model: String
    /// Why the reply ended: "end_turn"/"stop" normally, "refusal", or
    /// "max_tokens"/"length" when cut off.
    let stopReason: String?

    var wasCutOff: Bool { stopReason == "max_tokens" || stopReason == "length" }
}

extension Refinement {
    /// Removes a leading <think>…</think> block some open models put before
    /// their answer.
    static func strippingThinking(_ text: String) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<think>"), let end = text.range(of: "</think>") {
            text = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
```

### `Pipeline/PubMedClient.swift`

```swift
import Foundation

/// A paper found on PubMed.
struct PubMedPaper: Codable, Equatable {
    var pmid: String
    var title = ""
    var journal = ""
    var year = ""
    var authors: [String] = []
    var abstract = ""
    var doi: String?

    var url: String { "https://pubmed.ncbi.nlm.nih.gov/\(pmid)/" }

    /// "Smith J, Lee K, et al."
    var authorLine: String {
        authors.count > 3 ? authors.prefix(3).joined(separator: ", ") + ", et al." : authors.joined(separator: ", ")
    }
}

/// Searches PubMed through the National Library of Medicine's free E-utilities
/// service. No key is needed.
enum PubMedClient {
    private static let base = URL(string: "https://eutils.ncbi.nlm.nih.gov/entrez/eutils")!

    /// The most relevant papers for a PubMed query, with their abstracts.
    static func search(_ query: String, maxResults: Int = 6) async throws -> [PubMedPaper] {
        let ids = try await searchIDs(query, maxResults: max(1, min(maxResults, 10)))
        guard !ids.isEmpty else { return [] }
        return try await fetch(ids)
    }

    private static func searchIDs(_ query: String, maxResults: Int) async throws -> [String] {
        var components = URLComponents(url: base.appendingPathComponent("esearch.fcgi"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "term", value: query),
            URLQueryItem(name: "retmax", value: String(maxResults)),
            URLQueryItem(name: "sort", value: "relevance"),
            URLQueryItem(name: "retmode", value: "json"),
            URLQueryItem(name: "tool", value: "PearlForge"),
        ]
        let data = try await PipelineHTTP.send(URLRequest(url: components.url!, timeoutInterval: 60),
                                               failure: "PubMed search failed")
        struct Response: Decodable {
            struct Result: Decodable { let idlist: [String]? }
            let esearchresult: Result?
        }
        return try JSONDecoder().decode(Response.self, from: data).esearchresult?.idlist ?? []
    }

    private static func fetch(_ ids: [String]) async throws -> [PubMedPaper] {
        var components = URLComponents(url: base.appendingPathComponent("efetch.fcgi"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "db", value: "pubmed"),
            URLQueryItem(name: "id", value: ids.joined(separator: ",")),
            URLQueryItem(name: "rettype", value: "abstract"),
            URLQueryItem(name: "retmode", value: "xml"),
            URLQueryItem(name: "tool", value: "PearlForge"),
        ]
        let data = try await PipelineHTTP.send(URLRequest(url: components.url!, timeoutInterval: 60),
                                               failure: "PubMed lookup failed")
        let papers = PubMedXMLParser.parse(data)
        // Keep PubMed's relevance order.
        return ids.compactMap { id in papers.first { $0.pmid == id } }
    }
}

/// Reads the parts of PubMed's article XML that Pearl Forge shows.
final class PubMedXMLParser: NSObject, XMLParserDelegate {
    private var papers: [PubMedPaper] = []
    private var current: PubMedPaper?
    private var path: [String] = []
    /// The text inside each open element; inline markup like <i> inside an
    /// abstract is folded into its parent.
    private var texts: [String] = []
    private var lastName = ""
    private var initials = ""
    private var articleIDType = ""

    static func parse(_ data: Data) -> [PubMedPaper] {
        let delegate = PubMedXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.papers
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        path.append(element)
        texts.append("")
        switch element {
        case "PubmedArticle": current = PubMedPaper(pmid: "")
        case "Author": lastName = ""; initials = ""
        case "ArticleId": articleIDType = attributes["IdType"] ?? ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if !texts.isEmpty { texts[texts.count - 1] += string }
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let raw = texts.removeLast()
        if !texts.isEmpty { texts[texts.count - 1] += raw }
        defer { path.removeLast() }
        guard current != nil else { return }
        let value = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let parent = path.dropLast().last ?? ""
        switch element {
        case "PMID" where parent == "MedlineCitation" && current!.pmid.isEmpty:
            current!.pmid = value
        case "ArticleTitle":
            current!.title = value
        case "Title" where parent == "Journal":
            current!.journal = value
        case "Year" where parent == "PubDate":
            current!.year = value
        case "MedlineDate" where parent == "PubDate" && current!.year.isEmpty:
            current!.year = String(value.prefix(4))
        case "AbstractText":
            current!.abstract += (current!.abstract.isEmpty ? "" : " ") + value
        case "LastName": lastName = value
        case "Initials": initials = value
        case "Author" where !lastName.isEmpty:
            current!.authors.append(initials.isEmpty ? lastName : "\(lastName) \(initials)")
        case "ArticleId" where articleIDType == "doi" && current!.doi == nil:
            current!.doi = value
        case "PubmedArticle":
            if !current!.pmid.isEmpty { papers.append(current!) }
            current = nil
        default:
            break
        }
    }
}
```

### `Recordings/RecordingFiles.swift`

```swift
import Foundation

/// One run of a recording through the forge: a refinement (with the mode and
/// any request you gave) and that refinement spoken in your voice.
struct Pearl: Codable, Identifiable, Equatable {
    var id: UUID
    var number: Int
    var created: Date
    var mode: RefinementMode
    /// What you asked to be different for this version, if anything.
    var notes: String?
    /// The model that wrote it; differs from the requested model only when
    /// Anthropic's fallback stepped in.
    var refinedBy: String?
    /// The AI service that wrote it ("anthropic", "openai", …).
    var polisher: String?
    var voiceID: String?
    var textFile: String
    var audioFile: String?

    enum CodingKeys: String, CodingKey {
        case id, number, created, mode, notes, polisher
        case refinedBy = "refined_by"
        case voiceID = "voice_id"
        case textFile = "text_file"
        case audioFile = "audio_file"
    }

    /// "pearl-02-tighten", the start of a pearl's file names.
    static func baseName(number: Int, mode: RefinementMode) -> String {
        "pearl-\(String(format: "%02d", number))-\(mode.rawValue)"
    }
}

/// A piece of reading found for a recording: a research paper, essay,
/// article or blog post that relates to the thought.
struct Reference: Codable, Identifiable, Equatable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case research, article, essay, blog, book, other

        var title: String {
            switch self {
            case .research: return "Research"
            case .article: return "Article"
            case .essay: return "Essay"
            case .blog: return "Blog post"
            case .book: return "Book"
            case .other: return "Other"
            }
        }

        var symbol: String {
            switch self {
            case .research: return "graduationcap"
            case .article: return "newspaper"
            case .essay: return "text.book.closed"
            case .blog: return "text.bubble"
            case .book: return "book"
            case .other: return "link"
            }
        }
    }

    var id: UUID
    var title: String
    var url: String
    /// The site or journal: "The Atlantic", "JAMA Pediatrics".
    var source: String
    var kind: Kind
    var year: String?
    var authors: String?
    /// How it relates to the thought, in a sentence or two.
    var note: String
    /// The PubMed id, for papers found through PubMed.
    var pmid: String?
    var found: Date
}

/// What a lecture was asked for, and what it cost.
struct LectureInfo: Codable, Equatable {
    var topic: String
    /// The length asked for, in minutes.
    var minutes: Int
    /// The Claude model that researched and wrote it.
    var model: String
    /// The language it was written in, when you chose one.
    var language: String?
    /// One sentence on what it covers.
    var summary: String?
    /// What Claude charged, worked out from the usage it reported.
    var claudeCost: Double?
    /// Claude's estimate before it started (unadjusted), so later estimates
    /// can learn how far off it runs.
    var estimatedClaudeCost: Double?
    var webSearches: Int?
    /// Characters in the spoken text: the ElevenLabs credits it used.
    var characters: Int?
    /// What 1,000 credits were worth on your ElevenLabs plan at the time.
    var dollarsPerThousandCredits: Double?

    /// What speaking it cost, when your plan's rate is known.
    var voiceCost: Double? {
        guard let characters, let rate = dollarsPerThousandCredits else { return nil }
        return Double(characters) / 1000 * rate
    }

    enum CodingKeys: String, CodingKey {
        case topic, minutes, model, language, summary, characters
        case claudeCost = "claude_cost"
        case estimatedClaudeCost = "estimated_claude_cost"
        case webSearches = "web_searches"
        case dollarsPerThousandCredits = "dollars_per_thousand_credits"
    }
}

/// The details saved alongside each recording as meta.json.
struct RecordingMeta: Codable, Equatable {
    var title: String
    var created: Date
    var originalFile: String?
    var favorite: Bool
    var pearls: [Pearl]
    /// Broad topics such as "Relationships" or "Work & Career". Nil until the
    /// recording has been sorted.
    var categories: [String]?
    /// One first-person sentence summing up the thought.
    var gist: String?
    var references: [Reference]
    /// True for text you typed rather than recorded; it has no original audio.
    var typed: Bool?
    /// Set for a lecture you asked for; its pearl is the lecture itself.
    var lecture: LectureInfo?

    var isTyped: Bool { typed == true }

    init(title: String, created: Date, originalFile: String?, favorite: Bool, pearls: [Pearl],
         categories: [String]? = nil, gist: String? = nil, references: [Reference] = [], typed: Bool? = nil,
         lecture: LectureInfo? = nil) {
        self.typed = typed
        self.lecture = lecture
        self.title = title
        self.created = created
        self.originalFile = originalFile
        self.favorite = favorite
        self.pearls = pearls
        self.categories = categories
        self.gist = gist
        self.references = references
    }

    enum CodingKeys: String, CodingKey {
        case title, created, favorite, pearls, categories, gist, references, typed, lecture
        case originalFile = "original_file"
        // The first version saved one refinement per recording at the top level.
        case mode
        case voiceID = "voice_id"
        case outputFile = "output_file"
        case refinedBy = "refined_by"
    }

    /// The fixed id given to the single refinement of a first-version recording.
    static let legacyPearlID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        created = try container.decode(Date.self, forKey: .created)
        originalFile = try container.decodeIfPresent(String.self, forKey: .originalFile)
        favorite = try container.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        categories = try container.decodeIfPresent([String].self, forKey: .categories)
        gist = try container.decodeIfPresent(String.self, forKey: .gist)
        references = try container.decodeIfPresent([Reference].self, forKey: .references) ?? []
        typed = try container.decodeIfPresent(Bool.self, forKey: .typed)
        lecture = try container.decodeIfPresent(LectureInfo.self, forKey: .lecture)
        if let pearls = try container.decodeIfPresent([Pearl].self, forKey: .pearls) {
            self.pearls = pearls
        } else {
            // A first-version recording: its one refinement becomes pearl 1.
            pearls = [Pearl(id: Self.legacyPearlID,
                            number: 1,
                            created: created,
                            mode: try container.decodeIfPresent(RefinementMode.self, forKey: .mode) ?? .clean,
                            notes: nil,
                            refinedBy: try container.decodeIfPresent(String.self, forKey: .refinedBy),
                            polisher: PolisherProvider.anthropic.rawValue,
                            voiceID: try container.decodeIfPresent(String.self, forKey: .voiceID),
                            textFile: "refined_transcript.txt",
                            audioFile: try container.decodeIfPresent(String.self, forKey: .outputFile))]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(created, forKey: .created)
        try container.encodeIfPresent(originalFile, forKey: .originalFile)
        try container.encode(favorite, forKey: .favorite)
        try container.encode(pearls, forKey: .pearls)
        try container.encodeIfPresent(categories, forKey: .categories)
        try container.encodeIfPresent(gist, forKey: .gist)
        try container.encode(references, forKey: .references)
        try container.encodeIfPresent(typed, forKey: .typed)
        try container.encodeIfPresent(lecture, forKey: .lecture)
    }
}

/// A saved recording with its texts. The app keeps a copy of these so History
/// opens instantly and works offline; only audio is fetched on demand.
struct RecordingEntry: Codable, Identifiable, Equatable {
    var folderName: String
    var meta: RecordingMeta
    var transcript: String
    var pearlTexts: [UUID: String]

    var id: String { folderName }

    /// Newest pearl first.
    var pearlsNewestFirst: [Pearl] {
        meta.pearls.sorted { $0.number > $1.number }
    }

    func pearl(_ id: UUID) -> Pearl? {
        meta.pearls.first { $0.id == id }
    }

    /// The newest pearl that has audio, for playing a recording in a list.
    var latestSpokenPearl: Pearl? {
        pearlsNewestFirst.first { $0.audioFile != nil }
    }

    /// The newest pearl's text, or what you said if there's no pearl yet.
    var latestText: String {
        pearlsNewestFirst.first.flatMap { pearlTexts[$0.id] } ?? transcript
    }
}

/// How a recording is laid out on disk. Each recording has its own folder:
///
///     2026-10-15_143012_I_think_theres_a_decent/
///     ├── original.m4a               the unmodified recording
///     ├── original_transcript.txt    what you actually said
///     ├── pearl-01-clean.txt         each run through the forge…
///     ├── pearl-01-clean.mp3         …and that run in your voice
///     ├── pearl-02-tighten.txt
///     ├── pearl-02-tighten.mp3
///     └── meta.json
enum RecordingFiles {
    static let originalTranscriptName = "original_transcript.txt"
    static let metaName = "meta.json"

    /// A new recording's folder name, from its date and the first words of
    /// its first refinement.
    static func folderName(created: Date, refined: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return "\(formatter.string(from: created))_\(slug(refined))"
    }

    /// The first few words, letters and digits only, joined with underscores:
    /// "I_think_theres_a_decent". A port of the Pinokio build's _slug.
    static func slug(_ text: String, words: Int = 6, maxLength: Int = 40) -> String {
        let firstWords = text.split(whereSeparator: \.isWhitespace).prefix(words).joined(separator: " ")
        let kept = firstWords.filter { $0 == " " || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
        let joined = kept.split(separator: " ").joined(separator: "_")
        let slug = String(joined.prefix(maxLength))
        return slug.isEmpty ? "note" : slug
    }

    /// The first line of the refined text, as the Pinokio build titled them.
    static func title(for refined: String) -> String {
        String((refined.split(separator: "\n").first ?? "").prefix(80))
    }

    static func encodeMeta(_ meta: RecordingMeta) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(meta)
    }

    static func decodeMeta(_ data: Data) throws -> RecordingMeta {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RecordingMeta.self, from: data)
    }

    /// A temporary copy of a pearl's audio named after the recording, for
    /// sharing: "I suspect emotional desensitization… – pearl 2.mp3".
    static func shareCopy(of audio: Data, title: String, pearlNumber: Int) throws -> URL {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines)
        let cleaned = title.components(separatedBy: unsafe).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
        let name = "\(cleaned.isEmpty ? "Pearl Forge" : String(cleaned.prefix(60))) – pearl \(pearlNumber).mp3"
        let url = URL.temporaryDirectory.appending(path: name)
        try audio.write(to: url, options: .atomic)
        return url
    }
}
```

## Appendix C — Example meta.json files

Generated by the iPhone app's own code. A recorded thought with two pearls, topics and a reference:

```json
{
  "categories" : [
    "Personal Growth",
    "Mind & Emotions"
  ],
  "created" : "2026-10-24T14:30:12Z",
  "favorite" : true,
  "gist" : "I'm wondering whether I put things off to avoid feeling bad.",
  "original_file" : "original.m4a",
  "pearls" : [
    {
      "audio_file" : "pearl-01-clean.mp3",
      "created" : "2026-10-24T14:30:12Z",
      "id" : "6F1C2B9E-2D4A-4C61-9B0E-1A2B3C4D5E6F",
      "mode" : "clean",
      "number" : 1,
      "polisher" : "anthropic",
      "refined_by" : "claude-opus-5-5",
      "text_file" : "pearl-01-clean.txt",
      "voice_id" : "VOICE_ID"
    },
    {
      "audio_file" : "pearl-02-tighten.mp3",
      "created" : "2026-10-24T14:40:12Z",
      "id" : "0A9B8C7D-6E5F-4A3B-8C2D-1E0F9A8B7C6D",
      "mode" : "tighten",
      "notes" : "Say it in Italian, the way a native speaker would. keep the bridge analogy",
      "number" : 2,
      "polisher" : "openai",
      "refined_by" : "gpt-5.5",
      "text_file" : "pearl-02-tighten.txt",
      "voice_id" : "VOICE_ID"
    }
  ],
  "references" : [
    {
      "authors" : "Steel P",
      "found" : "2026-10-24T14:30:12Z",
      "id" : "11111111-2222-4333-8444-555555555555",
      "kind" : "research",
      "note" : "Links procrastination to impulsiveness and task aversiveness.",
      "pmid" : "17201571",
      "source" : "Psychological bulletin",
      "title" : "The nature of procrastination: a meta-analytic and theoretical review of quintessential self-regulatory failure.",
      "url" : "https://pubmed.ncbi.nlm.nih.gov/17201571/",
      "year" : "2007"
    }
  ],
  "title" : "I think there's a decent chance I procrastinate because"
}
```

A typed lecture request (`typed: true`, no `original_file`):

```json
{
  "categories" : [
    "Learning & Ideas"
  ],
  "created" : "2026-10-24T14:30:12Z",
  "favorite" : false,
  "gist" : "Why entanglement puzzled Einstein and what the experiments showed.",
  "lecture" : {
    "characters" : 9840,
    "claude_cost" : 0.21,
    "dollars_per_thousand_credits" : 0.18,
    "estimated_claude_cost" : 0.197,
    "minutes" : 10,
    "model" : "claude-sonnet-5-5",
    "summary" : "Why entanglement puzzled Einstein and what the experiments showed.",
    "topic" : "the strangeness of quantum entanglement",
    "web_searches" : 5
  },
  "pearls" : [
    {
      "audio_file" : "pearl-01-lecture.mp3",
      "created" : "2026-10-24T14:30:12Z",
      "id" : "22222222-3333-4444-8555-666666666666",
      "mode" : "lecture",
      "number" : 1,
      "polisher" : "anthropic",
      "refined_by" : "claude-sonnet-5-5",
      "text_file" : "pearl-01-lecture.txt",
      "voice_id" : "VOICE_ID"
    }
  ],
  "references" : [

  ],
  "title" : "The Strangeness of Quantum Entanglement",
  "typed" : true
}
```

Folder names for these: `2026-10-24_093012_I_think_theres_a_decent_chance` and `2026-10-24_093012_The_Strangeness_of_Quantum_Entanglement` (the time in a folder name is local: these examples were made on a computer five hours behind UTC).
