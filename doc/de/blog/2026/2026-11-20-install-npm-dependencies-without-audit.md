<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# npm-Abhängigkeiten ohne Audit und Fund installieren

## Motivation

- Jedes gewartete TypeScript-Repo bekommt vor den Aufgaben seine
  Abhängigkeiten installiert
- `npm install` fragt dabei zusätzlich die Registry nach einem
  Sicherheits-Audit und sammelt Spendenhinweise; ein Wartungslauf liest
  beides nicht
- Diese Anfragen machen die Installation langsam und unberechenbar: eine
  Installation ganz ohne Abhängigkeiten dauerte einmal 11,6 s, danach 0,8 s
- Der Test der Installation lief auf einem ausgelasteten Rechner in sein
  Limit von 30 Sekunden

## Strategie

- Weglassen, was der Lauf nicht braucht; die Installation selbst bleibt
  gleich
- Dem Test der echten Installation die Zeit geben, die ein ausgelasteter
  Rechner braucht

## Realisierung

- npm läuft als `npm install --no-audit --no-fund`
- pnpm und yarn bleiben bei einem schlichten `install`: sie prüfen beim
  Installieren nichts
- `node_modules` und die Lock-Datei sehen aus wie vorher
- Der Test `installs the npm dependencies of a TypeScript repo` darf zwei
  Minuten statt 30 Sekunden dauern

## Offene Punkte

- Ein Audit geht weiterhin von Hand mit `npm audit`
