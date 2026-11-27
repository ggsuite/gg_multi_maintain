<!--
@license
Copyright (c) ggsuite

Use of this source code is governed by terms that can be
found in the LICENSE file in the root of this package.
-->

# In einem normalen Ticket pflegen und nach einem Fehler weitermachen

## Motivation

- Ein Lauf hat bisher jedes Repo nach `<workspace>/.maintain/<lauf-id>`
  geklont und die Klone wieder gelöscht. Ein gescheitertes Repo hinterließ
  einen Klon, mit dem niemand weiterarbeiten konnte: Der Entwickler musste
  es in einem neuen Ticket reparieren und auf den nächsten Lauf warten
- Der Lauf soll dort arbeiten, wo jede andere gg-Arbeit passiert — in
  einem Ticket — und dort weitermachen, wo er stehen blieb, sobald die
  gescheiterten Repos repariert sind

## Strategie

- Zuerst den Ocean mit `gg do upgrade ocean` abgleichen; scheitert das,
  endet der Lauf
- Ein normales Ticket `maintain_<lauf-id>` anlegen und alle ausgewählten
  Repos mit einem `gg do add --no-localize` hinzufügen; die Ticket-ID ist
  zugleich der Branch
- Den Zustand des Laufs im Ticket halten und nach jedem Repo speichern
- `gg do maintain --continue` pflegt, was noch nicht fertig ist, in den
  Checkouts des Tickets
- Das Ticket entfernen, wenn alles gut ging, sonst mit `report.txt`
  behalten; der Ordner `.maintain` fällt weg

## Das Ticket

- `RepoHost` stellt die Checkouts eines Laufs bereit: `TicketRepoHost`
  ruft `UpdateOceanCommand`, `TicketCommand`, `AddCommand` und
  `RemoveTicketCommand` aus gg_multi_workspace im selben Prozess auf
- Ohne Lokalisieren lässt `gg do add` die Dateien, die es pflegt, etwa
  `.gitattributes`, uncommittet. Die frischen Checkouts werden
  zurückgesetzt, damit sie nie als Änderung zählen
- Ein Checkout wird über sein Remote gefunden, in einem Durchgang über das
  Ticket
- `--dry-run` nutzt `CloneRepoHost`: temporäre Klone, jeweils `--jobs`
  gleichzeitig, kein Ocean-Abgleich, kein Ticket

## Weitermachen

- `MaintainState` liegt unter dem Schlüssel `maintain` in
  `<ticket>/.gg/publish_state.json`, der Zustandsdatei jedes Tickets; ihre
  übrigen Schlüssel bleiben
- Er hält die Optionen, die Repos, ihre Abhängigkeiten, den Commit, mit
  dem jedes Repo begann, und die Ergebnisse
- `--continue [-i <ticket>]` nimmt das Ticket von `-i`, das Ticket, in dem
  es läuft, oder das neueste `maintain_*`-Ticket und lehnt die Optionen
  eines neuen Laufs ab
- Gemergte, unveränderte und übersprungene Repos werden nicht mehr
  angefasst; fehlende Checkouts werden erneut hinzugefügt, ein
  unfertiger Merge wird fortgesetzt
- Änderungen werden am Start-Commit gemessen, also zählen Commits des
  früheren Laufs und des Entwicklers mit

## Jedes Repo mit Remote

- Die Pflege merged nur und veröffentlicht nichts in eine Registry, also
  werden auch Testprojekte und private Pakete gepflegt
- Nur Repos ohne Remote werden übersprungen
- Ein Checkout, der nicht auf dem Branch des Laufs steht, scheitert, bevor
  etwas committet wird

## Offene Punkte

- `gg do publish` in einem Pflege-Ticket würde `publish_state.json` ohne
  den Schlüssel `maintain` neu schreiben
- Zwei gleichnamige Repos verschiedener Organisationen passen nicht in ein
  Ticket; das zweite scheitert als fehlend
