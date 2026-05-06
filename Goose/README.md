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

## Privacidade

Toda a percepção (screen capture, OCR, Accessibility) roda **on-device**. O Foundation Models também — quando habilitado, o modelo é local. Nada do que o ganso "vê" sai da sua máquina. O único tráfego de rede é a janela `RealBrowserWindow` carregando uma URL escolhida pelo brain (visível pra você).

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

O código C# original está preservado em `../Source/` como referência para portar comportamentos.
