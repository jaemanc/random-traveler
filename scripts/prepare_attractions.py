"""Bundle landmark previews with Wikimedia author and license metadata."""
import concurrent.futures
import html
import io
import json
import re
import subprocess
import time
from pathlib import Path
from urllib.parse import quote, unquote, urlparse
from PIL import Image

LANDMARKS = {
'Seoul': ['Gyeongbokgung','N Seoul Tower','Bukchon Hanok Village','Changdeokgung','Cheonggyecheon','Dongdaemun Design Plaza','Lotte World Tower','Deoksugung'],
'Busan': ['Haeundae Beach','Gwangalli Beach','Gamcheon Culture Village','Haedong Yonggungsa','Busan Tower','Jagalchi Market','Gwangandaegyo','Taejongdae'],
'Jeju': ['Hallasan','Seongsan Ilchulbong','Manjanggul','Jeju Stone Park','Jeongbang Waterfall','Cheonjiyeon Waterfall','Jusangjeolli Cliff','Udo (island)'],
'Tokyo': ['Tokyo Tower','Sensō-ji','Shibuya Crossing','Tokyo Skytree','Meiji Shrine','Tokyo Imperial Palace','Rainbow Bridge (Tokyo)','Shinjuku Gyo-en'],
'Fukuoka': ['Fukuoka Tower','Dazaifu Tenmangu','Ōhori Park','Kushida Shrine','Canal City Hakata','Fukuoka Castle','Hakata Station','Uminonakamichi Seaside Park'],
'Osaka': ['Osaka Castle','Dōtonbori','Tsūtenkaku','Universal Studios Japan','Shitennō-ji','Umeda Sky Building','Kuromon Ichiba Market','Osaka Aquarium Kaiyukan'],
'Taipei': ['Taipei 101','Chiang Kai-shek Memorial Hall','National Palace Museum','Lungshan Temple','Shilin Night Market','Elephant Mountain (Taipei)','Ximending','Taipei Grand Mosque'],
'Bangkok': ['Grand Palace','Wat Arun','Wat Pho','Chatuchak Weekend Market','Khaosan Road','Lumphini Park','Wat Saket','Siam Paragon'],
'Singapore': ['Marina Bay Sands','Gardens by the Bay','Merlion','Singapore Botanic Gardens','Jewel Changi Airport','Sentosa','ArtScience Museum','Singapore Flyer'],
'Hong Kong': ['Victoria Harbour','Victoria Peak','Tian Tan Buddha','Star Ferry','Wong Tai Sin Temple','Hong Kong Disneyland','Man Mo Temple','Tsing Ma Bridge'],
'Paris': ['Eiffel Tower','Louvre Museum','Arc de Triomphe','Notre-Dame de Paris','Sacré-Cœur, Paris','Palace of Versailles','Pont Alexandre III','Montmartre'],
'London': ['Big Ben','Tower Bridge','Buckingham Palace','London Eye','British Museum','St Paul\'s Cathedral','Westminster Abbey','The Shard'],
'New York': ['Statue of Liberty','Central Park','Empire State Building','Brooklyn Bridge','Times Square','One World Trade Center','Chrysler Building','Grand Central Terminal'],
'Los Angeles': ['Hollywood Sign','Griffith Observatory','Santa Monica Pier','Getty Center','Venice Beach','Universal Studios Hollywood','Walt Disney Concert Hall','Hollywood Walk of Fame'],
}

def curl(url):
    for attempt in range(4):
        time.sleep(0.3)
        result=subprocess.run(['curl','-sSL','--max-time','20','-w','\n%{http_code}','-H','User-Agent: ElsewhereTravel/1.0 (travel app; contact via GitHub)',url],capture_output=True,check=True)
        body,code=result.stdout.rsplit(b'\n',1)
        if code==b'200':return body
        if code!=b'429':raise RuntimeError(f'HTTP {code.decode()}')
        time.sleep(2**attempt)
    raise RuntimeError('HTTP 429')

def fetch(item):
    city,title=item
    try:
        summary=json.loads(curl('https://en.wikipedia.org/api/rest_v1/page/summary/'+quote(title.replace(' ','_'))))
        thumb=summary.get('thumbnail',{}).get('source')
        if not thumb or '.svg' in thumb.lower() or 'logo' in thumb.lower():return None
        path=urlparse(thumb).path
        name=unquote(path.split('/')[-2] if '/thumb/' in path else path.split('/')[-1])
        api='https://commons.wikimedia.org/w/api.php?action=query&prop=imageinfo&iiprop=extmetadata&format=json&titles=File:'+quote(name)
        pages=json.loads(curl(api))['query']['pages']
        meta=next(iter(pages.values())).get('imageinfo',[{}])[0].get('extmetadata',{})
        license=meta.get('LicenseShortName',{}).get('value','')
        if not (license.startswith('CC BY') or license.startswith('CC0') or 'Public domain' in license):return None
        author=re.sub('<[^>]+>','',meta.get('Artist',{}).get('value','Unknown'))
        author=html.unescape(author).strip()[:100]
        raw=curl(thumb)
        im=Image.open(io.BytesIO(raw)).convert('RGB')
        if im.width<250 or im.height<170:return None
        slug=re.sub('[^a-z0-9]+','-',title.lower()).strip('-')
        dest=Path('assets/attractions')/(city.lower().replace(' ','-')+'-'+slug+'.jpg')
        im.thumbnail((800,600))
        im.save(dest,quality=86,optimize=True)
        return city, {'title':summary.get('title',title),'asset':str(dest),'author':author,'license':license,'source':'https://commons.wikimedia.org/wiki/File:'+quote(name.replace(' ','_'))}
    except Exception as e:
        print('skip',city,title,type(e).__name__,getattr(e,'stderr',b'')[:100])
        return None

if __name__ == "__main__":
    results={city:[] for city in LANDMARKS}
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
        for result in pool.map(fetch,((c,t) for c,titles in LANDMARKS.items() for t in titles)):
            if result:
                city,photo=result
                if len(results[city])<6:results[city].append(photo)
    Path('assets/attractions.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
    print({city:len(photos) for city,photos in results.items()})
