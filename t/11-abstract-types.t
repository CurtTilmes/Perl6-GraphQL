use Test;

use GraphQL;

class Dog
{
    has $.name;
    has $.nickname;
    has $.barkVolume;
}

class Cat
{
    has $.name;
    has $.meowVolume;
}

my $schema = GraphQL::Schema.new('
interface Pet {
  name: String!
}

type Dog implements Pet {
  name: String!
  nickname: String
  barkVolume: Int
}

type Cat implements Pet {
  name: String!
  meowVolume: Int
}

union CatOrDog = Cat | Dog

type Query {
  pet(kind: Boolean): CatOrDog
}',
resolvers =>
{
    Query => 
    {
        pet => sub (:$kind)
        {
            $kind
            ?? Cat.new(:name('Fluffy'), :meowVolume(17))
            !! Dog.new(:name('Fido'), :nickname('Bruiser'), :barkVolume(22))
        }
    }
});

is $schema.execute('
{
  pet(kind: false) {
    name
    ... on Cat {
      meowVolume
    }
    ... on Dog {
      nickname
      barkVolume
    }
  }
}').to-json,
'{
  "data": {
    "pet": {
      "name": "Fido",
      "nickname": "Bruiser",
      "barkVolume": 22
    }
  }
}', 'Union with type specific fragment, false';

is $schema.execute('
{
  pet(kind: true) {
    name
    ... on Cat {
      meowVolume
    }
    ... on Dog {
      nickname
      barkVolume
    }
  }
}').to-json,
'{
  "data": {
    "pet": {
      "name": "Fluffy",
      "meowVolume": 17
    }
  }
}', 'Union with type specific fragment, true';

done-testing;

