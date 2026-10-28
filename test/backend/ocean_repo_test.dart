// @license
// Copyright (c) ggsuite
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:gg_multi_maintain/gg_multi_maintain.dart';
import 'package:test/test.dart';

void main() {
  group('OceanRepo', () {
    test('example is gg_json of ggsuite', () {
      final repo = OceanRepo.example();
      expect(repo.org, 'ggsuite');
      expect(repo.name, 'gg_json');
      expect(repo.directory.path, '.ocean/ggsuite/gg_json');
      expect(repo.url, 'https://github.com/ggsuite/gg_json.git');
    });

    test('example takes every value', () {
      final repo = OceanRepo.example(
        org: 'o',
        name: 'n',
        directory: Directory('d'),
        url: 'u',
      );
      expect(
        [repo.org, repo.name, repo.directory.path, repo.url],
        ['o', 'n', 'd', 'u'],
      );
    });

    test('key and toString join org and name', () {
      final repo = OceanRepo.example(org: 'tssuite', name: 'is-ready');
      expect(repo.key, 'tssuite/is-ready');
      expect('$repo', 'tssuite/is-ready');
    });
  });
}
