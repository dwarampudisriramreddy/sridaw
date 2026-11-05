import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sridaw/model/project.dart';
import 'package:sridaw/model/project_store.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('sridaw-projects-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('saves a project inside the storage root and reopens it', () async {
    final store = ProjectStore(root: root);
    final project = Project(
      name: 'Demo',
      bpm: 143,
      totalBars: 2,
      scaleRoot: 2,
      scaleName: 'Minor',
    );
    project.tracks.first
      ..name = 'Bass'
      ..instrument = 34
      ..channel = 2
      ..notes.add(Note(pitch: 38, start: 4, len: 2, vel: 91));

    final path = await store.save(project, name: 'Night Drive');

    expect(project.name, 'Night Drive');
    expect(path, p.join(root.path, 'Night Drive.sridaw'));
    expect(await File(path).exists(), isTrue);

    final loaded = await store.load('Night Drive');
    expect(loaded.name, 'Night Drive');
    expect(loaded.bpm, 143);
    expect(loaded.totalBars, 2);
    expect(loaded.scaleRoot, 2);
    expect(loaded.scaleName, 'Minor');
    expect(loaded.track.name, 'Bass');
    expect(loaded.track.instrument, 34);
    expect(loaded.track.channel, 2);
    expect(loaded.track.notes, hasLength(1));
    expect(loaded.track.notes.first.pitch, 38);
    expect(loaded.track.notes.first.start, 4);
    expect(loaded.track.notes.first.len, 2);
    expect(loaded.track.notes.first.vel, 91);
  });

  test('lists saved projects newest first and strips the extension', () async {
    final store = ProjectStore(root: root);
    final first = Project(name: 'First');
    await store.save(first);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = Project(name: 'Second');
    await store.save(second);

    final projects = await store.list();

    expect(projects.map((project) => project.name), ['Second', 'First']);
    expect(
      projects.every((project) => project.path.endsWith('.sridaw')),
      isTrue,
    );
  });

  test('sanitises unsafe names and rejects missing projects', () async {
    final store = ProjectStore(root: root);
    final project = Project(name: 'x');

    final path = await store.save(project, name: '../Bad:Name.sridaw');

    expect(p.basename(path), '_Bad_Name.sridaw');
    expect(await File(path).exists(), isTrue);
    expect(() => store.load('Missing'), throwsA(isA<ProjectStoreException>()));
  });
}
