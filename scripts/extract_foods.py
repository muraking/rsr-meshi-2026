import json
import re
import unicodedata
from pathlib import Path
from lxml import html

ROOT = Path(__file__).resolve().parents[1]
SOURCE_URL = "https://rsr.wess.co.jp/2026/site/food_shop/"

RULES = {
    "麺": ["ラーメン", "らーめん", "らぁ麺", "うどん", "そば", "焼きそば", "パスタ", "麺", "油そば"],
    "ご飯": ["丼", "飯", "ごはん", "おにぎり", "カレー", "ライス", "ロコモコ"],
    "カレー": ["カレー", "イシカリー"],
    "肉": ["牛", "豚", "鶏", "肉", "ジンギスカン", "ホルモン", "ステーキ", "ソーセージ", "フランク", "ザンギ", "チキン", "チャーシュー", "カルビ"],
    "海鮮": ["海鮮", "たこ", "タコ", "いか", "イカ", "えび", "エビ", "かに", "カニ", "鮭", "サーモン", "帆立", "ホタテ", "まぐろ", "マグロ"],
    "軽食": ["ポテト", "たこ焼き", "餃子", "ホットドッグ", "ドッグ", "バーガー", "サンド", "フランク", "ザンギ", "唐揚", "串", "フライ", "ピザ", "ブロッコリー"],
    "スイーツ": ["アイス", "ソフトクリーム", "かき氷", "フルーツ", "ケーキ", "クレープ", "ドーナツ", "飴", "いちご", "メロン", "パフェ", "チョコ", "スムージー", "プリン", "タルト"],
    "朝食": ["朝食", "モーニング", "おにぎり", "スープ", "コーヒー"],
    "飲み物": ["ビール", "ハイボール", "サワー", "チューハイ", "日本酒", "焼酎", "カクテル", "ワイン", "酒", "コーヒー", "ラテ", "ジュース", "ソーダ", "ドリンク", "茶", "水", "ポカリ", "レモネード", "シェイク"],
}

# Approximate centers georeferenced from the official 2026 festival map (Aug. 7
# revision) against the official Google Maps venue POI. These are area centers,
# not individual tent surveys, and must only be presented as estimates.
AREA_COORDS = {
    "Water Station": (43.175210, 141.292910),
    "Tarukawa Restaurant": (43.177370, 141.294850),
    "Radio FOOD＆BAR": (43.177690, 141.292080),
    "Bannaguro Restaurant with 石狩市場×小樽横丁": (43.179060, 141.293830),
    "Matsuri Café": (43.178800, 141.292780),
    "Hamanasu Restaurant": (43.178110, 141.287720),
    "PROVO FOOD & BAR": (43.177610, 141.286050),
    "オフィシャルダイニング チュプ": (43.174990, 141.288850),
    "Oyahuru Restaurant & Decorate": (43.175130, 141.286440),
    "Hachiman Restaurant & Decorate": (43.177170, 141.284180),
    "Bitoi Restaurant": (43.176340, 141.282810),
    "Forest Restaurant": (43.172940, 141.279930),
    "RED STAR CAFE": (43.178270, 141.280970),
    "Happiness CarRestaurant": (43.181300, 141.284760),
    "greentope": (43.179860, 141.281830),
}

def clean(value):
    return re.sub(r"\s+", " ", value or "").strip()

def slug(value):
    value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z0-9]+", "-", value).strip("-")

def categories(name):
    found = [cat for cat, words in RULES.items() if any(word.lower() in name.lower() for word in words)]
    return found or ["その他"]

doc = html.fromstring((ROOT / "official-food-raw.html").read_bytes())
shops = []
for area_node in doc.xpath('//div[contains(concat(" ", normalize-space(@class), " "), " page_paragraph ")]'):
    heading = area_node.xpath("./h2")
    cards = area_node.xpath('.//a[contains(concat(" ", normalize-space(@class), " "), " food_shop_list_item ")]')
    if not heading or not cards:
        continue
    area = clean(heading[0].text_content())
    for card in cards:
        href = card.get("href", "")
        if not href.startswith("#"):
            continue
        modal_nodes = doc.xpath(f'//*[@id="{href[1:]}"]')
        if not modal_nodes:
            continue
        modal = modal_nodes[0]
        name_nodes = card.xpath('.//*[contains(concat(" ", normalize-space(@class), " "), " food_shop_title ")]')
        image_nodes = card.xpath('.//img')
        name = clean(name_nodes[0].text_content()) if name_nodes else "名称未掲載"
        image_url = image_nodes[0].get("src", "") if image_nodes else ""
        blocks = modal.xpath('.//*[contains(concat(" ", normalize-space(@class), " "), " modal_body ")]//*[contains(concat(" ", normalize-space(@class), " "), " parents ")]')
        special_names, other_names, description, pr = [], [], "", ""
        info_links = []
        for block in blocks:
            title_nodes = block.xpath('.//h3')
            title = clean(title_nodes[0].text_content()) if title_nodes else ""
            list_items = [clean(x.text_content()) for x in block.xpath('.//li') if clean(x.text_content())]
            strong = [clean(x.text_content()) for x in block.xpath('.//strong') if clean(x.text_content())]
            paras = [clean(x.text_content()) for x in block.xpath('.//p') if clean(x.text_content())]
            if "RSRスペシャル" in title:
                special_names = strong or (paras[:1] if paras else [])
                description = " ".join(paras[1:])
            elif "その他のメニュー" in title:
                other_names = list_items
            elif "店舗PR" in title:
                pr = " ".join(paras)
            elif "店舗情報" in title:
                info_links.extend(a.get("href") for a in block.xpath('.//a[@href]') if a.get("href", "").startswith("http"))
        menus = []
        for index, menu_name in enumerate(special_names + other_names):
            is_special = index < len(special_names)
            cats = categories(menu_name)
            tags = (["RSRスペシャル"] if is_special else [])
            for tag in ["辛い", "ごま", "チーズ", "にんにく", "限定", "北海道産"]:
                if tag in menu_name or (is_special and tag in description):
                    tags.append(tag)
            menus.append({"id": f"{href[1:]}-m{index+1}", "name": menu_name, "special": is_special, "categories": cats, "tags": tags})
        if not menus:
            card_menu = card.xpath('.//*[contains(concat(" ", normalize-space(@class), " "), " food_shop_menu ")]')
            fallback = clean(card_menu[0].text_content()) if card_menu else "メニュー詳細は公式情報へ"
            menus.append({"id": f"{href[1:]}-m1", "name": fallback, "special": False, "categories": ["その他"], "tags": ["詳細未掲載"]})
        coord = AREA_COORDS.get(area)
        shops.append({
            "id": href[1:], "name": name, "area": area, "imageUrl": image_url,
            "sourceUrl": SOURCE_URL + href, "externalUrl": info_links[0] if info_links else None,
            "description": pr, "menus": menus,
            "lat": coord[0] if coord else None, "lng": coord[1] if coord else None,
            "coordinateType": "estimated-area-center" if coord else "unavailable",
            "coordinateSource": "RSR2026公式会場マップ（8月7日更新）と公式Google Maps会場POIによる推定" if coord else None,
            "tabelogUrl": None, "tabelogScore": None
        })

output = {"sourceUrl": SOURCE_URL, "retrievedAt": "2026-08-12", "shops": shops}
(ROOT / "data").mkdir(exist_ok=True)
(ROOT / "data" / "shops.json").write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"stores={len(shops)} menus={sum(len(s['menus']) for s in shops)} uncategorized={sum(1 for s in shops for m in s['menus'] if m['categories']==['その他'])}")
