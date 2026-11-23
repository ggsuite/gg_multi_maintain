// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import '../helpers/git_fixture.dart';

void main() {
  group('CloneRepoHost', () {
    late GitFixture fixture;
    late CloneRepoHost host;
    late List<String> log;
    final options = MaintainOptions.example();

    setUp(() {
      fixture = GitFixture();
      host = CloneRepoHost.example(
        root: Directory(path.join(fixture.root.path, 'runs')),
      );
      log = [];
    });

    OceanRepo repoOf(String org, String name) => OceanRepo.example(
      org: org,
      name: name,
      url: fixture.remote('${org}_$name', GitFixture.dartPackage(name)),
    );

    Future<Directory> open(List<OceanRepo> repos) async {
      final folder = host.folderOf(
        workspacePath: fixture.root.path,
        options: options,
      );
      await host.create(folder: folder, options: options, ggLog: log.add);
      await host.add(
        folder: folder,
        oceanPath: fixture.ocean.path,
        options: options,
        repos: repos,
        ggLog: log.add,
      );
      return folder;
    }

    test('clones every repo on the branch of the run', () async {
      final a = repoOf('ggsuite', 'gg_a');
      await host.prepare(workspacePath: fixture.root.path, ggLog: log.add);
      final folder = await open([a]);
      expect(path.basename(folder.path), 'gg_maintain_2026_10_28_074200');
      final dir = host.checkoutOf(folder, a)!;
      expect(dir.path, path.join(folder.path, 'ggsuite', 'gg_a'));
      expect(GitFixture.git(dir, ['branch', '--show-current']), options.branch);
      await host.close(folder: folder, ggLog: log.add);
      expect(folder.existsSync(), isFalse);
      expect(log, isEmpty);
    });

    test('keeps repos of the same name apart', () async {
      final a = repoOf('ggsuite', 'json');
      final b = repoOf('rljson', 'json');
      final folder = await open([a, b]);
      expect(
        host.checkoutOf(folder, a)!.path,
        path.join(folder.path, 'ggsuite', 'json'),
      );
      expect(
        host.checkoutOf(folder, b)!.path,
        path.join(folder.path, 'rljson', 'json'),
      );
    });

    test('logs a repo it cannot clone and goes on', () async {
      final gone = OceanRepo.example(
        name: 'gone',
        url: path.join(fixture.root.path, 'none'),
      );
      final a = repoOf('ggsuite', 'gg_a');
      final folder = await open([gone, a]);
      expect(log.single, startsWith('Could not clone ggsuite/gone'));
      expect(host.checkoutOf(folder, gone), isNull);
      expect(host.checkoutOf(folder, a), isNotNull);
    });

    test('finds no checkout in a folder that does not exist', () {
      expect(
        host.checkoutOf(Directory('/no/such/folder'), OceanRepo.example()),
        isNull,
      );
    });

    test('finds a checkout by the identity of its remote', () {
      final folder = Directory(path.join(fixture.root.path, 'ticket'));
      final dir = Directory(path.join(folder.path, 'gg_json'))
        ..createSync(recursive: true);
      GitFixture.git(dir, ['init', '-q']);
      GitFixture.git(dir, [
        'remote',
        'add',
        'origin',
        'git@github.com:ggsuite/gg_json.git',
      ]);
      expect(host.checkoutOf(folder, OceanRepo.example())!.path, dir.path);
    });

    test('restore drops what is not committed', () async {
      final a = repoOf('ggsuite', 'gg_a');
      final folder = await open([a]);
      final dir = host.checkoutOf(folder, a)!;
      GitFixture.writeFiles(dir, {
        'pubspec.yaml': 'changed',
        '.gitattributes': '* text=auto\n',
      });
      await host.restore(folder, [a, repoOf('ggsuite', 'not_cloned')]);
      expect(GitFixture.git(dir, ['status', '--porcelain']), isEmpty);
    });

    test('works in the temp folder by default', () {
      expect(CloneRepoHost().root.path, Directory.systemTemp.path);
    });
  });

  group('TicketRepoHost', () {
    test('names the ticket after the run', () {
      expect(
        const TicketRepoHost()
            .folderOf(workspacePath: '/ws', options: MaintainOptions.example())
            .path,
        path.join('/ws', 'maintain_2026_10_28_074200'),
      );
    });
  });
}
