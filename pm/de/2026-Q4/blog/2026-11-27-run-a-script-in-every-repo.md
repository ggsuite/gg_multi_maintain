<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Ein Skript in jedem Repo ausführen

## Motivation

- Manche Wartung ist kein Upgrade: Eine Migration verschiebt Dateien,
  benennt einen Konfigurationsschlüssel um oder schreibt Links um, und das
  in jedem Repo
- `gg do maintain` läuft schon in jedem Repo parallel, in
  Abhängigkeitsreihenfolge, und committet und mergt, was sich geändert hat;
  nur die Aufgaben waren fest

## Strategie

- `--run <skript>` einführen: ein Skript, das im Wurzelordner jedes Repos
  läuft
- Es nach SDK und Abhängigkeiten und vor der DNA ausführen, damit die DNA
  auf dem aufsetzt, was das Skript geändert hat
- Es neben den Aufgaben-Flags halten: Es geht allein oder mit ihnen, und
  `--all` schließt es nicht ein

## --run

- Der Interpreter richtet sich nach der Endung: `.dart` mit `dart run`,
  `.js` und `.mjs` mit `node`, `.sh` mit `bash`, `.ps1` mit `pwsh`; jede
  andere Datei läuft, wie sie ist
- Der Pfad wird beim Start absolut gemacht und muss existieren
- Ein Skript, das mit einem anderen Code als 0 endet, lässt das Repo im
  Schritt `run <skriptname>` scheitern; seine Ausgabe landet im Log des Repos
- Die Commit- und Merge-Nachricht nennt es, z. B. »Upgrade the DNA and run
  migrate.dart«, oder allein »Run migrate.dart«
- `--continue` behält das Skript, es gehört zu den gespeicherten Optionen
- Das Skript läuft je Repo einmal: Hat sich ein Repo seit dem Start schon
  geändert, überspringt `--continue` es dort; fehlt das Skript inzwischen,
  sagt die Meldung das

## Tests

- Die Optionen: Skript im JSON hin und zurück, die Nachrichten mit und ohne
  Aufgaben
- Das Kommando: `--run` allein, mit einem Aufgaben-Flag, mit fehlender Datei
- Die Pipeline: die Reihenfolge SDK, Skript, DNA; das Skript zuletzt ohne
  DNA; ein scheiterndes Skript; ein echtes Dart-Skript
- `RunScript`: der Interpreter je Endung, ein Skript, das eine Datei
  schreibt und loggt, ein Skript, das scheitert
