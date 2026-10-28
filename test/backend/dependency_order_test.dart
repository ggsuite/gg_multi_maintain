// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart';

import '../helpers/git_fixture.dart';

void main() {
  group('DependencyOrder', () {
    late GitFixture fixture;
    setUp(() => fixture = GitFixture());

    OceanRepo repo(
      String name, {
      String? package,
      Map<String, String> dependencies = const {},
      Map<String, String> devDependencies = const {},
    }) {
      final dir = fixture.oceanRepo(
        'ggsuite',
        name,
        files: {
          'pubspec.yaml': GitFixture.pubspec(
            package ?? name,
            dependencies: dependencies,
            devDependencies: devDependencies,
          ),
        },
      );
      return OceanRepo.example(name: name, directory: dir);
    }

    test('lists dependencies first, with their dependencies', () async {
      final repos = [
        repo('app', dependencies: {'lib': '^1.0.0', 'path': '^1.9.0'}),
        repo('lib', dependencies: {'base': '^1.0.0'}),
        repo('base'),
        repo('tool', devDependencies: {'base': '^1.0.0'}),
      ];
      final order = await DependencyOrder.example().get(repos: repos);
      expect(order.keys.toList(), [
        'ggsuite/base',
        'ggsuite/lib',
        'ggsuite/app',
        'ggsuite/tool',
      ]);
      expect(order, {
        'ggsuite/base': <String>{},
        'ggsuite/lib': {'ggsuite/base'},
        'ggsuite/app': {'ggsuite/lib'},
        'ggsuite/tool': {'ggsuite/base'},
      });
    });

    test('keeps repos the graph drops for a duplicate name', () async {
      final repos = [
        repo('one', package: 'same'),
        repo('two', package: 'same'),
      ];
      final order = await DependencyOrder().get(repos: repos);
      expect(order.keys.toSet(), {'ggsuite/one', 'ggsuite/two'});
      expect(order.values.every((deps) => deps.isEmpty), isTrue);
    });

    test('returns nothing for no repos', () async {
      expect(await DependencyOrder.example().get(repos: const []), isEmpty);
      expect(Directory(fixture.root.path).existsSync(), isTrue);
    });
  });
}
