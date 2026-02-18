<p align="center">
  <img src="https://github.com/opentolk/opentolk/raw/main/Resources/AppIcon.png" width="128" height="128" alt="OpenTolk">
</p>

<h1 align="center">OpenTolk</h1>

<p align="center">
  <strong>Voice-first AI platform for macOS.</strong><br>
  Speak naturally. Your words become text, actions, or AI-powered workflows — instantly.
</p>

<p align="center">
  <a href="#install">Install</a> &bull;
  <a href="#how-it-works">How It Works</a> &bull;
  <a href="#plugins">Plugins</a> &bull;
  <a href="#build-from-source">Build</a> &bull;
  <a href="PLUGINS.md">Plugin Docs</a> &bull;
  <a href="https://github.com/opentolk/community-plugins">Community Plugins</a>
</p>

---

## What is OpenTolk?

OpenTolk lives in your menu bar. Press a hotkey, speak, and your words get transcribed and pasted into whatever app you're using — a text editor, Slack, your browser, anywhere.

But that's just the start. With **plugins**, your voice becomes a command layer for your entire Mac:

- Say **"translate this to Spanish"** — AI translates and pastes the result
- Say **"summarize"** — AI condenses your clipboard into key points
- Say **"research quantum computing"** — an AI agent searches the web and gives you a briefing
- Say **"proofread"** — fixes grammar and rephrases for clarity

Plugins are simple JSON files. The easiest plugin is **9 lines** — no code, no API keys, no setup. Just a system prompt.

---

## Install

### Download

Download the latest `.dmg` from [Releases](https://github.com/opentolk/opentolk/releases).

Requires **macOS 14 (Sonoma)** or later.

### Build from Source

```bash
git clone https://github.com/opentolk/opentolk.git
cd opentolk
bash build.sh
open OpenTolk.app
```

The build script compiles a release build, creates the `.app` bundle, and code-signs it.

---

## How It Works

1. **Press your hotkey** (Right Option by default)
2. **Speak** — OpenTolk records until you stop talking
3. **Text appears** in your active app, instantly

That's it for basic dictation. For power users, the plugin system intercepts transcribed text and routes it to the right handler before pasting.

### Recording Modes

| Mode | How | When to use |
|------|-----|-------------|
| **Tap** | Quick press, speak, auto-stops on silence | Natural dictation |
| **Hold** | Hold hotkey while speaking, release to stop | Precise control |

### Transcription Providers

| Provider | Setup | Limits | Languages |
|----------|-------|--------|-----------|
| **OpenTolk Cloud** | Sign in with Apple/Google | Free: 5k words/mo. Pro: Unlimited | Free: English. Pro: 99+ |
| **Groq** | Your API key | Unlimited | 99+ |
| **OpenAI Whisper** | Your API key | Unlimited | 99+ |
| **Local** | Nothing — runs on your Mac | Unlimited | 99+ |

Switch providers anytime in Settings. Local mode means zero data leaves your machine.

---

## Plugins

Plugins are what make OpenTolk more than a dictation tool. They turn your voice into a programmable interface.

### Your First Plugin

Save this as `~/.opentolk/plugins/translate.tolkplugin`:

```json
{
  "id": "com.opentolk.translate",
  "name": "Translate",
  "version": "1.0.0",
  "description": "Translates text to Spanish",
  "trigger": { "type": "keyword", "keywords": ["translate"], "position": "start", "strip_trigger": true },
  "execution": { "type": "ai", "system_prompt": "Translate to Spanish. Output only the translation." },
  "output": { "mode": "paste" }
}
```

Done. Say **"translate good morning everyone"** — OpenTolk strips the trigger word, sends "good morning everyone" to the AI, and pastes "buenos dias a todos" into your app.

No server. No deploy. No API key management per plugin. It just works.

### What Plugins Can Do

| Type | What it does | Example |
|------|-------------|---------|
| **AI** | Sends text to an LLM with a system prompt | Translate, summarize, rewrite, explain |
| **Script** | Runs a shell script (bash, python, node) | Word count, file operations, custom tools |
| **HTTP** | Calls any REST API | Weather, stock prices, webhooks |
| **Shortcut** | Runs a macOS Shortcut | Home automation, system actions |
| **Pipeline** | Chains multiple plugins together | Proofread → translate → paste |

### Trigger Types

| Trigger | How it matches | Latency |
|---------|---------------|---------|
| **Keyword** | Exact word at start/end/anywhere | Instant |
| **Regex** | Pattern matching | Instant |
| **Intent** | AI understands what you mean | ~200ms |
| **Catch-all** | Matches everything (fallback) | Instant |

Intent triggers are the magic — say "what's the weather like" or "is it going to rain" or "temperature outside" and the intent-based router figures out they all mean the same thing.

### Conversational Plugins

AI plugins can be **conversational** — they remember context across turns:

```json
{
  "execution": { "type": "ai", "system_prompt": "You are a helpful assistant.", "conversational": true, "streaming": true },
  "output": { "mode": "reply" }
}
```

This opens a floating chat panel with streaming responses. Ask follow-up questions. The AI remembers the conversation.

### AI Agent Plugins (Tool Use)

Plugins can use **tools** — web search, clipboard access, even calling other plugins:

```json
{
  "execution": {
    "type": "ai",
    "system_prompt": "You are a research assistant. Search the web and provide answers with sources.",
    "tools": [
      { "name": "web_search", "type": "builtin" },
      { "name": "read_clipboard", "type": "builtin" }
    ]
  }
}
```

For the full plugin reference, see **[PLUGINS.md](PLUGINS.md)**.

Browse and install community plugins from **[opentolk/community-plugins](https://github.com/opentolk/community-plugins)** — or directly from the Browse tab in the app.

---

## Snippets

Text expansion that triggers before plugins. Define a trigger phrase and its replacement:

| You say | OpenTolk types |
|---------|---------------|
| "my email" | ronny@example.com |
| "meeting template" | A full meeting notes template |
| "address" | Your full mailing address |

Manage snippets in Settings > Snippets.

---

## Pro Plan

OpenTolk is fully functional for free. The Pro plan adds:

| | Free | Pro |
|---|---|---|
| Cloud transcription | 5,000 words/month | Unlimited |
| Languages (cloud) | English | 99+ |
| Max recording | 30 seconds | 120 seconds |
| Settings sync | - | Across all Macs |
| Snippet sync | - | Across all Macs |
| History sync | - | Across all Macs |

**Using your own API key (Groq, OpenAI) or Local mode gives you unlimited everything for free.** Pro is for the cloud convenience.

---

## Settings

Right-click the menu bar icon or press the settings hotkey:

- **General** — Launch at login
- **Permissions** — Microphone, Accessibility
- **Transcription** — Provider, API keys, language
- **Audio** — Silence detection, max duration, input device
- **Hotkey** — Choose key, tap vs hold threshold
- **Snippets** — Text expansions
- **Plugins** — Installed, browse, updates
- **Account** — Sign in, subscription

---

## Architecture

```
~/.opentolk/
├── plugins/              # Your plugins live here
│   ├── translate.tolkplugin    # Single-file plugin (JSON)
│   └── research.tolkplugin/    # Directory plugin
│       ├── manifest.json
│       ├── tools/
│       └── icon.png
├── plugin-data/          # Plugin persistent storage
├── settings.json         # User preferences
├── snippets.json         # Text expansions
├── history.json          # Dictation history
└── usage.json            # Free tier tracking
```

The app is a native Swift menu bar app using SwiftUI. No Electron. No web views. It's fast, lightweight, and uses ~20MB of RAM.

---

## Contributing

We welcome contributions! Here's how to get started:

1. Fork the repo
2. Create a branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Run `bash build.sh` to verify it builds
5. Submit a PR

For plugin contributions, submit to [community-plugins](https://github.com/opentolk/community-plugins).

---

## License

MIT License. See [LICENSE](LICENSE).

---

<p align="center">
  <strong>OpenTolk is open source.</strong><br>
  Built for people who think faster than they type.
</p>
