# Nauki

## 2026-10-23 – Vhod iz tujega gradiva ni preverjen
- **Kaj se je zgodilo:** prva verzija je prevzela vhod strežnika (DisplayPort) iz priloženega zipa; v resnici
  je bil HDMI 1, zato je preklop »na strežnik« poslal monitor na prazen vhod.
- **Nauk:** vhode vedno preberi z monitorja (`get input`) in preveri pri uporabniku; zdaj to dela `setup.command`.
- **Velja za:** ta projekt.

## 2026-10-23 – Monitor v varčevalnem načinu prezre prvi ukaz
- **Kaj se je zgodilo:** po iztaknjenju laptopa je monitor na praznem vhodu zaspal, prvi DDC ukaz ga je samo
  zbudil; skripta je javila uspeh, monitor pa ni preklopil, in se je za ~1 min odklopil od strežnika.
- **Nauk:** po vsakem ukazu preberi vhod in ponovi; čakaj, da se monitor spet pojavi.
- **Velja za:** ta projekt (vsak DDC preklop).

## 2026-10-23 – Ponovno pošiljanje med preklopom povzroči utripanje
- **Kaj se je zgodilo:** med preklopom monitor vrača prehodno vrednost (115); skripta je to razumela kot
  neuspeh in ukaz poslala še dvakrat – trije utripi. Popravek je nato čakal predolgo in spregledal
  monitor, ki je ukaz prezrl.
- **Nauk:** ponovi samo, ko monitor kaže vhod drugega računalnika, in največ vsakih 6 s; prehodne vrednosti
  pomenijo »počakaj«. Logiko preveri z lažnim m1ddc (`scripts/test.sh`), ne s pravim monitorjem.
- **Velja za:** ta projekt.

## 2026-10-23 – Zaščita pred utripanjem je pojedla vračanje
- **Kaj se je zgodilo:** laptop je iztaknjenje v prvih 20 s po prevzemu ignoriral, zato se monitor ni vrnil.
- **Nauk:** časovne zaščite naj dogodek odložijo, ne zavržejo.
- **Velja za:** vse projekte z dogodki in debounceom.

## 2026-10-23 – `git add -A` pred pregledom
- **Kaj se je zgodilo:** »commitaj vse« je v commit potegnil `.DS_Store` z ohlapnim sporočilom.
- **Nauk:** pred commitom vedno `git status --short`; `.gitignore` takoj ob začetku (`nacin-dela`).
- **Velja za:** vse projekte.

## 2026-10-23 – Lupina Desktop Commanderja
- **Kaj se je zgodilo:** `$TMPDIR` ni bil nastavljen (pisanje v `/notes.md` na sistemskem disku ni uspelo);
  zsh glob brez zadetkov (`dist/*.zip` v prazni mapi) je ustavil skripto s `set -e`.
- **Nauk:** začasne datoteke vedno z `mktemp`; v zsh globih, ki so lahko prazni, kvalifikator `(N)`.
- **Velja za:** vse projekte (skripte prek Desktop Commanderja, zsh).

## 2026-10-23 – Javna objava in zgodovina
- **Kaj se je zgodilo:** stara zgodovina je vsebovala uporabniško ime, ime računalnika, imena oseb in UUID-je.
  Zgodovino smo zamenjali z enim začetnim commitom (3.0.0) in pobrisali stare tage (z Mihovim potrdilom).
- **Nauk:** projekt, ki bi lahko postal javen, naj od začetka nima osebnih podatkov v gitu (`private/`).
- **Velja za:** vse projekte.
