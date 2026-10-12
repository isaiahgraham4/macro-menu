import Foundation

/// Turns the labels Apple's built-in image classifier (the Vision framework, on the device) gives a photo into foods Leanr
/// can look up. Pure logic with no Vision import, so it can be checked on its own; `MealVision` does the classifying.
///
/// The classifier reports a chain of labels with one shared score, general to specific ("food", "meat", "hamburger" all
/// 0.89), plus unrelated labels for what else it sees (plates, tables). Only the specific food in each chain is wanted, and
/// toppings that belong to a dish ("pepperoni", "cheese" on a pizza) must not become separate foods.
enum VisionFoodLabels {
    struct Reading: Equatable, Sendable {
        var identifier: String
        var confidence: Double
    }

    /// What to search Leanr's foods for, most specific first. Labels not listed here are ignored (objects, animals, scenery),
    /// and so are labels too general to log ("food", "meat", "vegetable", "dessert", "drink").
    static let names: [String: [String]] = [
        // Fruit
        "apple": ["apple"], "apricot": ["apricot"], "avocado": ["avocado"], "banana": ["banana"], "blackberry": ["blackberries"],
        "blueberry": ["blueberries"], "cantaloupe": ["rockmelon"], "cherry": ["cherries"], "coconut": ["coconut"],
        "cranberry": ["cranberries"], "fig": ["figs"], "grape": ["grapes"], "grapefruit": ["grapefruit"], "guava": ["guava"],
        "honeydew": ["honeydew melon"], "kiwi": ["kiwifruit"], "lemon": ["lemon"], "lime": ["lime"], "lychee": ["lychees"],
        "mandarine": ["mandarin"], "mango": ["mango"], "melon": ["rockmelon", "honeydew melon", "watermelon"],
        "nectarine": ["nectarine"], "oranges": ["orange"], "papaya": ["papaya"], "passionfruit": ["passionfruit"],
        "peach": ["peach"], "pear": ["pear"], "persimmon": ["persimmon"], "pineapple": ["pineapple"], "plum": ["plum"],
        "pomegranate": ["pomegranate"], "raspberry": ["raspberries"], "starfruit": ["starfruit"],
        "strawberry": ["strawberries"], "watermelon": ["watermelon"], "berry": ["strawberries", "blueberries", "raspberries"],
        "citrus_fruit": ["orange", "mandarin", "lemon"],
        // Nuts and seeds
        "almond": ["almonds"], "cashew": ["cashews"], "macadamia": ["macadamias"], "peanut": ["peanuts"], "pecan": ["pecans"],
        "pistachio": ["pistachios"], "chestnut": ["chestnuts"], "nut": ["mixed nuts", "almonds", "cashews"],
        "sunflower_seeds": ["sunflower seeds"], "seed": ["pumpkin seeds", "sunflower seeds", "chia seeds"],
        "sesame": ["sesame seeds"],
        // Vegetables
        "artichoke": ["artichoke"], "arugula": ["rocket"], "asparagus": ["asparagus"], "beet": ["beetroot"],
        "bell_pepper": ["red capsicum", "green capsicum", "yellow capsicum"],
        "pepper_veggie": ["red capsicum", "green capsicum", "yellow capsicum"], "broccoli": ["broccoli"],
        "carrot": ["carrot"], "cauliflower": ["cauliflower"], "celery": ["celery"], "chives": ["spring onion"],
        "cilantro": ["coriander leaves"], "coleslaw": ["coleslaw", "cabbage"], "corn": ["sweet corn", "corn"],
        "cucumber": ["cucumber"], "daikon": ["radish"], "edamame": ["edamame"], "eggplant": ["eggplant"],
        "garlic": ["garlic"], "green_beans": ["green beans"], "habanero": ["red chilli"], "jalapeno": ["red chilli"],
        "kohlrabi": ["kohlrabi"], "leek": ["leek"], "lettuce": ["lettuce"], "mushroom": ["mushrooms"], "onion": ["onion"],
        "pea": ["peas"], "potato": ["potato"], "pumpkin": ["pumpkin"], "radish": ["radish"], "rhubarb": ["rhubarb"],
        "spinach": ["spinach"], "tomato": ["tomato"], "zucchini": ["zucchini"], "sauerkraut": ["sauerkraut"],
        "bean": ["baked beans", "black beans", "kidney beans"], "pickle": ["pickles"],
        // Grains, bread and baking
        "rice": ["white rice", "brown rice"], "quinoa": ["quinoa"], "pasta": ["pasta"], "spaghetti": ["pasta", "spaghetti"],
        "ramen": ["instant noodles", "egg noodles"], "cereal": ["rolled oats", "granola", "bran flakes"],
        "oatmeal": ["porridge", "rolled oats"], "bread": ["white bread", "wholemeal bread", "sourdough bread"],
        "white_bread": ["white bread"], "bagel": ["bagel"], "croissant": ["croissant"],
        "muffin": ["muffin", "blueberry muffin", "english muffin"], "pretzel": ["pretzels"],
        "tortilla": ["wrap", "corn tortilla"], "pita": ["pita bread"], "naan": ["naan"],
        "biscuit": ["biscuit", "marie biscuit"], "popcorn": ["popcorn"], "waffle": ["waffle"],
        "pancake": ["pancakes"], "crepe": ["pancakes"],
        // Dishes
        "pizza": ["pizza"], "hamburger": ["hamburger", "cheeseburger"], "hotdog": ["hot dog", "frankfurt"],
        "sandwich": ["sandwich", "roast beef sandwich", "ham sub"], "burrito": ["burrito", "bean burrito"],
        "taco": ["taco"], "nachos": ["nachos"], "quesadilla": ["quesadilla"], "fries": ["french fries", "chips"],
        "fried_chicken": ["fried chicken", "chicken wing", "chicken tenders"],
        "grilled_chicken": ["chicken breast", "chicken"], "poultry": ["roast chicken", "chicken"],
        "sushi": ["sushi", "white rice"], "soup": ["soup", "minestrone soup"], "curry": ["curry"],
        "stir_fry": ["fried rice", "chicken chow mein"], "dumpling": ["dumpling"], "gyoza": ["dumpling"],
        "wonton": ["wonton soup"], "springroll": ["spring roll"], "falafel": ["falafel"], "hummus": ["hummus"],
        "meatball": ["meatballs", "spaghetti and meatballs"], "omelet": ["omelette"], "egg": ["egg"],
        "fried_egg": ["egg, fried", "egg"], "scrambled_eggs": ["egg, scrambled", "egg"], "yolk": ["egg yolk"],
        "salad": ["salad", "lettuce"], "biryani": ["fried rice", "white rice"], "caprese": ["mozzarella", "tomato"],
        "tabbouleh": ["bulgur"], "kebab": ["kebab"], "casserole": ["casserole"],
        // Meat and fish
        "bacon": ["bacon"], "beef": ["beef mince", "sirloin steak"], "ham": ["ham"], "salami": ["salami"],
        "sausage": ["sausage", "beef sausage", "bratwurst"], "spareribs": ["pork spare ribs"],
        "steak": ["sirloin steak", "rump steak", "eye fillet"], "pepperoni": ["pepperoni pizza", "pepperoni"],
        "anchovy": ["anchovies"], "crab": ["crab"], "fish": ["salmon", "white fish"], "lobster": ["lobster"],
        "mackerel": ["mackerel"], "mussel": ["mussels"], "oyster": ["oysters"], "salmon": ["salmon"],
        "sardine": ["sardines"], "scallop": ["scallops"], "seabass": ["sea bass"], "shellfish": ["prawns", "mussels"],
        "shellfish_prepared": ["prawns"], "seafood": ["prawns", "salmon"], "snapper": ["snapper"],
        "swordfish": ["swordfish"], "trout": ["trout"], "tuna": ["tuna"],
        // Dairy
        "butter": ["butter"], "cheese": ["cheddar cheese", "mozzarella"], "yogurt": ["yoghurt", "greek yoghurt"],
        "milkshake": ["milkshake"], "ice_cream": ["ice cream"], "frozen_dessert": ["ice cream"],
        // Sweets
        "brownie": ["brownie"], "cake": ["cake", "chocolate cake"], "cake_regular": ["cake", "chocolate cake"],
        "cheesecake": ["cheesecake"], "cupcake": ["cupcake", "chocolate cake"], "birthday_cake": ["chocolate cake"],
        "wedding_cake": ["chocolate cake"], "cookie": ["chocolate chip cookie", "biscuit"],
        "chocolate_chip": ["chocolate chip cookie"], "chocolate": ["milk chocolate", "dark chocolate"],
        "donut": ["doughnut"], "candy": ["jelly lollies", "jelly beans"], "candy_other": ["jelly lollies", "jelly beans"],
        "marshmallow": ["marshmallows"], "jello": ["jelly, made up"], "jelly": ["jam", "jelly"],
        "pudding": ["vanilla pudding", "rice pudding"], "pie": ["apple pie"], "honey": ["honey"],
        // Drinks
        "beer": ["beer"], "red_wine": ["red wine"], "white_wine": ["white wine"], "wine": ["red wine", "white wine"],
        "sparkling_wine": ["white wine"], "cocktail": ["pina colada", "daiquiri"], "liquor": ["vodka, gin or rum"],
        "tequila": ["vodka, gin or rum"], "coffee": ["black coffee", "espresso"], "tea_drink": ["black tea", "green tea"],
        "juice": ["orange juice", "apple juice"], "smoothie": ["strawberry banana smoothie"], "soda": ["cola", "lemonade"],
        "water": ["water"],
        // Condiments
        "mustard": ["mustard"], "guacamole": ["avocado", "guacamole"], "teriyaki": ["teriyaki sauce"],
    ]

    /// Labels that sit above more specific ones in the classifier's chain. They're only used when nothing more specific
    /// shares their score ("cake" alone is a cake; "cake" with "pancake" is the pancake).
    static let groups: Set<String> = [
        "cake", "cake_regular", "berry", "citrus_fruit", "fish", "seafood", "shellfish", "poultry", "nut", "seed",
        "candy", "candy_other", "wine", "bread", "cookie", "frozen_dessert", "bell_pepper",
    ]

    /// A dish and the labels that are just its parts: seen with the dish, they aren't foods of their own.
    static let covers: [String: Set<String>] = [
        "pizza": ["cheese", "pepperoni", "salami", "bread", "white_bread", "tomato", "mushroom", "onion", "bell_pepper",
                  "pepper_veggie", "bacon", "sausage", "ham", "pineapple"],
        "hamburger": ["beef", "bread", "white_bread", "cheese", "tomato", "lettuce", "onion", "pickle", "sesame", "seed",
                      "bacon", "egg", "fried_egg"],
        "hotdog": ["sausage", "bread", "white_bread", "mustard", "onion", "sauerkraut"],
        "sandwich": ["bread", "white_bread", "cheese", "ham", "lettuce", "tomato", "bacon", "cucumber", "egg", "beef",
                     "salami"],
        "burrito": ["tortilla", "cheese", "beef", "lettuce", "tomato", "bean", "rice", "avocado", "guacamole", "corn",
                    "onion", "cilantro", "jalapeno"],
        "taco": ["tortilla", "cheese", "beef", "lettuce", "tomato", "bean", "avocado", "guacamole", "onion", "cilantro",
                 "jalapeno"],
        "quesadilla": ["tortilla", "cheese", "bean", "guacamole", "onion", "bell_pepper", "pepper_veggie"],
        "nachos": ["cheese", "tortilla", "bean", "guacamole", "jalapeno", "tomato", "onion", "corn"],
        "salad": ["lettuce", "tomato", "cucumber", "onion", "arugula", "spinach", "carrot", "corn", "bell_pepper",
                  "pepper_veggie", "cheese", "avocado", "radish", "celery"],
        "sushi": ["rice", "salmon", "tuna", "fish", "seafood", "cucumber", "avocado", "shellfish", "sesame"],
        "ramen": ["egg", "mushroom", "onion", "pasta", "spaghetti", "beef"],
        "soup": ["carrot", "onion", "celery", "pasta", "potato", "mushroom", "pea", "bean"],
        "omelet": ["egg", "cheese", "mushroom", "tomato", "ham", "onion", "bell_pepper", "pepper_veggie", "yolk"],
        "stir_fry": ["rice", "broccoli", "carrot", "onion", "mushroom", "beef", "bell_pepper", "pepper_veggie", "pea"],
        "pancake": ["cake", "cake_regular", "butter", "honey", "blueberry", "strawberry", "berry"],
        "cheesecake": ["cake", "cake_regular", "berry", "strawberry", "blueberry", "cheese"],
        "cupcake": ["cake", "cake_regular", "candy", "marshmallow"],
        "ice_cream": ["chocolate", "cookie", "cake"],
        "spaghetti": ["meatball", "tomato", "cheese", "beef"],
        "meatball": ["tomato", "cheese"],
        "caprese": ["cheese", "tomato"],
        "fried_egg": ["egg", "yolk"], "scrambled_eggs": ["egg", "yolk"], "egg": ["yolk"],
    ]

    /// A label's lowest score to count, from the whole photo and from a quarter of it. Quarters are held to more, because
    /// a close-up of a small area looks more certain than it is.
    static let wholeThreshold = 0.12
    static let tileThreshold = 0.30
    /// A food must score at least this fraction of the best one, so a stray label doesn't become a second row.
    static let relativeThreshold = 0.25
    /// A dish hides its parts when it scores at least this much of theirs.
    static let dishThreshold = 0.05
    static let dishShare = 0.4
    /// Labels in one chain share a score to this tolerance.
    static let chainTolerance = 0.015

    /// The foods in a photo, most certain first. `whole` is the classifier's output for the whole photo and `tiles` its
    /// output for parts of it (a plate with a burger, chips and a drink reads better one quarter at a time).
    static func foods(whole: [Reading], tiles: [[Reading]] = [], limit: Int = 4) -> [SeenFood] {
        scored(whole: whole, tiles: tiles, limit: limit).map(\.food)
    }

    /// The same, with how sure the classifier was of each.
    static func scored(whole: [Reading], tiles: [[Reading]] = [], limit: Int = 4) -> [(food: SeenFood, score: Double)] {
        var best: [String: Double] = [:]
        for label in candidates(in: whole, threshold: wholeThreshold) { best[label.0] = max(best[label.0] ?? 0, label.1) }
        for tile in tiles {
            for label in candidates(in: tile, threshold: tileThreshold) { best[label.0] = max(best[label.0] ?? 0, label.1) }
        }
        // A dish seen anywhere hides its parts seen anywhere.
        for (dish, parts) in covers {
            guard let dishScore = best[dish], dishScore >= dishThreshold else { continue }
            for part in parts { if let score = best[part], dishScore >= score * dishShare { best[part] = nil } }
        }
        guard let top = best.values.max() else { return [] }
        var seen: [(food: SeenFood, score: Double)] = []
        var used: Set<String> = []
        for (label, score) in best.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }) {
            guard score >= top * relativeThreshold, let words = names[label], let first = words.first, used.insert(first).inserted else { continue }
            seen.append((SeenFood(name: first, alternatives: Array(words.dropFirst().prefix(3)), brand: nil, count: 1), score))
            if seen.count == limit { break }
        }
        return seen
    }

    /// The food labels worth considering in one classifier result, with one label per chain.
    static func candidates(in readings: [Reading], threshold: Double) -> [(String, Double)] {
        let foods = readings.filter { names[$0.identifier] != nil && $0.confidence >= threshold }
        let leaves = foods.filter { !groups.contains($0.identifier) }
        return foods.compactMap { reading in
            if groups.contains(reading.identifier),
               leaves.contains(where: { abs($0.confidence - reading.confidence) <= chainTolerance }) { return nil }
            return (reading.identifier, reading.confidence)
        }
    }
}
