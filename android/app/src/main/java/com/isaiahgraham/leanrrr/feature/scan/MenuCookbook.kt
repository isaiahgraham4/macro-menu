package com.isaiahgraham.leanrrr.feature.scan

// Pure Kotlin (no Android classes), so the JUnit tests run it on the JVM. A port of MenuCookbook.swift.

/**
 * What restaurant dishes are usually made of, so a dish on a photographed menu can be added up from Leanrrr's own foods.
 * Every food named here is an exact name in GenericFoods.json or SurveyFoods.json (the tests hold that), and the gram
 * weights are a typical Australian restaurant serve. They're starting points to adjust, not published figures.
 */
object MenuCookbook {
    enum class Style {
        /** A plated dish: a shared or starter-sized version is scaled down. */
        PLATE,
        /** Comes as it comes (a drink, a dessert, a side): never scaled, and nothing is added to it. */
        AS_SOLD,
        /** A kind of dish built around what the menu says goes in it: a burger, a curry, a pizza. */
        BASE,
    }

    data class Part(val food: String, val grams: Double)

    data class Recipe(
        val names: List<List<String>>,
        val style: Style,
        val parts: List<Part>,
        /** How much of the named protein goes in a BASE. */
        val protein: Double,
        /** The protein to use when the menu doesn't name one. */
        val usual: Part?,
        /** What the base already has, so naming it adds nothing: a pizza's cheese and sauce. */
        val covers: Set<Role> = emptySet(),
    )

    enum class Role { PROTEIN, STARCH, VEG, SAUCE, CHEESE, TOPPING }

    data class Ingredient(
        /** Null for words that look like a food but aren't one here: "fish sauce", "chicken salt". */
        val food: String?,
        val role: Role,
        val grams: Double,
    )

    /** Words for a dish, or a heading, as `MenuEstimator.tokens` writes them. */
    fun phrase(names: String): List<List<String>> = names.split("|").map { MenuEstimator.tokens(it) }

    private fun parts(text: String): List<Part> = text.split(";").mapNotNull { item ->
        val pieces = item.split("=")
        val grams = pieces.getOrNull(1)?.trim()?.toDoubleOrNull()
        if (pieces.size != 2 || grams == null) null else Part(pieces[0].trim(), grams)
    }

    private fun dish(names: String, style: Style, list: String, protein: Double = 0.0, usual: String? = null, covers: Set<Role> = emptySet()) =
        Recipe(phrase(names), style, parts(list), protein, usual?.let { parts(it).firstOrNull() }, covers)

    private const val FRIES = "French fries, takeaway"
    private const val SIDE = "Garden salad, no dressing"
    private const val RICE = "White rice, cooked"

    /** Specific dishes first: when two names are the same length, the earlier one wins. */
    val recipes: List<Recipe> = listOf(
        // Pub and grill
        dish("parma|parmi|parmy|parmigiana|parmigiano chicken", Style.PLATE, "Chicken parmigiana (no pasta)=330; $FRIES=150; $SIDE=80"),
        dish("schnitzel|schnitty", Style.PLATE, "Chicken breast, cooked=200; Plain flour=25; Canola oil=20; $FRIES=150; $SIDE=80"),
        dish("fish and chip|fish n chip|fish chip", Style.PLATE, "Battered fish fillet=220; $FRIES=200; $SIDE=60; Mayonnaise=25"),
        dish("banger and mash|sausage and mash", Style.PLATE, "Beef sausage, cooked=180; Mashed potato=250; Peas, cooked=60"),
        dish("lamb shank", Style.PLATE, "Lamb loin, lean, cooked=220; Mashed potato=220; Pasta sauce=80"),
        dish("rib|pork rib|beef rib|bbq rib", Style.PLATE, "Pork spare ribs, roasted=350; Barbecue sauce=40; $FRIES=120"),
        dish("roast of the day|sunday roast|roast chicken", Style.PLATE, "Roast chicken, meat and skin=220; Potato, baked=200; Mixed vegetables, boiled=100"),
        dish("pulled pork", Style.BASE, "Bread roll=80; Pork chop, cooked=140; Barbecue sauce=30; Coleslaw=60"),
        dish("steak sandwich", Style.PLATE, "Sourdough bread=120; Top sirloin (rump) steak, cooked=130; Onion=40; Tomato=30; Cos lettuce=20; Barbecue sauce=20; Mayonnaise=15"),
        dish("steak|scotch fillet|porterhouse|rump|sirloin|ribeye|rib eye|eye fillet|t bone|tomahawk|striploin", Style.BASE, "Butter=10", protein = 280.0, usual = "Top sirloin (rump) steak, cooked=280"),
        dish("burger|cheeseburger|slider", Style.BASE, "Bread roll=80; Cheddar cheese=20; Cos lettuce=20; Tomato=30; Mayonnaise=15", protein = 150.0, usual = "Beef patty, 15% fat, cooked=150"),
        // Italian
        dish("margherita|margarita", Style.AS_SOLD, "Cheese pizza, frozen=420; Basil, fresh=5"),
        dish("pizza|calzone", Style.BASE, "Cheese pizza, frozen=400", protein = 60.0, covers = setOf(Role.SAUCE, Role.CHEESE)),
        dish("bolognese|ragu|spaghetti meat sauce", Style.PLATE, "Spaghetti with meat sauce=450; Parmesan, grated=10"),
        dish("meatball|polpette", Style.PLATE, "Spaghetti and meatballs=420"),
        dish("lasagne|lasagna", Style.PLATE, "Lasagne with meat=420"),
        dish("carbonara", Style.PLATE, "Pasta, cooked=300; Bacon, cooked=50; Egg=50; Cream=60; Parmesan, grated=25"),
        dish("marinara|seafood pasta", Style.PLATE, "Pasta, cooked=300; Pasta sauce=120; Prawns, cooked=60; Mussels, cooked=50; Calamari, cooked=40; Olive oil=10"),
        dish("ravioli|tortellini|agnolotti", Style.BASE, "Cheese ravioli with marinara=350; Parmesan, grated=10", protein = 50.0),
        dish("gnocchi", Style.BASE, "Gnocchi, potato=300; Pasta sauce=100; Parmesan, grated=15; Olive oil=10", protein = 100.0),
        dish("mac and cheese|macaroni cheese", Style.PLATE, "Macaroni and cheese, canned=350; Cheddar cheese=30"),
        dish("risotto", Style.BASE, "White rice, cooked=280; Parmesan, grated=20; Butter=15; Olive oil=8", protein = 120.0),
        dish("pasta|spaghetti|linguine|penne|fettuccine|fettucine|rigatoni|pappardelle|casarecce|orecchiette|tagliatelle|bucatini|spaghettini", Style.BASE, "Pasta, cooked=300; Pasta sauce=100; Olive oil=12; Parmesan, grated=10", protein = 120.0),
        dish("garlic bread|garlic pizza bread", Style.AS_SOLD, "Bread roll=100; Butter=25"),
        dish("burrata", Style.AS_SOLD, "Mozzarella=120; Tomato=80; Olive oil=12"),
        dish("bruschetta", Style.AS_SOLD, "Sourdough bread=100; Tomato=100; Olive oil=12; Basil, fresh=5"),
        dish("arancini", Style.AS_SOLD, "White rice, cooked=120; Mozzarella=30; Plain flour=15; Canola oil=12"),
        // Asian
        dish("pad thai", Style.PLATE, "Pad Thai with meat=450"),
        dish("butter chicken|murgh makhani", Style.PLATE, "Chicken curry=350; Cream=30; $RICE=200"),
        dish("tikka masala|tikka", Style.PLATE, "Chicken curry=350; $RICE=200"),
        dish("rendang", Style.PLATE, "Beef curry=350; Coconut milk, canned=40; $RICE=200"),
        dish("dal|dhal|daal|tadka", Style.PLATE, "Lentil curry=320; $RICE=180"),
        dish("green curry|red curry|massaman|panang|penang|thai curry|yellow curry", Style.BASE, "Coconut milk, canned=120; Mixed vegetables, boiled=100; $RICE=200; Canola oil=8", protein = 150.0, usual = "Chicken thigh, cooked=150"),
        dish("korma|vindaloo|rogan josh|madras|saag|balti|jalfrezi|bhuna|curry", Style.BASE, "Vegetable curry=200; $RICE=200", protein = 150.0, usual = "Chicken thigh, cooked=150"),
        dish("nasi goreng", Style.PLATE, "Fried rice (no meat)=350; Chicken thigh, cooked=80; Egg, fried=46"),
        dish("fried rice", Style.BASE, "Fried rice (no meat)=380", protein = 80.0),
        dish("laksa", Style.PLATE, "Rice noodles, cooked=160; Coconut milk, canned=150; Chicken thigh, cooked=100; Prawns, cooked=40; Tofu, firm=40; Bean sprouts=40"),
        dish("pho", Style.PLATE, "Soup, pho, with meat=650"),
        dish("ramen", Style.PLATE, "Ramen bowl with chicken=650"),
        dish("chow mein|lo mein|hokkien|singapore noodle|char kway teow|mie goreng|mee goreng|yakisoba|udon stir fry", Style.BASE, "Egg noodles, cooked=280; Mixed vegetables, boiled=80; Canola oil=15; Soy sauce=20", protein = 120.0),
        dish("stir fry|stir fried|stirfry|wok", Style.BASE, "Mixed vegetables, boiled=150; $RICE=200; Canola oil=15; Soy sauce=20", protein = 150.0),
        dish("katsu", Style.PLATE, "Chicken breast, cooked=170; Plain flour=20; Canola oil=18; $RICE=200; Cabbage=50"),
        dish("teriyaki", Style.BASE, "$RICE=200; Teriyaki sauce=40; Mixed vegetables, boiled=60; Canola oil=8", protein = 170.0, usual = "Chicken thigh, cooked=170"),
        dish("bibimbap", Style.BASE, "$RICE=250; Mixed vegetables, boiled=100; Egg, fried=46; Sesame oil=8", protein = 90.0),
        dish("poke|poke bowl", Style.BASE, "$RICE=220; Avocado=40; Edamame=30; Cucumber=30; Mayonnaise=12; Soy sauce=12", protein = 120.0, usual = "Salmon, raw=120"),
        dish("sashimi", Style.AS_SOLD, "Salmon, raw=120"),
        dish("sushi|nigiri|maki", Style.AS_SOLD, "$RICE=180; Salmon, raw=50; Avocado=20"),
        dish("dumpling|gyoza|wonton|dim sim|bao|bun bao", Style.AS_SOLD, "Dumplings, fried=175"),
        dish("spring roll|egg roll", Style.AS_SOLD, "Spring roll (vegetable)=140"),
        dish("salt and pepper squid|salt and pepper calamari|calamari|squid", Style.PLATE, "Calamari, fried=220; Mayonnaise=20; $SIDE=50"),
        // Mexican and Mediterranean
        dish("taco", Style.BASE, "Corn tortilla=72; Cabbage=40; Salsa=40; Sour cream=20", protein = 110.0, usual = "Beef mince, 10% fat, cooked=110"),
        dish("burrito bowl", Style.BASE, "$RICE=200; Black beans, cooked=80; Salsa=50; Cheddar cheese=25; Sour cream=25", protein = 120.0, usual = "Chicken thigh, cooked=120"),
        dish("burrito", Style.BASE, "Wrap, flour tortilla=100; $RICE=120; Black beans, cooked=70; Cheddar cheese=25; Salsa=40", protein = 120.0, usual = "Chicken thigh, cooked=120"),
        dish("nachos", Style.PLATE, "Nachos with cheese=320; Beef mince, 10% fat, cooked=80; Sour cream=30; Salsa=40; Avocado=30"),
        dish("quesadilla", Style.BASE, "Cheese quesadilla=194", protein = 80.0, covers = setOf(Role.CHEESE)),
        dish("souvlaki|gyros|gyro|yiros|kebab|doner|shawarma", Style.PLATE, "Kebab wrap (gyro)=320"),
        dish("falafel", Style.PLATE, "Falafel=120; Pita bread=60; Hummus=50; $SIDE=60"),
        dish("hummus|hommus|baba ganoush|dip", Style.AS_SOLD, "Hummus=100; Pita bread=60"),
        // Salads, soups, sides
        dish("side salad|garden salad|green salad|mixed leaf|house salad", Style.AS_SOLD, "$SIDE=120; Olive oil=8"),
        dish("caesar", Style.BASE, "Cos lettuce=150; Bacon, cooked=30; Egg, poached=50; Caesar dressing=45; Parmesan, grated=15; Bread roll=30", protein = 120.0),
        dish("greek salad", Style.PLATE, "Tomato=100; Cucumber=100; Feta=60; Olives=30; Onion=30; Olive oil=15"),
        dish("salad|slaw", Style.BASE, "Cos lettuce=120; Tomato=50; Cucumber=40; Olive oil=15", protein = 120.0),
        dish("soup|chowder|broth|bisque|minestrone", Style.BASE, "Vegetable soup, chunky=350; Bread roll=50", protein = 60.0),
        dish("potato wedge|wedge", Style.AS_SOLD, "Oven chips, baked=250; Sour cream=30"),
        dish("sweet potato fry|sweet potato chip", Style.AS_SOLD, "Sweet potato, baked=200; Canola oil=15; Mayonnaise=15"),
        dish("chip|fry|shoestring|french fry|hand cut chip", Style.AS_SOLD, "$FRIES=200"),
        dish("onion ring", Style.AS_SOLD, "Onion rings, takeaway=150"),
        dish("wing|buffalo wing", Style.AS_SOLD, "Fried chicken wing=300"),
        // Breakfast and cafe
        dish("benedict|eggs bene|egg ben", Style.PLATE, "English muffin=57; Egg, poached=100; Ham, lean=50; Mayonnaise=40; Butter=8"),
        dish("big breakfast|big brekkie|farmers breakfast|full breakfast", Style.PLATE, "Egg, fried=92; Bacon, cooked=60; Beef sausage, cooked=86; Sourdough bread=80; Mushrooms=60; Tomato=60; Hash browns=60; Butter=10"),
        dish("smashed avo|smashed avocado|avo toast|avocado toast|avocado on toast|avo on toast", Style.PLATE, "Sourdough bread=100; Avocado=100; Feta=30; Egg, poached=50"),
        dish("bacon and egg roll|bacon egg roll|bacon and egg", Style.AS_SOLD, "Bread roll=80; Bacon, cooked=50; Egg, fried=46; Barbecue sauce=15"),
        dish("pancake|hotcake|hot cake", Style.AS_SOLD, "Pancakes=231; Maple syrup=40; Butter=10"),
        dish("french toast", Style.AS_SOLD, "French toast=195; Maple syrup=30; Bacon, cooked=25"),
        dish("waffle", Style.AS_SOLD, "Waffle=132; Maple syrup=30; Vanilla ice cream=40"),
        dish("omelette|omelet|frittata", Style.BASE, "Omelette=200; Sourdough bread=60", protein = 40.0),
        dish("toastie|toasted sandwich|jaffle", Style.BASE, "White bread=90; Cheddar cheese=40; Butter=12", protein = 50.0),
        dish("club sandwich|blt", Style.PLATE, "White bread=120; Bacon, cooked=40; Chicken breast, cooked=60; Tomato=40; Cos lettuce=20; Mayonnaise=20"),
        dish("sandwich|roll|baguette|sub|focaccia|panini", Style.BASE, "Bread roll=110; Cos lettuce=20; Tomato=30; Mayonnaise=15", protein = 90.0),
        dish("wrap", Style.BASE, "Wrap, flour tortilla=70; Cos lettuce=30; Tomato=30; Mayonnaise=15", protein = 110.0),
        dish("granola|muesli", Style.AS_SOLD, "Granola=80; Greek yoghurt, plain=120; Blueberries=50"),
        dish("acai|smoothie bowl", Style.AS_SOLD, "Strawberry banana smoothie=250; Granola=40; Banana=60"),
        dish("porridge|oat", Style.AS_SOLD, "Porridge, made with water=300; Milk, full cream=60; Honey=20"),
        dish("banana bread", Style.AS_SOLD, "Banana bread=100; Butter=10"),
        dish("croissant", Style.AS_SOLD, "Croissant=70"),
        dish("muffin", Style.AS_SOLD, "Blueberry muffin=130"),
        // Desserts
        dish("tiramisu", Style.AS_SOLD, "Tiramisu=175"),
        dish("cheesecake", Style.AS_SOLD, "Cheesecake=130"),
        dish("brownie", Style.AS_SOLD, "Brownie=80; Vanilla ice cream=50"),
        dish("fondant|lava cake|chocolate cake|mud cake|torte", Style.AS_SOLD, "Chocolate cake=130; Vanilla ice cream=40"),
        dish("sticky date|pudding", Style.AS_SOLD, "Banana bread=140; Cream=30; Brown sugar=15"),
        dish("creme brulee|panna cotta|custard", Style.AS_SOLD, "Vanilla pudding=150; Cream=30; Sugar=12"),
        dish("gelato|ice cream|sorbet|affogato", Style.AS_SOLD, "Vanilla ice cream=120"),
        dish("pavlova|meringue", Style.AS_SOLD, "Lemon meringue pie=100; Cream=30; Strawberries=50"),
        dish("crumble|apple pie|tart", Style.AS_SOLD, "Apple pie=150; Vanilla ice cream=40"),
        dish("churro", Style.AS_SOLD, "Doughnut=108; Chocolate fudge sauce=30"),
        dish("baklava", Style.AS_SOLD, "Cinnamon danish=80; Honey=15"),
        // Drinks
        dish("flat white|latte|cappuccino|magic", Style.AS_SOLD, "Espresso=30; Milk, full cream=220"),
        dish("mocha|hot chocolate", Style.AS_SOLD, "Espresso=30; Milk, full cream=220; Chocolate fudge sauce=25"),
        dish("long black|short black|espresso|americano|macchiato", Style.AS_SOLD, "Espresso=60"),
        dish("chai", Style.AS_SOLD, "Black tea=120; Milk, full cream=130; Honey=10"),
        dish("tea|english breakfast|earl grey|peppermint|chamomile", Style.AS_SOLD, "Black tea=237"),
        dish("milkshake|shake|thick shake", Style.AS_SOLD, "Chocolate milkshake=300"),
        dish("smoothie", Style.AS_SOLD, "Strawberry banana smoothie=347"),
        dish("juice|orange juice|apple juice", Style.AS_SOLD, "Orange juice=250"),
        dish("coke|cola|pepsi|soft drink|sprite|lemonade|fanta|solo", Style.AS_SOLD, "Cola=375"),
        dish("soda water|sparkling water|still water|mineral water", Style.AS_SOLD, "Soda water=355"),
        dish("beer|lager|pale ale|ale|ipa|pilsner|pilsener|stout|schooner|pint|pot|cider", Style.AS_SOLD, "Beer=425"),
        dish("wine|shiraz|cabernet|merlot|pinot noir|tempranillo|sangiovese|malbec|rioja|grenache", Style.AS_SOLD, "Red wine=150"),
        dish("white wine|sauvignon blanc|sav blanc|chardonnay|riesling|pinot gris|pinot grigio|prosecco|sparkling|champagne|rose|moscato|fiano|vermentino", Style.AS_SOLD, "White wine=150"),
        dish("cocktail|spritz|negroni|margarita cocktail|mojito|martini|old fashioned|daiquiri|paloma|highball", Style.AS_SOLD, "Daiquiri=120; Lemonade (lemon-lime soft drink)=60"),
        dish("gin|vodka|rum|whisky|whiskey|tequila|bourbon", Style.AS_SOLD, "Vodka, gin or rum=42; Soda water=120"),    )

    private fun item(names: String, food: String?, role: Role, grams: Double = 0.0): List<Pair<String, Ingredient>> {
        val usual = when (role) {
            Role.PROTEIN -> 180.0
            Role.STARCH -> 180.0
            Role.VEG -> 70.0
            Role.SAUCE -> 35.0
            Role.CHEESE -> 30.0
            Role.TOPPING -> 20.0
        }
        return phrase(names).map { it.joinToString(" ") to Ingredient(food, role, if (grams > 0) grams else usual) }
    }

    /**
     * The ingredient named by each run of words, as `MenuEstimator.tokens` writes them. The longest run wins, so "sweet potato"
     * isn't potato and "fish sauce" isn't fish.
     */
    val ingredients: Map<String, Ingredient> by lazy {
        val table = HashMap<String, Ingredient>()
        val lists = listOf(
            // Words that aren't the food they look like.
            item("fish sauce|oyster sauce|chicken salt|chicken stock|beef stock|chicken jus|lamb jus|beef jus|jus|prawn cracker|rice paper|rice wine|rice vinegar|chilli|chili|herb|salt|pepper|lemon|lime|stock|bread crumb|breadcrumb|peanut free|nut free|egg free|dairy free|gluten free", null, Role.TOPPING),
            // Proteins
            item("chicken|free range chicken|grilled chicken|chicken thigh|fried chicken|karaage", "Chicken thigh, cooked", Role.PROTEIN),
            item("chicken breast", "Chicken breast, cooked", Role.PROTEIN),
            item("roast chicken|rotisserie chicken", "Roast chicken, meat and skin", Role.PROTEIN),
            item("beef|beef cheek|brisket|wagyu|angus|short rib", "Beef mince, 10% fat, cooked", Role.PROTEIN),
            item("steak|rump|sirloin|porterhouse|scotch fillet|ribeye|rib eye|eye fillet", "Top sirloin (rump) steak, cooked", Role.PROTEIN, 280.0),
            item("beef patty|patty|smashed patty", "Beef patty, 15% fat, cooked", Role.PROTEIN, 150.0),
            item("lamb|lamb shoulder|lamb rump|lamb cutlet|lamb backstrap", "Lamb loin, lean, cooked", Role.PROTEIN),
            item("pork|pork loin|pork cutlet|pork scotch", "Pork chop, cooked", Role.PROTEIN),
            item("pork belly", "Pork belly, raw", Role.PROTEIN, 140.0),
            item("ham|leg ham|prosciutto|jamon", "Ham, lean", Role.PROTEIN, 60.0),
            item("bacon|pancetta|speck", "Bacon, cooked", Role.PROTEIN, 50.0),
            item("salami|chorizo|nduja|soppressa", "Salami", Role.PROTEIN, 50.0),
            item("pepperoni", "Pepperoni slices", Role.PROTEIN, 50.0),
            item("sausage|snag|chipolata|merguez", "Beef sausage, cooked", Role.PROTEIN, 120.0),
            item("turkey", "Turkey breast, cooked", Role.PROTEIN),
            item("salmon|ocean trout|atlantic salmon", "Salmon, cooked", Role.PROTEIN),
            item("smoked salmon", "Smoked salmon", Role.PROTEIN, 80.0),
            item("tuna|yellowfin|kingfish", "Tuna steak, cooked", Role.PROTEIN),
            item("fish|barramundi|snapper|flathead|whiting|cod|hake|ling|market fish|gummy shark|flake|bream|john dory", "White fish (cod), cooked", Role.PROTEIN),
            item("prawn|shrimp|king prawn", "Prawns, cooked", Role.PROTEIN, 130.0),
            item("scallop", "Scallops, cooked", Role.PROTEIN, 100.0),
            item("calamari|squid", "Calamari, fried", Role.PROTEIN, 130.0),
            item("octopus", "Octopus, cooked", Role.PROTEIN, 130.0),
            item("mussel|clam|vongole|pippi", "Mussels, cooked", Role.PROTEIN, 130.0),
            item("crab|blue swimmer crab|spanner crab", "Crab, cooked", Role.PROTEIN, 100.0),
            item("lobster|moreton bay bug|bug", "Lobster, cooked", Role.PROTEIN, 120.0),
            item("egg|free range egg", "Egg, poached", Role.PROTEIN, 60.0),
            item("tofu|bean curd", "Tofu, firm", Role.PROTEIN, 150.0),
            item("tempeh", "Tempeh", Role.PROTEIN, 120.0),
            item("halloumi|haloumi", "Feta", Role.PROTEIN, 90.0),
            item("lentil", "Lentils, cooked", Role.PROTEIN, 140.0),
            item("chickpea", "Chickpeas, canned", Role.PROTEIN, 120.0),
            item("black bean|kidney bean|bean mix|cannellini", "Black beans, cooked", Role.PROTEIN, 110.0),
            // Starches
            item("rice|jasmine rice|steamed rice|coconut rice|basmati|saffron rice|sushi rice", "White rice, cooked", Role.STARCH, 200.0),
            item("brown rice", "Brown rice, cooked", Role.STARCH, 200.0),
            item("noodle|egg noodle|hokkien noodle|udon|ramen noodle", "Egg noodles, cooked", Role.STARCH, 250.0),
            item("rice noodle|vermicelli", "Rice noodles, cooked", Role.STARCH, 220.0),
            item("soba", "Soba noodles, cooked", Role.STARCH, 220.0),
            item("pasta|spaghetti|linguine|penne|rigatoni|fettuccine", "Pasta, cooked", Role.STARCH, 280.0),
            item("couscous|cous cous", "Couscous, cooked", Role.STARCH, 160.0),
            item("quinoa", "Quinoa, cooked", Role.STARCH, 150.0),
            item("chip|fry|shoestring fry|hand cut chip|beer battered chip|french fry", "French fries, takeaway", Role.STARCH, 150.0),
            item("wedge|potato wedge", "Oven chips, baked", Role.STARCH, 180.0),
            item("mash|mashed potato|potato puree|paris mash|pomme puree|parsnip puree", "Mashed potato", Role.STARCH, 180.0),
            item("potato|chat potato|roast potato|kipfler|crushed potato|dutch cream", "Potato, baked", Role.STARCH, 170.0),
            item("sweet potato", "Sweet potato, baked", Role.STARCH, 150.0),
            item("polenta", "Corn, cooked", Role.STARCH, 120.0),
            item("bread|sourdough|toast|ciabatta|turkish bread|focaccia", "Sourdough bread", Role.STARCH, 80.0),
            item("bun|brioche|brioche bun|milk bun|roll", "Bread roll", Role.STARCH, 80.0),
            item("pita|pitta|flatbread|flat bread", "Pita bread", Role.STARCH, 60.0),
            item("naan|roti|garlic naan|paratha", "Naan", Role.STARCH, 90.0),
            item("tortilla", "Wrap, flour tortilla", Role.STARCH, 50.0),
            // Vegetables
            item("broccolini|broccoli|tenderstem", "Broccoli, boiled", Role.VEG),
            item("green bean|bean|snake bean", "Green beans, boiled", Role.VEG),
            item("green|seasonal green|seasonal vegetable|seasonal veg|vegetable|veg|mixed veg|roast vegetable|roasted vegetable", "Mixed vegetables, boiled", Role.VEG, 100.0),
            item("spinach|silverbeet|baby spinach", "Spinach, boiled", Role.VEG, 50.0),
            item("kale|cavolo nero", "Kale", Role.VEG, 40.0),
            item("rocket|arugula|mixed leaf|leaf|salad green", "Rocket", Role.VEG, 30.0),
            item("salad|side salad|garden salad", "Garden salad, no dressing", Role.VEG, 80.0),
            item("lettuce|cos|baby cos", "Cos lettuce", Role.VEG, 40.0),
            item("tomato|cherry tomato|heirloom tomato|roma tomato|semi dried tomato|sun dried tomato", "Tomato", Role.VEG, 60.0),
            item("mushroom|field mushroom|shiitake|oyster mushroom|portobello|enoki", "Mushrooms", Role.VEG, 80.0),
            item("onion|red onion|caramelised onion|pickled onion|shallot", "Onion", Role.VEG, 40.0),
            item("capsicum|pepper strip|roast capsicum|red pepper", "Red capsicum", Role.VEG, 50.0),
            item("zucchini|courgette", "Zucchini", Role.VEG, 60.0),
            item("eggplant|aubergine", "Eggplant", Role.VEG, 90.0),
            item("asparagus", "Asparagus", Role.VEG, 60.0),
            item("pumpkin|butternut|butternut pumpkin", "Butternut pumpkin, baked", Role.VEG, 100.0),
            item("carrot|baby carrot", "Carrot, boiled", Role.VEG, 60.0),
            item("cauliflower", "Cauliflower, boiled", Role.VEG, 100.0),
            item("corn|sweetcorn|sweet corn", "Corn, cooked", Role.VEG, 50.0),
            item("pea|snow pea|sugar snap", "Peas, cooked", Role.VEG, 50.0),
            item("cabbage|wombok|red cabbage", "Cabbage", Role.VEG, 50.0),
            item("slaw|coleslaw", "Coleslaw", Role.VEG, 70.0),
            item("bok choy|pak choy|gai lan|choy sum|asian green", "Bok choy", Role.VEG, 70.0),
            item("beetroot|beet", "Beetroot", Role.VEG, 60.0),
            item("fennel", "Fennel", Role.VEG, 40.0),
            item("cucumber", "Cucumber", Role.VEG, 40.0),
            item("bean sprout|sprout", "Bean sprouts", Role.VEG, 40.0),
            item("pickle|gherkin|cornichon", "Pickles", Role.VEG, 25.0),
            item("olive", "Olives", Role.TOPPING, 30.0),
            item("avocado|avo|guacamole|guac", "Avocado", Role.TOPPING, 60.0),
            // Sauces and fats
            item("cream|cream sauce|creamy", "Cream", Role.SAUCE, 60.0),
            item("butter|garlic butter|herb butter|cafe de paris", "Butter", Role.SAUCE, 15.0),
            item("aioli|mayo|mayonnaise|tartare|tartare sauce|burger sauce|special sauce|remoulade|kewpie", "Mayonnaise", Role.SAUCE, 20.0),
            item("hollandaise|bearnaise", "Mayonnaise", Role.SAUCE, 40.0),
            item("napoli|tomato sauce|napolitana|sugo|arrabbiata|passata|pomodoro", "Pasta sauce", Role.SAUCE, 100.0),
            item("pesto", "Pesto", Role.SAUCE, 25.0),
            item("satay|peanut sauce", "Peanut butter", Role.SAUCE, 30.0),
            item("bbq sauce|barbecue sauce|smoky bbq", "Barbecue sauce", Role.SAUCE, 30.0),
            item("teriyaki", "Teriyaki sauce", Role.SAUCE, 30.0),
            item("coconut cream|coconut milk|coconut curry", "Coconut milk, canned", Role.SAUCE, 100.0),
            item("dressing|vinaigrette|balsamic", "Olive oil", Role.SAUCE, 12.0),
            item("tahini", "Tahini", Role.SAUCE, 20.0),
            item("hummus|hommus", "Hummus", Role.SAUCE, 40.0),
            item("tzatziki|yoghurt|yogurt|raita|labneh", "Greek yoghurt, plain", Role.SAUCE, 40.0),
            item("sour cream|creme fraiche", "Sour cream", Role.SAUCE, 30.0),
            item("salsa|pico de gallo", "Salsa", Role.SAUCE, 40.0),
            // Cheese
            item("cheese|cheddar|tasty cheese", "Cheddar cheese", Role.CHEESE),
            item("mozzarella|bocconcini|burrata|fior di latte", "Mozzarella", Role.CHEESE, 60.0),
            item("parmesan|parmigiano|grana padano|pecorino", "Parmesan, grated", Role.CHEESE, 15.0),
            item("feta|goat cheese|goats cheese|chevre", "Feta", Role.CHEESE, 40.0),
            item("ricotta", "Ricotta", Role.CHEESE, 50.0),
            item("brie|camembert", "Brie", Role.CHEESE, 40.0),
            item("swiss|gruyere|provolone|emmental", "Swiss cheese", Role.CHEESE),
            item("mascarpone|cream cheese", "Cream cheese", Role.CHEESE, 30.0),
            // Crunch on top
            item("almond|flaked almond", "Almonds", Role.TOPPING),
            item("walnut", "Walnuts", Role.TOPPING),
            item("cashew", "Cashews", Role.TOPPING),
            item("peanut", "Peanuts, roasted", Role.TOPPING),
            item("pistachio|dukkah", "Pistachios", Role.TOPPING, 15.0),
            item("pine nut|pinenut", "Pine nuts", Role.TOPPING, 15.0),
            item("sesame|seed|pepita", "Pumpkin seeds", Role.TOPPING, 10.0),        )
        for (list in lists) for ((key, value) in list) table[key] = value
        table
    }

    /** Starches that do the same job on a plate: a menu that names one means it instead of the usual one, not as well as. */
    val swaps: List<Set<String>> = listOf(
        setOf("White rice, cooked", "Brown rice, cooked", "Egg noodles, cooked", "Rice noodles, cooked", "Soba noodles, cooked", "Pasta, cooked", "Couscous, cooked", "Quinoa, cooked"),
        setOf("French fries, takeaway", "Oven chips, baked", "Mashed potato", "Potato, baked", "Sweet potato, baked"),
        setOf("Sourdough bread", "Bread roll", "Pita bread", "Naan", "Wrap, flour tortilla"),
    )

    /** Dishes that already have their rice, pasta or noodles in them. */
    val filled: Set<String> = setOf("Spaghetti with meat sauce", "Spaghetti and meatballs", "Pad Thai with meat", "Ramen bowl with chicken", "Soup, pho, with meat",
        "Macaroni and cheese, canned", "Lasagne with meat", "Fried rice (no meat)", "Cheese ravioli with marinara", "Gnocchi, potato", "Kebab wrap (gyro)")

    /** Every food the tables use, for the checks. */
    val foodNames: Set<String>
        get() {
            val names = ingredients.values.mapNotNull { it.food }.toMutableSet()
            for (recipe in recipes) { names += recipe.parts.map { it.food }; recipe.usual?.let { names += it.food } }
            return names + setOf("Canola oil", "Plain flour", "Olive oil")
        }
}
