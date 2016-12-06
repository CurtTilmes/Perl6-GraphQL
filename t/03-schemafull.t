use v6;

use Test;
use lib 'lib';

use GraphQL;
use GraphQL::Types;

my $schemastring = 
Q<<
interface Entity {
    id: ID!
    name: String
}

interface Foo {
    is_foo: Boolean
}

interface Goo {
    is_goo: Boolean
}

type Bar implements Foo {
    is_foo: Boolean
    is_bar: Boolean
}

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

union SingleUnion = Person

union MultipleUnion = Person | Pet

type Friend {
    single: SingleUnion
    multiple: MultipleUnion
}

scalar Url

type User implements Entity {
    id: ID!
    name: String
    website: Url
}

type Root {
    me: User
}

schema {
    query: Root
}   
>>,

ok my $Entity = GraphQL::Interface.new(
    name => 'Entity',
    fields => GraphQL::FieldList.new(
        'id', GraphQL::Field.new(
            name => 'id',
            type => GraphQL::Non-Null.new(
                ofType => $GraphQLID
            )
        ),
        'name', GraphQL::Field.new(
            name => 'name',
            type => $GraphQLString
        )
    )
), 'Make Interface Entity';

ok my $Foo = GraphQL::Interface.new(
    name => 'Foo',
    fields => GraphQL::FieldList.new(
        'is_foo', GraphQL::Field.new(
            name => 'is_foo',
            type => $GraphQLBoolean
        )
    )
), 'Make Interface Foo';

ok my $Goo = GraphQL::Interface.new(
    name => 'Goo',
    fields => GraphQL::FieldList.new(
        'is_goo', GraphQL::Field.new(
            name => 'is_goo',
            type => $GraphQLBoolean
        )
    )
), 'Make Interface Goo';

ok my $Bar = GraphQL::Object.new(
    name => 'Bar',
    interfaces => [ $Foo ],
    fields => GraphQL::FieldList.new(
        'is_foo', GraphQL::Field.new(
            name => 'is_foo',
            type => $GraphQLBoolean
        ),
        'is_bar', GraphQL::Field.new(
            name => 'is_bar',
            type => $GraphQLBoolean
        )
    )
), 'Make Object Bar';

ok my $Baz = GraphQL::Object.new(
    name => 'Baz',
    interfaces => [ $Foo, $Goo ],
    fields => GraphQL::FieldList.new(
        'is_foo', GraphQL::Field.new(
            name => 'is_foo',
            type => $GraphQLBoolean
        ),
        'is_goo', GraphQL::Field.new(
            name => 'is_goo',
            type => $GraphQLBoolean
        ),
        'is_baz', GraphQL::Field.new(
            name => 'is_baz',
            type => $GraphQLBoolean
        )
    )
), 'Make Object Baz';

ok my $Person = GraphQL::Object.new(
    name => 'Person',
    fields => GraphQL::FieldList.new(
        'name', GraphQL::Field.new(
            name => 'name',
            type => $GraphQLString
        )
    )
), 'Make Object Person';

ok my $Pet = GraphQL::Object.new(
    name => 'Pet',
    fields => GraphQL::FieldList.new(
        'name', GraphQL::Field.new(
            name => 'name',
            type => $GraphQLString
        )
    )
), 'Make Object Pet';

ok my $SingleUnion = GraphQL::Union.new(
    name => 'SingleUnion',
    possibleTypes => set($Person)
), 'Make Union SingleUnion';        

ok my $MultipleUnion = GraphQL::Union.new(
    name => 'MultipleUnion',
    possibleTypes => set($Person, $Pet)
), 'Make Union MultipleUnion';        

ok my $Friend = GraphQL::Object.new(
    name => 'Friend',
    fields => GraphQL::FieldList.new(
        'single', GraphQL::Field.new(
            name => 'single',
            type => $SingleUnion
        ),
        'multiple', GraphQL::Field.new(
            name => 'multiple',
            type => $MultipleUnion
        )
    )
), 'Make Object Friend';

ok my $Url = GraphQL::Scalar.new(name => 'Url'), 'Make named scalar';

ok my $User = GraphQL::Object.new(
    name => 'User',
    interfaces => [ $Entity ],
    fields => GraphQL::FieldList.new(
        'id', GraphQL::Field.new(
            name => 'id',
            type => GraphQL::Non-Null.new(
                ofType => $GraphQLID
            )
        ),
        'name', GraphQL::Field.new(
            name => 'name',
            type => $GraphQLString
        ),
        'website', GraphQL::Field.new(
            name => 'website',
            type => $Url
        )
    )
), 'Make Object Type';

ok my $schema = GraphQL::Schema.new(
    query => 'Root',
    types =>
    {
        Entity => $Entity,
        Foo => $Foo,
        Goo => $Goo,
        Bar => $Bar,
        Baz => $Baz,
        Person => $Person,
        Pet => $Pet,
        SingleUnion => $SingleUnion,
        MultipleUnion => $MultipleUnion,
        Friend => $Friend,
        Url => $Url,
        User => $User,
        Root => GraphQL::Object.new(
            name => 'Root',
            fields => GraphQL::FieldList.new(
                'id', GraphQL::Field.new(
                    name => 'me',
                    type => $User
                )
            )
        )
    }
), 'Make Schema';

ok my $testschema = build-schema($schemastring), 'Parse schema';

is-deeply $testschema.type('Entity'), $Entity, 'Compare Interface Entity';

is-deeply $testschema.type('Foo'), $Foo, 'Compare Interface Foo';

is-deeply $testschema.type('Goo'), $Goo, 'Compare Interface Goo';

is-deeply $testschema.type('Bar'), $Bar, 'Compare Object Bar';

is-deeply $testschema.type('Baz'), $Baz, 'Compare Object Baz';

is-deeply $testschema.type('Person'), $Person, 'Compare Object Person';

is-deeply $testschema.type('Pet'), $Pet, 'Compare Object Pet';

is-deeply $testschema.type('SingleUnion'), $SingleUnion, 'Compare Union Single';

# The MultipleUnion randomly fails to compare because of the set comparison

#is-deeply $testschema.type('MultipleUnion'), $MultipleUnion,
#    'Compare Union Multiple';

#is-deeply $testschema, $schema, 'Compare whole schema';

done-testing;

