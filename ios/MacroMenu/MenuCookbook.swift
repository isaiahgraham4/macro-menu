import Foundation

/// What restaurant dishes are usually made of, so a dish on a photographed menu can be added up from Takeawise's own foods.
/// Every food named here is an exact name in `GenericFoods.json` or `SurveyFoods.json` (the checks hold that), and the gram
/// weights are a typical Australian restaurant serve. They're starting points to adjust, not published figures.
enum MenuCookbook {
    enum Style: Sendable {
        /// A plated dish: a shared or starter-sized version is scaled down.
        case plate
        /// Comes as it comes (a drink, a dessert, a side): never scaled, and nothing is added to it.
        case asSold
        /// A kind of dish built around what the menu says goes in it: a burger, a curry, a pizza.
        case base
    }

    struct Part: Equatable, Sendable {
        var food: String
        var grams: Double
    }

    struct Recipe: Sendable {
        var names: [[String]]
        var style: Style
        var parts: [Part]
        /// How much of the named protein goes in a `.base`.
        var protein: Double
        /// The protein to use when the menu doesn't name one.
        var usual: Part?
        /// What the base already has, so naming it adds nothing: a pizza's cheese and sauce.
        var covers: Set<Role> = []
    }

    enum Role: Sendable { case protein, starch, veg, sauce, cheese, topping }

    struct Ingredient: Sendable {
        /// Nil for words that look like a food but aren't one here: "fish sauce", "chicken salt".
        var food: String?
        var role: Role
        var grams: Double
    }

    /// Words for a dish, or a heading, as `MenuEstimator.tokens` writes them.
    static func phrase(_ names: String) -> [[String]] {
        names.split(separator: "|").map { MenuEstimator.tokens(String($0)) }
    }

    private static func parts(_ text: String) -> [Part] {
        text.split(separator: ";").compactMap { item in
            let pieces = item.split(separator: "=")
            guard pieces.count == 2, let grams = Double(pieces[1].trimmingCharacters(in: .whitespaces)) else { return nil }
            return Part(food: pieces[0].trimmingCharacters(in: .whitespaces), grams: grams)
        }
    }

    private static func dish(_ names: String, _ style: Style, _ list: String, protein: Double = 0, usual: String? = nil, covers: Set<Role> = []) -> Recipe {
        Recipe(names: phrase(names), style: style, parts: parts(list), protein: protein, usual: usual.flatMap { parts($0).first }, covers: covers)
    }

    private static let fries = "French fries, takeaway"
    private static let side = "Garden salad, no dressing"
    private static let rice = "White rice, cooked"

    /// Specific dishes first: when two names are the same length, the earlier one wins.
    static let recipes: [Recipe] = [
        // Pub and grill
        dish("parma|parmi|parmy|parmigiana|parmigiano chicken", .plate, "Chicken parmigiana (no pasta)=330; \(fries)=150; \(side)=80"),
        dish("schnitzel|schnitty", .plate, "Chicken breast, cooked=200; Plain flour=25; Canola oil=20; \(fries)=150; \(side)=80"),
        dish("fish and chip|fish n chip|fish chip", .plate, "Battered fish fillet=220; \(fries)=200; \(side)=60; Mayonnaise=25"),
        dish("banger and mash|sausage and mash", .plate, "Beef sausage, cooked=180; Mashed potato=250; Peas, cooked=60"),
        dish("lamb shank", .plate, "Lamb loin, lean, cooked=220; Mashed potato=220; Pasta sauce=80"),
        dish("rib|pork rib|beef rib|bbq rib", .plate, "Pork spare ribs, roasted=350; Barbecue sauce=40; \(fries)=120"),
        dish("roast of the day|sunday roast|roast chicken", .plate, "Roast chicken, meat and skin=220; Potato, baked=200; Mixed vegetables, boiled=100"),
        dish("pulled pork", .base, "Bread roll=80; Pork chop, cooked=140; Barbecue sauce=30; Coleslaw=60"),
        dish("steak sandwich", .plate, "Sourdough bread=120; Top sirloin (rump) steak, cooked=130; Onion=40; Tomato=30; Cos lettuce=20; Barbecue sauce=20; Mayonnaise=15"),
        dish("steak|scotch fillet|porterhouse|rump|sirloin|ribeye|rib eye|eye fillet|t bone|tomahawk|striploin", .base, "Butter=10", protein: 280, usual: "Top sirloin (rump) steak, cooked=280"),
        dish("burger|cheeseburger|slider", .base, "Bread roll=80; Cheddar cheese=20; Cos lettuce=20; Tomato=30; Mayonnaise=15", protein: 150, usual: "Beef patty, 15% fat, cooked=150"),
        // Italian
        dish("margherita|margarita", .asSold, "Cheese pizza, frozen=420; Basil, fresh=5"),
        dish("pizza|calzone", .base, "Cheese pizza, frozen=400", protein: 60, covers: [.sauce, .cheese]),
        dish("bolognese|ragu|spaghetti meat sauce", .plate, "Spaghetti with meat sauce=450; Parmesan, grated=10"),
        dish("meatball|polpette", .plate, "Spaghetti and meatballs=420"),
        dish("lasagne|lasagna", .plate, "Lasagne with meat=420"),
        dish("carbonara", .plate, "Pasta, cooked=300; Bacon, cooked=50; Egg=50; Cream=60; Parmesan, grated=25"),
        dish("marinara|seafood pasta", .plate, "Pasta, cooked=300; Pasta sauce=120; Prawns, cooked=60; Mussels, cooked=50; Calamari, cooked=40; Olive oil=10"),
        dish("ravioli|tortellini|agnolotti", .base, "Cheese ravioli with marinara=350; Parmesan, grated=10", protein: 50),
        dish("gnocchi", .base, "Gnocchi, potato=300; Pasta sauce=100; Parmesan, grated=15; Olive oil=10", protein: 100),
        dish("mac and cheese|macaroni cheese", .plate, "Macaroni and cheese, canned=350; Cheddar cheese=30"),
        dish("risotto", .base, "White rice, cooked=280; Parmesan, grated=20; Butter=15; Olive oil=8", protein: 120),
        dish("pasta|spaghetti|linguine|penne|fettuccine|fettucine|rigatoni|pappardelle|casarecce|orecchiette|tagliatelle|bucatini|spaghettini", .base, "Pasta, cooked=300; Pasta sauce=100; Olive oil=12; Parmesan, grated=10", protein: 120),
        dish("garlic bread|garlic pizza bread", .asSold, "Bread roll=100; Butter=25"),
        dish("burrata", .asSold, "Mozzarella=120; Tomato=80; Olive oil=12"),
        dish("bruschetta", .asSold, "Sourdough bread=100; Tomato=100; Olive oil=12; Basil, fresh=5"),
        dish("arancini", .asSold, "White rice, cooked=120; Mozzarella=30; Plain flour=15; Canola oil=12"),
        // Asian
        dish("pad thai", .plate, "Pad Thai with meat=450"),
        dish("butter chicken|murgh makhani", .plate, "Chicken curry=350; Cream=30; \(rice)=200"),
        dish("tikka masala|tikka", .plate, "Chicken curry=350; \(rice)=200"),
        dish("rendang", .plate, "Beef curry=350; Coconut milk, canned=40; \(rice)=200"),
        dish("dal|dhal|daal|tadka", .plate, "Lentil curry=320; \(rice)=180"),
        dish("green curry|red curry|massaman|panang|penang|thai curry|yellow curry", .base, "Coconut milk, canned=120; Mixed vegetables, boiled=100; \(rice)=200; Canola oil=8", protein: 150, usual: "Chicken thigh, cooked=150"),
        dish("korma|vindaloo|rogan josh|madras|saag|balti|jalfrezi|bhuna|curry", .base, "Vegetable curry=200; \(rice)=200", protein: 150, usual: "Chicken thigh, cooked=150"),
        dish("nasi goreng", .plate, "Fried rice (no meat)=350; Chicken thigh, cooked=80; Egg, fried=46"),
        dish("fried rice", .base, "Fried rice (no meat)=380", protein: 80),
        dish("laksa", .plate, "Rice noodles, cooked=160; Coconut milk, canned=150; Chicken thigh, cooked=100; Prawns, cooked=40; Tofu, firm=40; Bean sprouts=40"),
        dish("pho", .plate, "Soup, pho, with meat=650"),
        dish("ramen", .plate, "Ramen bowl with chicken=650"),
        dish("chow mein|lo mein|hokkien|singapore noodle|char kway teow|mie goreng|mee goreng|yakisoba|udon stir fry", .base, "Egg noodles, cooked=280; Mixed vegetables, boiled=80; Canola oil=15; Soy sauce=20", protein: 120),
        dish("stir fry|stir fried|stirfry|wok", .base, "Mixed vegetables, boiled=150; \(rice)=200; Canola oil=15; Soy sauce=20", protein: 150),
        dish("katsu", .plate, "Chicken breast, cooked=170; Plain flour=20; Canola oil=18; \(rice)=200; Cabbage=50"),
        dish("teriyaki", .base, "\(rice)=200; Teriyaki sauce=40; Mixed vegetables, boiled=60; Canola oil=8", protein: 170, usual: "Chicken thigh, cooked=170"),
        dish("bibimbap", .base, "\(rice)=250; Mixed vegetables, boiled=100; Egg, fried=46; Sesame oil=8", protein: 90),
        dish("poke|poke bowl", .base, "\(rice)=220; Avocado=40; Edamame=30; Cucumber=30; Mayonnaise=12; Soy sauce=12", protein: 120, usual: "Salmon, raw=120"),
        dish("sashimi", .asSold, "Salmon, raw=120"),
        dish("sushi|nigiri|maki", .asSold, "\(rice)=180; Salmon, raw=50; Avocado=20"),
        dish("dumpling|gyoza|wonton|dim sim|bao|bun bao", .asSold, "Dumplings, fried=175"),
        dish("spring roll|egg roll", .asSold, "Spring roll (vegetable)=140"),
        dish("salt and pepper squid|salt and pepper calamari|calamari|squid", .plate, "Calamari, fried=220; Mayonnaise=20; \(side)=50"),
        // Mexican and Mediterranean
        dish("taco", .base, "Corn tortilla=72; Cabbage=40; Salsa=40; Sour cream=20", protein: 110, usual: "Beef mince, 10% fat, cooked=110"),
        dish("burrito bowl", .base, "\(rice)=200; Black beans, cooked=80; Salsa=50; Cheddar cheese=25; Sour cream=25", protein: 120, usual: "Chicken thigh, cooked=120"),
        dish("burrito", .base, "Wrap, flour tortilla=100; \(rice)=120; Black beans, cooked=70; Cheddar cheese=25; Salsa=40", protein: 120, usual: "Chicken thigh, cooked=120"),
        dish("nachos", .plate, "Nachos with cheese=320; Beef mince, 10% fat, cooked=80; Sour cream=30; Salsa=40; Avocado=30"),
        dish("quesadilla", .base, "Cheese quesadilla=194", protein: 80, covers: [.cheese]),
        dish("souvlaki|gyros|gyro|yiros|kebab|doner|shawarma", .plate, "Kebab wrap (gyro)=320"),
        dish("falafel", .plate, "Falafel=120; Pita bread=60; Hummus=50; \(side)=60"),
        dish("hummus|hommus|baba ganoush|dip", .asSold, "Hummus=100; Pita bread=60"),
        // Salads, soups, sides
        dish("side salad|garden salad|green salad|mixed leaf|house salad", .asSold, "\(side)=120; Olive oil=8"),
        dish("caesar", .base, "Cos lettuce=150; Bacon, cooked=30; Egg, poached=50; Caesar dressing=45; Parmesan, grated=15; Bread roll=30", protein: 120),
        dish("greek salad", .plate, "Tomato=100; Cucumber=100; Feta=60; Olives=30; Onion=30; Olive oil=15"),
        dish("salad|slaw", .base, "Cos lettuce=120; Tomato=50; Cucumber=40; Olive oil=15", protein: 120),
        dish("soup|chowder|broth|bisque|minestrone", .base, "Vegetable soup, chunky=350; Bread roll=50", protein: 60),
        dish("potato wedge|wedge", .asSold, "Oven chips, baked=250; Sour cream=30"),
        dish("sweet potato fry|sweet potato chip", .asSold, "Sweet potato, baked=200; Canola oil=15; Mayonnaise=15"),
        dish("chip|fry|shoestring|french fry|hand cut chip", .asSold, "\(fries)=200"),
        dish("onion ring", .asSold, "Onion rings, takeaway=150"),
        dish("wing|buffalo wing", .asSold, "Fried chicken wing=300"),
        // Breakfast and cafe
        dish("benedict|eggs bene|egg ben", .plate, "English muffin=57; Egg, poached=100; Ham, lean=50; Mayonnaise=40; Butter=8"),
        dish("big breakfast|big brekkie|farmers breakfast|full breakfast", .plate, "Egg, fried=92; Bacon, cooked=60; Beef sausage, cooked=86; Sourdough bread=80; Mushrooms=60; Tomato=60; Hash browns=60; Butter=10"),
        dish("smashed avo|smashed avocado|avo toast|avocado toast|avocado on toast|avo on toast", .plate, "Sourdough bread=100; Avocado=100; Feta=30; Egg, poached=50"),
        dish("bacon and egg roll|bacon egg roll|bacon and egg", .asSold, "Bread roll=80; Bacon, cooked=50; Egg, fried=46; Barbecue sauce=15"),
        dish("pancake|hotcake|hot cake", .asSold, "Pancakes=231; Maple syrup=40; Butter=10"),
        dish("french toast", .asSold, "French toast=195; Maple syrup=30; Bacon, cooked=25"),
        dish("waffle", .asSold, "Waffle=132; Maple syrup=30; Vanilla ice cream=40"),
        dish("omelette|omelet|frittata", .base, "Omelette=200; Sourdough bread=60", protein: 40),
        dish("toastie|toasted sandwich|jaffle", .base, "White bread=90; Cheddar cheese=40; Butter=12", protein: 50),
        dish("club sandwich|blt", .plate, "White bread=120; Bacon, cooked=40; Chicken breast, cooked=60; Tomato=40; Cos lettuce=20; Mayonnaise=20"),
        dish("sandwich|roll|baguette|sub|focaccia|panini", .base, "Bread roll=110; Cos lettuce=20; Tomato=30; Mayonnaise=15", protein: 90),
        dish("wrap", .base, "Wrap, flour tortilla=70; Cos lettuce=30; Tomato=30; Mayonnaise=15", protein: 110),
        dish("granola|muesli", .asSold, "Granola=80; Greek yoghurt, plain=120; Blueberries=50"),
        dish("acai|smoothie bowl", .asSold, "Strawberry banana smoothie=250; Granola=40; Banana=60"),
        dish("porridge|oat", .asSold, "Porridge, made with water=300; Milk, full cream=60; Honey=20"),
        dish("banana bread", .asSold, "Banana bread=100; Butter=10"),
        dish("croissant", .asSold, "Croissant=70"),
        dish("muffin", .asSold, "Blueberry muffin=130"),
        // Desserts
        dish("tiramisu", .asSold, "Tiramisu=175"),
        dish("cheesecake", .asSold, "Cheesecake=130"),
        dish("brownie", .asSold, "Brownie=80; Vanilla ice cream=50"),
        dish("fondant|lava cake|chocolate cake|mud cake|torte", .asSold, "Chocolate cake=130; Vanilla ice cream=40"),
        dish("sticky date|pudding", .asSold, "Banana bread=140; Cream=30; Brown sugar=15"),
        dish("creme brulee|panna cotta|custard", .asSold, "Vanilla pudding=150; Cream=30; Sugar=12"),
        dish("gelato|ice cream|sorbet|affogato", .asSold, "Vanilla ice cream=120"),
        dish("pavlova|meringue", .asSold, "Lemon meringue pie=100; Cream=30; Strawberries=50"),
        dish("crumble|apple pie|tart", .asSold, "Apple pie=150; Vanilla ice cream=40"),
        dish("churro", .asSold, "Doughnut=108; Chocolate fudge sauce=30"),
        dish("baklava", .asSold, "Cinnamon danish=80; Honey=15"),
        // Drinks
        dish("flat white|latte|cappuccino|magic", .asSold, "Espresso=30; Milk, full cream=220"),
        dish("mocha|hot chocolate", .asSold, "Espresso=30; Milk, full cream=220; Chocolate fudge sauce=25"),
        dish("long black|short black|espresso|americano|macchiato", .asSold, "Espresso=60"),
        dish("chai", .asSold, "Black tea=120; Milk, full cream=130; Honey=10"),
        dish("tea|english breakfast|earl grey|peppermint|chamomile", .asSold, "Black tea=237"),
        dish("milkshake|shake|thick shake", .asSold, "Chocolate milkshake=300"),
        dish("smoothie", .asSold, "Strawberry banana smoothie=347"),
        dish("juice|orange juice|apple juice", .asSold, "Orange juice=250"),
        dish("coke|cola|pepsi|soft drink|sprite|lemonade|fanta|solo", .asSold, "Cola=375"),
        dish("soda water|sparkling water|still water|mineral water", .asSold, "Soda water=355"),
        dish("beer|lager|pale ale|ale|ipa|pilsner|pilsener|stout|schooner|pint|pot|cider", .asSold, "Beer=425"),
        dish("wine|shiraz|cabernet|merlot|pinot noir|tempranillo|sangiovese|malbec|rioja|grenache", .asSold, "Red wine=150"),
        dish("white wine|sauvignon blanc|sav blanc|chardonnay|riesling|pinot gris|pinot grigio|prosecco|sparkling|champagne|rose|moscato|fiano|vermentino", .asSold, "White wine=150"),
        dish("cocktail|spritz|negroni|margarita cocktail|mojito|martini|old fashioned|daiquiri|paloma|highball", .asSold, "Daiquiri=120; Lemonade (lemon-lime soft drink)=60"),
        dish("gin|vodka|rum|whisky|whiskey|tequila|bourbon", .asSold, "Vodka, gin or rum=42; Soda water=120"),
    ]

    private static func item(_ names: String, _ food: String?, _ role: Role, _ grams: Double = 0) -> [(key: String, value: Ingredient)] {
        let usual: Double = switch role {
        case .protein: 180
        case .starch: 180
        case .veg: 70
        case .sauce: 35
        case .cheese: 30
        case .topping: 20
        }
        return phrase(names).map { ($0.joined(separator: " "), Ingredient(food: food, role: role, grams: grams > 0 ? grams : usual)) }
    }

    /// The ingredient named by each run of words, as `MenuEstimator.tokens` writes them. The longest run wins, so "sweet potato"
    /// isn't potato and "fish sauce" isn't fish.
    static let ingredients: [String: Ingredient] = {
        var table: [String: Ingredient] = [:]
        let lists = [
            // Words that aren't the food they look like.
            item("fish sauce|oyster sauce|chicken salt|chicken stock|beef stock|chicken jus|lamb jus|beef jus|jus|prawn cracker|rice paper|rice wine|rice vinegar|chilli|chili|herb|salt|pepper|lemon|lime|stock|bread crumb|breadcrumb|peanut free|nut free|egg free|dairy free|gluten free", nil, .topping),
            // Proteins
            item("chicken|free range chicken|grilled chicken|chicken thigh|fried chicken|karaage", "Chicken thigh, cooked", .protein),
            item("chicken breast", "Chicken breast, cooked", .protein),
            item("roast chicken|rotisserie chicken", "Roast chicken, meat and skin", .protein),
            item("beef|beef cheek|brisket|wagyu|angus|short rib", "Beef mince, 10% fat, cooked", .protein),
            item("steak|rump|sirloin|porterhouse|scotch fillet|ribeye|rib eye|eye fillet", "Top sirloin (rump) steak, cooked", .protein, 280),
            item("beef patty|patty|smashed patty", "Beef patty, 15% fat, cooked", .protein, 150),
            item("lamb|lamb shoulder|lamb rump|lamb cutlet|lamb backstrap", "Lamb loin, lean, cooked", .protein),
            item("pork|pork loin|pork cutlet|pork scotch", "Pork chop, cooked", .protein),
            item("pork belly", "Pork belly, raw", .protein, 140),
            item("ham|leg ham|prosciutto|jamon", "Ham, lean", .protein, 60),
            item("bacon|pancetta|speck", "Bacon, cooked", .protein, 50),
            item("salami|chorizo|nduja|soppressa", "Salami", .protein, 50),
            item("pepperoni", "Pepperoni slices", .protein, 50),
            item("sausage|snag|chipolata|merguez", "Beef sausage, cooked", .protein, 120),
            item("turkey", "Turkey breast, cooked", .protein),
            item("salmon|ocean trout|atlantic salmon", "Salmon, cooked", .protein),
            item("smoked salmon", "Smoked salmon", .protein, 80),
            item("tuna|yellowfin|kingfish", "Tuna steak, cooked", .protein),
            item("fish|barramundi|snapper|flathead|whiting|cod|hake|ling|market fish|gummy shark|flake|bream|john dory", "White fish (cod), cooked", .protein),
            item("prawn|shrimp|king prawn", "Prawns, cooked", .protein, 130),
            item("scallop", "Scallops, cooked", .protein, 100),
            item("calamari|squid", "Calamari, fried", .protein, 130),
            item("octopus", "Octopus, cooked", .protein, 130),
            item("mussel|clam|vongole|pippi", "Mussels, cooked", .protein, 130),
            item("crab|blue swimmer crab|spanner crab", "Crab, cooked", .protein, 100),
            item("lobster|moreton bay bug|bug", "Lobster, cooked", .protein, 120),
            item("egg|free range egg", "Egg, poached", .protein, 60),
            item("tofu|bean curd", "Tofu, firm", .protein, 150),
            item("tempeh", "Tempeh", .protein, 120),
            item("halloumi|haloumi", "Feta", .protein, 90),
            item("lentil", "Lentils, cooked", .protein, 140),
            item("chickpea", "Chickpeas, canned", .protein, 120),
            item("black bean|kidney bean|bean mix|cannellini", "Black beans, cooked", .protein, 110),
            // Starches
            item("rice|jasmine rice|steamed rice|coconut rice|basmati|saffron rice|sushi rice", "White rice, cooked", .starch, 200),
            item("brown rice", "Brown rice, cooked", .starch, 200),
            item("noodle|egg noodle|hokkien noodle|udon|ramen noodle", "Egg noodles, cooked", .starch, 250),
            item("rice noodle|vermicelli", "Rice noodles, cooked", .starch, 220),
            item("soba", "Soba noodles, cooked", .starch, 220),
            item("pasta|spaghetti|linguine|penne|rigatoni|fettuccine", "Pasta, cooked", .starch, 280),
            item("couscous|cous cous", "Couscous, cooked", .starch, 160),
            item("quinoa", "Quinoa, cooked", .starch, 150),
            item("chip|fry|shoestring fry|hand cut chip|beer battered chip|french fry", "French fries, takeaway", .starch, 150),
            item("wedge|potato wedge", "Oven chips, baked", .starch, 180),
            item("mash|mashed potato|potato puree|paris mash|pomme puree|parsnip puree", "Mashed potato", .starch, 180),
            item("potato|chat potato|roast potato|kipfler|crushed potato|dutch cream", "Potato, baked", .starch, 170),
            item("sweet potato", "Sweet potato, baked", .starch, 150),
            item("polenta", "Corn, cooked", .starch, 120),
            item("bread|sourdough|toast|ciabatta|turkish bread|focaccia", "Sourdough bread", .starch, 80),
            item("bun|brioche|brioche bun|milk bun|roll", "Bread roll", .starch, 80),
            item("pita|pitta|flatbread|flat bread", "Pita bread", .starch, 60),
            item("naan|roti|garlic naan|paratha", "Naan", .starch, 90),
            item("tortilla", "Wrap, flour tortilla", .starch, 50),
            // Vegetables
            item("broccolini|broccoli|tenderstem", "Broccoli, boiled", .veg),
            item("green bean|bean|snake bean", "Green beans, boiled", .veg),
            item("green|seasonal green|seasonal vegetable|seasonal veg|vegetable|veg|mixed veg|roast vegetable|roasted vegetable", "Mixed vegetables, boiled", .veg, 100),
            item("spinach|silverbeet|baby spinach", "Spinach, boiled", .veg, 50),
            item("kale|cavolo nero", "Kale", .veg, 40),
            item("rocket|arugula|mixed leaf|leaf|salad green", "Rocket", .veg, 30),
            item("salad|side salad|garden salad", "Garden salad, no dressing", .veg, 80),
            item("lettuce|cos|baby cos", "Cos lettuce", .veg, 40),
            item("tomato|cherry tomato|heirloom tomato|roma tomato|semi dried tomato|sun dried tomato", "Tomato", .veg, 60),
            item("mushroom|field mushroom|shiitake|oyster mushroom|portobello|enoki", "Mushrooms", .veg, 80),
            item("onion|red onion|caramelised onion|pickled onion|shallot", "Onion", .veg, 40),
            item("capsicum|pepper strip|roast capsicum|red pepper", "Red capsicum", .veg, 50),
            item("zucchini|courgette", "Zucchini", .veg, 60),
            item("eggplant|aubergine", "Eggplant", .veg, 90),
            item("asparagus", "Asparagus", .veg, 60),
            item("pumpkin|butternut|butternut pumpkin", "Butternut pumpkin, baked", .veg, 100),
            item("carrot|baby carrot", "Carrot, boiled", .veg, 60),
            item("cauliflower", "Cauliflower, boiled", .veg, 100),
            item("corn|sweetcorn|sweet corn", "Corn, cooked", .veg, 50),
            item("pea|snow pea|sugar snap", "Peas, cooked", .veg, 50),
            item("cabbage|wombok|red cabbage", "Cabbage", .veg, 50),
            item("slaw|coleslaw", "Coleslaw", .veg, 70),
            item("bok choy|pak choy|gai lan|choy sum|asian green", "Bok choy", .veg, 70),
            item("beetroot|beet", "Beetroot", .veg, 60),
            item("fennel", "Fennel", .veg, 40),
            item("cucumber", "Cucumber", .veg, 40),
            item("bean sprout|sprout", "Bean sprouts", .veg, 40),
            item("pickle|gherkin|cornichon", "Pickles", .veg, 25),
            item("olive", "Olives", .topping, 30),
            item("avocado|avo|guacamole|guac", "Avocado", .topping, 60),
            // Sauces and fats
            item("cream|cream sauce|creamy", "Cream", .sauce, 60),
            item("butter|garlic butter|herb butter|cafe de paris", "Butter", .sauce, 15),
            item("aioli|mayo|mayonnaise|tartare|tartare sauce|burger sauce|special sauce|remoulade|kewpie", "Mayonnaise", .sauce, 20),
            item("hollandaise|bearnaise", "Mayonnaise", .sauce, 40),
            item("napoli|tomato sauce|napolitana|sugo|arrabbiata|passata|pomodoro", "Pasta sauce", .sauce, 100),
            item("pesto", "Pesto", .sauce, 25),
            item("satay|peanut sauce", "Peanut butter", .sauce, 30),
            item("bbq sauce|barbecue sauce|smoky bbq", "Barbecue sauce", .sauce, 30),
            item("teriyaki", "Teriyaki sauce", .sauce, 30),
            item("coconut cream|coconut milk|coconut curry", "Coconut milk, canned", .sauce, 100),
            item("dressing|vinaigrette|balsamic", "Olive oil", .sauce, 12),
            item("tahini", "Tahini", .sauce, 20),
            item("hummus|hommus", "Hummus", .sauce, 40),
            item("tzatziki|yoghurt|yogurt|raita|labneh", "Greek yoghurt, plain", .sauce, 40),
            item("sour cream|creme fraiche", "Sour cream", .sauce, 30),
            item("salsa|pico de gallo", "Salsa", .sauce, 40),
            // Cheese
            item("cheese|cheddar|tasty cheese", "Cheddar cheese", .cheese),
            item("mozzarella|bocconcini|burrata|fior di latte", "Mozzarella", .cheese, 60),
            item("parmesan|parmigiano|grana padano|pecorino", "Parmesan, grated", .cheese, 15),
            item("feta|goat cheese|goats cheese|chevre", "Feta", .cheese, 40),
            item("ricotta", "Ricotta", .cheese, 50),
            item("brie|camembert", "Brie", .cheese, 40),
            item("swiss|gruyere|provolone|emmental", "Swiss cheese", .cheese),
            item("mascarpone|cream cheese", "Cream cheese", .cheese, 30),
            // Crunch on top
            item("almond|flaked almond", "Almonds", .topping),
            item("walnut", "Walnuts", .topping),
            item("cashew", "Cashews", .topping),
            item("peanut", "Peanuts, roasted", .topping),
            item("pistachio|dukkah", "Pistachios", .topping, 15),
            item("pine nut|pinenut", "Pine nuts", .topping, 15),
            item("sesame|seed|pepita", "Pumpkin seeds", .topping, 10),
        ]
        for list in lists { for (key, value) in list { table[key] = value } }
        return table
    }()

    /// Starches that do the same job on a plate: a menu that names one means it instead of the usual one, not as well as.
    static let swaps: [Set<String>] = [
        ["White rice, cooked", "Brown rice, cooked", "Egg noodles, cooked", "Rice noodles, cooked", "Soba noodles, cooked", "Pasta, cooked", "Couscous, cooked", "Quinoa, cooked"],
        ["French fries, takeaway", "Oven chips, baked", "Mashed potato", "Potato, baked", "Sweet potato, baked"],
        ["Sourdough bread", "Bread roll", "Pita bread", "Naan", "Wrap, flour tortilla"],
    ]

    /// Dishes that already have their rice, pasta or noodles in them.
    static let filled: Set<String> = ["Spaghetti with meat sauce", "Spaghetti and meatballs", "Pad Thai with meat", "Ramen bowl with chicken", "Soup, pho, with meat",
                                      "Macaroni and cheese, canned", "Lasagne with meat", "Fried rice (no meat)", "Cheese ravioli with marinara", "Gnocchi, potato", "Kebab wrap (gyro)"]

    /// Every food the tables use, for the checks.
    static var foodNames: Set<String> {
        var names = Set(ingredients.values.compactMap(\.food))
        for recipe in recipes { names.formUnion(recipe.parts.map(\.food)); if let usual = recipe.usual { names.insert(usual.food) } }
        return names.union(["Canola oil", "Plain flour", "Olive oil"])
    }
}
