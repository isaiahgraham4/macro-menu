import Foundation

/// The menu scanner's reading and adding up, without a camera. Lines are laid out the way Vision reports them.
enum MenuScanChecks {
    private static func line(_ text: String, x: Double, y: Double, width: Double = 0.34, height: Double = 0.016) -> MenuLine {
        MenuLine(text: text, x: x, y: y, width: width, height: height)
    }

    static func run(foods: [Food], chainNames: [String: String]) {
        // Words on a line
        precondition(MenuParser.splitPrice("Chicken Parma $28.50").price == 28.5)
        precondition(MenuParser.splitPrice("Margherita 22").words == "Margherita")
        precondition(MenuParser.splitPrice("House red 12 / 48").price == 12)
        precondition(MenuParser.splitPrice("Chips ........ 9").price == 9)
        precondition(MenuParser.splitPrice("Chicken parma S24").price == 24)
        precondition(MenuParser.splitPrice("Top 2").price == nil)
        precondition(MenuParser.splitPrice("5-5").price == 5.5 && MenuParser.splitPrice("12-18").price == 12)
        precondition(MenuParser.clean("Margherita (V)") == "Margherita")
        precondition(MenuParser.clean("Pad Thai GF, DF") == "Pad Thai")
        precondition(MenuParser.clean("12. Mixed veg") == "Mixed veg")

        // Two columns, prices printed apart, headings, descriptions, and the small print left out
        let menu = MenuParser.read([
            line("THE CORNER HOTEL", x: 0.2, y: 0.04, width: 0.58, height: 0.05),
            line("Lunch & Dinner", x: 0.43, y: 0.1, width: 0.1, height: 0.012),
            line("ENTREES", x: 0.06, y: 0.14, width: 0.16, height: 0.024),
            line("Garlic Bread", x: 0.06, y: 0.18, width: 0.2), line("9", x: 0.44, y: 0.18, width: 0.02),
            line("Salt & Pepper Squid", x: 0.06, y: 0.21, width: 0.28), line("18", x: 0.43, y: 0.21, width: 0.03),
            line("lemon, aioli, rocket", x: 0.06, y: 0.232, width: 0.26, height: 0.012),
            line("MAINS", x: 0.06, y: 0.29, width: 0.12, height: 0.024),
            line("Chicken Parma", x: 0.06, y: 0.33, width: 0.22), line("28", x: 0.43, y: 0.33, width: 0.03),
            line("crumbed chicken, napoli, ham, mozzarella,", x: 0.06, y: 0.352, width: 0.36, height: 0.012),
            line("chips and salad", x: 0.06, y: 0.368, width: 0.2, height: 0.012),
            line("Add chicken 6", x: 0.06, y: 0.39, width: 0.18, height: 0.012),
            line("PIZZAS", x: 0.55, y: 0.14, width: 0.14, height: 0.024),
            line("The Hawaiian", x: 0.55, y: 0.18, width: 0.2), line("24", x: 0.92, y: 0.18, width: 0.03),
            line("ham, pineapple, mozzarella", x: 0.55, y: 0.202, width: 0.3, height: 0.012),
            line("Margherita (V)", x: 0.55, y: 0.24, width: 0.2), line("$22", x: 0.92, y: 0.24, width: 0.03),
            line("tomato, basil, fior di latte", x: 0.55, y: 0.262, width: 0.3, height: 0.012),
            line("DESSERTS", x: 0.55, y: 0.31, width: 0.16, height: 0.024),
            line("Tiramisu", x: 0.55, y: 0.35, width: 0.14), line("14", x: 0.92, y: 0.35, width: 0.03),
            line("15% surcharge on public holidays. Please tell us about allergies.", x: 0.33, y: 0.95, width: 0.38, height: 0.012),
            line("(03) 9555 0100  www.thecorner.com.au", x: 0.33, y: 0.97, width: 0.38, height: 0.012),
        ])
        precondition(menu.restaurant == "The Corner Hotel")
        precondition(menu.dishes.map(\.name) == ["Garlic Bread", "Salt & Pepper Squid", "Chicken Parma", "The Hawaiian", "Margherita", "Tiramisu"], "\(menu.dishes.map(\.name))")
        precondition(menu.dishes.map(\.section) == ["Entrees", "Entrees", "Mains", "Pizzas", "Pizzas", "Desserts"], "\(menu.dishes.map(\.section))")
        precondition(menu.dishes[2].price == 28 && menu.dishes[2].details == "crumbed chicken, napoli, ham, mozzarella, chips and salad", menu.dishes[2].details)
        precondition(menu.dishes[1].details == "lemon, aioli, rocket")

        // One column, everything on one line, price on the description's line, capitals for dish names
        let oneColumn = MenuParser.read([
            line("Pumpkin Soup - roast pumpkin, cream, sourdough 16", x: 0.1, y: 0.1, width: 0.75),
            line("GRILLED BARRAMUNDI", x: 0.1, y: 0.14, width: 0.3),
            line("crushed potato, beans, lemon butter  36", x: 0.1, y: 0.16, width: 0.5, height: 0.012),
            line("Steak Frites", x: 0.1, y: 0.2, width: 0.2),
            line("300g scotch fillet, shoestring fries, cafe de paris butter", x: 0.1, y: 0.22, width: 0.6, height: 0.012),
            line("44", x: 0.8, y: 0.2, width: 0.03),
        ])
        precondition(oneColumn.dishes.map(\.name) == ["Pumpkin Soup", "Grilled Barramundi", "Steak Frites"], "\(oneColumn.dishes.map(\.name))")
        precondition(oneColumn.dishes[0].price == 16 && oneColumn.dishes[0].details == "roast pumpkin, cream, sourdough")
        precondition(oneColumn.dishes[1].price == 36 && oneColumn.dishes[2].price == 44)

        // A centred menu isn't mistaken for two columns
        let centred = MenuParser.read((0..<12).map { index in
            let wide = index.isMultiple(of: 2)
            return line(wide ? "Dish number \(index) with a long name 20" : "Short dish \(index) 18", x: wide ? 0.2 : 0.35, y: 0.1 + Double(index) * 0.05, width: wide ? 0.6 : 0.3)
        })
        precondition(centred.dishes.map(\.name).first == "Dish number 0 with a long name" && centred.dishes.count == 12, "\(centred.dishes.map(\.name))")

        // The tables only use foods Takeawise has, by weight
        let estimator = MenuEstimator(foods: foods, chainNames: chainNames)
        for name in MenuCookbook.foodNames {
            guard let food = estimator.food(name) else { preconditionFailure("MenuCookbook names a food Takeawise doesn't have: \(name)") }
            precondition((food.servingWeight?.0 ?? 0) > 0, "No weight for \(name)")
        }

        func estimate(_ name: String, _ details: String = "", section: String? = "Mains") -> MenuEstimate {
            guard let result = estimator.estimate(MenuDish(name: name, details: details, section: section)) else { preconditionFailure("No estimate for \(name)") }
            return result
        }
        func calories(_ result: MenuEstimate) -> Double { result.total().cal }
        func uses(_ result: MenuEstimate, _ food: String) -> Bool { result.components.contains { $0.food.name == food } }

        // Whole dishes land where a restaurant serve does
        for (name, details, low, high) in [
            ("Chicken Parma", "crumbed chicken, napoli, ham, mozzarella, chips and salad", 950.0, 1500.0),
            ("Spaghetti Bolognese", "beef ragu, parmesan", 550, 900), ("Fish and Chips", "beer battered flathead, tartare", 900, 1500),
            ("Cheeseburger", "beef patty, cheddar, pickles, milk bun", 550, 950), ("Butter Chicken", "basmati rice, naan", 750, 1300),
            ("Margherita", "tomato, basil, fior di latte", 950, 1400), ("Caesar Salad", "cos, bacon, egg, parmesan, croutons", 300, 700),
            ("Flat White", "", 100, 200), ("Pad Thai", "rice noodles, prawns, tamarind, peanuts", 500, 900),
        ] {
            let result = estimate(name, details)
            precondition((low...high).contains(calories(result)), "\(name): \(calories(result)) Cal")
        }

        // A burger with the protein named swaps the usual patty, and a choice counts once
        let chicken = estimate("Chicken Burger", "grilled chicken, slaw, aioli")
        precondition(uses(chicken, "Chicken thigh, cooked") && !uses(chicken, "Beef patty, 15% fat, cooked"))
        let either = estimate("Green Curry", "chicken or tofu, thai basil, jasmine rice")
        precondition(uses(either, "Chicken thigh, cooked") && !uses(either, "Tofu, firm"))

        // Words that only look like foods
        let sauce = estimate("Grilled Barramundi", "fish sauce caramel, crushed potato, beans, lemon butter")
        precondition(uses(sauce, "White fish (cod), cooked") && uses(sauce, "Potato, baked"))
        let noodles = estimate("Stir Fried Egg Noodles", "bok choy, tofu")
        precondition(!uses(noodles, "Egg, poached"), "egg noodles aren't eggs")
        let leftOut = estimate("Chicken Salad", "tomato, cucumber, no onion, add bacon")
        precondition(!uses(leftOut, "Onion") && !uses(leftOut, "Bacon, cooked"))

        // Rice or noodles named on a dish made with them don't count twice, and a named side replaces the usual one
        precondition(!uses(estimate("Pad Thai", "rice noodles, prawns"), "Rice noodles, cooked"))
        precondition(!uses(estimate("Spaghetti Bolognese", "spaghetti, beef ragu"), "Pasta, cooked"))
        precondition(!uses(estimate("Egg Fried Rice", "egg, spring onion"), "White rice, cooked"))
        let mash = estimate("Chicken Parma", "with mash")
        precondition(uses(mash, "Mashed potato") && !uses(mash, "French fries, takeaway"))
        let hokkien = estimate("Beef Stir Fry", "hokkien noodles, bok choy")
        precondition(uses(hokkien, "Egg noodles, cooked") && !uses(hokkien, "White rice, cooked"))

        // A printed weight is used, a starter is smaller, and a side the menu adds is counted
        let steak = estimate("Steak Frites", "400g scotch fillet, shoestring fries")
        precondition(abs((steak.components.first { $0.food.name == "Top sirloin (rump) steak, cooked" }?.grams ?? 0) - 400) < 1)
        precondition(calories(estimate("Salt & Pepper Squid", section: "Entrees")) < calories(estimate("Salt & Pepper Squid", section: "Mains")) * 0.7)
        precondition(calories(estimate("Tiramisu", section: "Entrees")) == calories(estimate("Tiramisu", section: "Desserts")))
        precondition(uses(estimate("Lamb Shank", "with naan"), "Naan"))

        // A pizza's own cheese and sauce aren't counted again
        let diavola = estimate("The Diavola", "napoli, salami, mozzarella", section: "Pizzas")
        precondition(uses(diavola, "Salami") && !uses(diavola, "Mozzarella") && !uses(diavola, "Pasta sauce"))

        // A heading tells it what kind of dish a made-up name is
        let hawaiian = estimate("The Hawaiian", "ham, pineapple, mozzarella", section: "Pizzas")
        precondition(uses(hawaiian, "Cheese pizza, frozen") && uses(hawaiian, "Ham, lean"))
        precondition(uses(estimate("Barossa Valley 2021", section: "Wines"), "Red wine"))

        // How sure it is, and nothing rather than a guess
        precondition(estimate("Tiramisu", section: "Desserts").basis == .typicalDish)
        precondition(estimate("The Forager", "mushroom, spinach, poached egg, sourdough").basis == .ingredients)
        precondition(estimate("Barramundi", "", section: "Seafood").basis == .rough)
        precondition(estimator.estimate(MenuDish(name: "Chef's Surprise", section: "Mains")) == nil)

        // The restaurant's own item beats any sum
        if let kfc = foods.first(where: { $0.chain == "kfc" }) {
            let result = estimator.estimate(MenuDish(name: kfc.name), chain: "kfc")
            precondition(result?.basis == .official && result?.food(named: kfc.name)?.id == kfc.id, kfc.name)
        }
        precondition(estimator.chain(for: "KFC") == "kfc")
        for name in ["The Corner Hotel", "Lygon St Trattoria", "Thai Orchid", "Chin Chin"] { precondition(estimator.chain(for: name) == nil, name) }

        // Logging: taking something out and choosing a size change the figure, and it says it's an estimate
        var dish = estimate("Chicken Parma", "chips and salad")
        guard let whole = dish.food(named: "Chicken Parma") else { preconditionFailure("Nothing to log") }
        precondition(whole.serve == "1 dish, estimated" && whole.chain == "mine" && whole.isValid && whole.cal.truncatingRemainder(dividingBy: 10) == 0)
        dish.components[1].isOn = false
        precondition((dish.food(named: "Chicken Parma")?.cal ?? 0) < whole.cal)
        precondition(abs(dish.total(.large).cal - dish.total().cal * 1.5) < 0.01)
        for index in dish.components.indices { dish.components[index].isOn = false }
        precondition(dish.food(named: "Chicken Parma") == nil)

        // Apple Intelligence's list is priced from Takeawise's foods, and needs at least two it knows
        let suggested = estimator.estimate(suggested: [("kangaroo", 180), ("beetroot", 80), ("mashed potato", 150), ("not a food at all", 50)], section: "Mains")
        precondition(suggested?.basis == .suggested && (suggested?.components.count ?? 0) >= 2, "\(String(describing: suggested?.components.map(\.food.name)))")
        precondition(estimator.estimate(suggested: [("not a food at all", 50)], section: nil) == nil)
    }
}
