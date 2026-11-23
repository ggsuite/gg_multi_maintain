// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:convert';
import 'dart:io';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  group('MaintainState', () {
    late Directory ticket;

    setUp(() {
      ticket = Directory.systemTemp.createTempSync('maintain_state_test');
      addTearDown(() => ticket.deleteSync(recursive: true));
    });

    OceanRepo repo(String name) => OceanRepo.example(
      name: name,
      directory: Directory(path.join(ticket.path, name)),
    );

    test('survives a round trip through the ticket', () {
      final a = repo('gg_a');
      final b = repo('gg_b');
      MaintainState(
        options: MaintainOptions.example(tasks: {MaintainTask.sdk}),
        repos: [a, b],
        dependencies: {
          a.key: {},
          b.key: {a.key, 'ggsuite/z'},
        },
        bases: {a.key: 'abc'},
        results: {
          a.key: RepoResult(
            repo: a,
            outcome: RepoOutcome.failed,
            detail: 'boom',
            step: 'commit',
          ),
          b.key: RepoResult(repo: b, outcome: RepoOutcome.merged),
        },
      ).save(ticket);

      final state = MaintainState.load(ticket)!;
      expect(state.options.tasks, {MaintainTask.sdk});
      expect(state.options.runId, '2026_10_28_074200');
      expect(state.repos.map((r) => r.key), [a.key, b.key]);
      expect(state.repos.first.directory.path, a.directory.path);
      expect(state.repos.first.url, a.url);
      expect(state.bases, {a.key: 'abc'});
      expect(state.dependencies, {
        a.key: <String>{},
        b.key: {a.key, 'ggsuite/z'},
      });
      final failed = state.results[a.key]!;
      expect(failed.repo.key, a.key);
      expect(failed.outcome, RepoOutcome.failed);
      expect(failed.detail, 'boom');
      expect(failed.step, 'commit');
      expect(state.results[b.key]!.detail, '');
      expect(state.isDone(a), isFalse);
      expect(state.isDone(b), isTrue);
      expect(state.todo, [state.repos.first]);
    });

    test('keeps the other keys of publish_state.json', () {
      final file = MaintainState.fileIn(ticket)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"deleteTicket": true}');
      MaintainState.example().save(ticket);
      expect(MaintainState.existsIn(ticket), isTrue);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(json['deleteTicket'], isTrue);
      expect(json.keys, contains(MaintainState.key));
      expect(file.path, endsWith(path.join('.gg', 'publish_state.json')));
    });

    test('loads nothing from a ticket without a run', () {
      expect(MaintainState.existsIn(ticket), isFalse);
      expect(MaintainState.load(ticket), isNull);
      MaintainState.fileIn(ticket)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('{"deleteTicket": true}');
      expect(MaintainState.load(ticket), isNull);
      MaintainState.fileIn(ticket).writeAsStringSync('[]');
      expect(MaintainState.load(ticket), isNull);
    });

    test('example holds one repo', () {
      expect(MaintainState.example().repos.single.key, 'ggsuite/gg_json');
    });
  });
}
