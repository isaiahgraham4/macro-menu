import Foundation

func barcodeChecks() throws {
    let ean = try BarcodeLookup.validatedCode("3017 6204 22003")
    let upc = try BarcodeLookup.validatedCode("036000291452")
    assert(ean == "3017620422003" && upc == "036000291452")
    assert((try? BarcodeLookup.validatedCode("3017620422004")) == nil)
    assert((try? BarcodeLookup.validatedCode("00000000")) == nil)
    assert((try? BarcodeLookup.validatedCode("abc3017620422003")) == nil)
    func parse(_ json: String) throws -> BarcodeProduct {
        try BarcodeLookup.parse(Data(json.utf8), code: "3017620422003")
    }
    let kj = try parse(#"{"status":1,"product":{"product_name":"Test food","nutriments":{"energy_100g":418.4,"proteins_100g":"8","carbohydrates_100g":20,"sodium_100g":0.12}}}"#)
    assert(kj.per100 && abs(kj.food.cal - 100) < 0.001 && kj.food.p == 8)
    assert(kj.food.f == nil && kj.food.nut?["sodium"] == 120)
    let savedScan = RecentBarcodes.recording(kj, in: Data())
    let restoredScan = RecentBarcodes.products(from: savedScan)
    assert(restoredScan.count == 1 && restoredScan[0].per100)
    assert(restoredScan[0].food.cal == kj.food.cal && restoredScan[0].unit == kj.unit)
    assert(RecentBarcodes.products(from: RecentBarcodes.recording(kj, in: savedScan)).count == 1)
    assert(RecentBarcodes.products(from: Data("invalid".utf8)).isEmpty)
    var scanHistory = savedScan
    for index in 0..<25 {
        var item = kj
        item.sourceURL = URL(string: "https://world.openfoodfacts.org/product/\(index)")!
        scanHistory = RecentBarcodes.recording(item, in: scanHistory)
    }
    assert(RecentBarcodes.products(from: scanHistory).count == 20)
    assert(RecentBarcodes.products(from: scanHistory).first?.sourceURL.lastPathComponent == "24")
    let kcal = try parse(#"{"status":1,"product":{"product_name":"Drink","product_quantity_unit":"ml","nutriments":{"energy-kcal_100g":50,"energy_100g":999,"proteins_100g":0}}}"#)
    assert(kcal.food.cal == 50 && kcal.unit == "mL" && kcal.food.serve == "100 mL")
    let serving = try parse(#"{"status":1,"product":{"product_name":"Bar","serving_size":"1 bar (40 g)","nutriments":{"energy-kcal_serving":200,"proteins_serving":15,"fat_serving":7,"carbohydrates_100g":80}}}"#)
    assert(!serving.per100 && serving.food.cal == 200 && serving.food.c == nil && serving.food.f == 7)
    let both = try parse(#"{"status":1,"product":{"product_name":"Bar","serving_size":"1 bar (40 g)","nutriments":{"energy-kcal_serving":200,"proteins_serving":15,"energy-kcal_100g":500,"proteins_100g":37.5}}}"#)
    assert(!both.per100 && both.food.cal == 200 && both.food.p == 15)
    let derived = try parse(#"{"status":1,"product":{"product_name":"Milk","serving_size":"1 glass (250 ml)","nutriments":{"energy_100g":209.2,"proteins_100g":3,"fat_100g":2,"sodium_100g":0.04}}}"#)
    assert(!derived.per100 && derived.unit == "mL" && abs(derived.food.cal - 125) < 0.001)
    assert(derived.food.p == 7.5 && derived.food.f == 5 && derived.food.nut?["sodium"] == 100)
    let doubleServing = Nutrition([Portion(food: derived.food, quantity: 2)])
    assert(abs(doubleServing.cal - 250) < 0.001 && doubleServing.p == 15 && doubleServing.nut["sodium"] == 200)
    let label = "Serving size: 1 bar (40 g)\nPer 100 g  Per serving\nEnergy 2092 kJ 836.8 kJ\nProtein 37.5 g 15 g\nSodium 250 mg 100 mg"
    let layout = LabelParser.layout(label)
    assert(layout.servingColumn == 1 && layout.per100Column == 0 && layout.amount == 40)
    assert(abs(LabelParser.servingSuggestions(label, column: 1)["cal"]! - 200) < 0.001)
    assert(abs(LabelParser.servingSuggestions(label, column: 0)["cal"]! - 200) < 0.001)
    assert(LabelParser.servingSuggestions(label, column: 0)["sodium"] == 100)
    let reversed = "Serving size 250 mL\nPer serving Per 100 mL\nEnergy 523 kJ 209.2 kJ\nProtein 7.5 g 3 g"
    assert(LabelParser.layout(reversed).servingColumn == 0)
    assert(LabelParser.layout(reversed).unit == "mL")
    assert(abs(LabelParser.servingSuggestions(reversed, column: 1)["cal"]! - 125) < 0.001)
    let only100 = "Serving size:\n30g\nPer 100g\nEnergy 1673.6 kJ\nProtein 10g"
    assert(LabelParser.layout(only100).servingColumn == nil)
    assert(abs(LabelParser.servingSuggestions(only100, column: 0)["cal"]! - 120) < 0.001)
    assert(LabelParser.layout("Energy 500kJ").per100Column == nil)
    assert(LabelParser.layout("Per 100g\nEnergy 500kJ").amount == nil)
    assert((try? parse(#"{"status":0}"#)) == nil)
    assert((try? parse(#"{"status":1,"product":{"product_name":"Missing protein","nutriments":{"energy-kcal_100g":200}}}"#)) == nil)
    assert((try? parse(#"{"status":1,"product":{"product_name":"Mixed basis","nutriments":{"energy-kcal_100g":200,"proteins_serving":15}}}"#)) == nil)
    assert((try? parse(#"{"status":1,"product":{"product_name":"Invalid","nutriments":{"energy-kcal_100g":-5,"proteins_100g":15}}}"#)) == nil)
    var mine = Food(name: "Corner store wrap", kj: 1500, cal: 358.5, p: 20, c: nil, f: nil)
    mine.barcode = "9300000000009"
    assert(BarcodeLookup.match("9300000000009", in: [mine])?.name == "Corner store wrap")
    mine.barcode = "036000291452"
    assert(BarcodeLookup.match("0036000291452", in: [mine]) != nil)
    assert(BarcodeLookup.match("9300000000009", in: [mine]) == nil)
    let decoded = try JSONDecoder().decode(Food.self, from: JSONEncoder().encode(mine))
    assert(decoded.barcode == "036000291452")
    assert(serving.food.barcode != nil)
    print("Barcode checks passed: validation, kJ conversion, serving basis, missing data and sodium units")
}
