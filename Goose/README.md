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

## Status atual

**Fatia 0 — Fundação macOS** ✅
- Janela transparente borderless click-through em level `.screenSaver`
- Cobre todos os Spaces (canJoinAllSpaces)
- SpriteKit scene com sprite real do ganso e idle animation (4 frames)
- Filtro `.nearest` preserva o pixel art crisp
- Status bar item para quit
- ESC hold com feedback visual (estilo do original)

## Próximas fatias

- **Fatia 1** — Goose anda: port de Vector2/SamMath/Easings, IK dos pés, footprints, sons (honk/bite via AVAudioEngine)
- **Fatia 2** — Vision OCR + Accessibility API + ContextSnapshot
- **Fatia 3** — Apple Foundation Models triage + action `leaveNote` com sticky note
- **Fatia 4** — Action `browse` com browser fake + Reddit/Wiki/DDG
- **Fatia 5** — Polimento, "goose mistakes", memória, settings

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
