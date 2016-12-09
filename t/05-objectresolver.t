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

schema {
    query: User
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
    User => sub { return $somebody }
});

$schema.resolvers(
{
    User => {
        someextra => sub { return "an extra field" }
    }
});

ok my $document = $schema.document('
query {
    name
    id
    birthday
    status
    someextra
}
'), 'Make document';

ok my $ret = GraphQL-ExecuteRequest(:$schema, :$document), 'Execute query';

is-deeply $ret, 
{
    data => Hash::Ordered.new(
        'name', 'Fred',
        'id', 7,
        'birthday', 'Friday',
        'status', True,
        'someextra', 'an extra field'
    )
}, 'Compare results';

done-testing;
