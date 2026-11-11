# AgentPet

English · [한국어](README.ko.md)

**A macOS desktop companion that types, rests, and catches fire in step with the number of local AI agent tasks running.**

The default character is Clawd, and you can change the body, eye, and flame colors independently. With no tasks running it rests with its eyes closed; the busier things get, the bigger the smoke and flames.

| Default body | Default eyes | Default flame |
| --- | --- | --- |
| Orange | Black | Electric blue |

| 0 · Resting | 1–2 · Relaxed | 3–4 · Focused |
| :---: | :---: | :---: |
| ![0 sessions: Clawd resting with its eyes closed](docs/previews/sessions-00.gif) | ![1–2 sessions: typing at a relaxed pace](docs/previews/sessions-01-02.gif) | ![3–4 sessions: typing with focus](docs/previews/sessions-03-04.gif) |
| **5–6 · Smoke** | **7–9 · Flames** | **10 or more · Bigger flames** |
| ![5–6 sessions: fast typing and smoke](docs/previews/sessions-05-06.gif) | ![7–9 sessions: electric blue flames](docs/previews/sessions-07-09.gif) | ![10 or more sessions: larger flames and sparks in the same color](docs/previews/sessions-10-plus.gif) |

These are the actual animations in the default colors. When you change colors, the body shading and the bright core of the flames are kept.

## Installation

[Download the latest release](https://github.com/tinkerer0/agent_pet/releases/latest), unzip it, and run `AgentPet.app`.

The release ZIP includes the color settings, the motion threshold settings, and the connections for additional tools.

It is built for macOS 13 or later. It has been verified to run on Apple Silicon; on Intel it has only been verified to build. The distributed app is ad-hoc signed and is not notarized by Apple. If macOS blocks it from running, you can build it yourself.

If you have the Xcode Command Line Tools, you can build from the repository alone. The character assets are included.

```sh
git clone https://github.com/tinkerer0/agent_pet.git
cd agent_pet
bash scripts/build.sh
open dist/AgentPet.app
```

## Usage

- **Drag:** Move it. The position, size, and chosen colors are kept the next time you launch.
- **Right-click or menu bar:** Change colors and size, preview the stages, auto-detect, and quit.
- **Color… (색상…):** Pick the body, eyes, and flame separately; changes apply immediately. The color window shows only two pickers: a circular color wheel and the basic colored-pencil palette. "Restore default colors" (기본색으로 복원) returns to the original Clawd colors.
- **Motion thresholds… (모션 기준…):** Adjust the session counts at which the focused, smoke, flame, and bigger-flame stages begin. There are presets that show the bigger flames at 3, 5, or 10 sessions, and the settings are saved when you click "Apply" (적용). If two stages are set to the same count, the stronger motion is shown. 0 sessions is always the resting stage.
- **Transparent margins:** You can click through to the apps underneath.

These are the default settings. Even if you run only a few sessions, you can see the bigger flames by lowering the motion thresholds.

| Active sessions | Appearance |
| --- | --- |
| 0 | Resting with arms down and eyes closed · rising zzz |
| 1–2 | Typing at a relaxed pace |
| 3–4 | Typing with focus |
| 5–6 | Fast typing · smoke |
| 7–9 | Flames in the chosen color · electric blue by default |
| 10 or more | Same flame color · bigger flames and sparks · faster typing |

It reacts to the **total number of tasks** across the agents it detects, regardless of the chosen colors. It checks every 2 seconds, and a lower stage takes effect only after it has held for 4 seconds. The motion preview shows each of the six motions regardless of the session thresholds. Choose "Auto · actual task count" (자동 · 실제 작업 수) to end the preview.

## Supported sessions

| Tool | How it connects |
| --- | --- |
| Codex · Claude Code | Detected automatically by default |
| Grok · Cursor · Cline · Gemini CLI | Each tool's local hook connection |
| OpenCode | Local plugin connection |
| Other tools | Start and end notifications through the common `--signal` command |

No particular terminal app or session manager is required. Additional tools are counted only after their first connection. It does not figure out the work status of every program without setup, and it does not include browser chats or sessions on other computers. [How to connect tools and what is covered](docs/integrations.md) (Korean)

## Detection and privacy

It reads Codex's open local session logs and Claude Code's local state files. For additional tools, it receives task events from the hooks or plugins you connect. It needs no API key and no external network connection, and it does not separately store or transmit conversation content.

Detection depends on each tool's log and event formats. If a format changes, or in environments where end signals are missed, the count may be off. [How detection works and what is stored](PRIVACY.md) (Korean)

```sh
bash scripts/test.sh
dist/AgentPet.app/Contents/MacOS/AgentPet --status
```

[Build and asset structure](DEVELOPMENT.md) (Korean)

## Feedback

I am new to this field and there is a lot I still get wrong. If you see something to fix or something I should know, an issue or PR would be very much appreciated.

## License

The code is under the [MIT](LICENSE) license. The designs of Clawd and its color-variant characters are not covered by the MIT license. This app is a personal project and is not affiliated with Anthropic, OpenAI, or xAI. [Character notices](THIRD_PARTY_NOTICES.md) (Korean)
