use v6;

use GraphQL;
use Test;

ok my $schema = GraphQL::Schema.new('type Query { hello: String }',
    resolvers => { Query => { hello => sub { 'Hello World' } } }),
    'Make basic schema';


ok my $ret = $schema.execute('{badfield}'), 'Bad Field Query';

is $ret.to-json, Q<{
  "errors": [
    {
      "message": "Cannot query field 'badfield' on type 'Query'."
    }
  ]
}>, 'Bad Field Error';

done-testing;
