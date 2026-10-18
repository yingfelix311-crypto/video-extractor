import importlib.util
import json
from pathlib import Path
import unittest

from yt_dlp import YoutubeDL
from yt_dlp.utils import ExtractorError

source = Path(__file__).parents[1] / 'yt_dlp_plugins/extractor/shouxia_douyin.py'
spec = importlib.util.spec_from_file_location('shouxia_douyin_under_test', source)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

ID = '7692712648774080610'
URL = f'https://www.douyin.com/video/{ID}'
MEDIA = 'https://media.example.org/video.mp4?offered=unchanged'


def item(video_id=ID):
    return {'aweme_id': video_id, 'desc': 'fixture video', 'create_time': 123,
            'author': {'nickname': 'fixture author'},
            'video': {'play_addr': {'url_list': [MEDIA]}, 'width': 1440,
                      'height': 2560, 'duration': 230412, 'bit_rate': None}}


def page(items):
    return '<script>window._ROUTER_DATA = ' + json.dumps({
        'loaderData': {'video_(id)/page': {'videoInfoRes': {'item_list': items}}}
    }) + ';</script>'


class Probe(module.DouyinShareIE):
    def __init__(self, html=None, upstream=None, upstream_error=None):
        super().__init__(YoutubeDL({'quiet': True, 'no_warnings': True}))
        self.html = html if html is not None else page([item()])
        self.upstream = upstream
        self.upstream_error = upstream_error
        self.pages = []

    def _download_json(self, *args, **kwargs):
        if self.upstream_error:
            raise self.upstream_error
        return {'aweme_detail': self.upstream} if self.upstream else None

    def _download_webpage(self, url, video_id, *args, **kwargs):
        self.pages.append((url, kwargs))
        return self.html

    def _parse_aweme_video_app(self, detail):
        return {'id': detail['aweme_id'], 'upstream': True}

    def _get_cookies(self, url):
        # A secret-like sentinel must never be placed into returned headers/formats.
        return {'sid_tt': type('Cookie', (), {'value': 'fixture-private-value'})()}

    def _set_cookie(self, *args, **kwargs):
        raise AssertionError('must not forward authentication to media hosts')


class ShareTests(unittest.TestCase):
    def test_fallback_matches_exact_id_and_preserves_offered_stream(self):
        p = Probe(page([item('1'), item()]))
        result = p._real_extract(URL)
        self.assertEqual(result['id'], ID)
        self.assertEqual(result['formats'][0]['url'], MEDIA)
        self.assertEqual(result['duration'], 230.412)
        self.assertEqual(result['formats'][0]['height'], 2560)
        self.assertEqual(len(p.pages), 1)
        self.assertEqual(p.pages[0][0], f'https://www.iesdouyin.com/share/video/{ID}/')
        self.assertIn('Android', p.pages[0][1]['headers']['User-Agent'])
        self.assertNotIn('fixture-private-value', json.dumps(result))

    def test_upstream_success_is_unchanged(self):
        p = Probe(upstream=item())
        self.assertTrue(p._real_extract(URL)['upstream'])
        self.assertEqual(p.pages, [])

    def test_non_cookie_upstream_error_is_preserved(self):
        err = ExtractorError('Network unavailable')
        p = Probe(upstream_error=err)
        with self.assertRaises(ExtractorError) as caught:
            p._real_extract(URL)
        self.assertIs(caught.exception, err)
        self.assertEqual(p.pages, [])

    def test_wrong_id_cannot_download_another_video(self):
        with self.assertRaises(ExtractorError) as caught:
            Probe(page([item('1')]))._real_extract(URL)
        # Native DownloadPolicy treats these terms as a browser-auth failure.
        for term in ('cookie', '登录', '权限', '浏览器配置', '浏览器会话'):
            self.assertNotIn(term, caught.exception.msg.lower())

    def test_missing_and_malformed_data_fail_without_execution(self):
        for html in ('<html>login required</html>',
                     '<script>window._ROUTER_DATA = (() => alert(1))();</script>',
                     page([])):
            with self.subTest(html=html), self.assertRaises(ExtractorError):
                Probe(html)._real_extract(URL)

    def test_non_http_streams_are_rejected(self):
        for url in ('file:///etc/passwd', 'javascript:alert(1)', 'ftp://example.org/v'):
            data = item()
            data['video']['play_addr']['url_list'] = [url]
            with self.subTest(url=url), self.assertRaises(ExtractorError):
                Probe(page([data]))._real_extract(URL)

    def test_multiple_streams_are_deduplicated_and_optional_metadata_is_safe(self):
        data = item()
        data.pop('author'); data.pop('desc')
        data['video']['bit_rate'] = [{'bit_rate': 1000000, 'play_addr': {
            'url_list': [MEDIA, 'https://media.example.org/second.mp4']}}]
        result = Probe(page([data]))._real_extract(URL)
        self.assertEqual(len(result['formats']), 2)
        self.assertEqual(result['title'], ID)

    def test_bitrate_dimensions_allow_requested_lower_resolution(self):
        data = item()
        data['video'].update(width=1920, height=1080, bit_rate=[{
            'bit_rate': 1000000, 'play_addr': {'url_list': ['https://media.example.org/720.mp4'],
                                            'width': 1280, 'height': 720}}])
        p = Probe(page([data]))
        result = p._real_extract(URL)
        self.assertEqual(result['formats'][1]['height'], 720)
        selector = YoutubeDL({'format': 'best[height<=720]', 'check_formats': False, 'quiet': True})
        selected = selector.process_ie_result(result, download=False)
        self.assertEqual(selected['url'], 'https://media.example.org/720.mp4')


if __name__ == '__main__':
    unittest.main()
