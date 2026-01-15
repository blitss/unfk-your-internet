# unf*ck your internet (OpenWrt)

very opinionated project to unf*ck your internet in Russia by combining:

* DPI circumvention (using zapret)
* ~~Cloudflare WARP (where DPI bypass no longer possible or not stable enough) - using sing-box.~~ в итоге отказался от этой идеи из-за того что warp работает нестабильно
* regional blocks (thru VPN) and whatever zapret can't circumvent  - using Vless and [Red Shield VPN](https://new2.redshieldvpn.info/?r=0QLBpDjBaPO9OwhWLRo5)
# Настройка Zapret

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

Чтобы запустить:

```sh
curl -fsSL "https://raw.githubusercontent.com/blitss/zapret-spb-strategy/main/install.sh" | sh
```

# Настройка sing-box и полноценного обхода

К сожалению, zapret не дает 100% гарантии что все будет работать как надо (WA у меня так и не получилось сделать, например), и многие сервисы блокируют доступ с российских айпи. К тому же, РКН периодически что-то меняет и подкручивает, поэтому стратегии со временем отваливаются. Так я пришел к комбинированному подходу, где какие-то айпи и домены ходят через VPN.

#### Про VPN который я использую

Red shield vpn - очень классный vpn, которым я пользуюсь сам. Они дают возможность сгенерить конфиг для vless/amnezia/и т.д. + у них есть приложения под все платформы. За 1.5 года у меня ни разу не было ситуации что он не работал + у них есть возможность обхода белых списков, когда работает только мессенджер макс и Яндекс Карты. Это в тысячу раз лучше чем пытаться настроить свой VPN сервер (я прошел через этот путь) просто потому что такой вариант постоянно отваливается, а у ребят все работает как часы. Можно зарегистрироваться по моей ссылке и вам и мне дадут месяц как подарок: https://new2.redshieldvpn.info/?r=0QLBpDjBaPO9OwhWLRo5 (я не получаю никакой финансовой выгоды с этого)

<details>
  <summary>Вот скорость которая получается через vless на роутере и VPN:</summary>
  <img width="414" height="399" alt="image" src="https://github.com/user-attachments/assets/7d19c308-4447-4311-9511-65a2dec02c2c" />
</details>

Я использую podkop чтобы он управлял sing-box и запускал его. Тут пока что нет детальных инструкций и скрипта по настройке, но можно посмотреть списки которые я использую и добавить их самому, если вы знаете как это делается: https://github.com/blitss/unfk-your-internet/tree/main/sing-box

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

