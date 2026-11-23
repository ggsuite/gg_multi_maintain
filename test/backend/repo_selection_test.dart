// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart';

import '../helpers/git_fixture.dart';

void main() {
  group('RepoSelection', () {
    late GitFixture fixture;

    setUp(() {
      fixture = GitFixture();
      fixture.oceanRepo('ggsuite', 'gg_a', url: 'https://x/ggsuite/gg_a.git');
      fixture.oceanRepo('ggsuite', 'gg_b', url: 'https://x/ggsuite/gg_b.git');
      fixture.oceanRepo(
        'ggsuite',
        'testproject_gg_1',
        url: 'https://x/ggsuite/testproject_gg_1.git',
      );
      fixture.oceanRepo('ggsuite', 'local');
      fixture.oceanRepo(
        'ggsuite',
        'private_app',
        files: {
          'pubspec.yaml':
              '${GitFixture.pubspec('private_app')}'
              'publish_to: none\n',
        },
        url: 'https://x/ggsuite/private_app.git',
      );
      fixture.oceanRepo(
        'tssuite',
        'is-ready',
        files: {'package.json': '{"name": "@tssuite/is-ready"}'},
        url: 'https://x/tssuite/is-ready.git',
      );
    });

    RepoSelectionResult select({
      List<String> orgs = const [],
      List<String> repos = const [],
    }) => RepoSelection.example().select(
      oceanPath: fixture.ocean.path,
      options: MaintainOptions.example(orgs: orgs, repos: repos),
    );

    Map<String, String> skippedOf(RepoSelectionResult result) => {
      for (final MapEntry(:key, :value) in result.skipped.entries)
        key.key: value,
    };

    test('selects every repo with a remote, private ones too', () {
      final result = select();
      expect(result.selected.map((r) => r.key), [
        'ggsuite/gg_a',
        'ggsuite/gg_b',
        'ggsuite/private_app',
        'ggsuite/testproject_gg_1',
        'tssuite/is-ready',
      ]);
      expect(skippedOf(result), {'ggsuite/local': 'no remote'});
      final first = result.selected.first;
      expect(first.url, 'https://x/ggsuite/gg_a.git');
      expect(first.directory.path, endsWith('gg_a'));
    });

    test('limits to the given orgs', () {
      final result = select(orgs: ['tssuite']);
      expect(result.selected.map((r) => r.key), ['tssuite/is-ready']);
      expect(result.skipped, isEmpty);
    });

    test('matches names and keys with wildcards', () {
      expect(select(repos: ['gg_*']).selected.map((r) => r.key), [
        'ggsuite/gg_a',
        'ggsuite/gg_b',
      ]);
      expect(
        select(repos: ['ggsuite/gg_b', 'is-*']).selected.map((r) => r.key),
        ['ggsuite/gg_b', 'tssuite/is-ready'],
      );
      expect(select(repos: ['gg']).selected, isEmpty);
    });

    test('takes the org of a flat repo from its remote', () {
      final flat = fixture.oceanRepo(
        '.',
        'flat',
        url: 'https://github.com/rljson/flat.git',
      );
      expect(flat.existsSync(), isTrue);
      final result = select(repos: ['flat']);
      expect(result.selected.map((r) => r.key), ['rljson/flat']);
    });
  });
}
