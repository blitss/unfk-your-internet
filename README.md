# unf*ck your internet (OpenWrt)

very opinionated project to unf*ck your internet in Russia by combining:

* DPI circumvention (using zapret)
* ~~Cloudflare WARP (where DPI bypass no longer possible or not stable enough) - using sing-box.~~ в итоге отказался от этой идеи из-за того что warp работает нестабильно
* regional blocks (using EU VPN) - using Vless and Red Shield VPN, for services like OpenAI

Cтратегия для `zapret`, с идеей **таргетить только заблокированные домены + подсети CDN (Cloudflare/Hetzner/Amazon и др.)**, а не применять tampering “ко всему подряд”.

## Что это

- Репозиторий хранит **конфиг** (`config.yaml`) и **артефакты** (списки/бинарники), которые должны оказаться на роутере в `/opt/zapret/...`.
- **Обновление списков** происходит в репозитории через GitHub Actions (ежедневно) — см. workflow.

## Что работает / что нет (коротко)

**Работает:**
- Instagram, X, LinkedIn
- FaceTime, Telegram calls, Google Meet
- ~~WhatsApp (iOS/web)~~ перестал работать с недавних пор, как будто заблокировали subnet'ы теперь
- Cloudflare WARP
- QUIC/HTTP3 — на большинстве ресурсов, но не везде

**Не получилось / ограничения:**
- HTTP (80) трафик специально не “допиливался”
- Discord нестабилен (со временем начинаются проблемы со входом в каналы/стримами), для Discord используется VPN как запасной вариант
- На Windows по умолчанию может работать плохо:
  - вариант 1: включить TCP Timestamps:

```powershell
netsh interface tcp set global timestamps=enabled
```

  - вариант 2: заменить `--dpi-desync-fooling=ts` на `--dpi-desync-fooling=badseq` (может ухудшить результат)

## Установка на OpenWrt (на роутере)

Скрипт `install.sh`:
- скачивает файлы из репозитория в `/opt/zapret/...` (без `git`)
- парсит `config.yaml` через `yq` и проставляет `uci set zapret.config.<KEY>=...`
- запускает `/opt/zapret/sync_config.sh`

Пример:

```sh
curl -fsSL "https://raw.githubusercontent.com/blitss/zapret-spb-strategy/main/install.sh" | sh
```

## Обновление списков (в репозитории)

Workflow `.github/workflows/sync-lists.yml` запускает `sync-lists.sh` **раз в сутки** и коммитит изменения в `ipset/`.

## Credits

- **zapret**: проект [bol-van/zapret](https://github.com/bol-van/zapret)
  - WA “udp 11/01” подсказка: [discussioncomment-15359781](https://github.com/bol-van/zapret/discussions/1908#discussioncomment-15359781)
- **CDN IPv4 ranges** (`ipset/cust2.txt`):
  - источник: [123jjck/cdn-ip-ranges](https://github.com/123jjck/cdn-ip-ranges) → [`all/all_plain_ipv4.txt`](https://raw.githubusercontent.com/123jjck/cdn-ip-ranges/main/all/all_plain_ipv4.txt)
- **WhatsApp CIDR IPv4** (`ipset/wa-ipset.txt`):
  - источник: [HybridNetworks/whatsapp-cidr](https://github.com/HybridNetworks/whatsapp-cidr) → [`WhatsApp/whatsapp_cidr_ipv4.txt`](https://raw.githubusercontent.com/HybridNetworks/whatsapp-cidr/main/WhatsApp/whatsapp_cidr_ipv4.txt)
- **RKN blocked domains** (`ipset/zapret-hosts-user.txt`):
  - источник: [IndeecFOX/zapret4rocket](https://github.com/IndeecFOX/zapret4rocket) → [`extra_strats/TCP/RKN/List.txt`](https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/master/extra_strats/TCP/RKN/List.txt)
- **tls client hello “max”** (`files/fake/max.bin`):
  - источник: [Flowseal/zapret-discord-youtube](https://github.com/Flowseal/zapret-discord-youtube) (bin)
- **custom.d script example**:
  - [bol-van/zapret](https://github.com/bol-van/zapret) → `init.d/custom.d.examples.linux/50-stun4all`

