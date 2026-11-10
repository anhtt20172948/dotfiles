import os


class Greeter:
    def __init__(self, name):
        self.name = name

    def greet(self, loud=False):
        if loud:
            return f"HELLO {self.name}".upper()
        for _ in range(2):
            print(os.getcwd())
        return "hello " + self.name
