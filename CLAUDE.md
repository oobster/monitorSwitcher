# Monitor Switcher

Najprej preberi `HANDOVER.md`. Pravila dela so v skillih `nacin-dela` in `apple-apps`.

Na kratko:
- Pogovor slovensko, tikanje, kratko. HANDOVER, LESSONS in `decisions/` slovensko.
- **Repozitorij je javen:** vse, kar vidijo drugi (README, CHANGELOG, INSTRUCTIONS, vmesnik, nastavitve,
  sporočila skript), je v angleščini in splošno. Nikjer imen oseb, uporabniških imen, imen računalnikov,
  UUID-jev, IP-jev ali ključev. Zasebno v `private/` (v `.gitignore`).
- Po vsaki spremembi kode `scripts/test.sh` (brez oken, ~20 s).
- Commit po vsaki zaključeni spremembi, takoj `git push --follow-tags` (navaden push; force samo z
  lastnikovim potrdilom).
- Gradnja samo s `scripts/build.sh` (čisto drevo, ustvari tag). Namestitev na Mac mini
  (`scripts/deploy.sh`) šele po lastnikovem »ja«.
- Nikoli ne pošlji DDC ukaza zaslonu, ki ni deljeni (`PROTECTED_UUIDS`), in ne preklapljaj pravega
  monitorja brez potrebe, ko lastnik dela na tem Macu – za logiko uporabi lažni m1ddc v `scripts/test.sh`.
