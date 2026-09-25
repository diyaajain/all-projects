grocery_inventory = {
    "Milk" : ("Dairy",3.50,8),
    "Eggs" : ("Dairy",5.50,30),
    "Bread" : ("Bakery",2.99,15),
    "Apples" : ("Produce",1.50,50)
}

# Task 2: Check Eggs price and reduce if needed
eggs_category, eggs_price, eggs_stock = grocery_inventory["Eggs"]
if eggs_price > 5:
    print("Eggs are too expensive, reducing the price by $1.")
    grocery_inventory["Eggs"] = (
        eggs_category,
        eggs_price - 1,
        eggs_stock
    )
else:
    print("The price of Eggs is reasonable.")

milk_category, milk_price, milk_stock = grocery_inventory["Milk"]
if milk_stock < 10:
    print("Milk needs to be restocked. Increasing stock by 20 units.")
    grocery_inventory["Milk"] = (
        milk_category,
        milk_price,
        milk_stock + 20
    )
else:
    print("Milk has sufficient stock")

apple_category, apple_price, apple_stock = grocery_inventory["Apples"]
if apple_price > 2:
    print("Apples removed from inventory due to high price.")
    grocery_inventory.pop("Apples")


grocery_inventory.update({"Tomatoes": ("Produce",1.20,30)})
print("Inventory after adding Tomatoes:", grocery_inventory)

print("Updated inventory:", grocery_inventory)