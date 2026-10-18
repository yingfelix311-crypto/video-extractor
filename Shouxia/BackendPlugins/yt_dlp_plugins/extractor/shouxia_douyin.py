import json
import re
from urllib.parse import urlsplit

from yt_dlp.extractor.tiktok import DouyinIE as _DouyinIE
from yt_dlp.utils import ExtractorError, float_or_none, int_or_none

__all__ = ['DouyinShareIE']


class DouyinShareIE(_DouyinIE, plugin_name='shouxia_mobile_share'):
    _MOBILE_UA = (
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36')

    def _real_extract(self, url):
        try:
            return super()._real_extract(url)
        except ExtractorError as error:
            # A different upstream failure (e.g. transport or unavailable video)
            # must not be silently replaced with an authentication diagnosis.
            if 'Fresh cookies' not in error.msg:
                raise

        video_id = self._match_id(url)
        webpage = self._download_webpage(
            f'https://www.iesdouyin.com/share/video/{video_id}/', video_id,
            note='Downloading mobile share page',
            headers={'User-Agent': self._MOBILE_UA, 'Referer': self._WEBPAGE_HOST},
            impersonate='chrome-131:android-14', require_impersonation=True)
        marker = re.search(r'window\._ROUTER_DATA\s*=\s*', webpage)
        try:
            data, _ = json.JSONDecoder().raw_decode(webpage[marker.end():]) if marker else (None, 0)
            items = data['loaderData']['video_(id)/page']['videoInfoRes']['item_list']
            detail = next(item for item in items
                          if isinstance(item, dict) and str(item.get('aweme_id')) == video_id)
        except (ValueError, TypeError, KeyError, StopIteration, AttributeError):
            raise ExtractorError(
                '抖音平台解析暂不可用：接口与分享页均未返回该视频信息。'
                '请确认网页能播放后重试，或等待解析器更新。', expected=True)
        return self._share_video_result(detail, video_id)

    def _share_video_result(self, detail, video_id):
        video = detail.get('video') or {}
        if not isinstance(video, dict):
            video = {}
        addresses = [(video.get('play_addr'), None, True)]
        bitrates = video.get('bit_rate')
        for bitrate in bitrates if isinstance(bitrates, list) else []:
            if isinstance(bitrate, dict):
                addresses.append((bitrate.get('play_addr'), int_or_none(bitrate.get('bit_rate'), scale=1000), False))

        formats, seen = [], set()
        for address, tbr, primary in addresses:
            if not isinstance(address, dict):
                continue
            urls = address.get('url_list')
            for media_url in urls if isinstance(urls, list) else []:
                if not isinstance(media_url, str):
                    continue
                try:
                    parsed = urlsplit(media_url)
                    valid = (parsed.scheme in ('https', 'http') and parsed.hostname
                             and not parsed.username and not parsed.password)
                except ValueError:
                    valid = False
                if not valid or media_url in seen:
                    continue
                seen.add(media_url)
                formats.append({
                    'format_id': f'mobile-share-{len(formats)}', 'url': media_url,
                    'ext': 'mp4',
                    'width': int_or_none(address.get('width')) or (int_or_none(video.get('width')) if primary else None),
                    'height': int_or_none(address.get('height')) or (int_or_none(video.get('height')) if primary else None),
                    'tbr': tbr,
                    'filesize': int_or_none(address.get('data_size')),
                })
        if not formats:
            raise ExtractorError('抖音分享页没有可下载的视频播放地址。', expected=True)

        author = detail.get('author')
        return {
            'id': video_id, 'title': detail.get('desc') or video_id,
            'description': detail.get('desc'),
            'duration': float_or_none(video.get('duration'), scale=1000),
            'timestamp': int_or_none(detail.get('create_time')),
            'uploader': author.get('nickname') if isinstance(author, dict) else None,
            'formats': formats,
            # Keep credentials in the downloader's domain-scoped jar. In
            # particular, do not copy sid_tt to arbitrary media host cookies.
            'http_headers': {'User-Agent': self._MOBILE_UA, 'Referer': self._WEBPAGE_HOST},
        }
