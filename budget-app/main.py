class Category:
    def __init__(self, name):
        self.name = name
        self.ledger = []

    def deposit(self, amount, description=""):
        self.ledger.append({
            "amount": amount,
            "description": description
        })

    def withdraw(self, amount, description=""):
        if self.check_funds(amount):
            self.ledger.append({
                "amount": -amount,
                "description": description
            })
            return True
        return False

    def get_balance(self):
        return sum(item["amount"] for item in self.ledger)

    def transfer(self, amount, category):
        if self.check_funds(amount):
            self.withdraw(amount, f"Transfer to {category.name}")
            category.deposit(amount, f"Transfer from {self.name}")
            return True
        return False

    def check_funds(self, amount):
        return amount <= self.get_balance()

    def __str__(self):
        output = self.name.center(30, "*") + "\n"

        for item in self.ledger:
            description = item["description"][:23]
            amount = f"{item['amount']:.2f}"[:7]
            output += f"{description:<23}{amount:>7}\n"

        output += f"Total: {self.get_balance():.2f}"
        return output


def create_spend_chart(categories):
    title = "Percentage spent by category\n"

    spent = []
    total_spent = 0

    for category in categories:
        amount = sum(
            -item["amount"]
            for item in category.ledger
            if item["amount"] < 0
        )
        spent.append(amount)
        total_spent += amount

    percentages = [
        int((amount / total_spent) * 100) // 10 * 10
        for amount in spent
    ]

    chart = title

    for percent in range(100, -1, -10):
        chart += f"{percent:>3}|"
        for p in percentages:
            if p >= percent:
                chart += " o "
            else:
                chart += "   "
        chart += " \n"

    chart += "    " + "-" * (len(categories) * 3 + 1) + "\n"

    max_len = max(len(category.name) for category in categories)

    for i in range(max_len):
        chart += "     "
        for category in categories:
            if i < len(category.name):
                chart += category.name[i] + "  "
            else:
                chart += "   "
        if i != max_len - 1:
            chart += "\n"

    return chart