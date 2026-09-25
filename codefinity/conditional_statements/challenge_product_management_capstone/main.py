# Input variables
days_until_expiration = 5  # Example value
stock_level = 60  # Example value
product_type = "Perishable"  # Can be "Perishable" or "Non-Perishable"

if product_type == 'Perishable':
    if days_until_expiration <=3 or stock_level > 50:
        print("30% discount applied")
    if days_until_expiration >=4 or days_until_expiration <=6 or stock_level > 50:
        print("20% discount applied")
    if days_until_expiration >=6 or stock_level <= 50:
        print("10% discount applied")

else:
    print("No discount available for non-perishable items.")