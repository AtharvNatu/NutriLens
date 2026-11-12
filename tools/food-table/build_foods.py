#!/usr/bin/env python3
"""Builds NutriLens's nutrition table (Packages/NutriCore/Sources/NutriCore/Resources/foods.json).

Indian- and Maharashtrian-first. All values are per 100 g as eaten (per 100 ml for drinks).

Sources
- Protein for the 32 items in Protein-Sources.pdf is taken from that table (midpoint of a range).
  Its dal, sprout, legume and grain values are for the dry/raw food ("cooked lower"); cooked forms
  here are derived from them (dry weight x 2.2-2.8 after cooking, noted per item).
- Energy, carbohydrate and fat, and dishes not in the PDF: typical values in the style of the
  Indian Food Composition Tables (IFCT 2017) and standard home recipes. Restaurant and family
  recipes vary, so treat every value as an estimate.

Run:  python3 tools/food-table/build_foods.py
"""
import json
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "Packages/NutriCore/Sources/NutriCore/Resources/foods.json"
PDF = "Protein-Sources.pdf"

# (id, name, marathi, category, region, kcal, protein, carbs, fat, serving_g, serving, aliases, notes)
# region: mh = Maharashtrian, in = other Indian, intl = international (common in India), basic = ingredient
FOODS = [
    # ---------------- Maharashtrian breakfast & snacks ----------------
    ("kande_pohe", "Kande pohe", "कांदे पोहे", "breakfast", "mh", 160, 3.2, 25, 5.3, 200, "1 plate", ["pohe", "poha", "kanda poha", "batata pohe"], None),
    ("dadpe_pohe", "Dadpe pohe", "दडपे पोहे", "breakfast", "mh", 170, 3, 26, 6, 150, "1 plate", [], None),
    ("upma", "Upma", "उपमा", "breakfast", "mh", 150, 3.5, 22, 5.3, 200, "1 plate", ["rava upma", "uppit"], None),
    ("sheera", "Sheera", "शिरा", "sweet", "mh", 300, 4, 42, 13, 100, "1 katori", ["shira", "sooji halwa", "rava sheera"], None),
    ("sabudana_khichdi", "Sabudana khichdi", "साबुदाणा खिचडी", "breakfast", "mh", 205, 3, 32, 7.3, 200, "1 plate", ["sago khichdi"], None),
    ("sabudana_vada", "Sabudana vada", "साबुदाणा वडा", "snack", "mh", 300, 4.5, 38, 14.5, 50, "1 vada", [], None),
    ("thalipeeth", "Thalipeeth (bhajani)", "थालीपीठ", "breakfast", "mh", 240, 7.5, 33, 8.5, 80, "1 thalipeeth", ["thalipith"], None),
    ("misal", "Misal (without pav)", "मिसळ", "breakfast", "mh", 150, 6.5, 15, 7, 300, "1 bowl", ["misal usal", "puneri misal", "kolhapuri misal"], None),
    ("misal_pav", "Misal pav", "मिसळ पाव", "breakfast", "mh", 173, 6.9, 21.6, 6.4, 370, "1 plate (misal + 2 pav)", [], "Misal 300 g + 2 pav."),
    ("vada_pav", "Vada pav", "वडा पाव", "snack", "mh", 290, 6.5, 40, 11.5, 150, "1 vada pav", ["wada pav", "vadapav"], None),
    ("batata_vada", "Batata vada", "बटाटा वडा", "snack", "mh", 260, 4.5, 30, 13.5, 70, "1 vada", ["aloo bonda", "potato vada"], None),
    ("pav_bhaji", "Pav bhaji", "पावभाजी", "snack", "mh", 179, 4, 21.8, 8.5, 280, "1 plate (bhaji + 2 buttered pav)", ["pavbhaji"], "Bhaji 200 g + 2 buttered pav."),
    ("bhaji_pav_bhaji", "Pav bhaji (bhaji only)", "भाजी", "snack", "mh", 120, 2.5, 13, 6.5, 200, "1 katori", [], None),
    ("pav", "Pav (ladi pav)", "पाव", "bread", "mh", 270, 8.5, 50, 4, 35, "1 pav", ["dinner roll", "bun"], None),
    ("kanda_bhaji", "Kanda bhaji", "कांदा भजी", "snack", "mh", 320, 7, 30, 19, 80, "4 pieces", ["onion bhaji", "onion pakoda", "kanda bhajji"], None),
    ("kothimbir_vadi", "Kothimbir vadi", "कोथिंबीर वडी", "snack", "mh", 230, 7, 22, 12.5, 50, "2 pieces", [], None),
    ("alu_vadi", "Alu vadi", "अळूवडी", "snack", "mh", 220, 5, 24, 11.5, 50, "2 pieces", ["patra", "aluvadi"], None),
    ("bhel", "Bhel puri", "भेळ", "snack", "mh", 200, 4.5, 32, 6, 150, "1 plate", ["bhel"], None),
    ("pani_puri", "Pani puri", "पाणीपुरी", "snack", "in", 160, 3.5, 26, 4.8, 120, "6 puris", ["golgappa", "paani puri", "panipuri", "puchka"], None),
    ("sev_puri", "Sev puri", "शेवपुरी", "snack", "mh", 260, 5, 33, 12, 120, "1 plate", ["dahi puri"], None),
    ("dabeli", "Dabeli", "दाबेली", "snack", "mh", 250, 5.5, 36, 9.5, 120, "1 dabeli", ["kutchi dabeli"], None),
    ("ragda_pattice", "Ragda pattice", "रगडा पॅटिस", "snack", "mh", 170, 5, 25, 5.5, 250, "1 plate", [], None),
    ("chivda", "Chivda (poha)", "चिवडा", "snack", "mh", 480, 9, 52, 26, 30, "1 small katori", ["poha chivda", "namkeen"], None),
    ("chakli", "Chakli", "चकली", "snack", "mh", 520, 9, 55, 29, 20, "1 chakli", ["murukku"], None),
    ("shankarpali", "Shankarpali", "शंकरपाळी", "sweet", "mh", 500, 7, 60, 26, 30, "a handful", [], None),

    # ---------------- Maharashtrian meals ----------------
    ("poli", "Poli / chapati", "पोळी", "bread", "mh", 290, 9, 54, 4.5, 40, "1 poli", ["chapati", "chapatti", "roti", "fulka"], "Whole-wheat flatbread with a little oil."),
    ("phulka", "Phulka (no oil)", "फुलका", "bread", "in", 265, 9, 54, 1.5, 30, "1 phulka", [], None),
    ("jowar_bhakri", "Jowar bhakri", "ज्वारीची भाकरी", "bread", "mh", 270, 8.4, 57.5, 1.5, 60, "1 bhakri", ["bhakri", "jowar roti", "jolada rotti"], "About 80 % flour by weight; jowar protein from Protein-Sources.pdf."),
    ("bajra_bhakri", "Bajra bhakri", "बाजरीची भाकरी", "bread", "mh", 288, 9.2, 53.6, 4, 60, "1 bhakri", ["bajra roti"], "About 80 % flour by weight; bajra protein from Protein-Sources.pdf."),
    ("nachni_bhakri", "Nachni bhakri", "नाचणीची भाकरी", "bread", "mh", 262, 5.8, 57.6, 1, 60, "1 bhakri", ["ragi roti", "ragi bhakri"], None),
    ("puran_poli", "Puran poli", "पुरणपोळी", "sweet", "mh", 300, 6.5, 50, 8.5, 80, "1 puran poli", ["holige", "obbattu"], None),
    ("varan", "Varan (plain toor dal)", "वरण", "dal", "mh", 125, 7.9, 20.7, 0.6, 150, "1 katori", ["varan"], "Derived from toor dal in Protein-Sources.pdf (dry weight x 2.8 cooked)."),
    ("amti", "Amti (tempered dal)", "आमटी", "dal", "mh", 95, 4.5, 12, 3.2, 200, "1 katori", ["katachi amti", "goda masala dal"], None),
    ("varan_bhaat", "Varan bhaat with ghee", "वरण भात", "rice", "mh", 143, 4.7, 24.6, 2.4, 255, "1 plate", ["dal rice", "dal chawal"], "Rice 150 g + varan 100 g + 1 tsp ghee."),
    ("masale_bhaat", "Masale bhaat", "मसाले भात", "rice", "mh", 175, 3.5, 27, 6, 250, "1 plate", ["vangi bhaat"], None),
    ("matki_usal", "Matki usal", "मटकीची उसळ", "main", "mh", 135, 6.5, 15, 5.5, 150, "1 katori", ["usal", "matki"], None),
    ("moong_usal", "Moong usal", "मुगाची उसळ", "main", "mh", 125, 6.5, 14, 4.8, 150, "1 katori", ["sprouts usal"], None),
    ("zunka", "Zunka", "झुणका", "main", "mh", 200, 8, 16, 11.5, 100, "1 katori", ["jhunka"], None),
    ("pithla", "Pithla", "पिठलं", "main", "mh", 120, 5, 10, 6.7, 150, "1 katori", ["pitla", "pithla bhakri"], None),
    ("bharli_vangi", "Bharli vangi", "भरली वांगी", "main", "mh", 140, 3, 9, 10.5, 150, "1 katori", ["stuffed brinjal", "bharwa baingan"], None),
    ("batata_bhaji", "Batata bhaji (sukhi)", "बटाटा भाजी", "main", "mh", 130, 2, 17, 6, 150, "1 katori", ["aloo sabzi", "potato bhaji"], None),
    ("kobi_bhaji", "Kobi bhaji", "कोबीची भाजी", "main", "mh", 75, 1.8, 7, 4.5, 150, "1 katori", ["cabbage sabzi"], None),
    ("methi_bhaji", "Methi bhaji", "मेथीची भाजी", "main", "mh", 90, 3.5, 7, 5.5, 150, "1 katori", ["methi sabzi"], None),
    ("palak_bhaji", "Palak bhaji", "पालकाची भाजी", "main", "mh", 80, 3, 6, 5, 150, "1 katori", ["palak sabzi", "spinach bhaji"], None),
    ("bhendi_bhaji", "Bhendi bhaji", "भेंडीची भाजी", "main", "mh", 110, 2.2, 9, 7.3, 150, "1 katori", ["bhindi", "okra sabzi"], None),
    ("kadhi_mh", "Kadhi (Maharashtrian)", "कढी", "dal", "mh", 60, 2.5, 5, 3.3, 200, "1 katori", ["kadhi", "taak kadhi"], None),
    ("sol_kadhi", "Sol kadhi", "सोलकढी", "drink", "mh", 60, 0.8, 3.5, 4.8, 200, "1 glass", ["solkadhi"], None),
    ("thecha", "Thecha", "ठेचा", "side", "mh", 180, 4, 9, 14.5, 15, "1 tbsp", ["mirchi thecha"], None),
    ("shengdana_chutney", "Shengdana chutney (dry)", "शेंगदाणा चटणी", "side", "mh", 520, 22, 20, 40, 10, "1 tbsp", ["peanut chutney"], None),
    ("koshimbir", "Koshimbir", "कोशिंबीर", "side", "mh", 60, 2.5, 5, 3.4, 100, "1 katori", ["raita", "cucumber salad"], None),

    # ---------------- Maharashtrian sweets ----------------
    ("modak", "Ukadiche modak", "उकडीचे मोदक", "sweet", "mh", 230, 3, 35, 8.5, 40, "1 modak", ["modak"], None),
    ("shrikhand", "Shrikhand", "श्रीखंड", "sweet", "mh", 260, 7, 38, 9, 100, "1 katori", [], None),
    ("amrakhand", "Amrakhand", "आम्रखंड", "sweet", "mh", 250, 6.5, 38, 8, 100, "1 katori", [], None),
    ("basundi", "Basundi", "बासुंदी", "sweet", "mh", 230, 6, 28, 10.5, 100, "1 katori", ["rabdi"], None),
    ("aamras", "Aamras", "आमरस", "sweet", "mh", 80, 0.6, 19.5, 0.3, 150, "1 katori", ["mango pulp"], None),
    ("karanji", "Karanji", "करंजी", "sweet", "mh", 450, 6, 50, 25, 40, "1 karanji", ["gujiya"], None),
    ("besan_ladoo", "Besan ladoo", "बेसन लाडू", "sweet", "mh", 500, 9, 52, 28.5, 40, "1 ladoo", ["ladoo", "laddu"], None),
    ("rava_ladoo", "Rava ladoo", "रवा लाडू", "sweet", "mh", 430, 6, 60, 18.5, 40, "1 ladoo", [], None),

    # ---------------- Maharashtrian non-veg ----------------
    ("chicken_rassa", "Chicken rassa (Kolhapuri / Malvani)", "चिकन रस्सा", "nonveg", "mh", 165, 14, 4, 10.5, 250, "1 bowl", ["kombdi rassa", "kolhapuri chicken", "malvani chicken"], None),
    ("tambda_rassa", "Tambda rassa", "तांबडा रस्सा", "nonveg", "mh", 140, 10, 3, 9.8, 250, "1 bowl", ["mutton rassa"], None),
    ("pandhra_rassa", "Pandhra rassa", "पांढरा रस्सा", "nonveg", "mh", 110, 7, 3, 7.8, 250, "1 bowl", [], None),
    ("mutton_curry", "Mutton curry / sukka", "मटण", "nonveg", "in", 210, 17, 4, 14, 200, "1 katori", ["mutton", "mutton sukka", "lamb curry"], None),
    ("surmai_fry", "Surmai fry", "सुरमई फ्राय", "nonveg", "mh", 230, 22, 6, 13, 120, "2 slices", ["kingfish fry", "fish fry"], None),
    ("bombil_fry", "Bombil fry", "बोंबील फ्राय", "nonveg", "mh", 250, 15, 12, 15.5, 100, "1 portion", ["bombay duck"], None),
    ("kolambi_masala", "Kolambi masala", "कोळंबी मसाला", "nonveg", "mh", 150, 15, 5, 7.8, 150, "1 katori", ["prawn masala", "prawns curry", "shrimp curry"], None),
    ("fish_curry", "Fish curry (Malvani)", "माशाची आमटी", "nonveg", "mh", 130, 11, 4, 7.8, 200, "1 bowl", ["fish curry", "malvani fish curry"], None),

    # ---------------- Other Indian ----------------
    ("idli", "Idli", "इडली", "breakfast", "in", 140, 4.5, 29, 0.5, 80, "2 idlis", [], None),
    ("dosa", "Dosa (plain)", "डोसा", "breakfast", "in", 165, 3.9, 29, 3.7, 100, "1 dosa", ["plain dosa"], None),
    ("masala_dosa", "Masala dosa", "मसाला डोसा", "breakfast", "in", 190, 3.8, 27, 7.5, 180, "1 dosa", [], None),
    ("uttapam", "Uttapam", "उत्तप्पा", "breakfast", "in", 170, 4.5, 27, 5, 150, "1 uttapam", ["uttappa"], None),
    ("medu_vada", "Medu vada", "मेदू वडा", "breakfast", "in", 300, 9, 28, 17, 50, "1 vada", ["vada", "uddin vada"], None),
    ("sambar", "Sambar", "सांबार", "dal", "in", 65, 3, 9, 2, 200, "1 katori", [], None),
    ("coconut_chutney", "Coconut chutney", "खोबऱ्याची चटणी", "side", "in", 200, 3, 8, 17.5, 30, "2 tbsp", [], None),
    ("dal_tadka", "Dal tadka", "डाळ तडका", "dal", "in", 120, 6, 15, 4, 200, "1 katori", ["dal fry", "dal"], None),
    ("moong_dal_cooked", "Moong dal (cooked)", "मुगाची डाळ", "dal", "in", 126, 8.6, 21, 0.5, 200, "1 katori", ["yellow dal"], "Derived from moong dal in Protein-Sources.pdf (dry weight x 2.8 cooked)."),
    ("masoor_dal_cooked", "Masoor dal tadka", "मसूर डाळ", "dal", "in", 120, 7, 16, 3.5, 200, "1 katori", [], "Protein based on masoor dal in Protein-Sources.pdf."),
    ("dal_makhani", "Dal makhani", "दाल मखनी", "dal", "in", 140, 5.5, 13, 7.5, 200, "1 katori", [], None),
    ("rajma", "Rajma", "राजमा", "main", "in", 130, 6, 16, 4.5, 200, "1 katori", ["rajma chawal"], None),
    ("chole", "Chole", "छोले", "main", "in", 155, 6.5, 19, 6, 200, "1 katori", ["chana masala", "chickpea curry"], None),
    ("chole_bhature", "Chole bhature", "छोले भटुरे", "main", "in", 239, 7.1, 29.7, 10.3, 340, "1 plate (chole + 2 bhature)", ["cholebhature"], None),
    ("bhatura", "Bhatura", "भटुरा", "bread", "in", 360, 8, 45, 16.5, 70, "1 bhatura", ["bhature"], None),
    ("puri", "Puri", "पुरी", "bread", "in", 330, 7, 42, 15, 25, "1 puri", ["poori"], None),
    ("paratha", "Paratha (plain)", "पराठा", "bread", "in", 320, 8, 45, 12, 70, "1 paratha", [], None),
    ("aloo_paratha", "Aloo paratha", "आलू पराठा", "bread", "in", 280, 6, 38, 11.5, 120, "1 paratha", [], None),
    ("paneer_paratha", "Paneer paratha", "पनीर पराठा", "bread", "in", 300, 11, 33, 13.5, 120, "1 paratha", [], None),
    ("thepla", "Methi thepla", "थेपला", "bread", "in", 300, 8, 40, 12, 40, "1 thepla", [], None),
    ("naan", "Naan / butter naan", "नान", "bread", "in", 300, 9, 48, 8, 90, "1 naan", ["butter naan", "kulcha"], None),
    ("paneer_butter_masala", "Paneer butter masala", "पनीर बटर मसाला", "main", "in", 220, 8.5, 8, 17.5, 150, "1 katori", ["paneer makhani", "shahi paneer"], None),
    ("kadai_paneer", "Kadai paneer", "कढई पनीर", "main", "in", 200, 9, 7, 15, 150, "1 katori", [], None),
    ("palak_paneer", "Palak paneer", "पालक पनीर", "main", "in", 160, 8, 6, 11.5, 150, "1 katori", [], None),
    ("paneer_bhurji", "Paneer bhurji", "पनीर भुर्जी", "main", "in", 240, 14, 5, 18.5, 120, "1 katori", [], None),
    ("paneer_tikka", "Paneer tikka", "पनीर टिक्का", "main", "in", 250, 15, 6, 18.5, 120, "6 pieces", [], None),
    ("soya_chunk_curry", "Soya chunk curry", "सोयाबीन वड्या", "main", "in", 130, 11, 9, 5.5, 150, "1 katori", ["soya curry", "meal maker curry"], "Protein based on soya chunks in Protein-Sources.pdf."),
    ("tofu_bhurji", "Tofu bhurji", "टोफू भुर्जी", "main", "in", 140, 10, 4, 9.5, 120, "1 katori", [], "Protein based on tofu in Protein-Sources.pdf."),
    ("aloo_gobi", "Aloo gobi", "आलू गोबी", "main", "in", 110, 2.5, 12, 6, 150, "1 katori", ["flower bhaji", "cauliflower sabzi"], None),
    ("mixed_veg", "Mixed vegetable curry", "मिक्स भाजी", "main", "in", 100, 2.5, 9, 6, 150, "1 katori", ["veg curry", "sabzi"], None),
    ("baingan_bharta", "Baingan bharta", "वांग्याचे भरीत", "main", "in", 100, 2, 8, 6.8, 150, "1 katori", ["vangyache bharit", "bharit"], None),
    ("malai_kofta", "Malai kofta", "मलाई कोफ्ता", "main", "in", 230, 5, 14, 17, 200, "1 katori", ["kofta"], None),
    ("khichdi", "Moong dal khichdi", "खिचडी", "rice", "in", 130, 4.5, 21, 3.2, 250, "1 plate", ["khichadi"], None),
    ("white_rice", "Rice, cooked (bhaat)", "भात", "rice", "basic", 130, 2.7, 28, 0.3, 160, "1 katori", ["rice", "steamed rice", "chawal", "bhaat"], None),
    ("jeera_rice", "Jeera rice", "जिरा राईस", "rice", "in", 165, 3, 30, 3.8, 160, "1 katori", [], None),
    ("curd_rice", "Curd rice", "दही भात", "rice", "in", 125, 3.5, 20, 3.4, 200, "1 plate", ["dahi bhaat", "thayir sadam"], None),
    ("lemon_rice", "Lemon rice", "लिंबू भात", "rice", "in", 170, 3, 28, 5.2, 200, "1 plate", ["chitranna"], None),
    ("veg_biryani", "Veg biryani / pulao", "व्हेज बिर्याणी", "rice", "in", 160, 3.5, 26, 4.8, 250, "1 plate", ["pulao", "veg pulao", "veg biryani"], None),
    ("chicken_biryani", "Chicken biryani", "चिकन बिर्याणी", "nonveg", "in", 170, 9, 20, 6, 350, "1 plate", ["biryani", "dum biryani"], None),
    ("chicken_curry", "Chicken curry (home style)", "चिकन करी", "nonveg", "in", 150, 13, 5, 9, 250, "1 bowl", ["chicken masala", "curry"], None),
    ("butter_chicken", "Butter chicken", "बटर चिकन", "nonveg", "in", 180, 13, 6, 11.5, 200, "1 katori", ["murgh makhani"], None),
    ("tandoori_chicken", "Tandoori chicken", "तंदुरी चिकन", "nonveg", "in", 180, 26, 3, 7, 150, "2 pieces", ["chicken tikka", "tikka", "grilled chicken"], None),
    ("chicken_65", "Chicken 65 / chicken fry", "चिकन फ्राय", "nonveg", "in", 240, 20, 10, 13.5, 120, "1 portion", ["chicken fry", "fried chicken", "chicken wings"], None),
    ("egg_curry", "Egg curry", "अंडा करी", "nonveg", "in", 150, 8, 5, 11, 200, "1 bowl (2 eggs)", ["anda curry"], None),
    ("egg_bhurji", "Egg bhurji", "अंडा भुर्जी", "nonveg", "in", 190, 11, 4, 14.5, 120, "1 portion (2 eggs)", ["anda bhurji", "scrambled eggs"], None),
    ("masala_omelette", "Masala omelette", "ऑम्लेट", "nonveg", "in", 180, 11, 3, 14, 120, "2-egg omelette", ["omelette", "omelet", "fried egg"], None),
    ("dhokla", "Dhokla", "ढोकळा", "snack", "in", 160, 6, 25, 4, 100, "4 pieces", ["khaman"], None),
    ("kachori", "Kachori", "कचोरी", "snack", "in", 400, 8, 40, 23, 60, "1 kachori", [], None),
    ("samosa", "Samosa", "सामोसा", "snack", "in", 260, 5, 30, 14, 80, "1 samosa", [], None),
    ("pakoda", "Pakoda / bhajji (mixed)", "भजी", "snack", "in", 300, 7, 28, 18, 80, "4 pieces", ["pakode", "pakora", "bhajji", "bhaji"], None),
    ("kathi_roll", "Kathi roll / frankie", "फ्रँकी", "snack", "in", 230, 9, 27, 9.5, 180, "1 roll", ["frankie", "kaathi roll", "kathiroll", "wrap"], None),
    ("momos_veg", "Momos (veg, steamed)", "मोमोज", "snack", "in", 180, 6, 28, 5, 150, "6 momos", ["momos", "momo", "dim sum"], None),
    ("momos_chicken", "Momos (chicken, steamed)", "चिकन मोमोज", "snack", "in", 200, 10, 24, 7, 150, "6 momos", [], None),
    ("veg_fried_rice", "Veg fried rice", "फ्राइड राईस", "rice", "in", 170, 3.5, 27, 5.5, 250, "1 plate", ["fried rice", "schezwan rice"], "Indo-Chinese."),
    ("hakka_noodles", "Hakka noodles", "हक्का नूडल्स", "main", "in", 180, 4.5, 28, 5.8, 200, "1 plate", ["noodles", "chowmein", "schezwan noodles"], "Indo-Chinese."),
    ("veg_manchurian", "Veg manchurian (gravy)", "मंचुरियन", "main", "in", 150, 3, 16, 8.3, 150, "1 katori", ["manchurian", "gobi manchurian"], "Indo-Chinese."),
    ("jalebi", "Jalebi", "जिलेबी", "sweet", "in", 450, 3, 70, 18, 50, "2 pieces", [], None),
    ("gulab_jamun", "Gulab jamun", "गुलाबजाम", "sweet", "in", 330, 4.5, 50, 12.5, 50, "1 piece", ["gulabjam"], None),
    ("kulfi", "Kulfi", "कुल्फी", "sweet", "in", 230, 5.5, 25, 12, 70, "1 kulfi", [], None),
    ("kheer", "Kheer", "खीर", "sweet", "in", 140, 4, 21, 4.5, 150, "1 katori", ["payasam", "rice kheer"], None),
    ("gajar_halwa", "Gajar halwa", "गाजर हलवा", "sweet", "in", 250, 4, 32, 12, 100, "1 katori", ["halwa"], None),
    ("rasgulla", "Rasgulla", "रसगुल्ला", "sweet", "in", 186, 4, 40, 1.7, 50, "1 piece", [], None),

    # ---------------- Drinks ----------------
    ("chai", "Chai (milk tea, with sugar)", "चहा", "drink", "in", 70, 2, 9, 2.8, 120, "1 cup", ["tea", "masala chai", "cutting chai"], None),
    ("filter_coffee", "Coffee (with milk & sugar)", "कॉफी", "drink", "in", 60, 2, 7.5, 2.4, 120, "1 cup", ["coffee", "filter coffee"], None),
    ("lassi", "Lassi (sweet)", "लस्सी", "drink", "in", 100, 3, 15, 3, 250, "1 glass", ["milkshake"], None),
    ("nimbu_pani", "Nimbu sarbat", "लिंबू सरबत", "drink", "mh", 30, 0, 7.5, 0, 250, "1 glass", ["lemonade", "nimbu pani"], None),
    ("kokum_sarbat", "Kokum sarbat", "कोकम सरबत", "drink", "mh", 45, 0.1, 11, 0, 200, "1 glass", ["kokum"], None),
    ("sugarcane_juice", "Sugarcane juice", "उसाचा रस", "drink", "mh", 70, 0.2, 17.5, 0.1, 250, "1 glass", ["ganne ka ras", "juice"], None),
    ("coconut_water", "Coconut water", "शहाळ्याचे पाणी", "drink", "basic", 19, 0.7, 3.7, 0.2, 250, "1 coconut", ["tender coconut"], None),
    ("milk_cow", "Milk (cow, toned)", "दूध", "dairy", "basic", 58, 3.2, 4.7, 3, 250, "1 glass (250 ml)", ["milk"], None),
    ("whey_protein", "Whey protein (powder)", "प्रोटीन पावडर", "protein", "basic", 380, 78, 8, 5, 30, "1 scoop", ["protein shake", "whey"], "Check your product's label."),

    # ---------------- Fruit & basics ----------------
    ("banana", "Banana", "केळं", "fruit", "basic", 89, 1.1, 23, 0.3, 120, "1 medium", ["kela"], None),
    ("mango", "Mango (Alphonso)", "आंबा", "fruit", "mh", 60, 0.8, 15, 0.4, 150, "1 medium (flesh)", ["hapus", "aamba"], None),
    ("papaya", "Papaya", "पपई", "fruit", "basic", 43, 0.5, 11, 0.3, 150, "1 katori", [], None),
    ("guava", "Guava", "पेरू", "fruit", "basic", 68, 2.6, 14, 1, 100, "1 medium", ["peru"], None),
    ("chikoo", "Chikoo", "चिकू", "fruit", "basic", 83, 0.4, 20, 1.1, 100, "1 medium", ["sapota"], None),
    ("pomegranate", "Pomegranate", "डाळिंब", "fruit", "basic", 83, 1.7, 19, 1.2, 100, "1 katori seeds", ["anar"], None),
    ("apple", "Apple", "सफरचंद", "fruit", "basic", 52, 0.3, 14, 0.2, 180, "1 medium", [], None),
    ("orange", "Orange / mosambi", "संत्रे", "fruit", "basic", 47, 0.9, 12, 0.1, 130, "1 medium", ["santra", "mosambi", "citrus"], None),
    ("grapes", "Grapes", "द्राक्षे", "fruit", "basic", 69, 0.7, 18, 0.2, 150, "1 katori", ["grape"], None),
    ("watermelon", "Watermelon", "कलिंगड", "fruit", "basic", 30, 0.6, 7.6, 0.2, 250, "2 slices", ["melon", "kalingad"], None),
    ("dates", "Dates (khajur)", "खजूर", "fruit", "basic", 282, 2.5, 75, 0.4, 24, "3 dates", ["khajur"], None),
    ("green_salad", "Green salad / kachumber", "सॅलड", "side", "basic", 20, 1, 4, 0.2, 100, "1 katori", ["salad", "kachumber", "cucumber"], None),
    ("ghee", "Ghee", "तूप", "staple", "basic", 900, 0, 0, 99.8, 5, "1 tsp", ["tup", "clarified butter"], None),
    ("oil", "Cooking oil", "तेल", "staple", "basic", 884, 0, 0, 100, 5, "1 tsp", [], None),
    ("butter", "Butter", "लोणी", "staple", "basic", 717, 0.9, 0.1, 81, 10, "1 pat", ["amul butter"], None),
    ("sugar", "Sugar", "साखर", "staple", "basic", 387, 0, 100, 0, 5, "1 tsp", [], None),
    ("jaggery", "Jaggery (gul)", "गूळ", "staple", "basic", 383, 0.4, 95, 0.1, 10, "1 piece", ["gul", "gud"], None),

    # ---------------- Common international foods in India ----------------
    ("pizza", "Pizza", "पिझ्झा", "international", "intl", 266, 11, 33, 10, 107, "1 slice", ["pizza slice"], None),
    ("burger", "Burger (veg)", "बर्गर", "international", "intl", 250, 7, 33, 10, 150, "1 burger", ["hamburger", "aloo tikki burger", "chicken burger"], None),
    ("veg_sandwich", "Veg grilled sandwich", "सँडविच", "international", "intl", 230, 7, 30, 9, 150, "1 sandwich", ["sandwich", "bombay sandwich"], None),
    ("pasta", "Pasta (red sauce)", "पास्ता", "international", "intl", 150, 5, 24, 3.8, 250, "1 plate", ["spaghetti", "macaroni"], None),
    ("french_fries", "French fries", "फ्रेंच फ्राईज", "international", "intl", 312, 3.4, 41, 15, 120, "1 medium portion", ["fries", "finger chips"], None),
    ("maggi", "Instant noodles (Maggi), cooked", "मॅगी", "international", "intl", 130, 3, 18, 5.2, 240, "1 pack cooked", ["maggi", "instant noodles", "ramen"], None),
    ("white_bread", "White bread", "ब्रेड", "bread", "basic", 265, 9, 49, 3.2, 30, "1 slice", ["bread", "toast"], None),
    ("brown_bread", "Brown / whole-wheat bread", "ब्राऊन ब्रेड", "bread", "basic", 250, 12.5, 43, 3.5, 32, "1 slice", ["whole wheat bread"], None),
    ("oats_porridge", "Oats porridge (with milk)", "ओट्स", "breakfast", "basic", 110, 4.5, 16, 3.2, 250, "1 bowl", ["oatmeal", "oats", "porridge"], None),
    ("cornflakes", "Cornflakes (dry)", "कॉर्नफ्लेक्स", "breakfast", "basic", 370, 7, 84, 0.9, 30, "1 bowl (dry)", ["cereal"], None),
    ("parle_g", "Glucose biscuits (Parle-G)", "बिस्किट", "snack", "basic", 450, 7, 76, 13, 25, "4 biscuits", ["biscuit", "parle g", "cookie"], None),
    ("cake", "Cake (sponge / cream)", "केक", "sweet", "intl", 370, 5, 50, 17, 80, "1 slice", ["birthday cake", "pastry", "cupcake"], None),
    ("ice_cream", "Ice cream", "आईस्क्रीम", "sweet", "intl", 207, 3.5, 24, 11, 70, "1 scoop", ["icecream", "sundae"], None),
    ("chocolate", "Milk chocolate", "चॉकलेट", "sweet", "intl", 535, 7.6, 59, 30, 25, "1 small bar", ["dairy milk"], None),
    ("cheese_slice", "Cheese slice", "चीज", "dairy", "basic", 300, 18, 6, 23, 20, "1 slice", ["cheese", "processed cheese"], None),
    ("peanut_butter", "Peanut butter", "पीनट बटर", "nuts", "basic", 588, 25, 20, 50, 32, "2 tbsp", [], None),
]

# Protein-Sources.pdf: (id, name, marathi, category, kcal, protein, carbs, fat, serving_g, serving, aliases, pdf note)
PDF_FOODS = [
    ("egg", "Egg (whole)", "अंडे", "protein", 143, 13, 0.7, 9.5, 50, "1 egg", ["egg", "eggs", "boiled egg", "anda"], "1 egg ≈ 6–7 g protein."),
    ("chicken_raw", "Chicken (raw)", "चिकन (कच्चे)", "protein", 130, 27, 0, 2.5, 150, "1 portion (raw)", ["raw chicken"], "Lean cuts preferred."),
    ("chicken_cooked", "Chicken (cooked, lean)", "चिकन (शिजवलेले)", "protein", 165, 31, 0, 3.6, 120, "1 portion", ["chicken", "chicken breast", "boiled chicken"], "Higher concentration once cooked."),
    ("buffalo_milk", "Buffalo milk (Chitale)", "म्हशीचे दूध", "dairy", 97, 4.25, 5, 6.5, 250, "1 glass (250 ml)", ["buffalo milk", "chitale milk", "full cream milk"], "Higher fat and protein. Per 100 ml."),
    ("curd", "Curd (dahi)", "दही", "dairy", 62, 3.5, 4.5, 3.3, 100, "1 katori", ["dahi", "yogurt", "yoghurt"], "Standard curd."),
    ("chakka", "Hung curd (chakka)", "चक्का", "dairy", 110, 9.5, 4, 6.5, 100, "1 katori", ["hung curd", "greek yogurt"], "Strained, high protein."),
    ("paneer", "Paneer", "पनीर", "dairy", 290, 19, 3.5, 22.5, 100, "1 portion", ["cottage cheese"], "Dense protein."),
    ("buttermilk", "Buttermilk (taak)", "ताक", "dairy", 30, 1.5, 3, 1.2, 250, "1 glass", ["taak", "chaas", "masala chaas"], "Hydration."),
    ("tofu", "Tofu", "टोफू", "protein", 110, 10, 2.5, 6, 100, "1 portion", ["soya paneer"], "Lean veg protein."),
    ("soya_chunks", "Soya chunks (dry)", "सोयाबीन वड्या", "protein", 345, 51, 33, 0.5, 30, "¼ cup dry", ["soya chunks", "meal maker", "nutrela"], "Very high protein (dry weight)."),
    ("mushroom", "Mushrooms", "मशरूम", "protein", 28, 3.5, 3.3, 0.3, 100, "1 cup", ["mushroom"], "Low-calorie protein."),
    ("toor_dal", "Toor dal (dry)", "तूर डाळ", "protein", 343, 22, 58, 1.5, 30, "1 serving dry", ["toor dal", "tur dal", "arhar dal", "pigeon pea"], "Dry weight; cooked dal is lower per 100 g (see Varan)."),
    ("moong_dal", "Moong dal (dry)", "मूग डाळ", "protein", 348, 24, 59, 1.2, 30, "1 serving dry", ["moong dal", "mung dal"], "Dry weight. Easy to digest."),
    ("masoor_dal", "Masoor dal (dry)", "मसूर डाळ", "protein", 343, 25, 57, 1.1, 30, "1 serving dry", ["masoor dal", "red lentils"], "Dry weight. Good option."),
    ("moong_whole", "Moong, whole (dry, for sprouts)", "मूग", "protein", 347, 24, 59, 1.2, 30, "1 serving dry", ["green gram"], "Dry seed. PDF: moong sprouts ~24 g on dry weight; cooked lower."),
    ("moong_sprouts", "Moong sprouts (ready to eat)", "मोड आलेले मूग", "protein", 139, 9.6, 23.6, 0.5, 100, "1 katori", ["sprouts", "moong sprouts", "mung sprouts"], "Derived: dry seed ≈ 2.5× weight after sprouting."),
    ("matki_whole", "Matki (dry, for sprouts)", "मटकी", "protein", 343, 23, 61, 1.5, 30, "1 serving dry", ["moth beans"], "Dry seed. Maharashtrian staple."),
    ("matki_sprouts", "Matki sprouts (ready to eat)", "मोड आलेली मटकी", "protein", 137, 9.2, 24.4, 0.6, 100, "1 katori", ["matki sprouts"], "Derived: dry seed ≈ 2.5× weight after sprouting."),
    ("chickpeas_dry", "Chickpeas / kabuli chana (dry)", "काबुली चणे", "protein", 364, 19, 61, 6, 30, "1 serving dry", ["kabuli chana", "chickpeas", "chole chana"], "Dry weight; cooked lower."),
    ("chickpeas_cooked", "Chickpeas, boiled", "उकडलेले चणे", "protein", 165, 8.6, 27.7, 2.7, 100, "1 katori", ["boiled chana"], "Derived: dry × 2.2 after boiling."),
    ("kala_chana_dry", "Kala chana (dry)", "काळे चणे", "protein", 360, 20, 60, 5, 30, "1 serving dry", ["kala chana", "black chickpeas", "harbhara"], "Dry weight. High fibre."),
    ("kala_chana_cooked", "Kala chana, boiled", "उकडलेले काळे चणे", "protein", 164, 9.1, 27.3, 2.3, 100, "1 katori", ["chana usal", "boiled kala chana"], "Derived: dry × 2.2 after boiling."),
    ("peanuts", "Peanuts (shengdane)", "शेंगदाणे", "nuts", 567, 25.5, 16, 49, 30, "a handful", ["shengdana", "shengdane", "groundnuts", "peanut"], "Budget protein."),
    ("almonds", "Almonds (badam)", "बदाम", "nuts", 579, 21, 22, 50, 28, "about 20 almonds", ["badam", "almond", "nut"], "Healthy fats."),
    ("cashews", "Cashews (kaju)", "काजू", "nuts", 553, 18, 30, 44, 28, "about 18 cashews", ["kaju", "cashew"], "Moderate protein."),
    ("walnuts", "Walnuts (akhrot)", "अक्रोड", "nuts", 654, 15, 14, 65, 28, "about 14 halves", ["akhrot", "walnut"], "Omega-3."),
    ("pistachios", "Pistachios (pista)", "पिस्ता", "nuts", 560, 20, 28, 45, 28, "a handful", ["pista", "pistachio"], "Balanced."),
    ("pumpkin_seeds", "Pumpkin seeds", "भोपळ्याच्या बिया", "nuts", 559, 30, 11, 49, 20, "2 tbsp", ["pumpkin seed"], "Very high protein."),
    ("sunflower_seeds", "Sunflower seeds", "सूर्यफूल बिया", "nuts", 584, 20.5, 20, 51.5, 20, "2 tbsp", ["sunflower seed"], "Easy to add."),
    ("flax_seeds", "Flax seeds (javas)", "जवस", "nuts", 534, 18, 29, 42, 10, "1 tbsp ground", ["javas", "alsi", "flaxseed", "linseed"], "Use ground."),
    ("chia_seeds", "Chia seeds", "चिया बिया", "nuts", 486, 16.5, 42, 31, 12, "1 tbsp", ["chia"], "Fibre rich."),
    ("sesame_seeds", "Sesame seeds (til)", "तीळ", "nuts", 573, 18, 23, 50, 10, "1 tbsp", ["til", "sesame", "seed"], "Common."),
    ("wheat_atta", "Whole wheat (atta)", "गव्हाचे पीठ", "grains", 340, 12, 72, 2, 30, "1 serving flour", ["atta", "wheat flour", "gahu"], "Secondary protein source."),
    ("jowar_flour", "Jowar (flour)", "ज्वारीचे पीठ", "grains", 334, 10.5, 72, 1.8, 30, "1 serving flour", ["jowar", "sorghum"], "Carb base."),
    ("bajra_flour", "Bajra (flour)", "बाजरीचे पीठ", "grains", 360, 11.5, 67, 5, 30, "1 serving flour", ["bajra", "pearl millet"], "Slightly higher protein."),
    ("brown_rice_raw", "Brown rice (raw)", "ब्राऊन राईस", "grains", 362, 7.5, 76, 2.7, 50, "1 serving raw", ["brown rice raw"], "Low protein."),
    ("brown_rice_cooked", "Brown rice, cooked", "शिजवलेला ब्राऊन राईस", "rice", 123, 2.6, 25.6, 0.9, 160, "1 katori", ["brown rice"], "Derived: raw × 2.9 after cooking."),
]

# Apple Vision ClassifyImageRequest label -> food ids, most likely first. Vision's labels are generic,
# so each suggests a few Indian dishes and the user picks.
VISION_LABELS = {
    "biryani": ["chicken_biryani", "veg_biryani"],
    "curry": ["chicken_curry", "paneer_butter_masala", "chole", "rajma", "egg_curry", "mixed_veg", "dal_tadka"],
    "naan": ["naan", "poli", "paratha", "jowar_bhakri"],
    "samosa": ["samosa", "kachori"],
    "dumpling": ["modak", "momos_veg", "momos_chicken"],
    "rice": ["varan_bhaat", "white_rice", "masale_bhaat", "jeera_rice", "veg_fried_rice"],
    "soup": ["amti", "sambar", "dal_tadka", "kadhi_mh"],
    "crepe": ["dosa", "masala_dosa", "uttapam"],
    "pancake": ["uttapam", "thalipeeth", "dosa"],
    "bread": ["poli", "jowar_bhakri", "white_bread", "pav"],
    "white_bread": ["white_bread", "pav"],
    "sandwich": ["veg_sandwich", "vada_pav", "dabeli"],
    "hamburger": ["vada_pav", "burger", "dabeli"],
    "fried_chicken": ["chicken_65", "tandoori_chicken"],
    "grilled_chicken": ["tandoori_chicken", "chicken_cooked"],
    "kebab": ["tandoori_chicken", "paneer_tikka"],
    "meat": ["mutton_curry", "tambda_rassa", "chicken_rassa"],
    "meatball": ["malai_kofta"],
    "fish": ["surmai_fry", "fish_curry", "bombil_fry"],
    "shellfish": ["kolambi_masala"],
    "shellfish_prepared": ["kolambi_masala"],
    "egg": ["egg", "egg_curry"],
    "fried_egg": ["masala_omelette", "egg"],
    "scrambled_eggs": ["egg_bhurji", "masala_omelette", "paneer_bhurji"],
    "dessert": ["gulab_jamun", "shrikhand", "kheer", "basundi"],
    "pudding": ["kheer", "basundi", "sheera"],
    "frozen_dessert": ["kulfi", "ice_cream"],
    "ice_cream": ["ice_cream", "kulfi"],
    "cake": ["cake"],
    "cake_regular": ["cake"],
    "birthday_cake": ["cake"],
    "cupcake": ["cake"],
    "cookie": ["parle_g", "shankarpali"],
    "biscuit": ["parle_g", "shankarpali"],
    "candy": ["besan_ladoo", "jalebi"],
    "chocolate": ["chocolate"],
    "yogurt": ["curd", "shrikhand", "chakka", "koshimbir"],
    "tea_drink": ["chai"],
    "coffee": ["filter_coffee"],
    "juice": ["sugarcane_juice", "kokum_sarbat", "nimbu_pani"],
    "milkshake": ["lassi"],
    "oatmeal": ["oats_porridge", "upma", "kande_pohe"],
    "cereal": ["cornflakes", "chivda"],
    "salad": ["koshimbir", "green_salad", "moong_sprouts"],
    "vegetable": ["mixed_veg", "bhendi_bhaji", "kobi_bhaji"],
    "spinach": ["palak_paneer", "palak_bhaji", "methi_bhaji"],
    "potato": ["batata_bhaji", "aloo_gobi", "batata_vada"],
    "cauliflower": ["aloo_gobi"],
    "eggplant": ["bharli_vangi", "baingan_bharta"],
    "bean": ["rajma", "matki_usal", "moong_usal"],
    "green_beans": ["mixed_veg"],
    "pea": ["chole", "mixed_veg"],
    "mushroom": ["mushroom"],
    "nut": ["almonds", "peanuts", "cashews"],
    "peanut": ["peanuts"],
    "cashew": ["cashews"],
    "sunflower_seeds": ["sunflower_seeds"],
    "seed": ["pumpkin_seeds", "sesame_seeds", "flax_seeds"],
    "cheese": ["paneer", "cheese_slice"],
    "butter": ["butter", "ghee"],
    "sugar_cube": ["sugar"],
    "banana": ["banana"],
    "mango": ["mango", "aamras"],
    "papaya": ["papaya"],
    "guava": ["guava"],
    "grape": ["grapes"],
    "pomegranate": ["pomegranate"],
    "melon": ["watermelon"],
    "watermelon": ["watermelon"],
    "coconut": ["coconut_water", "coconut_chutney"],
    "citrus_fruit": ["orange"],
    "fruit": ["banana", "papaya", "guava"],
    "springroll": ["kathi_roll"],
    "taco": ["kathi_roll"],
    "burrito": ["kathi_roll"],
    "pizza": ["pizza"],
    "pasta": ["pasta", "hakka_noodles", "maggi"],
    "popcorn": ["chivda"],
}


def build():
    foods = []
    for fid, name, local, cat, region, kcal, p, c, f, grams, serving, aliases, notes in FOODS:
        foods.append(dict(id=fid, name=name, localName=local, category=cat, region=region, kcal=kcal, protein=p, carbs=c, fat=f,
                          servingGrams=grams, serving=serving, aliases=aliases, notes=notes, proteinSource=None))
    for fid, name, local, cat, kcal, p, c, f, grams, serving, aliases, note in PDF_FOODS:
        foods.append(dict(id=fid, name=name, localName=local, category=cat, region="basic", kcal=kcal, protein=p, carbs=c, fat=f,
                          servingGrams=grams, serving=serving, aliases=aliases, notes=note, proteinSource=PDF))

    # Plain forms of names are aliases too: "Misal (without pav)" -> "Misal", "Poli / chapati" -> "Poli", "chapati".
    for x in foods:
        base = re.sub(r"\s*\(.*?\)", "", x["name"]).strip()
        extra = [base] + [part.strip() for part in base.split("/")]
        for alias in extra:
            if alias and alias.lower() != x["name"].lower() and alias.lower() not in (a.lower() for a in x["aliases"]):
                x["aliases"] = x["aliases"] + [alias]

    ids = [x["id"] for x in foods]
    assert len(ids) == len(set(ids)), "duplicate ids"
    problems = []
    for x in foods:
        macro = 4 * x["protein"] + 4 * x["carbs"] + 9 * x["fat"]
        if abs(macro - x["kcal"]) / x["kcal"] > 0.2:
            problems.append(f'{x["id"]}: {x["kcal"]} kcal vs {macro:.0f} from macros')
        if x["protein"] + x["carbs"] + x["fat"] > 100:
            problems.append(f'{x["id"]}: macros exceed 100 g')
    for label, targets in VISION_LABELS.items():
        for t in targets:
            if t not in ids:
                problems.append(f"vision label {label} -> unknown id {t}")
    if problems:
        sys.exit("\n".join(problems))
    doc = {
        "version": 2,
        "units": "Per 100 g as eaten (per 100 ml for drinks). Typical values; recipes vary.",
        "sources": {
            "protein": f"{PDF} for the items marked proteinSource (midpoint of each range).",
            "other": "Indian Food Composition Tables (IFCT 2017)-style typical values and standard home recipes.",
        },
        "foods": [{k: v for k, v in x.items() if v is not None} for x in foods],
        "visionLabels": VISION_LABELS,
    }
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
    regions = {}
    for x in foods:
        regions[x["region"]] = regions.get(x["region"], 0) + 1
    print(f"{len(foods)} foods {regions}, {len(VISION_LABELS)} vision labels -> {OUT}")


if __name__ == "__main__":
    build()
