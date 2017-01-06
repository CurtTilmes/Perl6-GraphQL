use v6;

use Test;

use GraphQL;

my $schema = GraphQL::Schema.new('
enum DogCommand { SIT, DOWN, HEEL }

type Dog implements Pet {
  name: String!
  nickname: String
  barkVolume: Int
  doesKnowCommand(dogCommand: DogCommand!): Boolean!
  isHousetrained(atOtherHomes: Boolean): Boolean!
  owner: Human
}

interface Sentient {
  name: String!
}

interface Pet {
  name: String!
}

type Alien implements Sentient {
  name: String!
  homePlanet: String
}

type Human implements Sentient {
  name: String!
}

enum CatCommand { JUMP }

type Cat implements Pet {
  name: String!
  nickname: String
  doesKnowCommand(catCommand: CatCommand!): Boolean!
  meowVolume: Int
}

union CatOrDog = Cat | Dog
union DogOrHuman = Dog | Human
union HumanOrAlien = Human | Alien

type Query {
  dog: Dog
}
');

#say $schema.Str;

ok $schema.document('
query getDogName {
  dog {
    name
  }
}

query getOwnerName {
  dog {
    owner {
      name
    }
  }
}
'), 'Valid Operation Name Uniqueness';

nok try { $schema.document('
query getName {
  dog {
    name
  }
}

query getName {
  dog {
    owner {
      name
    }
  }
}
') }, 'Invalid Operation Name Uniqueness';

nok try { $schema.document('
query dogOperation {
  dog {
    name
  }
}

mutation dogOperation {
  mutateDog {
    id
  }
}') }, 'Invalid Operation Name Uniqueness query/mutation';

ok $schema.document('
{
  dog {
    name
  }
}'), 'Lone Anonymous Operation';

nok try { $schema.document('
{
  dog {
    name
  }
}

query getName {
  dog {
    owner {
      name
    }
  }
}

'); }, 'Invalid Lone Anonymous Operation';

nok try { $schema.document('
fragment fieldNotDefined on Dog {
  meowVolume
}') }, 'Fields Selection, field not defined';

nok try { $schema.document('
fragment aliasedLyingFieldTargetNotDefined on Dog {
  barkVolume: kawVolume
}') }, 'Field Selections, aliased target field must be defined on scoped type';

ok $schema.document('
fragment interfaceFieldSelection on Pet {
  name
}'), 'Field selection on interface';

nok try { $schema.document('
fragment definedOnImplementorsButNotInterface on Pet {
  nickname
}') }, 'Field not defined on interface';

ok $schema.document('
fragment inDirectFieldSelectionOnUnion on CatOrDog {
  __typename
  ... on Pet {
    name
  }
  ... on Dog {
    barkVolume
  }
}'), 'inDirect Field Selection on Union';

nok try { $schema.document('
fragment directFieldSelectionOnUnion on CatOrDog {
  name
  barkVolume
}') }, 'direct field selection on union';

ok $schema.document('
fragment mergeIdenticalFields on Dog {
  name
  name
}'), 'Merge Identical Fields';

ok $schema.document('
fragment mergeIdenticalAliasesAndFields on Dog {
  otherName: name
  otherName: name
}'), 'Merge Identical Aliases and Fields';

#nok $schema.document('
#fragment conflictingBecauseAlias on Dog {
#  name: nickname
#  name
#}'), 'Conflicting because alias';


done-testing;
