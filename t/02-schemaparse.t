use v6;

use Test;
use lib 'lib';

use GraphQL;
use GraphQL::Types;

my @testcases =
'Simple Hello with a string',
Q<<
type Query {
  hello: String
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(
                        name => 'hello',
                        type => $GraphQLString
                    )
                )
            )
    }
),
#----------------------------------------------------------------------
'Non-null',
Q<<
type Query {
  hello: String!
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(
                        name => 'hello',
                        type => GraphQL::Non-Null.new(ofType => $GraphQLString)
                    )
                )
            )
    }
),
#----------------------------------------------------------------------
'List of String',
Q<<
type Query {
  hello: [String]
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(
                        name => 'hello',
                        type => GraphQL::List.new(ofType => $GraphQLString)
                    )
                )
            )
    }
),
#----------------------------------------------------------------------
'Non-null List of Non-null String',
Q<<
type Query {
  hello: [String!]!
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(
                        name => 'hello',
                        type => GraphQL::Non-Null.new(
                            ofType => GraphQL::List.new(
                                ofType => GraphQL::Non-Null.new(
                                    ofType => $GraphQLString)
                            )
                        )
                    )
                )
            )
    }
),
#----------------------------------------------------------------------
'Arguments with various scalar types',
Q<<
type Query {
    id: ID!
    name: String
    age: Int
    balance: Float
    is_active: Boolean
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    id => GraphQL::Field.new(
                        name => 'id',
                        type => GraphQL::Non-Null.new(
                            ofType => $GraphQLID)
                    ),
                    name => GraphQL::Field.new(
                        name => 'name',
                        type => $GraphQLString
                    ),
                    age => GraphQL::Field.new(
                        name => 'age',
                        type => $GraphQLInt
                    ),
                    balance => GraphQL::Field.new(
                        name => 'balance',
                        type => $GraphQLFloat
                    ),
                    is_active => GraphQL::Field.new(
                        name => 'is_active',
                        type => $GraphQLBoolean
                    )
                )
            )
    }
),
#----------------------------------------------------------------------
'Field with argument',
Q<<
type Query {
  hello(limit: Int): String
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(
                        name => 'hello',
                        type => $GraphQLString,
                        args =>
                        [
                             GraphQL::TypeArgument.new(
                                 name => 'limit',
                                 type => $GraphQLInt
                             )
                        ]
                    )
                )
            )
    }
),
#----------------------------------------------------------------------
'Field with argument with default value',
Q<<
type Query {
  hello(limit: Int = 10): String
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(
                        name => 'hello',
                        type => $GraphQLString,
                        args =>
                        [
                             GraphQL::TypeArgument.new(
                                 name => 'limit',
                                 type => $GraphQLInt,
                                 defaultValue => 10
                             )
                        ]
                    )
                )
            )
    }
),
#----------------------------------------------------------------------
'Field with arguments of various types',
Q<<
type Query {
  hello(id: ID, first: Int, x: Float, cond: Boolean, person: String): String
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(
                        name => 'hello',
                        type => $GraphQLString,
                        args =>
                        [
                             GraphQL::TypeArgument.new(
                                 name => 'id',
                                 type => $GraphQLID
                             ),
                             GraphQL::TypeArgument.new(
                                 name => 'first',
                                 type => $GraphQLInt
                             ),
                             GraphQL::TypeArgument.new(
                                 name => 'x',
                                 type => $GraphQLFloat
                             ),
                             GraphQL::TypeArgument.new(
                                 name => 'cond',
                                 type => $GraphQLBoolean
                             ),
                             GraphQL::TypeArgument.new(
                                 name => 'person',
                                 type => $GraphQLString
                             )
                        ]
                    )
                )
            )
    }
),
#----------------------------------------------------------------------
'Field with arguments of various types with defaults',
Q<<
type Query {
  hello(id: ID         = "123xyz",
        first: Int     = 27,
        x: Float       = 1.2,
        cond: Boolean  = true,
        person: String = "Fred"): String
}
>>,
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(
                        name => 'hello',
                        type => $GraphQLString,
                        args =>
                        [
                             GraphQL::TypeArgument.new(
                                 name => 'id',
                                 type => $GraphQLID,
                                 defaultValue => '123xyz'
                             ),
                             GraphQL::TypeArgument.new(
                                 name => 'first',
                                 type => $GraphQLInt,
                                 defaultValue => 27
                             ),
                             GraphQL::TypeArgument.new(
                                 name => 'x',
                                 type => $GraphQLFloat,
                                 defaultValue => Num(1.2)
                             ),
                             GraphQL::TypeArgument.new(
                                 name => 'cond',
                                 type => $GraphQLBoolean,
                                 defaultValue => True,
                             ),
                             GraphQL::TypeArgument.new(
                                 name => 'person',
                                 type => $GraphQLString,
                                 defaultValue => 'Fred'
                             )
                        ]
                    )
                )
            )
    }
),;


for @testcases -> $description, $query, $schema
{
    ok my $testschema = build-schema($query), "Parsing $description";

    is-deeply($testschema, $schema, $description);
}

done-testing;
