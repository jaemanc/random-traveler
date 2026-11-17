import json
from pathlib import Path
from prepare_attractions import fetch

EXTRA={
'Seoul':['Seoul','Seoul City Hall','War Memorial of Korea','Bongeunsa','Banpo Bridge','Bukhansan','Seoul Forest'],
'Jeju':['Jeju Island','Jeju City','Hallim Park','Seopjikoji','Jeju Loveland','Hamdeok Beach'],
'Osaka':['Osaka','Osaka Station','Sumiyoshi Taisha','Shinsekai','Abeno Harukas','Namba'],
'Taipei':['Taipei','Taipei Fine Arts Museum','Daan Forest Park','Bopiliao Historical Block','Beitou Hot Spring','Maokong','Sun Yat-sen Memorial Hall (Taipei)'],
'Singapore':['Singapore','National Gallery Singapore','Esplanade – Theatres on the Bay','Clarke Quay','Chinatown, Singapore','Fort Canning Park'],
'Hong Kong':['Hong Kong','Avenue of Stars, Hong Kong','Hong Kong Convention and Exhibition Centre','Ngong Ping 360','Hong Kong Museum of Art','Peak Tram','Tsim Sha Tsui'],
'Paris':['Paris','Louvre Pyramid','Musée d\'Orsay','Sainte-Chapelle','Pont Neuf','Champs-Élysées','Tuileries Garden'],
'New York':['New York City','Rockefeller Center','Flatiron Building','High Line','Metropolitan Museum of Art','Washington Square Park','Ellis Island'],
'Los Angeles':['Los Angeles','Griffith Park','Hollywood Bowl','Los Angeles County Museum of Art','Rodeo Drive','La Brea Tar Pits','Los Angeles City Hall'],
}
path=Path('assets/attractions.json');results=json.loads(path.read_text())
for city,titles in EXTRA.items():
 for title in titles:
  if len(results[city])>=6:break
  item=fetch((city,title))
  if item and all(p['asset']!=item[1]['asset'] for p in results[city]):
   results[city].append(item[1]);path.write_text(json.dumps(results,ensure_ascii=False,indent=2))
 print(city,len(results[city]),flush=True)
