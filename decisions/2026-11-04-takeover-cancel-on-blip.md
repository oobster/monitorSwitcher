# Preklic poskusov prevzema tudi ob kratkem utripu zaslona

- **Kontekst:** popravek pregleda C1 (`3b367e4`, `TakeoverSequencer`) prekliče zakasnjene poskuse
  prevzema, ko deljeni monitor izgine (odklop, spanje, vrnitev). Prekliče jih tudi, ko monitor izgine
  le za trenutek (kratek utrip, npr. ko se monitor ob menjavi vhoda znova javi). To je bila Claudova
  izbira, odprta v HANDOVER (točka 4).
- **Odločitev:** ostane, kot je – poskusi se prekličejo tudi ob kratkem utripu.
- **Posledica:** pomembno samo, če poskus prevzema med utripom spodleti; takrat ni novega poskusa in
  se preklopi ročno iz menija ali s ponovnim priklopom kabla. Pozni poskus pa nikoli ne more preklopiti
  monitorja na laptop, ki ga nima več.
- **Odločil:** lastnik projekta, 2026-11-04.
