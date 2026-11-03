# `authorize-key.sh`: en končni prelom vrstice se tiho odreže

- **Kontekst:** popravek pregleda C1 (`3b367e4`) je `authorize-key.sh` naredil strogo »ena vrstica«:
  zavrnil je vsak argument s prelomom vrstice, tudi samo s končnim (pogosto pri kopiranju ključa iz
  datoteke ali terminala). To je bila Claudova izbira, odprta v HANDOVER (točka 4).
- **Odločitev:** **en sam** prelom vrstice na samem koncu argumenta (`\n` ali `\r\n`) se tiho odreže.
  Vsak drug `\n` ali `\r` (sredi ključa, dva končna preloma, samostojen končni `\r`, več ključev)
  ostane zavrnjen in nič se ne zapiše. Še vedno velja, da `ssh-keygen -l` prebere natanko en veljaven
  ključ in da se doda samo z vsiljenim ukazom in `restrict`.
- **Zakaj:** prilepljen ključ s končnim prelomom je običajen in nenevaren (po odrezu je to ista ena
  vrstica); drugi prelomi bi lahko v `authorized_keys` dodali vrstico brez omejitev.
- **Preverjeno:** `scripts/test.sh` (lažni HOME, lažni m1ddc, brez oken) – končni `\n` in `\r\n`
  sprejeta in pravilno dodana z omejitvami; dva končna preloma, `\r` na koncu, `\n` sredi ključa in
  dva ključa s končnim prelomom zavrnjeni.
- **Odločil:** lastnik projekta, 2026-11-04.
