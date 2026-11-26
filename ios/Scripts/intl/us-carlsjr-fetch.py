#!/usr/bin/env python3
"""Carl's Jr. (US): the Nutritional Information poster on carlsjr.com/nutritional_info, saved as us-carlsjr-source.json.

carlsjr.com/nutritional_info shows the whole guide as one large poster image (a Kentico content asset whose file name
carries the edition date, linked from the page, so a plain request finds the current edition). Carl's Jr. and Hardee's
publish the same poster format, so this uses the reader in us-hardees-fetch.py: the macOS Vision text recogniser
(ocr-pages.swift in this folder) in overlapping strips, plus a glyph-by-glyph reading of the cells Vision skips (mostly
zeros) from character shapes learnt from the rest of the poster. The poster gives each item its allergen letters (E egg,
F fish, M milk, P peanut, SF shellfish, S soy, T tree nut, W wheat, SS sesame: the nine US majors; "+" marks ice cream made
where peanuts or tree nuts are present), then serving weight, calories, calories from fat, fat, saturated fat, trans fat,
cholesterol, sodium, carbs, fibre, sugars and protein. Rows with Small / Medium / Large figures in one cell become one row per
size; drinks are listed per cup size in fluid ounces.

Every row must have calories, protein, carbs and fat, with calories within a third of 4p + 4c + 9f (misreads and misprints
are counted in `src`). Left out: Star Pals kids' meals (they include fries and a cookie) and bottled water.

Run: python3 ios/Scripts/intl/us-carlsjr-fetch.py
"""
import importlib.util
import pathlib
import re

HERE = pathlib.Path(__file__).parent
_spec = importlib.util.spec_from_file_location('hardees_reader', HERE / 'us-hardees-fetch.py')
reader = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(reader)


def tidy(name, r):
    n = reader.tidy(name, r)
    n = re.sub(r'\s*\((\d+) ?pc\)', r' (\1 pc)', n)
    n = re.sub(r'\(\s*(\d+)\s*pieces?\s*\)', r'(\1 pc)', n)
    n = re.sub(r'\s+(\d+) piece$', r' (\1 pc)', n)
    n = re.sub(r'\s*\((dipping cup)\)', '', n)
    n = n.replace(' Made with OREO Cookie Pieces', '').replace('House Dressing PC', 'House Dressing')
    return n


def skip(name, r):
    return reader.skip(name, r) or bool(re.search(r'(?i)star pals|^kids meal', name)) or 'STAR PALS' in r['section'].upper()


if __name__ == '__main__':
    reader.build('us-carlsjr', "Carl's Jr.", 'https://www.carlsjr.com/nutritional_info', 'Nutrition', tidy,
                 reader.category, reader.meat, skip)
