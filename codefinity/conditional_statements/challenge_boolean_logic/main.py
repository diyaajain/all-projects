seasonal = True
on_sale = False
selling_well = False
current_stock = 150
high_stock_threshold = 100

overstock_risk = seasonal and (current_stock > high_stock_threshold)
discount_eligible = not on_sale and not selling_well
make_discount = overstock_risk or discount_eligible

print("Should the item be discounted?", make_discount)