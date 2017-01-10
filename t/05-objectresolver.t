use v6;

use lib 'lib';
use GraphQL;

use Test;

ok my $schema = GraphQL::Schema.new('
type User {
    id: ID
    name: String
    birthday: String
    status: Boolean
    someextra: String
}

type Query {
  user: User
}

schema {
    query: Query
}'), 'Make schema';

class User
{
    has $.id;
    has $.name;
    has $.birthday;
    has $.status;
}

my $somebody = User.new(id => 7,
                        name => 'Fred',
                        birthday => 'Friday',
                        status => True);

$schema.resolvers(
{
    Query => { user => sub { return $somebody } }
});

$schema.resolvers(
{
    User => {
        someextra => sub { return "an extra field" }
    }
});

ok my $document = $schema.document('
query {
    user {
        name
        id
        birthday
        status
        someextra
    }
}
'), 'Make document';

ok my $ret = $schema.execute(:$document), 'Execute query';

is $ret.to-json, 
Q<<{
  "data": {
    "user": {
      "name": "Fred",
      "id": "7",
      "birthday": "Friday",
      "status": true,
      "someextra": "an extra field"
    }
  }
}>>, 'Compare results';

done-testing;
