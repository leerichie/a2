#!/usr/bin/env python3
"""Regenerates assets/parser/shared/nutrition/nutrients.json from the USDA
FoodData Central "SR Legacy" bulk CSV export.

SR Legacy is USDA's National Nutrient Database for Standard Reference --
the same kind of generic, per-100g whole-food composition data as the UK's
McCance & Widdowson/CoFID tables. It is a U.S. government work: public
domain, no license fee, no attribution requirement, safe to redistribute
derived numbers from.

This is the reusable import pipeline for A2's generic food coverage.
Adding or refreshing nutrition for a food should mean:
  1. Add/keep its canonical id + category in
     assets/parser/shared/food_catalogue.json (and an alias if it's new).
  2. Re-run this script.
It should never require editing parser code -- the runtime only ever reads
the generated nutrients.json by canonical id (see
lib/parser/catalogue/nutrition_catalogue.dart).

Usage:
    1. Download & unzip:
       https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip
       (see https://fdc.nal.usda.gov/download-datasets for newer releases)
    2. python3 tool/import_usda_nutrients.py /path/to/extracted/csv/dir

The raw USDA CSVs are NOT committed to this repo (food_nutrient.csv alone is
~35MB) -- only the small, compact generated nutrients.json is.

Matching is automatic (token-overlap against each food's catalogue name),
not a hand-written per-food lookup table -- that is the point: this script
does not change when a new ordinary food is added, only the catalogue data
and a re-run do. Where no confident match exists, whatever nutrient record
already existed for that id (if any) is preserved unchanged rather than
guessed at.
"""
import csv
import json
import os
import re
import sys

NUTRIENT_IDS = {
    "kcal": "1008",
    "protein": "1003",
    "carbs": "1005",
    "fat": "1004",
    "fibre": "1079",
}

# Categories where the "as normally eaten" state is cooked rather than raw
# (matches the app's existing convention -- e.g. rice/pasta are already
# stored as cooked-per-100g, not raw).
COOKED_PREFERRED_CATEGORIES = {
    "meat_poultry",
    "fish_seafood",
    "processed_meat",
    "legume_nut_seed",
    "grain",
}

STOPWORDS = {
    "raw", "cooked", "boiled", "steamed", "baked", "roasted", "fried",
    "grilled", "broiled", "without", "with", "added", "salt", "and", "or",
    "not", "further", "nfs", "prepared", "from", "recipe", "of",
}

# UK<->US vocabulary equivalents -- a generic linguistic layer applied
# uniformly to every match, not a per-food lookup table. One token can
# expand to several (e.g. "wholemeal" -> "whole" + "wheat").
TOKEN_SYNONYMS = {
    "minced": {"ground"},
    "mince": {"ground"},
    "prawn": {"shrimp"},
    "prawns": {"shrimp"},
    "courgette": {"zucchini"},
    "courgettes": {"zucchini"},
    "aubergine": {"eggplant"},
    "aubergines": {"eggplant"},
    "wholemeal": {"whole", "wheat"},
    "rapeseed": {"canola"},
}

# Words that change what a food actually is, not just phrasing -- when one
# of these shows up as an EXTRA word (the catalogue name didn't ask for it),
# it means the candidate is a sub-part, dietary variant, or preparation the
# generic canonical entry should not silently stand in for (an egg's yolk
# is not "egg"; "made with tofu" mayonnaise is not "mayonnaise"). Applied
# uniformly across every match, never as a per-food rule.
MODIFIER_PENALTY_WORDS = {
    "tofu", "imitation", "diet", "substitute", "vegan", "vegetarian",
    "yolk", "skin",
    "breaded", "battered", "tender", "tenders", "nugget", "nuggets",
    "patty", "patties", "wild", "florida", "california", "jerky",
    "oil", "roll", "noodle", "noodles", "frozen", "flour", "juice",
    "extract", "concentrate", "powder", "syrup", "dried", "canned",
    "sauce", "soup", "chip", "chips", "crisp", "crisps",
    "cracker", "crackers", "cake", "cakes", "pudding",
    "bran", "crude", "germ", "husk", "hull", "starch",
}
GENERIC_BONUS_WORDS = {"regular", "whole"}
# A generic (not per-food) preference for the plainest common cooking
# method over others when a category is normally eaten cooked.
PLAIN_COOKING_WORDS = {"roasted", "baked", "boiled", "grilled"}

# USDA's own food_category_id is a much stronger generic signal than word
# matching alone -- these categories are never a sensible source for a
# GENERIC canonical food regardless of what catalogue entry we're matching
# (baby food, fast-food/restaurant recreations, branded products, lab QC
# samples), so they're excluded outright.
ALWAYS_EXCLUDED_USDA_CATEGORIES = {"3", "21", "25", "26", "27"}

# Maps our catalogue categories to the USDA food_category_id(s) a real match
# should normally live in. Applied as a soft filter (only restricts
# candidates when at least one candidate actually falls in the mapped set,
# so an incomplete mapping never blocks an otherwise-good match).
CATEGORY_ALLOWLIST = {
    "fruit": {"9"},
    "vegetable": {"11"},
    "meat_poultry": {"5", "13", "17", "10"},
    "fish_seafood": {"15"},
    "processed_meat": {"7", "10", "13", "5"},
    "dairy": {"1"},
    "dairy_alternative": {"1", "4", "14"},
    "grain_bakery": {"18", "20", "8"},
    "grain": {"20", "8"},
    "legume_nut_seed": {"12", "16"},
    "sauce_condiment_fat": {"4", "6", "2"},
    "snack_dessert": {"19", "23", "18"},
    "egg": {"1"},
    "prepared_meal": {"22", "6"},
    "prepared_food": {"22", "6"},
    "drink": {"14", "28"},
    "soup": {"6"},
    "salad": {"11", "22"},
}
# Drinks in particular must never be sourced from a dry mix/powder -- the
# amount would be per 100g of powder, not per 100ml of the drink you'd
# actually log, which is a unit mismatch, not just an imperfect variant.
DRINK_UNIT_MISMATCH_WORDS = {"dry", "powder", "mix"}


def is_branded(description):
    # SR Legacy mixes in a handful of restaurant/brand items (KRAFT, SILK,
    # MCDONALD'S, ...) that are unmistakably ALL-CAPS in the raw text --
    # never a source for a generic canonical value.
    return bool(re.search(r"\b[A-Z]{2,}(?:'[A-Z]+)?\b", description))


def normalize(text):
    text = text.lower()
    text = re.sub(r"[^a-z0-9, ]", " ", text)
    return text


def singularize(token):
    # Naive plural folding (peppers -> pepper, tomatoes -> tomato,
    # cherries -> cherry) so a singular catalogue name matches USDA's
    # near-universally plural descriptions for produce. Guarded by
    # length/ending to avoid mangling short unrelated words.
    if len(token) <= 3:
        return token
    if token.endswith("ies"):
        return token[:-3] + "y"
    if token.endswith(("oes", "ses", "xes", "ches", "shes")):
        return token[:-2]
    if token.endswith("s") and not token.endswith("ss"):
        return token[:-1]
    return token


def tokens(text):
    raw = {t for t in re.split(r"[ ,]+", normalize(text)) if t}
    out = set()
    for t in raw:
        t = singularize(t)
        out |= TOKEN_SYNONYMS.get(t, {t})
    return out


def load_catalogue(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def load_existing_nutrients(path):
    with open(path, encoding="utf-8") as f:
        return {r["foodId"]: r for r in json.load(f)}


def load_usda(csv_dir):
    foods = {}
    food_category = {}
    with open(os.path.join(csv_dir, "food.csv"), newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["data_type"] == "sr_legacy_food":
                foods[row["fdc_id"]] = row["description"]
                food_category[row["fdc_id"]] = row["food_category_id"]
    values = {}
    wanted = set(NUTRIENT_IDS.values())
    with open(os.path.join(csv_dir, "food_nutrient.csv"), newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["nutrient_id"] not in wanted or row["fdc_id"] not in foods:
                continue
            amount = row["amount"]
            if not amount:
                continue
            values.setdefault(row["fdc_id"], {})[row["nutrient_id"]] = float(amount)
    return foods, food_category, values


def best_match(canonical_name, category, foods, food_category):
    canon_tokens = tokens(canonical_name) - STOPWORDS
    if not canon_tokens:
        return None
    prefer_cooked = category in COOKED_PREFERRED_CATEGORIES
    allowed_usda_categories = CATEGORY_ALLOWLIST.get(category)
    candidates = []
    for fdc_id, desc in foods.items():
        if is_branded(desc):
            continue
        if food_category.get(fdc_id) in ALWAYS_EXCLUDED_USDA_CATEGORIES:
            continue
        desc_tokens = tokens(desc)
        if not canon_tokens.issubset(desc_tokens):
            continue
        if category == "drink" and (desc_tokens & DRINK_UNIT_MISMATCH_WORDS):
            continue
        extra = desc_tokens - canon_tokens - STOPWORDS
        score = -3 * len(extra)
        score -= 20 * len(extra & MODIFIER_PENALTY_WORDS)
        score += 2 * len(extra & GENERIC_BONUS_WORDS)
        if prefer_cooked and "cooked" in desc_tokens:
            score += 5
        if prefer_cooked and "raw" in desc_tokens:
            score -= 5
        if not prefer_cooked and "raw" in desc_tokens:
            score += 5
        if any(w in extra for w in ("fried", "battered")):
            score -= 8
        if prefer_cooked and (extra & PLAIN_COOKING_WORDS):
            score += 2
        in_allowlist = (
            allowed_usda_categories is not None
            and food_category.get(fdc_id) in allowed_usda_categories
        )
        candidates.append((in_allowlist, score, len(desc), fdc_id, desc))
    if not candidates:
        return None
    # Soft category filter: only actually restrict to the allowlist if some
    # candidate is in it -- otherwise fall back to the full candidate set
    # rather than lose an otherwise-good match to an incomplete mapping.
    if allowed_usda_categories is not None and any(c[0] for c in candidates):
        candidates = [c for c in candidates if c[0]]
    candidates.sort(key=lambda c: (-c[1], c[2]))
    _, _, _, fdc_id, desc = candidates[0]
    return fdc_id, desc


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    csv_dir = sys.argv[1]
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    catalogue = load_catalogue(
        os.path.join(repo_root, "assets/parser/shared/food_catalogue.json")
    )
    nutrients_path = os.path.join(
        repo_root, "assets/parser/shared/nutrition/nutrients.json"
    )
    existing = load_existing_nutrients(nutrients_path)
    foods, food_category, values = load_usda(csv_dir)

    matched = 0
    kept = 0
    missing = []
    out = []
    for entry in catalogue:
        fid = entry["id"]
        canon = entry.get("canonical") or fid.replace("_", " ")
        category = entry.get("category", "")
        # Never let an automated match REPLACE an existing real record --
        # only use USDA to fill a genuine gap. A short catalogue name like
        # "chicken" or "cheese" is an umbrella over hundreds of USDA rows
        # (chicken feet, blue cheese, ...); text matching alone can't
        # reliably tell "the generic version" from "a specific one", so an
        # existing already-real value is safer left alone than 2nd-guessed.
        match = None if fid in existing else best_match(canon, category, foods, food_category)
        record = None
        if match is not None:
            fdc_id, desc = match
            v = values.get(fdc_id, {})
            required = (NUTRIENT_IDS["kcal"], NUTRIENT_IDS["protein"], NUTRIENT_IDS["carbs"])
            if all(n in v for n in required):
                record = {
                    "foodId": fid,
                    "kcalPer100g": round(v[NUTRIENT_IDS["kcal"]], 1),
                    "proteinPer100g": round(v[NUTRIENT_IDS["protein"]], 1),
                    "carbsPer100g": round(v[NUTRIENT_IDS["carbs"]], 1),
                    "fatPer100g": round(v[NUTRIENT_IDS["fat"]], 1)
                    if NUTRIENT_IDS["fat"] in v
                    else None,
                    "fibrePer100g": round(v[NUTRIENT_IDS["fibre"]], 1)
                    if NUTRIENT_IDS["fibre"] in v
                    else None,
                    "source": "USDA FoodData Central (SR Legacy)",
                    "sourceId": fdc_id,
                    "sourceDescription": desc,
                }
                matched += 1
        if record is None:
            if fid in existing:
                record = existing[fid]
                kept += 1
            else:
                missing.append(fid)
                continue
        out.append(record)

    out.sort(key=lambda r: r["foodId"])
    with open(nutrients_path, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")

    print(f"Matched from USDA SR Legacy: {matched}")
    print(f"Kept prior (non-USDA) value: {kept}")
    print(f"Still missing:                {len(missing)}")
    if missing:
        print("  " + ", ".join(sorted(missing)))


if __name__ == "__main__":
    main()
