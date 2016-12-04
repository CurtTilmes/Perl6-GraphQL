use v6;

use GraphQL;
use GraphQL::Types;

use Test;

my %testcases = Q<<
type Query {
  hello: String
}
>> => 
GraphQL::Schema.new(
    types =>
    {
        'Query' =>
            GraphQL::Object.new(
                name => 'Query',
                fields => GraphQL::FieldList.new(
                    hello => GraphQL::Field.new(name => 'hello',
                                                type => $GraphQLString)
                )
            )
    }
);


for %testcases.kv -> $query, $schema
{
    my $testschema = build-schema($query);

    is-deeply($testschema, $schema);
}

done-testing;
