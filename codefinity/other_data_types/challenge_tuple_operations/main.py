# Current inventory on shelf
shelf = ("apples", "oranges", "bananas", "apples", "grapes", "bananas", "apples")

apple_count = shelf.count("apples")
grapes_count = shelf.count("grapes")
banana_index = shelf.index("bananas")
oranges_index = shelf.index("oranges")

print("Number of Apples:", apple_count)
print("First Banana Index:", banana_index)

if (apple_count < 5):
    print("Apples need to be restocked.")
else:
    print("Apples are sufficiently stocked.")

if (grapes_count == 1):
    print("Grapes need to be restocked.")
else:
    print("Grapes are sufficiently stocked.")

if "oranges" in shelf:
    print("Oranges are at index:", oranges_index)
else:
    print("Oranges are out of stock.")