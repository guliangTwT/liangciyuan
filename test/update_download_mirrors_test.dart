import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/update/update_download_mirrors.dart';

void main() {
  group('updateDownloadCandidates', () {
    test('adds the direct GitHub URL and every mirror', () {
      const url = 'https://github.com/o/r/releases/download/1.0/app.exe';
      final candidates = updateDownloadCandidates(url);

      expect(candidates.first, url);
      expect(candidates, contains(url));
      for (final prefix in githubMirrorPrefixes) {
        expect(candidates, contains('$prefix$url'));
      }
    });

    test('unwraps an already-mirrored URL back to GitHub', () {
      const direct = 'https://github.com/o/r/releases/download/1.0/app.exe';
      final mirrored = '${githubMirrorPrefixes.first}$direct';
      final candidates = updateDownloadCandidates(mirrored);

      expect(candidates.first, mirrored);
      expect(candidates, contains(direct));
      expect(candidates.where((url) => url == direct), hasLength(1));
    });

    test('leaves non-GitHub URLs untouched', () {
      const url = 'https://example.com/app.exe';
      expect(updateDownloadCandidates(url), [url]);
      expect(unwrapGithubMirror(url), isNull);
    });
  });
}
