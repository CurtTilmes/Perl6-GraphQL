use v6;

use Test;

use GraphQL;
use GraphQL::Types;
use GraphQL::Compare;

my $schemastring = 
Q<<
# Entity interface
interface Entity {
    # id field
    id: ID!
    # name field
    name: String
}

# Foo interface
interface Foo {
    is_foo: Boolean
}

# Goo interface
interface Goo {
    is_goo: Boolean
}

# Bar object type
type Bar implements Foo {
    is_foo: Boolean
    is_bar: Boolean
}

# Baz object type
type Baz implements Foo, Goo {
    is_foo: Boolean
    is_goo: Boolean
    is_baz: Boolean
}

type Person {
    name: String
}

type Pet {
    name: String
}

# Single union of type person
union SingleUnion = Person

# Union can be either a Person or a Pet
union MultipleUnion = Person | Pet

# A Friend has a person (single), and either a Person or Pet (multiple)
type Friend {
    single: SingleUnion
    multiple: MultipleUnion
}

# URL is a special type of scalar
scalar URL

# User is a type of Entity
type User implements Entity {
    id: ID!
    name: String
    # website field is of special scalar type URL
    website: URL
}

# Root object type
type Root {
    me: User
}

schema {
    query: Root
}   
>>;

ok my $Entity = GraphQL::Interface.new(
    name => 'Entity',
    description => 'Entity interface',
    fieldlist => (
        GraphQL::Field.new(
            name => 'id',
            description => 'id field',
            type => GraphQL::Non-Null.new(
                ofType => GraphQLID
            )
        ),
        GraphQL::Field.new(
            name => 'name',
            description => 'name field',
            type => GraphQLString
        )
    )
), 'Make Interface Entity';

ok my $Foo = GraphQL::Interface.new(
    name => 'Foo',
    description => 'Foo interface',
    fieldlist => (
        GraphQL::Field.new(
            name => 'is_foo',
            type => GraphQLBoolean
        )
    )
), 'Make Interface Foo';

ok my $Goo = GraphQL::Interface.new(
    name => 'Goo',
    description => 'Goo interface',
    fieldlist => (
        GraphQL::Field.new(
            name => 'is_goo',
            type => GraphQLBoolean
        )
    )
), 'Make Interface Goo';

ok my $Bar = GraphQL::Object.new(
    name => 'Bar',
    description => 'Bar object type',
    interfaces => [ $Foo ],
    fieldlist => (
        GraphQL::Field.new(
            name => 'is_foo',
            type => GraphQLBoolean
        ),
        GraphQL::Field.new(
            name => 'is_bar',
            type => GraphQLBoolean
        )
    )
), 'Make Object Bar';

ok my $Baz = GraphQL::Object.new(
    name => 'Baz',
    description => 'Baz object type',
    interfaces => [ $Foo, $Goo ],
    fieldlist => (
        GraphQL::Field.new(
            name => 'is_foo',
            type => GraphQLBoolean
        ),
        GraphQL::Field.new(
            name => 'is_goo',
            type => GraphQLBoolean
        ),
        GraphQL::Field.new(
            name => 'is_baz',
            type => GraphQLBoolean
        )
    )
), 'Make Object Baz';

ok my $Person = GraphQL::Object.new(
    name => 'Person',
    fieldlist => (
        GraphQL::Field.new(
            name => 'name',
            type => GraphQLString
        )
    )
), 'Make Object Person';

ok my $Pet = GraphQL::Object.new(
    name => 'Pet',
    fieldlist => (
        GraphQL::Field.new(
            name => 'name',
            type => GraphQLString
        )
    )
), 'Make Object Pet';

ok my $SingleUnion = GraphQL::Union.new(
    name => 'SingleUnion',
    description => 'Single union of type person',
    possibleTypes => $Person
), 'Make Union SingleUnion';        

ok my $MultipleUnion = GraphQL::Union.new(
    name => 'MultipleUnion',
    description => 'Union can be either a Person or a Pet',
    possibleTypes => ($Person, $Pet)
), 'Make Union MultipleUnion';        

ok my $Friend = GraphQL::Object.new(
    name => 'Friend',
    description => 'A Friend has a person (single), and either a Person or Pet (multiple)',
    fieldlist => (
        GraphQL::Field.new(
            name => 'single',
            type => $SingleUnion
        ),
        GraphQL::Field.new(
            name => 'multiple',
            type => $MultipleUnion
        )
    )
), 'Make Object Friend';

ok my $URL = GraphQL::Scalar.new(
    name => 'URL',
    description => 'URL is a special type of scalar',
    ), 'Make named scalar';

ok my $User = GraphQL::Object.new(
    name => 'User',
    description => 'User is a type of Entity',
    interfaces => [ $Entity ],
    fieldlist => (
        GraphQL::Field.new(
            name => 'id',
            type => GraphQL::Non-Null.new(
                ofType => GraphQLID
            )
        ),
        GraphQL::Field.new(
            name => 'name',
            type => GraphQLString
        ),
        GraphQL::Field.new(
            name => 'website',
            description => 'website field is of special scalar type URL',
            type => $URL
        )
    )
), 'Make Object User';

ok my $schema = GraphQL::Schema.new(
    query => 'Root',
    $Entity,
    $Foo,
    $Goo,
    $Bar,
    $Baz,
    $Person,
    $Pet,
    $SingleUnion,
    $MultipleUnion,
    $Friend,
    $URL,
    $User,
    GraphQL::Object.new(
        name => 'Root',
        description => 'Root object type',
        fieldlist => (
            GraphQL::Field.new(
                name => 'me',
                type => $User
            )
        )
    )
), 'Make Schema';

$schema.resolve-schema;

ok my $testschema = GraphQL::Schema.new($schemastring), 'Parse schema';

$testschema.resolve-schema;

is-deeply $testschema.type('Entity'), $Entity, 'Compare Interface Entity';

is-deeply $testschema.type('Foo'), $Foo, 'Compare Interface Foo';

is-deeply $testschema.type('Goo'), $Goo, 'Compare Interface Goo';

is-deeply $testschema.type('Bar'), $Bar, 'Compare Object Bar';

is-deeply $testschema.type('Baz'), $Baz, 'Compare Object Baz';

is-deeply $testschema.type('Person'), $Person, 'Compare Object Person';

is-deeply $testschema.type('Pet'), $Pet, 'Compare Object Pet';

is-deeply $testschema.type('SingleUnion'), $SingleUnion, 'Compare Union Single';

is-deeply $testschema.type('MultipleUnion'), $MultipleUnion,
    'Compare Union Multiple';

is-deeply $testschema.type('Friend'), $Friend, 'Compare Object Friend';

is-deeply $testschema.type('URL'), $URL, 'Compare Scalar URL';

is-deeply $testschema.type('User'), $User, 'Compare Object User';

is-deeply $testschema, $schema, 'Compare whole schema';

done-testing;

