#!/usr/bin/env python3
"""Generates the deterministic fixture API served by FixtureTransport.

The JSON mirrors the production API contract (snake_case, integer cents, ISO-8601 dates), so the
exact same DTO decoding + mapping code runs against fixtures and the real backend.
Run: python3 scripts/generate_fixtures.py
"""
import json, random, os
from datetime import datetime, timedelta, timezone

OUT = os.path.join(os.path.dirname(__file__), "..", "Packages/NovaKit/Sources/Data/Fixtures")
random.seed(42)

def img(pid):
    return f"https://images.unsplash.com/photo-{pid}?auto=format&fit=crop&q=75"

P = {
    "floral_wrap": "1496747611176-843222e1e57c", "blue_beach": "1539008835657-9e8e9680c956",
    "red_maxi": "1595777457583-95e059d581b8", "denim_dress": "1591369822096-ffd140ec948f",
    "polka": "1502716119720-b23a93e5fe1b", "red_floral": "1572804013309-59a88b7e92f1",
    "velvet": "1566174053879-31528523f8ae", "gown": "1612336307429-8a898d10e223",
    "poncho": "1434389677669-e08b4cac3105", "tee": "1564584217132-2271feaeb3c5",
    "blouse": "1583846717393-dc2412c95ed7", "sheer": "1524504388940-b1c1722653e1",
    "ripped": "1541099649105-f69ad21f3246", "relaxed": "1506629082955-511b1aa562c8",
    "jogger": "1594633312681-425c7b97ccd1", "stripe": "1509631179647-0177331693ae",
    "romper": "1618932260643-eee4a2f652a6", "plaid": "1485968579580-b6d095142e6e",
    "biker": "1551028719-00167b16eac5", "noir": "1554412933-514a83d2f3c8",
    "denim_jacket": "1517841905240-472988babdf9", "burgundy": "1483985988355-763728e1935b",
    "sunnies": "1511499767150-a48a237f0083", "bag": "1584917865442-de89df76afd3",
    "heels": "1543163521-1bf539c55dd2", "pink_ruffle": "1581044777550-4cfa60707c03",
    "rack": "1490481651871-ab68de25d43d", "rack2": "1603400521630-9f2de124b33b",
    "flatlay": "1525507119028-ed4c629a60a3", "yellow": "1515886657613-9f3515b0c78f",
    "milan": "1539109136881-3be0616acf4b", "tees": "1562157873-818bc0726f68",
    "shades_woman": "1469334031218-e382a71b716b", "hood": "1487222477894-8943e31ef7b2", "daisy": "1529139574466-a303027c1d8b",
}

C = {  # palette names match the design's swatches
    "Taupe Floral": "#D9BFA9", "Rust": "#A0522D", "Sage": "#8A9A7B", "Ivory": "#F4EDE2",
    "Sand": "#D8C3A5", "Charcoal": "#4A4A4A", "Navy": "#1F2A44", "Crimson": "#B22234",
    "Blush": "#E8C4C0", "Denim": "#5B7DA8", "Black": "#1C1C1C", "Plum": "#5E2750",
    "Olive": "#6B6B3A", "Cognac": "#9A5B34", "Sky": "#A9C4DE", "Cream": "#EFE6D8",
}
def colors(*names): return [{"name": n, "hex": C[n]} for n in names]
ALL = ["XS", "S", "M", "L", "XL"]

now = datetime(2026, 9, 1, tzinfo=timezone.utc)
products = []
def add(pid, name, price, cat, style, images, cols, sizes=ALL, rating=4.6, reviews=120, tags=(), compare=None,
        in_stock=True, days_ago=30, popularity=100, summary="", details=()):
    products.append({
        "id": pid, "name": name, "brand": "NovaShop", "price_cents": int(price * 100),
        "compare_at_cents": int(compare * 100) if compare else None, "category_id": cat, "style": style,
        "images": [img(P[i]) for i in images], "colors": colors(*cols), "sizes": sizes, "rating": rating,
        "review_count": reviews, "summary": summary, "details": list(details), "tags": list(tags),
        "in_stock": in_stock, "released_at": (now - timedelta(days=days_ago)).isoformat().replace("+00:00", "Z"),
        "popularity": popularity,
    })

LINEN = ["100% European linen", "Relaxed fit — take your usual size", "Machine wash cold, line dry", "Model is 5'9\" and wears S"]
add("amelie-floral-midi", "Amelie Floral Midi Dress", 129, "dresses", "Midi", ["floral_wrap", "red_floral", "polka", "pink_ruffle", "red_maxi", "blue_beach"],
    ["Taupe Floral", "Rust", "Sage"], rating=4.8, reviews=320, tags=["new", "best-seller"], days_ago=4, popularity=980,
    summary="A breezy wrap midi in a soft painterly floral. Flutter sleeves, a tie waist and a skirt that moves beautifully.",
    details=["Viscose crepe, lined bodice", "Adjustable tie waist", "Midi length — 47\" from shoulder", "Machine wash cold"])
add("isla-linen", "Isla Linen Dress", 99, "dresses", "Maxi", ["blue_beach", "floral_wrap", "milan"], ["Sky", "Ivory", "Sand"],
    rating=4.7, reviews=184, tags=["new", "linen-edit"], days_ago=6, popularity=760,
    summary="Our lightest linen, cut into a bias-draped maxi with a thigh-high slit.", details=LINEN)
add("rosie-maxi", "Rosie Maxi Dress", 139, "dresses", "Maxi", ["red_maxi", "gown", "red_floral"], ["Crimson", "Blush"],
    rating=4.9, reviews=96, tags=["best-seller"], days_ago=40, popularity=640,
    summary="A sweeping chiffon maxi with a fitted bodice — made for golden hour.",
    details=["Recycled chiffon", "Concealed back zip", "Fully lined", "Dry clean recommended"])
add("luna-mini", "Luna Denim Mini Dress", 89, "dresses", "Mini", ["denim_dress", "denim_jacket"], ["Denim", "Sky"],
    rating=4.5, reviews=77, days_ago=15, popularity=410, compare=110,
    summary="A washed-denim shirt dress with pearl snaps and a swingy skater skirt.",
    details=["100% cotton denim", "Pearl snap placket", "Side seam pockets"])
add("rhea-polka", "Rhea Polka Dress", 119, "dresses", "Midi", ["polka", "red_floral"], ["Crimson", "Ivory"],
    rating=4.6, reviews=142, tags=["linen-edit"], days_ago=22, popularity=520,
    summary="Playful polka dots on a floaty tiered midi.", details=["Linen-viscose blend", "Smocked back", "Tiered skirt"])
add("maya-wrap", "Maya Wrap Dress", 109, "dresses", "Midi", ["red_floral", "polka"], ["Crimson", "Taupe Floral"],
    rating=4.4, reviews=58, days_ago=60, popularity=300, compare=139, summary="A true wrap dress with a belted waist.",
    details=["Cotton poplin", "Removable belt", "Midi length"])
add("vera-velvet", "Vera Velvet Dress", 149, "dresses", "Formal", ["velvet", "gown"], ["Plum", "Black"], rating=4.8, reviews=64,
    days_ago=12, popularity=280, tags=["new"], summary="Off-shoulder stretch velvet — evening, sorted.",
    details=["Stretch velvet", "Boned bodice", "Knee length"])
add("scarlet-gown", "Scarlet Column Gown", 189, "dresses", "Formal", ["gown", "red_maxi"], ["Crimson"], rating=4.9, reviews=41,
    days_ago=80, popularity=150, in_stock=False, summary="A column gown with a dramatic draped train.",
    details=["Crepe satin", "Draped train", "Invisible zip"])

add("sophia-knit", "Sophia Knit Poncho", 89, "tops", "Knit", ["poncho", "rack"], ["Ivory", "Sand"], rating=4.7, reviews=210,
    tags=["new", "linen-edit"], days_ago=3, popularity=700, summary="Open-weave cotton knit with a fringed hem.",
    details=["100% organic cotton", "Hand-finished fringe", "One size fits most"], sizes=["One Size"])
add("luna-linen-top", "Luna Linen Tee", 39, "tops", "Tee", ["tee", "tees"], ["Sky", "Ivory", "Black"], rating=4.5, reviews=330,
    tags=["linen-edit", "best-seller"], days_ago=50, popularity=1200, summary="The everyday tee, in breathable linen jersey.", details=LINEN)
add("clara-blouse", "Clara Silk Blouse", 79, "tops", "Blouse", ["blouse", "sheer"], ["Ivory", "Black"], rating=4.6, reviews=88,
    days_ago=18, popularity=390, summary="Washable silk with a pussy-bow neckline.", details=["100% washable silk", "Covered buttons"])
add("nora-sheer", "Nora Sheer Top", 69, "tops", "Blouse", ["sheer", "blouse"], ["Black"], rating=4.3, reviews=35, days_ago=9,
    tags=["new"], popularity=180, compare=85, summary="Sheer georgette with a soft drape.", details=["Recycled georgette", "Relaxed fit"])

add("harper-jeans", "Harper Distressed Jeans", 85, "denim", "Straight", ["ripped", "relaxed"], ["Denim"], rating=4.4, reviews=150,
    days_ago=35, popularity=560, summary="Vintage-wash straight leg with hand distressing.", details=["Rigid cotton denim", "High rise", "Straight leg"])
add("ava-relaxed", "Ava Wide Leg Jeans", 95, "denim", "Wide Leg", ["relaxed", "ripped"], ["Sky", "Denim"], rating=4.7, reviews=260,
    tags=["best-seller"], days_ago=28, popularity=880, summary="A light-wash wide leg that sits at the natural waist.",
    details=["Organic cotton", "Wide leg", "Full length"])
add("blush-jogger", "Blush Tailored Jogger", 75, "denim", "Jogger", ["jogger"], ["Blush"], rating=4.2, reviews=44, days_ago=70,
    popularity=120, compare=95, summary="Pleated tailored joggers with button tabs.", details=["Poly-viscose twill", "Elastic cuff"])
add("olive-playsuit", "Olive Playsuit", 69, "denim", "Jumpsuit", ["romper"], ["Olive"], rating=4.5, reviews=52, days_ago=14,
    popularity=210, tags=["linen-edit"], summary="A belted linen playsuit for warm days.", details=LINEN)

add("plaid-coat", "Harlow Plaid Coat", 169, "outerwear", "Coat", ["plaid", "burgundy"], ["Navy", "Charcoal"], rating=4.8, reviews=73,
    days_ago=20, popularity=330, summary="Wool-blend check coat with a relaxed shoulder.", details=["60% wool", "Fully lined", "Two flap pockets"])
add("biker-jacket", "Moto Leather Jacket", 199, "outerwear", "Jacket", ["biker"], ["Black"], rating=4.9, reviews=119, days_ago=90,
    popularity=610, tags=["best-seller"], summary="Buttery lamb leather biker.", details=["Lamb leather", "YKK zips", "Quilted lining"])
add("noir-coat", "Noir Button Coat", 219, "outerwear", "Coat", ["noir"], ["Black"], rating=4.6, reviews=28, days_ago=5,
    tags=["new"], popularity=90, summary="A fitted, double-row button coat.", details=["Wool-cashmere", "Knee length"])
add("denim-jacket", "Classic Denim Jacket", 110, "outerwear", "Jacket", ["denim_jacket"], ["Denim"], rating=4.5, reviews=190,
    days_ago=45, popularity=470, summary="The trucker jacket, softened.", details=["Cotton denim", "Chest pockets"])

add("elise-sunglasses", "Elise Sunglasses", 59, "accessories", "Sunglasses", ["sunnies", "shades_woman"], ["Cognac", "Black"],
    rating=4.6, reviews=97, tags=["new"], days_ago=2, popularity=540, sizes=["One Size"],
    summary="Round metal frames with polarised lenses.", details=["UV400 polarised lenses", "Gold-tone metal", "Case included"])
add("rouge-bag", "Rouge Top-Handle Bag", 149, "bags", "Top Handle", ["bag"], ["Crimson", "Cognac"], rating=4.7, reviews=66,
    days_ago=11, popularity=330, sizes=["One Size"], summary="Structured leather top-handle with a turn lock.",
    details=["Full-grain leather", "Detachable strap", "Suede lined"])
add("flora-heels", "Flora Stiletto Heels", 129, "shoes", "Heels", ["heels"], ["Sky"], rating=4.3, reviews=38, days_ago=25,
    popularity=160, sizes=["S", "M", "L"], compare=159, summary="Printed satin stilettos.", details=["Satin upper", "100mm heel"])

categories = [
    {"id": "dresses", "name": "Dresses", "image": img(P["floral_wrap"]), "styles": ["Maxi", "Midi", "Mini", "Formal"]},
    {"id": "tops", "name": "Tops", "image": img(P["poncho"]), "styles": ["Knit", "Tee", "Blouse"]},
    {"id": "denim", "name": "Denim", "image": img(P["ripped"]), "styles": ["Straight", "Wide Leg", "Jogger", "Jumpsuit"]},
    {"id": "shoes", "name": "Shoes", "image": img(P["heels"]), "styles": []},
    {"id": "bags", "name": "Bags", "image": img(P["bag"]), "styles": []},
    {"id": "outerwear", "name": "Outerwear", "image": img(P["plaid"]), "styles": ["Coat", "Jacket"]},
    {"id": "accessories", "name": "Accessories", "image": img(P["sunnies"]), "styles": []},
]

collections = [
    {"id": "new-season", "eyebrow": "NEW SEASON", "title": "Modern Style Lives Here",
     "subtitle": "Elevated essentials for a brighter you.", "cta_title": "Shop New Season",
     "hero_image": img(P["pink_ruffle"]), "editorial_images": [img(P["rack"]), img(P["yellow"])],
     "story_title": "Made to Move", "story_body": "Fluid shapes and warm neutrals, designed to take you from sunlit mornings to long evenings.",
     "product_tag": "new"},
    {"id": "linen-edit", "eyebrow": "NEW COLLECTION", "title": "The Linen Edit",
     "subtitle": "Timeless pieces for sunny days ahead.", "cta_title": "Shop the Collection",
     "hero_image": img(P["blue_beach"]), "editorial_images": [img(P["rack2"]), img(P["flatlay"])],
     "story_title": "Effortless by Nature", "story_body": "Lightweight fabrics, relaxed silhouettes and everyday elegance.",
     "product_tag": "linen-edit"},
]

catalog = {"categories": categories, "products": products, "collections": collections,
           "popular_searches": ["Linen dress", "Summer tops", "Wide leg jeans", "Sunglasses", "Shoulder bags"]}

NAMES = ["Sophia L.", "Olivia C.", "Emma W.", "Ava R.", "Mia K.", "Isabella T.", "Charlotte P.", "Amelia D.", "Harper G.",
         "Evelyn S.", "Luna M.", "Chloe B.", "Grace H.", "Zoe F.", "Nora J."]
BODIES = {
    5: ["Absolutely love this! The fit is perfect and the quality is amazing.", "Got so many compliments wearing this.",
        "True to size and the fabric feels expensive.", "Beautiful colour, even nicer in person.", "My new favourite — ordering another colour."],
    4: ["Lovely piece, runs very slightly large.", "Great quality, delivery was quick.", "Really pretty, wish it had pockets."],
    3: ["Nice but the colour is a bit different from the photos.", "Okay fit, fabric wrinkles easily."],
    2: ["Didn't work on my frame, returning."], 1: ["Arrived with a loose seam."],
}
reviews = {}
for p in products:
    n = 14 if p["id"] == "amelie-floral-midi" else random.randint(5, 10)
    out = []
    for i in range(n):
        r = random.choices([5, 4, 3, 2, 1], weights=[72, 20, 6, 2, 0.5] if p["rating"] >= 4.6 else [50, 30, 12, 6, 2])[0]
        photos = [p["images"][i % len(p["images"])]] if i % 3 == 0 else []
        out.append({"id": f"{p['id']}-r{i}", "product_id": p["id"], "author": random.choice(NAMES), "rating": r,
                    "body": random.choice(BODIES[r]), "date": (now - timedelta(days=random.randint(1, 200))).isoformat().replace("+00:00", "Z"),
                    "is_verified": random.random() > 0.25, "photo_urls": photos})
    out.sort(key=lambda x: x["date"], reverse=True)
    # Server-side aggregate across *all* reviews; the list is just the first page.
    dist = {"5": 0.72, "4": 0.20, "3": 0.06, "2": 0.02, "1": 0.0} if p["rating"] >= 4.6 else \
           {"5": 0.52, "4": 0.28, "3": 0.12, "2": 0.06, "1": 0.02}
    reviews[p["id"]] = {"summary": {"average": p["rating"], "total": p["review_count"], "distribution": dist}, "items": out}

notifications = [
    {"id": "n1", "kind": "order", "title": "Your order has shipped", "body": "Order #NS123456 is on its way. Track it anytime.",
     "date": (now - timedelta(hours=3)).isoformat().replace("+00:00", "Z"), "is_read": False},
    {"id": "n2", "kind": "promotion", "title": "The Linen Edit is here", "body": "Timeless pieces for sunny days. Use SUMMER20 for 20% off.",
     "date": (now - timedelta(days=1)).isoformat().replace("+00:00", "Z"), "is_read": False},
    {"id": "n3", "kind": "system", "title": "Price drop on your wishlist", "body": "Luna Denim Mini Dress is now $89.",
     "date": (now - timedelta(days=3)).isoformat().replace("+00:00", "Z"), "is_read": True},
    {"id": "n4", "kind": "promotion", "title": "Welcome to NovaShop", "body": "Enjoy 10% off your first order with WELCOME10.",
     "date": (now - timedelta(days=9)).isoformat().replace("+00:00", "Z"), "is_read": True},
]

os.makedirs(OUT, exist_ok=True)
for name, data in [("catalog", catalog), ("reviews", reviews), ("notifications", notifications)]:
    with open(os.path.join(OUT, f"{name}.json"), "w") as f:
        json.dump(data, f, separators=(",", ":"))
print(f"{len(products)} products, {sum(len(v["items"]) for v in reviews.values())} reviews")

# ─────────────────────────────────────────────────────────────────────────────
# Supabase seed — same data, one source of truth for fixtures and the real backend.
# ─────────────────────────────────────────────────────────────────────────────
SEED = os.path.join(os.path.dirname(__file__), "..", "supabase", "seed.sql")

def q(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, (list, dict)) and not (isinstance(value, list) and all(isinstance(v, str) for v in value)):
        return "'" + json.dumps(value).replace("'", "''") + "'::jsonb"
    if isinstance(value, list):
        return "array[" + ", ".join(q(v) for v in value) + "]::text[]" if value else "'{}'::text[]"
    return "'" + str(value).replace("'", "''") + "'"

def insert(table, rows, columns):
    lines = [f"insert into public.{table} ({', '.join(columns)}) values"]
    lines.append(",\n".join("  (" + ", ".join(q(r[c]) for c in columns) + ")" for r in rows))
    return "\n".join(lines) + "\non conflict do nothing;\n"

seed = ["-- Generated by scripts/generate_fixtures.py — do not edit by hand.", "begin;"]
seed.append(insert("categories", [dict(c, sort_order=i) for i, c in enumerate(categories)],
                   ["id", "name", "image", "styles", "sort_order"]))
seed.append(insert("products", [dict(p, rating_distribution=reviews[p["id"]]["summary"]["distribution"],
                                     stock=0 if not p["in_stock"] else 25, sort_order=i)
                                for i, p in enumerate(products)],
                   ["id", "name", "brand", "price_cents", "compare_at_cents", "category_id", "style", "images", "colors",
                    "sizes", "rating", "review_count", "rating_distribution", "summary", "details", "tags", "stock",
                    "released_at", "popularity", "sort_order"]))
seed.append(insert("collections", [dict(c, sort_order=i) for i, c in enumerate(collections)],
                   ["id", "eyebrow", "title", "subtitle", "cta_title", "hero_image", "editorial_images",
                    "story_title", "story_body", "product_tag", "sort_order"]))
seed.append(insert("reviews", [dict(r, created_at=r["date"]) for page in reviews.values() for r in page["items"]],
                   ["id", "product_id", "author", "rating", "body", "created_at", "is_verified", "photo_urls"]))
seed.append(insert("popular_searches", [{"term": t, "sort_order": i} for i, t in enumerate(catalog["popular_searches"])],
                   ["term", "sort_order"]))
seed.append(insert("coupons", [
    {"code": "SUMMER20", "kind": "percentage", "value": 0.2, "minimum_cents": 0, "active": True},
    {"code": "WELCOME10", "kind": "percentage", "value": 0.1, "minimum_cents": 0, "active": True},
    {"code": "NOVA25", "kind": "fixed", "value": 25, "minimum_cents": 15000, "active": True},
], ["code", "kind", "value", "minimum_cents", "active"]))
seed.append(insert("notifications", [dict(n, user_id=None, created_at=n["date"]) for n in notifications if n["kind"] != "order"],
                   ["id", "user_id", "kind", "title", "body", "is_read", "created_at"]))
seed.append("commit;")
os.makedirs(os.path.dirname(SEED), exist_ok=True)
with open(SEED, "w") as f:
    f.write("\n".join(seed) + "\n")
print(f"seed.sql: {len(products)} products, {sum(len(v['items']) for v in reviews.values())} reviews")
