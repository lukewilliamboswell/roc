// Examples with embedded .roc file content
// This file contains the actual Roc code inline to ensure proper bundling

export interface Example {
  name: string;
  description: string;
  code: string;
  filename: string;
}

export const examples: Example[] = [
  {
    name: "Hello World",
    description: "A simple hello world program",
    filename: "hello-world.roc",
    code: `app [main!] { pf: platform "../basic-cli/platform.roc" }

import pf.Stdout

main! = |_| Stdout.line!("Hello, world!")`,
  },
  {
    name: "Basic Types",
    description: "Numbers, strings, and booleans",
    filename: "basic-types.roc",
    code: `module [name, age, height, isActive, colors, numbers]

name : Str
name = "Alice"

age : I32
age = 25

height : Dec
height = 5.8

isActive : Bool
isActive = True

colors : List(Str)
colors = ["red", "green", "blue"]

numbers : List(I32)
numbers = [1, 2, 3, 4, 5]`,
  },
  {
    name: "Functions",
    description: "Function definitions and higher-order functions",
    filename: "functions.roc",
    code: `module [add, multiply, greet, isEven, applyTwice, factorial, Color, colorToHex]

add : I32, I32 -> I32
add = |a, b| a + b

multiply : I32, I32 -> I32
multiply = |x, y| x * y

greet : Str -> Str
greet = |name| "Hello, \${name}!"

isEven : I32 -> Bool
isEven = |n| n % 2 == 0

applyTwice : (I32 -> I32), I32 -> I32
applyTwice = |func, x| func(func(x))

factorial : I32 -> I32
factorial = |n|
  if n <= 1
    1
  else
    n * factorial(n - 1)

Color : [Red, Green, Blue]

colorToHex : Color -> Str
colorToHex = |color|
  match color {
      Red => "#FF0000"
      Green => "#00FF00"
      Blue => "#0000FF"
  }`,
  },
  {
    name: "Pattern Matching",
    description: "Pattern matching with custom types, lists, and records",
    filename: "pattern-matching.roc",
    code: `module [Shape, calculateArea, processResult, analyzeList, processUser, describeDay]

Shape : [Circle(Dec), Rectangle(Dec, Dec), Triangle(Dec, Dec)]

calculateArea : Shape -> Dec
calculateArea = |shape|
    match shape {
        Circle(radius) => 3.14159 * radius * radius
        Rectangle(width, height) => width * height
        Triangle(base, height) => 0.5 * base * height
    }

processResult : Result(Str, Str) -> Str
processResult = |result|
    match result {
        Ok(value) => "Success: \${value}"
        Err(error) => "Error: \${error}"
    }

analyzeList : List(I32) -> Str
analyzeList = |list|
    match list {
        [] => "Empty list"
        [single] => "Single element: \${single.toStr()}"
        [first, second] => "Two elements: \${first.toStr()} and \${second.toStr()}"
        [first, .. as rest] => "First: \${first.toStr()}, rest has \${rest.len().toStr()} elements"
    }

User : {
  name : Str,
  age : I32,
  isActive : Bool,
}

processUser : User -> Str
processUser = |user|
    match user {
        { name: "admin", age, isActive: Bool.True } => "Admin \${name} (age \${age.toStr()}) is active"
        { name, age, isActive: Bool.False } => "User \${name} is inactive"
        { name, age } if age >= 18 => "Adult user: \${name}"
        { name, age } => "Minor user: \${name} (age \${age.toStr()})"
    }

DayOfWeek : [Monday, Tuesday, Wednesday, Thursday, Friday, Saturday, Sunday]

describeDay : DayOfWeek, Bool -> Str
describeDay = |day, isHoliday|
    match (day, isHoliday) {
        (Saturday, _) | (Sunday, _) => "Weekend!"
        (_, Bool.True) => "Holiday!"
        (Monday, Bool.False) => "Monday blues"
        (Friday, Bool.False) => "TGIF!"
        (_, Bool.False) => "Regular weekday"
    }`,
  },
  {
    name: "Records",
    description: "Creating and working with records",
    filename: "records.roc",
    code: `module [Person, Address, createPerson, getFullName, updateAge, moveToNewAddress, processEmployee, Stats, updateStats]

Person : { name : Str, age : I32, email : Str }
Address : { street : Str, city : Str, zipCode : Str }

createPerson : Str, I32, Str -> Person
createPerson = |name, age, email| { name, age, email }

getFullName : Person -> Str
getFullName = |person| "\${person.name} <\${person.email}>"

updateAge : Person, I32 -> Person
updateAge = |person, newAge| { ..person, age: newAge }

Employee : {
    personal : Person,
    address : Address,
    salary : Dec,
    department : Str
}

moveToNewAddress : Employee, Address -> Employee
moveToNewAddress = |employee, newAddress|
    { ..employee, address: newAddress }

processEmployee : Employee -> Str
processEmployee = |{ personal: { name, age }, department, salary }|
    "\${name} (\${age.toStr()}) works in \${department} earning $\${salary.toStr()}"

Stats : { wins : I32, losses : I32, draws : I32 }

updateStats : Stats, [Win, Loss, Draw] -> Stats
updateStats = |stats, result|
    match result {
        Win => { ..stats, wins: stats.wins + 1 }
        Loss => { ..stats, losses: stats.losses + 1 }
        Draw => { ..stats, draws: stats.draws + 1 }
    }

playerSummary : Stats -> { total : I32, winRate : Dec }
playerSummary = |{wins, losses, draws}| {
    total = wins + losses + draws
    winRate = if total > 0 (wins.toFrac() / total.toFrac()) else 0.0

    { total, winRate }
}

examplePerson : Person
examplePerson = createPerson("Alice Johnson", 28, "alice@example.com")

exampleAddress : Address
exampleAddress = { street: "123 Main St", city: "Springfield", zipCode: "12345" }

exampleEmployee : Employee
exampleEmployee = {
    personal: examplePerson,
    address: exampleAddress,
    salary: 75000.0,
    department: "Engineering",
}`,
  },
];

// Helper function to get a specific example by name
export function getExampleByName(name: string): Example | undefined {
  return examples.find((example) => example.name === name);
}

// Helper function to get example names for UI
export function getExampleNames(): string[] {
  return examples.map((example) => example.name);
}

// Export count for debugging
export const exampleCount = examples.length;
