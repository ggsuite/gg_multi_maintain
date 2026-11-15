# gg_multi_maintain

[English](README.md) | Deutsch

[![CI](https://github.com/ggsuite/gg_multi_maintain/actions/workflows/quick_check.yaml/badge.svg)](https://github.com/ggsuite/gg_multi_maintain/actions/workflows/quick_check.yaml)
[![pub package](https://img.shields.io/pub/v/gg_multi_maintain.svg)](https://pub.dev/packages/gg_multi_maintain)

Führt Wartungsaufgaben wie SDK-, DNA- und Abhängigkeits-Upgrades parallel in allen Ocean-Repos aus und merged jedes geänderte Repo in seinen main-Branch, ohne zu veröffentlichen.

## Motivation

Ein gg-Workspace hat hundert Repos im Ocean. Das Dart-SDK anheben, eine
neue DNA-Schicht einziehen oder die Abhängigkeiten aktualisieren hieß
bisher: ein Ticket pro Repo, oder ein riesiges Ticket, dessen
Abhängigkeitshülle jedes Repo mitzog. `gg do maintain` erledigt solche
Routinearbeit für den ganzen Ocean mit einem Aufruf:

- jedes Repo bekommt einen eigenen frischen Klon und Branch, der Ocean
  bleibt, wie er ist
- die Repos laufen parallel, aber ein Repo wartet auf die Repos, von
  denen es abhängt, damit kein Repo auf einem kaputten aufsetzt
- jedes geänderte Repo wird mit allen Prüfungen und Tests von
  `gg one do commit` committet und mit `gg one do publish --merge-only`
  in seinen main-Branch gemerged
- nichts wird veröffentlicht: keine neue Version, kein Upload, kein Tag.
  Die Änderungen warten unter `## Unreleased` in `CHANGELOG.md`. Alles,
  was irgendwo veröffentlicht wird, läuft über ein normales Ticket und
  sein Review
- ein scheiterndes Repo hält nur die Repos auf, die von ihm abhängen

## Installation

`gg do maintain` kommt mit gg:

```bash
dart pub global activate gg
```

## Verwendung

Im Wurzelordner eines gg-Workspace aufrufen und mindestens eine Aufgabe
wählen:

```bash
gg do maintain --upgrade-sdk                 # Dart SDK and Node constraints
gg do maintain --upgrade-dna                 # the DNA layers, then regenerate
gg do maintain --upgrade-deps                # compatible dependency upgrades
gg do maintain --upgrade-deps --major        # also across major versions
gg do maintain --nightly                     # the nightly build
gg do maintain --all --org ggsuite --dry-run # see what would change
```

| Option | Bedeutung |
| --- | --- |
| `--upgrade-sdk` | Hebt `environment: sdk:` auf das installierte Dart und `engines.node` auf das installierte Node |
| `--upgrade-deps` | Hebt die Abhängigkeiten auf die neuesten kompatiblen Versionen |
| `--major` | Mit `--upgrade-deps`: erlaubt Sprünge über Major-Versionen |
| `--upgrade-dna` | Hebt die DNA-Schichten und die helix-Engine an und ruft `gg dna upgrade` auf: legt den neuesten DNA-Check ab und erzeugt die DNA neu |
| `--all` | Alle Aufgaben oben |
| `--nightly` | Der nächtliche Build: `--upgrade-deps --major`, siehe unten |
| `-j`, `--jobs` | Wie viele Repos gleichzeitig laufen, Standard 4 |
| `--org`, `--repo` | Begrenzt den Lauf, z. B. `--org tssuite` oder `--repo 'gg_*'` |
| `-n`, `--dry-run` | Wendet die Aufgaben an und meldet die Änderungen, ohne Commit und Merge |

Das Beispiel gibt die Hilfe des Befehls aus:

```dart
import 'package:args/command_runner.dart' show CommandRunner;
import 'package:gg_multi_maintain/gg_multi_maintain.dart';

Future<void> main() async {
  final runner = CommandRunner<void>('gg', 'Maintains the ocean.')
    ..addCommand(DoMaintain(ggLog: print));
  await runner.run(['help', 'maintain']);
}
```

Am Ende druckt der Befehl eine Zusammenfassung wie diese:

```text
Merged (2):
  ggsuite/gg_hash: pubspec.yaml
  ggsuite/gg_json: pubspec.yaml, 1 other file
Unchanged (1):
  ggsuite/gg_log
Skipped (1):
  ggsuite/testproject_gg_1: a test project
```

## Nächtlicher Build

Commit, Push und Publish eines Tickets heben keine Abhängigkeit an. Neue
Versionen, auch Major-Versionen, kommen über einen Lauf jede Nacht in die
main-Branches:

```bash
gg do maintain --nightly
```

Er hebt die Abhängigkeiten jedes Repos über Major-Versionen hinweg an
und merged jedes geänderte Repo ohne Review nach main — er ändert
Versionen, keinen Code. Er veröffentlicht nichts; das nächste Ticket, das
ein Repo veröffentlicht, veröffentlicht dessen Upgrades mit. Ein Repo,
dessen Prüfungen oder Tests nach dem Upgrade scheitern, wird nicht
gemerged, und nichts wird darauf
aufgesetzt: Die Repos, die von ihm abhängen, sind blockiert. Der Lauf
endet dann mit einem Fehler und schreibt
`<workspace>/.maintain/<lauf-id>/report.txt`: welches Repo in welchem
Schritt woran gescheitert ist und wo Klon und Log liegen. Repariert wird
das Repo in einem Ticket; die nächste Nacht macht dort weiter.

### Den Rechner des nächtlichen Builds einrichten

Der nächtliche Build läuft auf einem eigenen Rechner, nicht auf dem
Rechner eines Entwicklers und nicht auf GitHub:

1. Dart, Flutter (für Flutter-Repos), Node mit pnpm, git und die GitHub
   CLI installieren, dann gg: `dart pub global activate gg`
2. Einmal anmelden, mit einem Konto, das über Pull Requests nach `main`
   pushen darf: `gh auth login`. Eine Anmeldung an einer Registry ist
   nicht nötig, der Lauf lädt nichts hoch
3. Einen Workspace mit dem Ocean der Organisationen anlegen, z. B.
   `C:\nightly\.ocean`, wie auf einem Entwicklerrechner. `gg do upgrade
   ocean` holt die Repos dazu, die seither angelegt wurden
4. Den Lauf nachts einplanen, aus dem Wurzelordner des Workspace. Unter
   Windows:

   ```bash
   schtasks /create /tn gg-nightly /sc daily /st 02:00 /tr "cmd /c cd /d C:\nightly && gg do maintain --nightly > nightly.log 2>&1"
   ```

   Unter Linux oder macOS, als Zeile der crontab:

   ```bash
   0 2 * * * cd ~/nightly && gg do maintain --nightly > nightly.log 2>&1
   ```

5. `nightly.log` lesen und nach einer gescheiterten Nacht die
   `report.txt`, die es nennt

## Grenzen

- Testprojekte, private Pakete und Repos ohne Remote werden
  übersprungen. Ein Paket, das nie veröffentlicht wurde, ebenfalls, denn
  seine erste Version wird von Hand veröffentlicht.
- Haben sich nur Lock-Dateien oder gg-Zustand in `.gg/` geändert, gilt
  das Repo als unverändert und wird nicht gemerged.

## So funktioniert es

Jeder Lauf bekommt einen Ordner `<workspace>/.maintain/<lauf-id>/<org>/<repo>`.
Die Pipeline eines Repos: klonen, überspringen, falls nie
veröffentlicht, Branch `maintain_<lauf-id>` anlegen, installieren,
Aufgaben ausführen, Änderungen erkennen, `gg one do commit`,
`gg one do publish --merge-only`, Klon löschen. Ein gescheiterter Klon bleibt mit seinem Log im Lauf-Ordner.

## Status

Vor 1.0 — die Optionen können sich zwischen Minor-Versionen ändern.

## Mitwirken

Siehe den [Develop Guide](doc/guides/develop-guide.md).

## Lizenz

MIT — siehe [LICENSE](LICENSE).
