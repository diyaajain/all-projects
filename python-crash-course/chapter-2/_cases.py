name = 'Eric'
print("Hello " + name + ", would you like to learn some Python today?")
print(f"Hello, {name.title()}!")
print(f"Hello, {name.upper()}!")
print(f"Hello, {name.lower()}!")
famous_person = "Ranchoddas Shamaldas Chanchad"
print(f"{famous_person} once said, \"All is WelL!\"")

person = 'David Dobrik  '
person = person.rstrip()
print(person)

nostarch_url = 'https://nostarch.com'
nostarch_url = nostarch_url.removeprefix('https://')
print(nostarch_url)

description = 'Python is a programming language that lets you work quickly and integrate systems more effectively.'
print(description.replace('Python', 'JavaScript'))