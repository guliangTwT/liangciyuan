import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/media.dart';

void main() {
  group('direct media detection', () {
    test('accepts giriGiriLove mp4 episode links', () {
      expect(
        isDirectMediaUrl(
          'https://ana.girigirilove.com/zijian/oldanime/2002/04/FenaPiratePrincess/01.mp4',
        ),
        isTrue,
      );
    });

    test('accepts HLS playlists and query strings', () {
      expect(
        isDirectMediaUrl('https://cdn.example.com/a/b/index.m3u8?token=abc'),
        isTrue,
      );
    });

    test('rejects ordinary page URLs', () {
      expect(
        isDirectMediaUrl('https://ani.girigirilove.com/voddetail/6547.html'),
        isFalse,
      );
      expect(isDirectMediaUrl('about:blank'), isFalse);
      expect(isDirectMediaUrl('not a url'), isFalse);
    });

    test('does not mistake page paths for media', () {
      expect(isDirectMediaPath('/play/123.mp4.html'), isFalse);
    });

    test('distinguishes HLS from MP4 for the demuxer hint', () {
      expect(
        isHlsMediaUrl(
          'https://akua.girigirilove.com/zijian/41/playlist.m3u8?token=1',
        ),
        isTrue,
      );
      expect(
        isHlsMediaUrl(
          'https://ana.girigirilove.com/zijian/oldanime/2002/04/01.mp4',
        ),
        isFalse,
      );
    });
  });
}
