# Goose

Desktop goose para macOS. Port em Swift do projeto original em C# de samperson, evoluído para um agent que observa a tela e age sobre ela usando Apple Foundation Models.

## Requisitos

- macOS 26.1+
- Xcode 26.1+ ou Swift 6.2+ toolchain
- Apple Silicon (testado em M-series)

## Setup inicial

Os sprites do ganso não são versionados (ver `ASSETS.md`). Antes do primeiro build, busque-os:

```bash
git clone --depth 1 https://github.com/romainflcht/py-goose /tmp/py-goose
mkdir -p Sources/Goose/Resources/Sprites/Goose
cp -R /tmp/py-goose/sprite/* Sources/Goose/Resources/Sprites/Goose/
```

## Como rodar

```bash
cd Goose
swift run
```

O ganso aparece em uma janela transparente click-through cobrindo a tela. Para sair:

- Segurar **ESC** por ~1.5s (a barra "Continue holding ESC to evict goose" aparece no topo)
- Ou clicar no ícone 🪿 na barra de menu → **Quit Goose**

## Cérebro do ganso

Três caminhos, em ordem de preferência:

1. **OpenAI (`gpt-5-mini` por padrão)** — opt-in, desligado por padrão.
2. **Apple Foundation Models** — on-device, automático se o Apple Intelligence tá habilitado.
3. **Pools determinísticos** — fallback hand-curated, sempre funciona.

O router tenta na ordem; se falhar, cai pro próximo. O ganso **sempre funciona**, com ou sem internet/AI.

### Habilitar OpenAI

```bash
mkdir -p ~/.config/goose
echo "sk-..." > ~/.config/goose/openai-key
chmod 600 ~/.config/goose/openai-key
```

Ou exporte `OPENAI_API_KEY` antes do `swift run`. A key é lida no startup — re-launch pra trocar.

### Trocar de modelo

Default é `gpt-5-mini` (reasoning). Pra mais barato/rápido, edite `Goose/Sources/Goose/AI/OpenAIClient.swift`:
```swift
static let model = "gpt-5-mini"   // ou "gpt-4o-mini", "gpt-5-nano"
```

`reasoning_effort: "low"` e `max_completion_tokens: 1500` cobrem ambos 4o e 5-family.

### O que vai pra OpenAI

Só uma linha de contexto:
> `user is in <app> (was in <prev_app> before, <N>s on this app, <N>s idle)`

Sem OCR, sem títulos de janela, sem bytes de screenshot. OCR foi removido depois que vazou pro corpo das notas.

## Privacidade

- **Captura de tela, OCR, Accessibility, Foundation Models** — tudo **on-device**.
- **OpenAI (opt-in)** — só manda nome do app + timing. Não manda OCR.
- **`RealBrowserWindow`** — carrega URL escolhida, tráfego visível.
- **Spotify** — só AppleScript local, zero rede dessa app (o Spotify faz streaming dele).

## Smoke flags

```bash
swift run Goose --render-preview /tmp/x.png       # frame único, headless
swift run Goose --brain-dryrun                    # 20 decisões em stdout
swift run Goose --browser-demo "search query"     # só RealBrowserWindow, sem ganso
```

## Status atual

**Personalidade & navegador real (v2)** ✅
- Brain híbrido: roleta determinística + Foundation Models seam para a sticky note opinativa (fallback automático para os pools)
- `Personality` central: voz sarcástica-cínica com bursts de curiosidade, pools indexados por (tone, AppBucket)
- Contexto enriquecido: OCR top-K, idle, tempo no app, app anterior, ring buffer de 6 snapshots
- Honks descolados do agent loop: ticker independente 35–60s + bonus em mudança de app frontmost (debounced 30s)
- Browser real: substituído o sprite fake por `RealBrowserWindow` (WKWebView 1000×700, click-through, slide-in/dismiss)

**Fatia 0 — Fundação macOS** ✅
- Janela transparente borderless click-through em level `.screenSaver`
- Cobre todos os Spaces (canJoinAllSpaces)
- SpriteKit scene com sprite real do ganso e idle animation (4 frames)
- Filtro `.nearest` preserva o pixel art crisp
- Status bar item para quit
- ESC hold com feedback visual (estilo do original)

## Estrutura

```
Goose/
├── Package.swift
├── ASSETS.md                          # provenance & licensing dos sprites
└── Sources/Goose/
    ├── main.swift                     # entry, NSApplication setup
    ├── App/
    │   ├── AppDelegate.swift          # ciclo de vida, status item
    │   └── OverlayWindow.swift        # janela transparente
    ├── Scene/
    │   ├── GooseScene.swift           # SpriteKit, ganso animado
    │   └── GooseSprites.swift         # loader de spritesheets
    ├── Input/
    │   └── EscQuitMonitor.swift       # polling ESC global
    └── Resources/Sprites/Goose/       # PNGs (não versionados)
```

Inspirado no [Desktop Goose](https://samperson.itch.io/desktop-goose) original do samperson.
