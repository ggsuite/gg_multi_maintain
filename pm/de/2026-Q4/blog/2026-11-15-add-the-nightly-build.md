<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# Den nächtlichen Build einführen

## Motivation

- `gg do maintain` hebt SDK, DNA oder Abhängigkeiten aller Ocean-Repos
  parallel an und veröffentlicht jedes geänderte Repo für sich
- Pakete und Apps bleiben nur aktuell, wenn jemand das ausführt — mit
  Major-Versionen und jeden Tag
- Dieser Lauf soll auf einem eigenen Rechner stattfinden, jede Nacht, ohne
  dass jemand zusieht: Er ändert Versionen, keinen Code, und braucht
  deshalb kein Review
- Bricht eine Major-Version ein Repo, darf nichts darauf aufgesetzt werden,
  und der Entwickler muss erfahren, welches Repo gebrochen ist und warum

## Strategie

- `--nightly` als das eine Flag einführen, das ein Zeitplan startet
- Die Pipeline lassen, wie sie ist: Ein gescheitertes Repo blockiert schon
  die Repos, die von ihm abhängen, und behält Klon und Log
- Einen Bericht im Lauf-Ordner hinterlassen, weil niemand die Ausgabe eines
  geplanten Laufs liest
- Beschreiben, wie man den Rechner einrichtet

## --nightly

- `--nightly` ist `--upgrade-deps --major`: alle Abhängigkeiten, über
  Major-Versionen hinweg
- Es lässt sich mit den anderen Aufgaben kombinieren, z. B.
  `--nightly --upgrade-dna`
- Die Aufrufzeile und die Hilfe nennen es; `--major` ohne
  `--upgrade-deps` wird weiter abgelehnt

## Der Bericht

- Ist ein Repo gescheitert oder blockiert, schreibt `Maintainer.run`
  `<workspace>/.maintain/<lauf-id>/report.txt` und gibt den Pfad aus
- Er enthält die Lauf-ID und die Zusammenfassung ohne Farben: welches Repo
  in welchem Schritt gescheitert ist, die erste Zeile des Fehlers und wo
  Klon und Log liegen; dazu die blockierten Repos und worauf sie warten
- `MaintainReport.lines(colored: false)` und
  `MaintainReport.text(runId:)` erzeugen ihn
- Ein Lauf ohne Probleme hinterlässt keinen Bericht, und sein Lauf-Ordner
  wird wie bisher entfernt

## Der Rechner des nächtlichen Builds

- Das README (Englisch und Deutsch) zählt die Schritte auf: Werkzeuge und
  gg installieren, bei GitHub und pub.dev anmelden, ein npm-Token, das ohne
  Einmalpasswort veröffentlicht, ein Workspace mit dem Ocean und der
  Zeitplan — `schtasks` unter Windows, eine crontab-Zeile unter Linux und
  macOS
- `gg do upgrade ocean` holt Repos dazu, die seither angelegt wurden
- `index.jsonc` kam dazu: Das Repo hatte keine

## Tests

- `--nightly` allein und zusammen mit `--upgrade-dna`
- Der Bericht eines gescheiterten Laufs: Lauf-ID, gescheiterte und
  blockierte Repos, keine Farbcodes, sein Pfad im Log; kein Bericht, wenn
  nichts gescheitert ist
- `lines(colored: false)` und `text(runId:)` von `MaintainReport`

## Offene Punkte

- Der Rechner ist noch nicht eingerichtet, und wer ihn betreut, ist offen
- Eine gescheiterte Nacht hinterlässt nur den Bericht und den Exit-Code;
  eine Mail oder ein Issue kann folgen
