import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/update/update_download_candidates.dart';

void main() {
  group('updateDownloadCandidates', () {
    test('direct GitHub URL first, then acceleration mirrors', () {
      const url = 'https://github.com/o/r/releases/download/1.0/app.exe';
      final candidates = updateDownloadCandidates(url);

      expect(candidates.first, url);
      for (final prefix in githubMirrorPrefixes) {
        expect(candidates, contains('$prefix$url'));
      }
    });

    test('GitHub API URLs get mirrored too', () {
      const url = 'https://api.github.com/repos/o/r/releases/latest';
      final candidates = updateDownloadCandidates(url);
      expect(candidates.first, url);
      expect(candidates.length, greaterThan(1));
    });

    test('Codeberg URL falls back to the GitHub release page', () {
      final url = '${ApiEndpoints.mirrorProjectUrl}/releases/download/1.0/app.exe';
      final candidates = updateDownloadCandidates(url);

      expect(candidates.first, url);
      expect(
        candidates,
        contains(
          '${ApiEndpoints.projectUrl}/releases/download/1.0/app.exe',
        ),
      );
    });

    test('keeps a single entry for unrelated hosts', () {
      const url = 'https://example.com/app.exe';
      expect(updateDownloadCandidates(url), [url]);
    });

    test('returns nothing for an empty URL', () {
      expect(updateDownloadCandidates('   '), isEmpty);
    });

    test('does not duplicate the direct URL', () {
      const url = 'https://github.com/o/r/releases/download/1.0/app.exe';
      final candidates = updateDownloadCandidates(url);
      expect(candidates.where((candidate) => candidate == url), hasLength(1));
    });
  });

  group('endpoint wiring', () {
    test('GitHub is the primary update source', () {
      expect(ApiEndpoints.latestApp, startsWith('https://api.github.com/'));
    });

    test('Codeberg is the fallback update source', () {
      expect(
        ApiEndpoints.latestAppFallback,
        startsWith('https://codeberg.org/api/v1/repos/'),
      );
    });
  });
}