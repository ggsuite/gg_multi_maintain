# gg_multi_maintain

[English](README.md) | Deutsch

[![CI](https://github.com/ggsuite/gg_multi_maintain/actions/workflows/quick_check.yaml/badge.svg)](https://github.com/ggsuite/gg_multi_maintain/actions/workflows/quick_check.yaml)
[![pub package](https://img.shields.io/pub/v/gg_multi_maintain.svg)](https://pub.dev/packages/gg_multi_maintain)

Führt Wartungsaufgaben wie SDK-, DNA- und Abhängigkeits-Upgrades parallel in allen Ocean-Repos aus und veröffentlicht jedes geänderte Repo.

## Motivation

Ein gg-Workspace hat hundert Repos im Ocean. Das Dart-SDK anheben, eine
neue DNA-Schicht einziehen oder die Abhängigkeiten aktualisieren hieß
bisher: ein Ticket pro Repo, oder ein riesiges Ticket, dessen
Abhängigkeitshülle jedes Repo mitzog. `gg do maintain` erledigt solche
Routinearbeit für den ganzen Ocean mit einem Aufruf:

- jedes Repo bekommt einen eigenen frischen Klon und Branch, der Ocean
  bleibt, wie er ist
- die Repos laufen parallel, aber ein Repo wartet auf die Repos, von
  denen es abhängt, damit ein Upgrade die Versionen sieht, die derselbe
  Lauf gerade veröffentlicht hat
- jedes geänderte Repo wird einzeln mit `gg one do publish`
  veröffentlicht, mit allen Prüfungen und Tests von `gg one do commit`
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
gg do maintain --all --org ggsuite --dry-run # see what would change
```

| Option | Bedeutung |
| --- | --- |
| `--upgrade-sdk` | Hebt `environment: sdk:` auf das installierte Dart und `engines.node` auf das installierte Node |
| `--upgrade-deps` | Hebt die Abhängigkeiten auf die neuesten kompatiblen Versionen |
| `--major` | Mit `--upgrade-deps`: erlaubt Sprünge über Major-Versionen |
| `--upgrade-dna` | Hebt die DNA-Schichten und die helix-Engine an und erzeugt die DNA neu |
| `--all` | Alle Aufgaben oben |
| `-j`, `--jobs` | Wie viele Repos gleichzeitig laufen, Standard 4 |
| `--org`, `--repo` | Begrenzt den Lauf, z. B. `--org tssuite` oder `--repo 'gg_*'` |
| `--version-increment` | `patch`, `minor` oder `major` für jedes Repo |
| `--no-pana` | Überspringt pana vor dem Veröffentlichen von Dart-Paketen |
| `-n`, `--dry-run` | Wendet die Aufgaben an und meldet die Änderungen, ohne Commit und Publish |

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
Published (2):
  ggsuite/gg_hash: 3.1.5
  ggsuite/gg_json: 2.4.1
Unchanged (1):
  ggsuite/gg_log
Skipped (1):
  ggsuite/testproject_gg_1: a test project
```

## Grenzen

- Testprojekte, private Pakete und Repos ohne Remote werden
  übersprungen. Ein Paket, das nie veröffentlicht wurde, ebenfalls, denn
  seine erste Version wird von Hand veröffentlicht.
- npm-Veröffentlichungen fragen eventuell nach einem Einmalpasswort und
  laufen deshalb nacheinander. Das Mindestalter von pnpm für neue
  Versionen kann eine Version zurückhalten, die derselbe Lauf gerade
  veröffentlicht hat.
- Haben sich nur Lock-Dateien oder gg-Zustand in `.gg/` geändert, gilt
  das Repo als unverändert und wird nicht veröffentlicht.

## So funktioniert es

Jeder Lauf bekommt einen Ordner `<workspace>/.maintain/<lauf-id>/<org>/<repo>`.
Die Pipeline eines Repos: klonen, überspringen, falls nie
veröffentlicht, Branch `maintain_<lauf-id>` anlegen, installieren,
Aufgaben ausführen, Änderungen erkennen, `gg one do commit`,
`gg one do publish`, Klon löschen. Der Versionssprung ist `minor`, wenn
eine normale Abhängigkeit über ihre alte Grenze springt, sonst `patch`.
Ein gescheiterter Klon bleibt mit seinem Log im Lauf-Ordner.

## Status

Vor 1.0 — die Optionen können sich zwischen Minor-Versionen ändern.

## Mitwirken

Siehe den [Develop Guide](doc/guides/develop-guide.md).

## Lizenz

MIT — siehe [LICENSE](LICENSE).
