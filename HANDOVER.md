# Monitor Switcher – handover

Zadnja posodobitev: 2026-11-04

Repozitorij je **javen** (`oobster/monitorSwitcher`, Unlicense). V repozitorij ne gredo imena oseb,
uporabniška imena, imena računalnikov, UUID-ji zaslonov, IP-ji ali ključi. Zasebno sodi v `private/`
(v `.gitignore`).

## Namen
macOS app v menijski vrstici: deljeni monitor preklaplja med **strežnikom** (Mac, na katerega je
priklopljen) in **laptopi**. Strežnik preklaplja vhod prek DDC (`m1ddc`), laptopi ga prosijo prek SSH
v lokalnem omrežju (ključi so omejeni samo na preklop). Laptop monitor prevzame, ko vtakneš kabel,
in ga vrne, ko kabel iztakneš ali gre spat. Podrobno: `README.md`.

## Tip
**Orodje za drugega + javen projekt.** Doma: strežnik je Mac mini, laptopa sta dva (en je druge osebe,
ki naj ne potrebuje terminala za vsakdanjo rabo). Javno: navodila in vmesnik v angleščini, brez
osebnih podatkov, podpisana in notarizirana gradnja, da se odpre na vsakem Macu.
Posledice: napake morajo biti jasno izpisane, prva namestitev laptopa še zahteva Terminal
(odprto vprašanje spodaj), posodobitve laptopov gredo prek menija »Update from Server«.

## Trenutno stanje
- Verzija v repozitoriju: `VERSION` (3.2.0 – podpis Developer ID + notarizacija, nov bundle ID
  `se.premakni.MonitorSwitcher`, skripte v `scripts/`, hitri testi).
- Nameščeno doma:
  - strežnik (Mac mini): **3.2.0** (tag `v3.2.0`, 2026-11-01; notariziran, Gatekeeper »Notarized Developer ID«);
    objavljen tudi paket 3.2.0 za laptope.
  - laptopa: 3.1.0 prek »Update from Server« (potrjeno za vsaj enega, 2026-10-23); drugega preveri.
- GitHub release: v3.0.0, v3.1.0 (strežniški zip kot priponka); v3.2.0 še ne (tag je na GitHubu).

## Kako
| Kaj | Ukaz | Opomba |
|---|---|---|
| Hiter test | `scripts/test.sh` | ~20 s, brez oken in brez monitorja (lažni m1ddc) |
| Gradnja | `scripts/build.sh` | čisto drevo, nova `VERSION`, ustvari tag `vX.Y.Z`, notarizacija 1–5 min; `--dirty` za lokalni preizkus |
| Namestitev na strežnik | `scripts/deploy.sh` | **samo po lastnikovem »ja«**; poženi na Mac miniju, objavi tudi paket za laptope |
| Laptopi | meni → Update from Server | nov laptop: klientski zip + `zsh install.command` |
| Ključ novega laptopa | strežnik: meni → Laptop Keys … | ali `./authorize-key.sh "ssh-ed25519 …"` |
| Release na GitHubu | `gh release create vX.Y.Z dist/MonitorSwitcher-server-X.Y.Z.zip …` | opombe iz CHANGELOG |

- Podpis: identiteta »Developer ID Application« (Team `24L32KV9LQ`) in notarytool profil `AC_NOTARY`
  sta v Keychainu na Mac miniju. Brez njiju je gradnja ad-hoc (za druge, ki gradijo iz izvorne kode).
- App je en Swift file (`MonitorSwitcher.swift`), preveden s `swiftc` v `scripts/build-app.sh`; ni
  Xcode projekta, xcodegen in UI testov (premajhen app).

## Kje je kaj
- Strežnik: `~/Applications/MonitorSwitcher.app`, `~/.local/bin/monitor-switch*`,
  nastavitve `~/.config/monitor-switch/config`, dnevnik `~/.local/state/monitor-switch/log` (24 h),
  objavljen paket za laptope `~/.local/share/monitor-switch/client/`, ključi v `~/.ssh/authorized_keys`.
- Laptop: app, `~/.local/bin/monitor-switch` (SSH ovojnica) in `monitor-switch-update`,
  ključ `~/.ssh/monitorswitch_ed25519`.
- Nastavitve appa: domena `se.premakni.MonitorSwitcher` (do 3.1.0 `si.obal.monitorswitcher`;
  namestitev jih prenese).
- Odločitve: `decisions/`; nauki: `LESSONS.md`.

## Odprto
- Laptopa: »Update from Server« na 3.2.0 (nov bundle ID, prenos nastavitev ob namestitvi).
- Star vnos za samodejni zagon (`si.obal.monitorswitcher`) je v System Settings → General → Login Items
  še prisoten poleg novega – lahko se odstrani ročno.
- Release v3.2.0 na GitHubu (priponka strežniški zip) – po lastnikovem dogovoru.
- Prva notarizacija tega računa je trajala ~41 min (19:02–19:43 UTC); naslednje so običajno hitrejše.
- Popravki pregleda C1 (commit `3b367e4`, v CHANGELOG pod Unreleased): `authorize-key.sh` sprejme
  natanko en ključ v eni vrstici; laptop prekliče zakasnjene poskuse prevzema ob odklopu/spanju,
  release med tekočim preklopom se izvede za njim (`TakeoverSequencer`). **Ciljni testi C1 zeleni
  (38/0)**: `scripts/test.sh`, 2026-11-04. Neodvisna preverba (Codex) čaka.
  Verzija ni dvignjena, ni gradnje ne namestitve; gradnja s tagom in namestitev po lastnikovi potrditvi.

## Odprta vprašanja za lastnika
1. Jezik commit sporočil v javnem repozitoriju: `nacin-dela` pravi slovenščina, javni projekt je v
   angleščini (README, CHANGELOG, vmesnik). Predlog: angleščina za javne repozitorije.
2. Prva namestitev laptopa brez Terminala (npr. notariziran `.pkg` ali app, ki se ob prvem zagonu
   namesti sam)?
3. `m1ddc` je zdaj odvisen od Homebrewa; ga zapakirava v app (MIT licenca to dovoli)?
4. C1 izbire: `authorize-key.sh` zavrne tudi argument s končnim prelomom vrstice (strogo »ena
   vrstica«); poskusi prevzema se prekličejo tudi ob kratkem utripu zaslona (pomembno le, če
   poskus med utripom spodleti). Ustreza?
